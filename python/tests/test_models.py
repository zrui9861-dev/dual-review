"""Test Pydantic models validation and serialization."""

import json

import pytest
from pydantic import ValidationError

from dual_agent_sdk.models import (
    AgentConfig,
    Artifact,
    DisputeRecord,
    Issue,
    RoundRecord,
    Verdict,
)


# ---------------------------------------------------------------------------
# Issue
# ---------------------------------------------------------------------------


class TestIssue:
    def test_creation(self):
        issue = Issue(
            severity="critical",
            description="The function has a SQL injection vulnerability.",
            location="line 42",
            fix_hint="Use parameterized queries.",
        )
        assert issue.severity == "critical"
        assert "SQL injection" in issue.description
        assert issue.location == "line 42"
        assert issue.fix_hint == "Use parameterized queries."

    def test_creation_minimal(self):
        issue = Issue(severity="minor", description="Use a longer variable name.")
        assert issue.severity == "minor"
        assert issue.description == "Use a longer variable name."
        assert issue.location is None
        assert issue.fix_hint is None

    def test_invalid_severity_raises(self):
        with pytest.raises(ValidationError):
            Issue(severity="catastrophic", description="boom")  # type: ignore[arg-type]

    def test_empty_description_accepted_by_default(self):
        # Pydantic str fields accept empty strings unless constrained
        issue = Issue(severity="major", description="")
        assert issue.description == ""

    def test_all_severities_accepted(self):
        for sev in ("critical", "major", "minor", "style"):
            issue = Issue(severity=sev, description="desc")
            assert issue.severity == sev


# ---------------------------------------------------------------------------
# Artifact
# ---------------------------------------------------------------------------


class TestArtifact:
    def test_creation(self):
        artifact = Artifact(
            content="def foo(): return 42",
            reasoning="Simple constant return is fine.",
            confidence=0.9,
            uncertain_parts=["edge-case handling"],
        )
        assert "def foo" in artifact.content
        assert artifact.reasoning == "Simple constant return is fine."
        assert artifact.confidence == 0.9
        assert artifact.uncertain_parts == ["edge-case handling"]

    def test_default_uncertain_parts(self):
        artifact = Artifact(content="x", reasoning="r", confidence=0.5)
        assert artifact.uncertain_parts == []

    def test_confidence_min_boundary(self):
        artifact = Artifact(content="x", reasoning="r", confidence=0.0)
        assert artifact.confidence == 0.0

    def test_confidence_max_boundary(self):
        artifact = Artifact(content="x", reasoning="r", confidence=1.0)
        assert artifact.confidence == 1.0

    def test_confidence_out_of_range_below_raises(self):
        with pytest.raises(ValidationError):
            Artifact(content="x", reasoning="r", confidence=-0.01)

    def test_confidence_out_of_range_above_raises(self):
        with pytest.raises(ValidationError):
            Artifact(content="x", reasoning="r", confidence=1.01)


# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------


class TestVerdict:
    def test_creation(self):
        verdict = Verdict(
            score=0.92,
            issues=[
                Issue(severity="minor", description="Missing docstring."),
            ],
            is_blocking=False,
            suggestion="Add a docstring.",
            agreement_level=0.85,
        )
        assert verdict.score == 0.92
        assert len(verdict.issues) == 1
        assert verdict.issues[0].severity == "minor"
        assert not verdict.is_blocking
        assert verdict.suggestion == "Add a docstring."
        assert verdict.agreement_level == 0.85

    def test_defaults(self):
        verdict = Verdict(score=0.7, issues=[])
        assert verdict.issues == []
        assert not verdict.is_blocking
        assert verdict.suggestion is None
        assert verdict.agreement_level == 0.0

    def test_score_range(self):
        for val in (0.0, 0.5, 1.0):
            v = Verdict(score=val, issues=[])
            assert v.score == val

    def test_score_out_of_range_raises(self):
        with pytest.raises(ValidationError):
            Verdict(score=1.5, issues=[])

    def test_agreement_level_out_of_range_raises(self):
        with pytest.raises(ValidationError):
            Verdict(score=0.5, issues=[], agreement_level=1.5)


# ---------------------------------------------------------------------------
# RoundRecord
# ---------------------------------------------------------------------------


class TestRoundRecord:
    def test_creation(self):
        artifact = Artifact(content="code", reasoning="r", confidence=0.8)
        verdict = Verdict(score=0.9, issues=[])
        record = RoundRecord(
            round_num=3,
            artifact=artifact,
            verdict=verdict,
            timestamp=1717000000.0,
        )
        assert record.round_num == 3
        assert record.artifact is artifact
        assert record.verdict is verdict
        assert record.timestamp == 1717000000.0

    def test_negative_round_num_accepted_by_default(self):
        # Pydantic int fields accept negative values unless constrained with ge
        record = RoundRecord(
            round_num=-1,
            artifact=Artifact(content="x", reasoning="r", confidence=0.5),
            verdict=Verdict(score=0.5, issues=[]),
            timestamp=0.0,
        )
        assert record.round_num == -1


