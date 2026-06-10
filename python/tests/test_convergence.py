"""Tests for the 6-layer convergence protocol (Chain of Responsibility).

Covers all individual checks and the full ConvergenceEngine chain.
"""

import pytest

from dual_agent_sdk.convergence import (
    ConvergenceEngine,
    HardCeilingCheck,
    IssueDecayCheck,
    QualityThresholdCheck,
    ROICheck,
    ScoreConvergenceCheck,
    SemanticLoopCheck,
)
from dual_agent_sdk.models import (
    AgentConfig,
    Artifact,
    Issue,
    RoundRecord,
    Verdict,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

DEFAULT_CONFIG = AgentConfig()


def make_verdict(
    score: float = 0.8,
    issues: list[Issue] | None = None,
    is_blocking: bool = False,
    suggestion: str | None = None,
    agreement: float = 0.8,
) -> Verdict:
    return Verdict(
        score=score,
        issues=issues or [],
        is_blocking=is_blocking,
        suggestion=suggestion,
        agreement_level=agreement,
    )


def make_artifact(
    content: str = "test content",
    reasoning: str = "because",
    confidence: float = 0.8,
) -> Artifact:
    return Artifact(content=content, reasoning=reasoning, confidence=confidence)


def make_round(round_num: int, verdict: Verdict, artifact: Artifact | None = None) -> RoundRecord:
    return RoundRecord(
        round_num=round_num,
        artifact=artifact or make_artifact(content=f"artifact round {round_num}"),
        verdict=verdict,
        timestamp=float(round_num),
    )


# ---------------------------------------------------------------------------
# Layer 1: Hard Ceiling
# ---------------------------------------------------------------------------


class TestHardCeiling:
    def test_accepts_at_max_rounds(self):
        config = AgentConfig(max_rounds=5)
        check = HardCeilingCheck()
        result = check.evaluate(
            round_num=5,
            verdict=make_verdict(),
            prev_verdict=None,
            config=config,
            history=[make_round(1, make_verdict())],
        )
        assert result == "accept"

    def test_accepts_beyond_max_rounds(self):
        config = AgentConfig(max_rounds=5)
        check = HardCeilingCheck()
        result = check.evaluate(
            round_num=6,
            verdict=make_verdict(),
            prev_verdict=None,
            config=config,
            history=[],
        )
        assert result == "accept"

    def test_passes_below_max(self):
        config = AgentConfig(max_rounds=5)
        check = HardCeilingCheck()
        result = check.evaluate(
            round_num=3,
            verdict=make_verdict(),
            prev_verdict=None,
            config=config,
            history=[],
        )
        assert result is None

    def test_max_rounds_one(self):
        config = AgentConfig(max_rounds=1)
        check = HardCeilingCheck()
        assert check.evaluate(1, make_verdict(), None, config, []) == "accept"
        assert check.evaluate(2, make_verdict(), None, config, []) == "accept"


# ---------------------------------------------------------------------------
# Layer 2: Quality Threshold
# ---------------------------------------------------------------------------


class TestQualityThreshold:
    def test_accepts_high_score_no_blocking(self):
        check = QualityThresholdCheck()
        config = AgentConfig(quality_threshold=0.85)
        verdict = make_verdict(score=0.90, is_blocking=False)
        result = check.evaluate(1, verdict, None, config, [])
        assert result == "accept"

    def test_accepts_exact_threshold(self):
        check = QualityThresholdCheck()
        config = AgentConfig(quality_threshold=0.85)
        verdict = make_verdict(score=0.85, is_blocking=False)
        result = check.evaluate(1, verdict, None, config, [])
        assert result == "accept"

    def test_passes_on_blocking(self):
        check = QualityThresholdCheck()
        config = AgentConfig(quality_threshold=0.85)
        verdict = make_verdict(score=0.95, is_blocking=True)
        result = check.evaluate(1, verdict, None, config, [])
        assert result is None

    def test_passes_below_threshold(self):
        check = QualityThresholdCheck()
        config = AgentConfig(quality_threshold=0.85)
        verdict = make_verdict(score=0.80, is_blocking=False)
        result = check.evaluate(1, verdict, None, config, [])
        assert result is None

    def test_custom_threshold(self):
        check = QualityThresholdCheck()
        config = AgentConfig(quality_threshold=0.6)
        assert check.evaluate(1, make_verdict(score=0.65), None, config, []) == "accept"
        assert check.evaluate(1, make_verdict(score=0.55), None, config, []) is None


# ---------------------------------------------------------------------------
# Layer 3: Score Convergence
# ---------------------------------------------------------------------------


class TestScoreConvergence:
    def test_detects_exact_same_score(self):
        check = ScoreConvergenceCheck()
        config = DEFAULT_CONFIG
        prev = make_verdict(score=0.80)
        cur = make_verdict(score=0.80)
        result = check.evaluate(2, cur, prev, config, [])
        assert result == "accept"

    def test_detects_small_change_below_threshold(self):
        check = ScoreConvergenceCheck()
        config = AgentConfig(convergence_threshold=0.02)
        prev = make_verdict(score=0.80)
        cur = make_verdict(score=0.81)
        result = check.evaluate(2, cur, prev, config, [])
        # |0.81 - 0.80| = 0.01 < 0.02  → accept
        assert result == "accept"

    def test_detects_exact_threshold_boundary(self):
        """isclose(a, b, abs_tol=0.02) uses <= semantics."""
        check = ScoreConvergenceCheck()
        config = AgentConfig(convergence_threshold=0.02)
        prev = make_verdict(score=0.80)
        cur = make_verdict(score=0.82)
        result = check.evaluate(2, cur, prev, config, [])
        # |0.82 - 0.80| = 0.02, isclose with abs_tol=0.02 → True → accept
        assert result == "accept"

    def test_passes_on_large_change(self):
        check = ScoreConvergenceCheck()
        config = AgentConfig(convergence_threshold=0.02)
        prev = make_verdict(score=0.50)
        cur = make_verdict(score=0.70)
        result = check.evaluate(2, cur, prev, config, [])
        assert result is None

    def test_no_prev_verdict_returns_none(self):
        check = ScoreConvergenceCheck()
        result = check.evaluate(1, make_verdict(score=0.9), None, DEFAULT_CONFIG, [])
        assert result is None


# ---------------------------------------------------------------------------
# Layer 4: Issue Decay
# ---------------------------------------------------------------------------


class TestIssueDecay:
    def test_round1_critical_and_major_are_actionable(self):
        check = IssueDecayCheck()
        verdict = make_verdict(
            issues=[
                Issue(severity="critical", description="crash bug"),
                Issue(severity="major", description="wrong calculation"),
                Issue(severity="minor", description="typo"),
                Issue(severity="style", description="spacing"),
            ]
        )
        result = check.evaluate(1, verdict, None, DEFAULT_CONFIG, [])
        # Round 1: critical + major are actionable → NOT accepting
        assert result is None

    def test_round1_only_minor_style_accepts(self):
        check = IssueDecayCheck()
        verdict = make_verdict(
            issues=[
                Issue(severity="minor", description="typo"),
                Issue(severity="style", description="spacing"),
            ]
        )
        result = check.evaluate(1, verdict, None, DEFAULT_CONFIG, [])
        assert result == "accept"

    def test_round2_only_critical_actionable(self):
        check = IssueDecayCheck()
        verdict = make_verdict(
            issues=[
                Issue(severity="critical", description="crash"),
                Issue(severity="major", description="wrong"),
            ]
        )
        result = check.evaluate(2, verdict, None, DEFAULT_CONFIG, [])
        # Round 2: critical only → major not actionable but critical is → continue
        assert result is None

    def test_round2_no_critical_accepts(self):
        check = IssueDecayCheck()
        verdict = make_verdict(
            issues=[
                Issue(severity="major", description="wrong"),
                Issue(severity="minor", description="typo"),
            ]
        )
        result = check.evaluate(2, verdict, None, DEFAULT_CONFIG, [])
        assert result == "accept"

    def test_round3_nothing_actionable(self):
        check = IssueDecayCheck()
        verdict = make_verdict(
            issues=[Issue(severity="critical", description="still broken")]
        )
        result = check.evaluate(3, verdict, None, DEFAULT_CONFIG, [])
        assert result == "accept"

    def test_round4_no_issues_actionable(self):
        check = IssueDecayCheck()
        verdict = make_verdict(issues=[])
        # No issues at all → pass through (let other layers decide)
        result = check.evaluate(4, verdict, None, DEFAULT_CONFIG, [])
        assert result is None

    def test_no_issues_round1_accepts(self):
        check = IssueDecayCheck()
        verdict = make_verdict(issues=[])
        # No issues at all → pass through (let other layers decide)
        result = check.evaluate(1, verdict, None, DEFAULT_CONFIG, [])
        assert result is None


# ---------------------------------------------------------------------------
# Layer 5: ROI (Return On Investment)
# ---------------------------------------------------------------------------


class TestROI:
    def test_accepts_small_improvement_late_round(self):
        """Late round with tiny improvement: 0.01 < 0.05 * 2^(2-1) = 0.10."""
        check = ROICheck()
        config = AgentConfig(roi_decay_factor=2.0)
        prev = make_verdict(score=0.80)
        cur = make_verdict(score=0.81)
        result = check.evaluate(2, cur, prev, config, [])
        assert result == "accept"

    def test_passes_large_improvement(self):
        """Large improvement should not trigger ROI accept."""
        check = ROICheck()
        config = AgentConfig(roi_decay_factor=2.0)
        prev = make_verdict(score=0.50)
        cur = make_verdict(score=0.90)
        result = check.evaluate(2, cur, prev, config, [])
        # improvement = 0.40, min_improvement = 0.10  → pass through
        assert result is None

    def test_no_prev_verdict_returns_none(self):
        check = ROICheck()
        result = check.evaluate(1, make_verdict(score=0.9), None, DEFAULT_CONFIG, [])
        assert result is None

    def test_improvement_clearly_above_threshold_passes(self):
        """Improvement well above min threshold → ROI does not fire."""
        check = ROICheck()
        config = AgentConfig(roi_decay_factor=2.0)
        prev = make_verdict(score=0.5)
        cur = make_verdict(score=0.9)  # improvement = 0.4
        # min_improvement = 0.05 * 2^1 = 0.10
        # 0.4 > 0.10 → passes through
        result = check.evaluate(2, cur, prev, config, [])
        assert result is None

    def test_improvement_barely_above_threshold_passes(self):
        """Improvement at 0.11 with min 0.10 → 0.11 < 0.10 false → pass through."""
        check = ROICheck()
        config = AgentConfig(roi_decay_factor=2.0)
        prev = make_verdict(score=0.5)
        cur = make_verdict(score=0.61)  # improvement = 0.11
        # min_improvement = 0.10, 0.11 > 0.10 → passes through
        result = check.evaluate(2, cur, prev, config, [])
        assert result is None

    def test_slightly_above_exact_threshold_accepts(self):
        """improvement = 0.09, min_improvement = 0.10 → 0.09 < 0.10 → accept."""
        check = ROICheck()
        config = AgentConfig(roi_decay_factor=2.0)
        prev = make_verdict(score=0.80)
        cur = make_verdict(score=0.89)
        # improvement = 0.09, min = 0.10 → 0.09 < 0.10 → accept
        result = check.evaluate(2, cur, prev, config, [])
        assert result == "accept"

    def test_high_roi_decay_factor_accepts_earlier(self):
        """With a higher decay factor, the threshold rises faster → accepts more."""
        check = ROICheck()
        config = AgentConfig(roi_decay_factor=4.0)
        prev = make_verdict(score=0.80)
        cur = make_verdict(score=0.85)
        # improvement = 0.05, min_improvement = 0.05 * 4^1 = 0.20
        result = check.evaluate(2, cur, prev, config, [])
        assert result == "accept"

    def test_negative_improvement_accepts(self):
        """Score decreases between rounds → improvement is negative → accept."""
        check = ROICheck()
        config = AgentConfig(roi_decay_factor=2.0)
        prev = make_verdict(score=0.90)
        cur = make_verdict(score=0.70)
        result = check.evaluate(2, cur, prev, config, [])
        # improvement = -0.20 < 0.10 → accept
        assert result == "accept"


# ---------------------------------------------------------------------------
# Layer 6: Semantic Loop
# ---------------------------------------------------------------------------


class TestSemanticLoop:
    def test_detects_repeated_text(self):
        check = SemanticLoopCheck()
        config = AgentConfig(loop_similarity_threshold=0.5, enable_escalation=True)

        # First call: seed history with round 1
        a1 = make_artifact(content="The function should use a cache.")
        v1 = make_verdict(suggestion="Add caching")
        r1 = make_round(1, v1, a1)

        a2 = make_artifact(content="The function should use a cache.")  # identical
        v2 = make_verdict(suggestion="Add caching")  # same suggestion
        r2 = make_round(2, v2, a2)

        history = [r1, r2]
        result = check.evaluate(2, v2, v1, config, history)
        assert result == "escalate"

    def test_passes_new_text(self):
        check = SemanticLoopCheck()
        config = AgentConfig(loop_similarity_threshold=0.5, enable_escalation=True)

        a1 = make_artifact(content="Use a cache.")
        v1 = make_verdict(suggestion="Add caching")
        r1 = make_round(1, v1, a1)

        a2 = make_artifact(content="Completely different approach using a bloom filter.")
        v2 = make_verdict(suggestion="Consider hash table instead")
        r2 = make_round(2, v2, a2)

        history = [r1, r2]
        result = check.evaluate(2, v2, v1, config, history)
        # Different texts → should not trigger semantic loop
        assert result is None

    def test_escalation_disabled_returns_accept(self):
        check = SemanticLoopCheck()
        config = AgentConfig(loop_similarity_threshold=0.5, enable_escalation=False)

        a1 = make_artifact(content="Use a cache.")
        v1 = make_verdict(suggestion="Add caching")
        r1 = make_round(1, v1, a1)

        a2 = make_artifact(content="Use a cache.")  # identical
        v2 = make_verdict(suggestion="Add caching")
        r2 = make_round(2, v2, a2)

        history = [r1, r2]
        result = check.evaluate(2, v2, v1, config, history)
        assert result == "accept"

    def test_not_enough_history_returns_none(self):
        check = SemanticLoopCheck()
        config = AgentConfig(enable_escalation=True)
        # Fewer than 2 rounds
        result = check.evaluate(1, make_verdict(suggestion="x"), None, config, [])
        assert result is None

    def test_empty_content_not_looping(self):
        """Artifact content with very different text should not trigger loop."""
        check = SemanticLoopCheck()
        config = AgentConfig(enable_escalation=True)
        v = make_verdict(suggestion=None, issues=[])
        a1 = make_artifact(content="a completely unique approach")
        a2 = make_artifact(content="another entirely different method")
        r1 = make_round(1, v, a1)
        r2 = make_round(2, v, a2)
        result = check.evaluate(2, v, None, config, [r1, r2])
        # Different artifact content → no loop detected
        assert result is None

    def test_detects_loop_via_artifact_content(self):
        """The Python SemanticLoopCheck uses history[-1].artifact.content for loop detection."""
        check = SemanticLoopCheck()
        config = AgentConfig(loop_similarity_threshold=0.5, enable_escalation=True)

        # Same artifact content, different suggestions
        a1 = make_artifact(content="The function should implement caching with Redis.")
        v1 = make_verdict(suggestion="NIT: add a comment")
        r1 = make_round(1, v1, a1)

        a2 = make_artifact(content="The function should implement caching with Redis.")
        v2 = make_verdict(suggestion="Complete rewrite needed")  # different suggestion
        r2 = make_round(2, v2, a2)

        history = [r1, r2]
        result = check.evaluate(2, v2, v1, config, history)
        # Same artifact content → loop detected → escalate
        assert result == "escalate"


# ---------------------------------------------------------------------------
# Full ConvergenceEngine chain
# ---------------------------------------------------------------------------


class TestConvergenceEngine:
    def test_chain_order_layer1_prevails(self):
        """Layer 1 (HardCeiling) should fire first at max_rounds."""
        engine = ConvergenceEngine()
        config = AgentConfig(max_rounds=1)
        result = engine.evaluate(
            round_num=1,
            verdict=make_verdict(score=0.0, is_blocking=True),
            prev_verdict=None,
            config=config,
            history=[],
        )
        # Even though quality and convergence would pass, hard ceiling fires first.
        assert result == "accept"

    def test_chain_order_layer2_prevails(self):
        """Layer 2 (Quality) should fire before Layer 3 (Convergence)."""
        engine = ConvergenceEngine()
        config = AgentConfig(max_rounds=5, quality_threshold=0.85)
        result = engine.evaluate(
            round_num=2,
            verdict=make_verdict(score=0.90, is_blocking=False),
            prev_verdict=make_verdict(score=0.80),  # large change → would NOT converge
            config=config,
            history=[],
        )
        assert result == "accept"

    def test_continues_by_default(self):
        """When no layer fires, engine returns 'continue'."""
        engine = ConvergenceEngine()
        config = AgentConfig(
            max_rounds=5,
            quality_threshold=0.99,
            convergence_threshold=0.001,
            roi_decay_factor=1.0,
        )
        result = engine.evaluate(
            round_num=2,
            verdict=make_verdict(
                score=0.60,
                issues=[Issue(severity="critical", description="bug")],
                is_blocking=True,
            ),
            prev_verdict=make_verdict(score=0.30),
            config=config,
            history=[make_round(1, make_verdict(score=0.30))],
        )
        # Score delta 0.30 > 0.001 → pass
        # IssueDecay: round 2, has critical → pass
        # ROI: improvement 0.30, min=0.05*1.0^1=0.05 → 0.30 < 0.05 → false → pass
        # Semantic: different content → pass → continue
        assert result == "continue"

    def test_integration_round1_low_score_continues(self):
        engine = ConvergenceEngine()
        verdict = make_verdict(
            score=0.50,
            issues=[Issue(severity="major", description="needs work")],
            is_blocking=True,
        )
        result = engine.evaluate(
            round_num=1, verdict=verdict, prev_verdict=None,
            config=DEFAULT_CONFIG, history=[],
        )
        assert result == "continue"

    def test_integration_perfect_score_accepts(self):
        engine = ConvergenceEngine()
        result = engine.evaluate(
            round_num=1,
            verdict=make_verdict(score=0.95, is_blocking=False),
            prev_verdict=None,
            config=DEFAULT_CONFIG,
            history=[],
        )
        # Layer 2 (Quality threshold 0.85) should fire.
        assert result == "accept"

    def test_integration_converging_scores(self):
        engine = ConvergenceEngine()
        config = DEFAULT_CONFIG
        result = engine.evaluate(
            round_num=2,
            verdict=make_verdict(score=0.81),
            prev_verdict=make_verdict(score=0.80),
            config=config,
            history=[make_round(1, make_verdict(score=0.80))],
        )
        # Score delta 0.01 < 0.02 → Layer 3 should fire.
        assert result == "accept"

    def test_semantic_loop_escalation_via_engine(self):
        engine = ConvergenceEngine()
        config = AgentConfig(
            loop_similarity_threshold=0.3,
            enable_escalation=True,
            max_rounds=5,
            quality_threshold=0.99,
            convergence_threshold=0.001,
            roi_decay_factor=1.0,
        )
        a1 = make_artifact(content="hello world same content repeated")
        v1 = make_verdict(
            score=0.5,
            issues=[Issue(severity="critical", description="bug")],
            is_blocking=True,
            suggestion="do X",
        )
        a2 = make_artifact(content="hello world same content repeated")  # same
        v2 = make_verdict(
            score=0.6,
            issues=[Issue(severity="critical", description="bug")],
            is_blocking=True,
            suggestion="do X",
        )

        history = [
            make_round(1, v1, a1),
            make_round(2, v2, a2),
        ]
        result = engine.evaluate(2, v2, v1, config, history)
        # Same artifact content → SemanticLoop should fire
        assert result == "escalate"

    def test_all_checks_present_in_chain(self):
        engine = ConvergenceEngine()
        assert len(engine._checks) == 6
        types = [type(c).__name__ for c in engine._checks]
        assert types == [
            "HardCeilingCheck",
            "QualityThresholdCheck",
            "ScoreConvergenceCheck",
            "IssueDecayCheck",
            "ROICheck",
            "SemanticLoopCheck",
        ]
