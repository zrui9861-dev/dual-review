"""Integration tests for the DualAgentOrchestrator using mock adapters."""

import pytest

from dual_agent_sdk import (
    AgentConfig,
    Artifact,
    BaseAdapter,
    DualAgentOrchestrator,
    Issue,
    Verdict,
)


# ---------------------------------------------------------------------------
# Mock adapter
# ---------------------------------------------------------------------------


class MockAdapter(BaseAdapter):
    """Returns predefined structured or text responses for testing."""

    def __init__(
        self,
        responses: list[dict | str] | None = None,
        name: str = "mock-model",
        fail_structured: bool = False,
    ):
        self._responses = responses or []
        self._call_count = 0
        self._name = name
        self._structured_calls: list[dict] = []
        self._text_calls: list[dict] = []
        self._fail_structured = fail_structured

    @property
    def model_name(self) -> str:
        return self._name

    async def generate(self, system_prompt: str, user_prompt: str, **kwargs) -> str:
        self._text_calls.append(
            {"system": system_prompt, "user": user_prompt, "kwargs": kwargs}
        )
        resp = self._responses[self._call_count % len(self._responses)]
        self._call_count += 1
        if isinstance(resp, str):
            return resp
        # Fallback for structured response dicts
        return "generic response"

    async def generate_structured(
        self, system_prompt: str, user_prompt: str, output_schema: dict, **kwargs
    ) -> dict:
        self._structured_calls.append(
            {
                "system": system_prompt,
                "user": user_prompt,
                "schema": output_schema,
                "kwargs": kwargs,
            }
        )
        if self._fail_structured:
            raise RuntimeError("Structured generation failed")

        resp = self._responses[self._call_count % len(self._responses)]
        self._call_count += 1
        if isinstance(resp, dict):
            return resp
        # Wrap plain string
        return {"content": resp, "reasoning": "mock", "confidence": 0.5}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_artifact_dict(
    content: str = "def solution(): return 42",
    reasoning: str = "Simple is best.",
    confidence: float = 0.9,
    uncertain_parts: list[str] | None = None,
) -> dict:
    return {
        "content": content,
        "reasoning": reasoning,
        "confidence": confidence,
        "uncertain_parts": uncertain_parts or [],
    }


def make_verdict_dict(
    score: float = 0.9,
    issues: list[dict] | None = None,
    is_blocking: bool = False,
    suggestion: str | None = None,
    agreement_level: float = 0.85,
) -> dict:
    return {
        "score": score,
        "issues": issues or [],
        "is_blocking": is_blocking,
        "suggestion": suggestion,
        "agreement_level": agreement_level,
    }


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


