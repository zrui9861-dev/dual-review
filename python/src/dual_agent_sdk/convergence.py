"""6-layer convergence protocol (Chain of Responsibility).

Implements :class:`ConvergenceEngine`, which chains six ordered checks to
determine whether the Generator-Critic loop should accept the current
artifact, continue iterating, or escalate a deadlock.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from math import isclose
from typing import Optional

from .loop_detector import SemanticLoopDetector
from .models import AgentConfig, Decision, RoundRecord, Verdict


# ======================================================================
# Individual convergence checks
# ======================================================================

class ConvergenceCheck(ABC):
    """Abstract base for a single convergence rule.

    Each concrete check is a link in the Chain of Responsibility.  It
    receives the full round context and returns a :class:`Decision` or
    ``None`` to pass control to the next check.
    """

    @abstractmethod
    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision | None:
        """Evaluate this check.

        Returns:
            A decision if this check resolves the round, or ``None`` to
            fall through to the next check in the chain.
        """
        ...


class HardCeilingCheck(ConvergenceCheck):
    """**Layer 1** -- Hard round cap.

    If the current round number has reached *max_rounds* the loop must
    terminate, returning ``"accept"`` (the best artifact so far).
    """

    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision | None:
        if round_num >= config.max_rounds:
            return "accept"
        return None


class QualityThresholdCheck(ConvergenceCheck):
    """**Layer 2** -- Quality gate.

    Accepts immediately when *verdict.score* >= *config.quality_threshold*
    AND there are no blocking issues.
    """

    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision | None:
        if verdict.score >= config.quality_threshold and not verdict.is_blocking:
            return "accept"
        return None


class ScoreConvergenceCheck(ConvergenceCheck):
    """**Layer 3** -- Score delta.

    Accepts when the absolute score change between successive rounds is
    smaller than *config.convergence_threshold* (diminishing returns).
    """

    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision | None:
        if prev_verdict is None:
            return None
        if isclose(verdict.score, prev_verdict.score, abs_tol=config.convergence_threshold):
            return "accept"
        return None


class IssueDecayCheck(ConvergenceCheck):
    """**Layer 4** -- Severity-based issue filter.

    Gradually narrows the set of actionable issue severities so that
    later rounds only address critical problems:

    * Round 1  → *critical* + *major*
    * Round 2  → *critical* only
    * Round 3+ → no issues are actionable → accept

    When there are no issues at all, this check passes through (None)
    so other layers (e.g. SemanticLoopCheck) can still evaluate.
    """

    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision | None:
        # No issues at all → let other layers decide
        if not verdict.issues:
            return None

        if round_num == 1:
            allowed = {"critical", "major"}
        elif round_num == 2:
            allowed = {"critical"}
        else:
            # Round 3+: no issue severity is actionable
            return "accept"

        actionable = [i for i in verdict.issues if i.severity in allowed]
        if not actionable:
            return "accept"
        return None


class ROICheck(ConvergenceCheck):
    """**Layer 5** -- Return-on-investment / diminishing returns.

    Accepts when the improvement from the previous round to the current
    round is less than ``0.05 * (roi_decay_factor ** (round_num - 1))``.
    This means the bar for "meaningful improvement" rises exponentially
    across rounds, preventing marginal gains from extending the loop.

    Uses rounding to avoid floating-point precision issues at boundary values.
    """

    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision | None:
        if prev_verdict is None:
            return None
        # Round to 10 decimal places to avoid floating-point noise
        improvement = round(verdict.score - prev_verdict.score, 10)
        min_improvement = round(0.05 * (config.roi_decay_factor ** (round_num - 1)), 10)
        if improvement <= min_improvement:
            return "accept"
        return None


class SemanticLoopCheck(ConvergenceCheck):
    """**Layer 6** -- Semantic repetition detection.

    Uses :class:`SemanticLoopDetector` to detect if the generator is
    producing near-identical output across rounds.  When a loop is
    detected the result is ``"escalate"`` (if enabled in config) so a
    meta-judge can break the tie.
    """

    def __init__(self) -> None:
        super().__init__()
        self._detector: Optional[SemanticLoopDetector] = None

    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision | None:
        # Need at least two rounds to detect a semantic loop.
        if len(history) < 2:
            return None

        # Create a fresh detector per evaluation to avoid
        # accumulating duplicate seeds across repeated calls.
        detector = SemanticLoopDetector(
            threshold=config.loop_similarity_threshold,
            window_size=3,
        )

        # Seed the detector with all prior rounds (not the current one).
        for prior in history[:-1]:
            detector.add(prior.artifact.content)

        # Check the current round against the window of prior rounds.
        current_content = history[-1].artifact.content
        if detector.is_looping(current_content):
            return "escalate" if config.enable_escalation else "accept"

        return None


# ======================================================================
# Chain-of-Responsibility engine
# ======================================================================

class ConvergenceEngine:
    """Orchestrates the six convergence checks in priority order.

    Usage::

        engine = ConvergenceEngine()
        decision = engine.evaluate(round_num, verdict, prev_verdict,
                                   config, history)
    """

    def __init__(self) -> None:
        self._checks: list[ConvergenceCheck] = [
            HardCeilingCheck(),
            QualityThresholdCheck(),
            ScoreConvergenceCheck(),
            IssueDecayCheck(),
            ROICheck(),
            SemanticLoopCheck(),
        ]

    def evaluate(
        self,
        round_num: int,
        verdict: Verdict,
        prev_verdict: Verdict | None,
        config: AgentConfig,
        history: list[RoundRecord],
    ) -> Decision:
        """Run the chain and return the first non-``None`` decision.

        If every check returns ``None`` the engine defaults to
        ``"continue"``, meaning another round is warranted.
        """
        for check in self._checks:
            decision = check.evaluate(round_num, verdict, prev_verdict, config, history)
            if decision is not None:
                return decision
        return "continue"
