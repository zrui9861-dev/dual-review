"""Main dual-agent orchestrator -- the state machine that drives
Generator-Critic rounds to convergence.

Orchestration flow
------------------

::

    ┌──────────────────────────────────────────────────┐
    │                   run(task)                       │
    │                      │                            │
    │          ┌───────────▼───────────┐                │
    │          │   Generator produces  │◄───────────┐   │
    │          │      Artifact         │            │   │
    │          └───────────┬───────────┘            │   │
    │                      │                        │   │
    │          ┌───────────▼───────────┐            │   │
    │          │   Critic produces     │            │   │
    │          │      Verdict          │            │   │
    │          └───────────┬───────────┘            │   │
    │                      │                        │   │
    │          ┌───────────▼───────────┐            │   │
    │          │  ConvergenceEngine    │            │   │
    │          │  6-layer evaluation   │            │   │
    │          └───────────┬───────────┘            │   │
    │                      │                        │   │
    │       ┌──────────────┼──────────────┐         │   │
    │       ▼              ▼              ▼         │   │
    │   "accept"      "continue"     "escalate"     │   │
    │       │              │              │         │   │
    │       ▼              └──────────────┘         │   │
    │  return best     (loop back to                 │   │
    │   artifact        Generator with    ┌─────────┘   │
    │                    feedback)         │             │
    │                                     ▼             │
    │                              Meta-judge picks     │
    │                              best artifact        │
    └──────────────────────────────────────────────────┘
"""

from __future__ import annotations

import json
import time
from typing import Optional

from .adapters.base import BaseAdapter
from .convergence import ConvergenceEngine
from .loop_detector import SemanticLoopDetector
from .models import (
    AgentConfig,
    Artifact,
    Decision,
    DisputeRecord,
    Issue,
    RoundRecord,
    Verdict,
)
from .prompts import CRITIC_SYSTEM_PROMPT, GENERATOR_SYSTEM_PROMPT

# ---------------------------------------------------------------------------
# JSON schemas for structured generation
# ---------------------------------------------------------------------------

_ARTIFACT_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "content": {"type": "string", "description": "The complete solution content."},
        "reasoning": {
            "type": "string",
            "description": "Your reasoning chain: why you made each decision.",
        },
        "confidence": {
            "type": "number",
            "description": "Confidence score between 0.0 and 1.0.",
        },
        "uncertain_parts": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Parts you're uncertain about.",
        },
    },
    "required": ["content", "reasoning", "confidence", "uncertain_parts"],
    "additionalProperties": False,
}

_VERDICT_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "score": {
            "type": "number",
            "description": "Overall quality score between 0.0 and 1.0.",
        },
        "issues": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "severity": {
                        "type": "string",
                        "enum": ["critical", "major", "minor", "style"],
                    },
                    "description": {"type": "string"},
                    "location": {"type": "string"},
                    "fix_hint": {"type": "string"},
                },
                "required": ["severity", "description"],
                "additionalProperties": False,
            },
        },
        "is_blocking": {
            "type": "boolean",
            "description": "Whether the issues fundamentally block acceptance.",
        },
        "suggestion": {
            "type": "string",
            "description": "Consolidated suggestion for improvement if issues exist.",
        },
        "agreement_level": {
            "type": "number",
            "description": "How much you agree with the Generator's approach (0.0-1.0).",
        },
    },
    "required": ["score", "issues", "is_blocking", "agreement_level"],
    "additionalProperties": False,
}


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------