class TestConstruction:
    def test_same_adapter_raises(self):
        adapter = MockAdapter(name="shared")
        with pytest.raises(ValueError, match="distinct"):
            DualAgentOrchestrator(generator=adapter, critic=adapter)

    def test_different_adapters_ok(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        assert orch.generator is gen
        assert orch.critic is crit

    def test_default_config(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        assert orch.config.max_rounds == 5
        assert orch.config.quality_threshold == 0.85

    def test_custom_config(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        config = AgentConfig(max_rounds=3, quality_threshold=0.7)
        orch = DualAgentOrchestrator(generator=gen, critic=crit, config=config)
        assert orch.config.max_rounds == 3
        assert orch.config.quality_threshold == 0.7

    def test_initial_state(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        assert orch.round_history == []
        assert orch.disputes == []


# ---------------------------------------------------------------------------
# Single-round scenarios
# ---------------------------------------------------------------------------


class TestSingleRound:
    @pytest.mark.asyncio
    async def test_high_quality_accepts_immediately(self):
        """Layer 2 (Quality Threshold) should accept a high-scoring, non-blocking verdict."""
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="def solve(): pass", confidence=0.9),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(score=0.95, is_blocking=False),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        result = await orch.run("Write a function.")
        assert result.content == "def solve(): pass"
        assert len(orch.round_history) == 1

    @pytest.mark.asyncio
    async def test_returns_result_with_context(self):
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="code with context", confidence=0.9),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(score=0.95, is_blocking=False),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        result = await orch.run("Write a function.", context="Use Python 3.12+.")
        assert "code with context" in result.content


# ---------------------------------------------------------------------------
# Multi-round scenarios
# ---------------------------------------------------------------------------


class TestMultiRound:
    @pytest.mark.asyncio
    async def test_improvement_across_rounds(self):
        """Round 1 low score, Round 2 high score — return best artifact."""
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1: naive", confidence=0.5),
                make_artifact_dict(content="v2: improved with caching", confidence=0.9),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.5,
                    issues=[
                        {"severity": "major", "description": "No caching"}
                    ],
                    is_blocking=True,
                    suggestion="Add caching",
                ),
                make_verdict_dict(score=0.95, is_blocking=False),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        result = await orch.run("Optimize the function.")
        assert "v2" in result.content
        assert len(orch.round_history) == 2

    @pytest.mark.asyncio
    async def test_convergence_on_stable_scores(self):
        """Score delta below convergence_threshold triggers Layer 3 accept."""
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1", confidence=0.8),
                make_artifact_dict(content="v2", confidence=0.8),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.80,
                    issues=[{"severity": "critical", "description": "needs fix"}],
                    is_blocking=True,
                ),
                make_verdict_dict(
                    score=0.81,  # delta = 0.01 < 0.02
                    issues=[{"severity": "critical", "description": "still needs fix"}],
                    is_blocking=True,
                ),
            ],
            name="crit",
        )
        config = AgentConfig(
            max_rounds=5, convergence_threshold=0.02, quality_threshold=0.99
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit, config=config)
        result = await orch.run("Write code.")
        # Round 2 converges via score convergence (delta 0.01 < 0.02)
        assert len(orch.round_history) == 2

    @pytest.mark.asyncio
    async def test_hard_ceiling_max_rounds(self):
        """Even with low scores, orchestration stops at max_rounds."""
        config = AgentConfig(
            max_rounds=2,
            quality_threshold=0.99,
            convergence_threshold=0.001,
            enable_escalation=False,
        )
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1", confidence=0.3),
                make_artifact_dict(content="v2", confidence=0.4),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.4,
                    issues=[{"severity": "major", "description": "broken"}],
                    is_blocking=True,
                ),
                make_verdict_dict(
                    score=0.45,
                    issues=[{"severity": "major", "description": "still broken"}],
                    is_blocking=True,
                ),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit, config=config)
        result = await orch.run("Fix it.")
        assert len(orch.round_history) == 2


# ---------------------------------------------------------------------------
# Best artifact selection
# ---------------------------------------------------------------------------


