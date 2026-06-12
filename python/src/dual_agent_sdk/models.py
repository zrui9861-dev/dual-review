"""Pydantic v2 data models for the dual-agent orchestration SDK.

Defines all structured types used throughout the Generator-Critic lifecycle:
Artifact (generator output), Verdict (critic review), Issue (critic finding),
RoundRecord (audit trail), DisputeRecord (deadlock tracking), AgentConfig (tuning),
and Decision (state-machine outcome).
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

Severity = Literal["critical", "major", "minor", "style"]
"""Ordered severity: *critical* (wrong/unsafe), *major* (significant flaw),
*minor* (nice-to-have), *style* (cosmetic)."""

Decision = Literal["accept", "continue", "escalate"]
"""State-machine output after a convergence check:
*accept* -- stop & return the current artifact,
*continue* -- proceed to the next round,
*escalate* -- invoke meta-judge deadlock resolution."""


# ---------------------------------------------------------------------------
# Core domain models
# ---------------------------------------------------------------------------

class Issue(BaseModel):
    """A single finding reported by the Critic."""

    severity: Severity
    description: str
    location: Optional[str] = None
    fix_hint: Optional[str] = None


class Artifact(BaseModel):
    """The Generator's output for a single round."""

    content: str
    reasoning: str
    confidence: float = Field(ge=0.0, le=1.0)
    uncertain_parts: list[str] = Field(default_factory=list)


class Verdict(BaseModel):
    """The Critic's structured review of one Artifact."""

    score: float = Field(ge=0.0, le=1.0)
    issues: list[Issue] = Field(default_factory=list)
    is_blocking: bool = False
    suggestion: Optional[str] = None
    agreement_level: float = Field(default=0.0, ge=0.0, le=1.0)


class RoundRecord(BaseModel):
    """Immutable audit-trail entry for one Generator-Critic round."""

    round_num: int
    artifact: Artifact
    verdict: Verdict
    timestamp: float


class DisputeRecord(BaseModel):
    """Captures a persistent disagreement between Generator and Critic."""

    topic: str
    generator_position: str
    critic_position: str
    rounds_unresolved: int = 0


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

class AgentConfig(BaseModel):
    """Tunable parameters for the dual-agent orchestration loop.

    Attributes:
        max_rounds: Hard ceiling on Generator-Critic rounds (default 5).
        quality_threshold: If the verdict score meets or exceeds this value
            *and* there are no blocking issues the artifact is auto-accepted.
        convergence_threshold: If the score delta between successive rounds
            is below this value the loop terminates.
        roi_decay_factor: Exponent base for diminishing-returns acceptance;
            higher values make the orchestrator more willing to accept small
            improvements in later rounds.
        loop_similarity_threshold: Jaccard similarity (0-1) above which two
            generator outputs are considered semantically identical.
        enable_escalation: When True, semantic loops trigger the meta-judge
            escalation pathway instead of an unconditional accept.
    """

    max_rounds: int = Field(default=5, ge=1)
    quality_threshold: float = Field(default=0.85, ge=0.0, le=1.0)
    convergence_threshold: float = Field(default=0.02, ge=0.0)
    roi_decay_factor: float = Field(default=2.0, ge=1.0)
    loop_similarity_threshold: float = Field(default=0.92, ge=0.0, le=1.0)
    enable_escalation: bool = True