# ---------------------------------------------------------------------------
# DisputeRecord
# ---------------------------------------------------------------------------


class TestDisputeRecord:
    def test_defaults(self):
        dispute = DisputeRecord(
            topic="Error handling strategy",
            generator_position="Return None",
            critic_position="Raise exception",
        )
        assert dispute.topic == "Error handling strategy"
        assert dispute.generator_position == "Return None"
        assert dispute.critic_position == "Raise exception"
        assert dispute.rounds_unresolved == 0

    def test_explicit_rounds_unresolved(self):
        dispute = DisputeRecord(
            topic="T",
            generator_position="G",
            critic_position="C",
            rounds_unresolved=3,
        )
        assert dispute.rounds_unresolved == 3


# ---------------------------------------------------------------------------
# AgentConfig
# ---------------------------------------------------------------------------


class TestAgentConfig:
    def test_defaults(self):
        config = AgentConfig()
        assert config.max_rounds == 5
        assert config.quality_threshold == 0.85
        assert config.convergence_threshold == 0.02
        assert config.roi_decay_factor == 2.0
        assert config.loop_similarity_threshold == 0.92
        assert config.enable_escalation is True

    def test_custom(self):
        config = AgentConfig(
            max_rounds=10,
            quality_threshold=0.9,
            convergence_threshold=0.01,
            roi_decay_factor=1.5,
            loop_similarity_threshold=0.85,
            enable_escalation=False,
        )
        assert config.max_rounds == 10
        assert config.quality_threshold == 0.9
        assert config.convergence_threshold == 0.01
        assert config.roi_decay_factor == 1.5
        assert config.loop_similarity_threshold == 0.85
        assert config.enable_escalation is False

    def test_partial_overrides(self):
        config = AgentConfig(max_rounds=3)
        assert config.max_rounds == 3
        # Other defaults remain
        assert config.quality_threshold == 0.85
        assert config.roi_decay_factor == 2.0

    def test_max_rounds_below_one_raises(self):
        with pytest.raises(ValidationError):
            AgentConfig(max_rounds=0)

    def test_quality_threshold_out_of_range_raises(self):
        with pytest.raises(ValidationError):
            AgentConfig(quality_threshold=1.5)


# ---------------------------------------------------------------------------
# JSON serialization / deserialization
# ---------------------------------------------------------------------------


class TestSerialization:
    def test_artifact_to_json(self):
        artifact = Artifact(
            content="result = 42",
            reasoning="It works.",
            confidence=0.9,
            uncertain_parts=["performance"],
        )
        data = artifact.model_dump()
        assert data["content"] == "result = 42"
        assert data["confidence"] == 0.9
        assert data["uncertain_parts"] == ["performance"]

    def test_artifact_from_json(self):
        raw = {
            "content": "x = 1",
            "reasoning": "simple",
            "confidence": 0.7,
            "uncertain_parts": [],
        }
        artifact = Artifact.model_validate(raw)
        assert artifact.content == "x = 1"
        assert artifact.confidence == 0.7

    def test_verdict_to_json(self):
        verdict = Verdict(
            score=0.95,
            issues=[Issue(severity="style", description="PEP8")],
            is_blocking=False,
            suggestion="Fix style.",
            agreement_level=0.9,
        )
        data = verdict.model_dump()
        assert data["score"] == 0.95
        assert len(data["issues"]) == 1
        assert data["issues"][0]["severity"] == "style"

    def test_verdict_from_json(self):
        raw = {
            "score": 0.88,
            "issues": [
                {
                    "severity": "major",
                    "description": "Missing error handling.",
                    "location": "main.py:10",
                }
            ],
            "is_blocking": True,
            "suggestion": "Add try/except.",
            "agreement_level": 0.6,
        }
        verdict = Verdict.model_validate(raw)
        assert verdict.score == 0.88
        assert len(verdict.issues) == 1
        assert verdict.issues[0].severity == "major"
        assert verdict.is_blocking
        assert verdict.agreement_level == 0.6

    def test_roundtrip_artifact(self):
        original = Artifact(
            content="def solve():\n    pass",
            reasoning="placeholder",
            confidence=0.5,
        )
        reloaded = Artifact.model_validate_json(original.model_dump_json())
        assert reloaded.content == original.content
        assert reloaded.confidence == original.confidence

    def test_roundtrip_verdict(self):
        original = Verdict(
            score=0.75,
            issues=[
                Issue(severity="critical", description="Bug!", location="L5", fix_hint="..." )
            ],
            is_blocking=True,
            suggestion=None,
            agreement_level=0.3,
        )
        reloaded = Verdict.model_validate_json(original.model_dump_json())
        assert reloaded.score == original.score
        assert len(reloaded.issues) == 1
        assert reloaded.issues[0].fix_hint == "..."