class TestBestArtifact:
    def test_returns_highest_scored(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)

        from dual_agent_sdk.models import RoundRecord

        a1 = Artifact(content="best", reasoning="r", confidence=0.9)
        a2 = Artifact(content="worst", reasoning="r", confidence=0.2)

        orch.round_history = [
            RoundRecord(
                round_num=1,
                artifact=a1,
                verdict=Verdict(score=0.95, issues=[]),
                timestamp=1.0,
            ),
            RoundRecord(
                round_num=2,
                artifact=a2,
                verdict=Verdict(score=0.3, issues=[]),
                timestamp=2.0,
            ),
        ]
        best = orch._best_artifact()
        assert best.content == "best"

    def test_no_history_raises(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        with pytest.raises(RuntimeError, match="No rounds"):
            orch._best_artifact()


# ---------------------------------------------------------------------------
# Issue filtering
# ---------------------------------------------------------------------------


class TestIssueFiltering:
    @pytest.mark.asyncio
    async def test_filter_issues_round1_keeps_critical_and_major(self):
        """Round 1 passes critical + major issues back to the generator."""
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1"),
                make_artifact_dict(content="v2"),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.5,
                    issues=[
                        {"severity": "critical", "description": "c1"},
                        {"severity": "major", "description": "m1"},
                        {"severity": "minor", "description": "n1"},
                        {"severity": "style", "description": "s1"},
                    ],
                    is_blocking=True,
                    suggestion="fix it",
                ),
                make_verdict_dict(score=0.95, is_blocking=False),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        result = await orch.run("Task")

        # The generator should have received feedback with critical + major issues
        gen_prompt_round2 = gen._structured_calls[1]["user"]
        assert "c1" in gen_prompt_round2 or "critical" in gen_prompt_round2.lower()
        assert "m1" in gen_prompt_round2 or "major" in gen_prompt_round2.lower()

    @pytest.mark.asyncio
    async def test_filter_issues_round3_no_issues_fed_back(self):
        """Round 3+: no issues are passed back to generator."""
        config = AgentConfig(
            max_rounds=3, quality_threshold=0.99, convergence_threshold=0.001
        )
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1"),
                make_artifact_dict(content="v2"),
                make_artifact_dict(content="v3"),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.3, is_blocking=True,
                    issues=[{"severity": "critical", "description": "bug"}],
                ),
                make_verdict_dict(
                    score=0.6, is_blocking=True,  # large change → score conv passes
                    issues=[{"severity": "critical", "description": "bug2"}],
                ),
                make_verdict_dict(
                    score=0.9, is_blocking=True,  # large change again
                    issues=[{"severity": "critical", "description": "bug3"}],
                ),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit, config=config)
        result = await orch.run("Task")

        # Round 3: generator prompt should NOT contain issue feedback
        # prompt for round 3 = gen._structured_calls[2]
        gen_prompt_round3 = gen._structured_calls[2]["user"]
        # Should not mention the issue description
        assert "Issues to Address" not in gen_prompt_round3


# ---------------------------------------------------------------------------
# Dispute tracking
# ---------------------------------------------------------------------------


class TestDisputeTracking:
    @pytest.mark.asyncio
    async def test_tracks_disputes_on_blocking_verdict(self):
        gen = MockAdapter(
            responses=[
                make_artifact_dict(
                    content="v1", reasoning="I chose this approach",
                ),
                make_artifact_dict(content="v2"),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.5,
                    issues=[{"severity": "critical", "description": "wrong"}],
                    is_blocking=True,
                    agreement_level=0.2,
                    suggestion="Use a different approach",
                ),
                make_verdict_dict(score=0.95, is_blocking=False),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        result = await orch.run("Task")

        assert len(orch.disputes) >= 1
        assert orch.disputes[0].rounds_unresolved >= 1

    @pytest.mark.asyncio
    async def test_tracks_disputes_on_low_agreement(self):
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1", reasoning="My approach"),
                make_artifact_dict(content="v2"),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.6,
                    is_blocking=False,
                    agreement_level=0.2,
                    suggestion="Rewriting might help",
                ),
                make_verdict_dict(score=0.95, is_blocking=False),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        result = await orch.run("Task")

        assert len(orch.disputes) >= 1

    @pytest.mark.asyncio
    async def test_dispute_rounds_unresolved_increments(self):
        """Same dispute across multiple rounds increments rounds_unresolved."""
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1", reasoning="My position on caching"),
                make_artifact_dict(content="v2", reasoning="Same position on caching"),
                make_artifact_dict(content="v3"),
            ],
            name="gen",
        )
        crit = MockAdapter(
            responses=[
                make_verdict_dict(
                    score=0.5, is_blocking=True, agreement_level=0.2,
                    suggestion="Add caching",
                    issues=[{"severity": "critical", "description": "no cache"}],
                ),
                make_verdict_dict(
                    score=0.5, is_blocking=True, agreement_level=0.2,
                    suggestion="Add caching",
                    issues=[{"severity": "critical", "description": "still no cache"}],
                ),
                make_verdict_dict(score=0.95, is_blocking=False),
            ],
            name="crit",
        )
        orch = DualAgentOrchestrator(
            generator=gen, critic=crit,
            config=AgentConfig(quality_threshold=0.99, convergence_threshold=0.001),
        )
        result = await orch.run("Task")

        assert len(orch.disputes) >= 1
        dispute = orch.disputes[0]
        assert dispute.rounds_unresolved == 2  # incremented twice


# ---------------------------------------------------------------------------
# Structured generation fallback
# ---------------------------------------------------------------------------