class DualAgentOrchestrator:
    """State-machine orchestrator for the Generator-Critic dual-agent pattern.

    The orchestrator runs successive rounds of generation and critique
    until a convergence decision is reached.  It handles dispute tracking,
    graceful degradation when structured output fails, and deadlock
    resolution via meta-judge escalation.

    Typical usage::

        import asyncio
        from dual_agent_sdk import (
            DualAgentOrchestrator, AnthropicAdapter, OpenAIAdapter
        )

        async def main():
            gen = AnthropicAdapter(model="claude-sonnet-4-6")
            crit = OpenAIAdapter(model="gpt-4o")
            orch = DualAgentOrchestrator(generator=gen, critic=crit)
            result = await orch.run("Design a rate limiter for a REST API")
            print(result.content)

        asyncio.run(main())
    """

    # ------------------------------------------------------------------
    # Construction
    # ------------------------------------------------------------------

    def __init__(
        self,
        generator: BaseAdapter,
        critic: BaseAdapter,
        config: AgentConfig | None = None,
    ) -> None:
        """
        Args:
            generator: LLM adapter for the Generator role.
            critic: LLM adapter for the Critic role.
            config: Optional configuration; defaults to :class:`AgentConfig()`.
        """
        if generator is critic:
            raise ValueError(
                "Generator and Critic must be distinct adapter instances. "
                "Using the same adapter for both roles defeats the purpose "
                "of dual-agent review."
            )

        self.generator = generator
        self.critic = critic
        self.config = config or AgentConfig()
        self.convergence = ConvergenceEngine()
        self.loop_detector = SemanticLoopDetector(
            threshold=self.config.loop_similarity_threshold
        )
        self.round_history: list[RoundRecord] = []
        self.disputes: list[DisputeRecord] = []

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def run(self, task: str, context: str | None = None) -> Artifact:
        """Execute the dual-agent loop and return the best artifact.

        Args:
            task: The problem statement / task description.
            context: Optional additional context (previous work, constraints,
                domain knowledge, etc.).

        Returns:
            The highest-scoring :class:`Artifact` produced during the run.
        """
        previous_criticism: str | None = None

        for round_num in range(1, self.config.max_rounds + 1):
            # ----------------------------------------------------------
            # 1. Generator produces an Artifact
            # ----------------------------------------------------------
            artifact = await self._generate(task, context, previous_criticism)

            # ----------------------------------------------------------
            # 2. Critic reviews the Artifact
            # ----------------------------------------------------------
            verdict = await self._critique(task, artifact, previous_criticism)

            # ----------------------------------------------------------
            # 3. Record the round
            # ----------------------------------------------------------
            record = RoundRecord(
                round_num=round_num,
                artifact=artifact,
                verdict=verdict,
                timestamp=time.time(),
            )
            self.round_history.append(record)

            # Track persistent disagreements.
            await self._track_disputes(artifact, verdict)

            # ----------------------------------------------------------
            # 4. Evaluate convergence
            # ----------------------------------------------------------
            decision = self._evaluate(round_num, verdict)

            if decision == "accept":
                return self._best_artifact()

            if decision == "escalate":
                return await self._escalate(task)

            # decision == "continue" -- prepare feedback for next round.
            previous_criticism = self._build_criticism_feedback(verdict)

        # Hard ceiling: return the best we have.
        return self._best_artifact()

    # ------------------------------------------------------------------
    # Internal: generation & critique
    # ------------------------------------------------------------------

    async def _generate(
        self,
        task: str,
        context: str | None,
        previous_criticism: str | None,
    ) -> Artifact:
        """Ask the Generator to produce an artifact (structured or text)."""
        prompt = self._build_generator_prompt(task, context, previous_criticism)

        try:
            data = await self.generator.generate_structured(
                system_prompt=GENERATOR_SYSTEM_PROMPT,
                user_prompt=prompt,
                output_schema=_ARTIFACT_SCHEMA,
            )
            return Artifact.model_validate(data)
        except Exception:
            # Graceful fallback: get free-form text and extract artifact
            # fields via a follow-up parse.
            text = await self.generator.generate(
                system_prompt=GENERATOR_SYSTEM_PROMPT, user_prompt=prompt
            )
            return self._parse_artifact_from_text(text)

    async def _critique(
        self,
        task: str,
        artifact: Artifact,
        previous_criticism: str | None,
    ) -> Verdict:
        """Ask the Critic to review the artifact (structured or text)."""
        prompt = self._build_critic_prompt(task, artifact, previous_criticism)

        try:
            data = await self.critic.generate_structured(
                system_prompt=CRITIC_SYSTEM_PROMPT,
                user_prompt=prompt,
                output_schema=_VERDICT_SCHEMA,
            )
            return Verdict.model_validate(data)
        except Exception:
            text = await self.critic.generate(
                system_prompt=CRITIC_SYSTEM_PROMPT, user_prompt=prompt
            )
            return self._parse_verdict_from_text(text)

    # ------------------------------------------------------------------
    # Internal: prompt builders
    # ------------------------------------------------------------------

    @staticmethod
    def _build_generator_prompt(
        task: str, context: str | None, previous_criticism: str | None
    ) -> str:
        """Construct the user prompt for the Generator."""
        parts = [f"## Task\n\n{task}"]
        if context:
            parts.append(f"\n## Additional Context\n\n{context}")
        if previous_criticism:
            parts.append(
                f"\n## Previous Critic Feedback\n\n{previous_criticism}\n\n"
                "Please address every issue listed above.  If you disagree "
                "with any criticism, explain why in your reasoning."
            )
        parts.append(
            "\n\nProvide your solution as a JSON object matching the "
            "required schema.  Do NOT wrap the JSON in markdown fences."
        )
        return "\n".join(parts)

    @staticmethod
    def _build_critic_prompt(
        task: str, artifact: Artifact, previous_criticism: str | None
    ) -> str:
        """Construct the user prompt for the Critic."""
        parts = [
            f"## Original Task\n\n{task}",
            "\n## Generator's Solution (Artifact)\n",
            artifact.content,
            f"\n\n## Generator's Reasoning\n\n{artifact.reasoning}",
            f"\n\n## Generator's Confidence\n\n{artifact.confidence:.2f}",
        ]
        if artifact.uncertain_parts:
            parts.append(
                "\n## Generator's Uncertain Parts\n\n"
                + "\n".join(f"- {p}" for p in artifact.uncertain_parts)
            )
        if previous_criticism:
            parts.append(
                f"\n## Your Previous Criticism\n\n{previous_criticism}\n\n"
                "Check whether the Generator addressed your feedback."
            )
        parts.append(
            "\n\nProvide your review as a JSON object matching the required "
            "schema.  Do NOT wrap the JSON in markdown fences."
        )
        return "\n".join(parts)

    @staticmethod
    def _build_criticism_feedback(verdict: Verdict) -> str:
        """Convert a Verdict into actionable feedback for the Generator."""
        lines: list[str] = []
        if verdict.suggestion:
            lines.append(f"Suggestion: {verdict.suggestion}")
        if verdict.issues:
            lines.append("\nIssues found:")
            for i, issue in enumerate(verdict.issues, 1):
                line = f"  {i}. [{issue.severity}] {issue.description}"
                if issue.location:
                    line += f" (at: {issue.location})"
                if issue.fix_hint:
                    line += f" — fix: {issue.fix_hint}"
                lines.append(line)
        return "\n".join(lines)

    # ------------------------------------------------------------------
    # Internal: convergence & escalation
    # ------------------------------------------------------------------

    def _evaluate(self, round_num: int, verdict: Verdict) -> Decision:
        """Run the full convergence chain."""
        prev = self.round_history[-2].verdict if len(self.round_history) >= 2 else None
        return self.convergence.evaluate(
            round_num, verdict, prev, self.config, self.round_history
        )

    async def _escalate(self, task: str) -> Artifact:
        """Resolve a deadlock via meta-judge using the Critic as tie-breaker.

        The meta-judge receives all artifacts and verdicts and selects the
        single best result.  If structured generation fails we fall back to
        the best scored artifact.
        """
        if len(self.round_history) < 2:
            return self._best_artifact()

        # Build a summary of all rounds.
        round_summaries = []
        for record in self.round_history:
            round_summaries.append(
                f"## Round {record.round_num} (score: {record.verdict.score:.2f})\n\n"
                f"**Artifact:**\n{record.artifact.content}\n\n"
                f"**Verdict:**\n{self._build_criticism_feedback(record.verdict)}"
            )

        meta_prompt = (
            f"## Original Task\n\n{task}\n\n"
            "You are a META-JUDGE.  Below are multiple rounds of "
            "Generator-Critic collaboration that have resulted in a deadlock "
            "(semantic loop detected).\n\n"
            "Review all rounds and select the SINGLE BEST artifact.  "
            "Return the EXACT content of that artifact (no additions or "
            "modifications).\n\n"
            + "\n\n---\n\n".join(round_summaries)
        )

        try:
            # Ask the critic to act as meta-judge and return the best content.
            # We use a structured schema that has a "selected_content" field.
            data = await self.critic.generate_structured(
                system_prompt=(
                    "You are a META-JUDGE. Your task is to break a deadlock "
                    "between a Generator and Critic by selecting the single "
                    "best artifact."
                ),
                user_prompt=meta_prompt,
                output_schema={
                    "type": "object",
                    "properties": {
                        "selected_content": {"type": "string"},
                        "reason": {"type": "string"},
                    },
                    "required": ["selected_content", "reason"],
                    "additionalProperties": False,
                },
            )
            # Wrap the selected content back into an Artifact.
            return Artifact(
                content=data["selected_content"],
                reasoning=data.get("reason", "Selected by meta-judge during escalation."),
                confidence=0.5,  # meta-judge doesn't produce confidence
            )
        except Exception:
            return self._best_artifact()

    def _best_artifact(self) -> Artifact:
        """Return the artifact with the highest verdict score."""
        if not self.round_history:
            raise RuntimeError("No rounds completed; cannot produce an artifact.")
        best = max(self.round_history, key=lambda r: r.verdict.score)
        return best.artifact

    # ------------------------------------------------------------------
    # Internal: dispute tracking
    # ------------------------------------------------------------------

    async def _track_disputes(self, artifact: Artifact, verdict: Verdict) -> None:
        """Identify and persist disagreements between Generator and Critic.

        A dispute is flagged when the agreement_level is below 0.5 or when
        the Critic registers a blocking verdict.
        """
        if verdict.agreement_level < 0.5 or verdict.is_blocking:
            # Check if we already have a dispute on a similar topic.
            for dispute in self.disputes:
                if self._is_same_dispute(dispute, artifact, verdict):
                    dispute.rounds_unresolved += 1
                    return

            # New dispute.
            topic = verdict.suggestion or "Unnamed disagreement"
            self.disputes.append(
                DisputeRecord(
                    topic=topic[:200],
                    generator_position=artifact.reasoning[:500],
                    critic_position=self._build_criticism_feedback(verdict)[:500],
                    rounds_unresolved=1,
                )
            )

    @staticmethod
    def _is_same_dispute(
        dispute: DisputeRecord, artifact: Artifact, verdict: Verdict
    ) -> bool:
        """Heuristic: check if the new criticism overlaps with an existing dispute."""
        new_criticism = (
            verdict.suggestion or ""
        )[:100].lower()
        existing_topic = dispute.topic[:100].lower()
        # Simple overlap check — not a full semantic comparison.
        words_new = set(new_criticism.split())
        words_existing = set(existing_topic.split())
        if not words_new or not words_existing:
            return False
        overlap = len(words_new & words_existing) / len(words_new | words_existing)
        return overlap > 0.5

    # ------------------------------------------------------------------
    # Internal: text fallback parsing
    # ------------------------------------------------------------------

    @staticmethod
    def _parse_artifact_from_text(text: str) -> Artifact:
        """Best-effort parse of an Artifact from unstructured text."""
        try:
            # Try to extract JSON from the response.
            import re

            match = re.search(r"\{.*\}", text, re.DOTALL)
            if match:
                data = json.loads(match.group(0))
                return Artifact.model_validate(data)
        except Exception:
            pass
        # Ultimate fallback: treat the whole text as content.
        return Artifact(content=text, reasoning="", confidence=0.5)

    @staticmethod
    def _parse_verdict_from_text(text: str) -> Verdict:
        """Best-effort parse of a Verdict from unstructured text."""
        try:
            import re

            match = re.search(r"\{.*\}", text, re.DOTALL)
            if match:
                data = json.loads(match.group(0))
                return Verdict.model_validate(data)
        except Exception:
            pass
        # Ultimate fallback: neutral verdict.
        return Verdict(score=0.5, issues=[], is_blocking=False)