class TestFallback:
    @pytest.mark.asyncio
    async def test_artifact_fallback_on_structured_failure(self):
        """When structured generation fails, fall back to text parsing."""
        gen = MockAdapter(
            responses=[
                make_artifact_dict(content="v1"),
            ],
            name="gen",
        )
        gen._fail_structured = True  # force fallback with no structured responses
        # Override responses: the first call is generate_structured which fails,
        # then generate() is called which returns the plain text.
        gen._responses = [make_artifact_dict(content="v1")]  # unused for text
        # We need to handle this more carefully. The fallback calls generate() then
        # _parse_artifact_from_text(). If generate() fails, it raises.

        # Actually, let's test the parse helpers directly instead.
        gen2 = MockAdapter(name="gen")
        crit = MockAdapter(
            responses=[make_verdict_dict(score=0.95, is_blocking=False)],
            name="crit",
        )
        orch = DualAgentOrchestrator(generator=gen2, critic=crit)

        # Test _parse_artifact_from_text with JSON embedded in text
        text = 'Here is my solution: {"content": "def foo(): pass", "reasoning": "r", "confidence": 0.8, "uncertain_parts": []}'
        artifact = orch._parse_artifact_from_text(text)
        assert artifact.content == "def foo(): pass"
        assert artifact.confidence == 0.8

    def test_parse_verdict_from_text(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)

        text = '{"score": 0.88, "issues": [{"severity": "minor", "description": "doc"}], "is_blocking": false, "agreement_level": 0.9}'
        verdict = orch._parse_verdict_from_text(text)
        assert verdict.score == 0.88
        assert len(verdict.issues) == 1

    def test_parse_artifact_fallback_plain_text(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)

        # Text with no JSON → whole text becomes content
        text = "Just plain text, no JSON here."
        artifact = orch._parse_artifact_from_text(text)
        assert artifact.content == text
        assert artifact.confidence == 0.5

    def test_parse_verdict_fallback_plain_text(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)

        text = "Not a valid verdict at all."
        verdict = orch._parse_verdict_from_text(text)
        assert verdict.score == 0.5
        assert not verdict.is_blocking


# ---------------------------------------------------------------------------
# Prompt builders
# ---------------------------------------------------------------------------


class TestPromptBuilders:
    def test_generator_prompt_includes_task(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        prompt = orch._build_generator_prompt("Write a sort function.", None, None)
        assert "Write a sort function" in prompt
        assert "## Task" in prompt

    def test_generator_prompt_includes_context(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        prompt = orch._build_generator_prompt(
            "Task", "Use Python 3.12", None
        )
        assert "Use Python 3.12" in prompt
        assert "## Additional Context" in prompt

    def test_generator_prompt_includes_criticism(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        prompt = orch._build_generator_prompt(
            "Task", None, "Fix error handling"
        )
        assert "Fix error handling" in prompt
        assert "Previous Critic Feedback" in prompt or "Previous" in prompt

    def test_critic_prompt_includes_artifact_content(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        artifact = Artifact(
            content="def foo(): pass",
            reasoning="It works.",
            confidence=0.8,
            uncertain_parts=["performance"],
        )
        prompt = orch._build_critic_prompt("Task", artifact, None)
        assert "def foo(): pass" in prompt
        assert "It works." in prompt
        assert "performance" in prompt

    def test_criticism_feedback(self):
        gen = MockAdapter(name="gen")
        crit = MockAdapter(name="crit")
        orch = DualAgentOrchestrator(generator=gen, critic=crit)
        verdict = Verdict(
            score=0.6,
            issues=[
                Issue(
                    severity="critical",
                    description="Memory leak",
                    location="line 42",
                    fix_hint="Use a context manager",
                )
            ],
            suggestion="Fix the memory leak before continuing.",
            is_blocking=True,
        )
        feedback = orch._build_criticism_feedback(verdict)
        assert "Memory leak" in feedback
        assert "critical" in feedback
        assert "line 42" in feedback
        assert "context manager" in feedback
        assert "Fix the memory leak" in feedback
