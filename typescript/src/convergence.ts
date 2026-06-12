import { Verdict, RoundRecord, AgentConfig, Decision } from './models.js';
import { SemanticLoopDetector } from './loop-detector.js';

// ---------------------------------------------------------------------------
// Chain-of-Responsibility convergence checks
// Each check returns a Decision or null to pass control to the next check.
// ---------------------------------------------------------------------------

/**
 * Abstract base class for a single convergence check.
 * Subclasses implement {@link evaluate} and return a {@link Decision}
 * or null to hand off to the next check in the chain.
 */
abstract class ConvergenceCheck {
  /**
   * Evaluate this check's condition.
   *
   * @param roundNum - Current round number (1-based).
   * @param verdict - The Critic's verdict for the current round.
   * @param prevVerdict - The Critic's verdict from the previous round (null on round 1).
   * @param config - The active agent configuration.
   * @param history - All round records accumulated so far.
   * @returns A Decision if this check triggers, or null to continue the chain.
   */
  abstract evaluate(
    roundNum: number,
    verdict: Verdict,
    prevVerdict: Verdict | null,
    config: AgentConfig,
    history: RoundRecord[],
  ): Decision | null;
}

// ---------------------------------------------------------------------------
// Layer 1: Hard ceiling
// ---------------------------------------------------------------------------

/**
 * Forces acceptance when the maximum number of rounds is reached.
 * This is the safety valve that guarantees termination.
 */
class HardCeilingCheck extends ConvergenceCheck {
  evaluate(
    roundNum: number,
    _verdict: Verdict,
    _prevVerdict: Verdict | null,
    config: AgentConfig,
    _history: RoundRecord[],
  ): Decision | null {
    if (roundNum >= config.maxRounds) {
      return 'accept';
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Layer 2: Quality threshold
// ---------------------------------------------------------------------------

/**
 * Accepts the artifact when its score meets or exceeds the quality threshold
 * AND there are no blocking issues.
 */
class QualityThresholdCheck extends ConvergenceCheck {
  evaluate(
    _roundNum: number,
    verdict: Verdict,
    _prevVerdict: Verdict | null,
    config: AgentConfig,
    _history: RoundRecord[],
  ): Decision | null {
    if (verdict.score >= config.qualityThreshold && !verdict.isBlocking) {
      return 'accept';
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Layer 3: Score convergence
// ---------------------------------------------------------------------------

/**
 * Accepts when the score delta between the current and previous round
 * falls below the convergence threshold, indicating diminishing returns.
 */
class ScoreConvergenceCheck extends ConvergenceCheck {
  evaluate(
    _roundNum: number,
    verdict: Verdict,
    prevVerdict: Verdict | null,
    config: AgentConfig,
    _history: RoundRecord[],
  ): Decision | null {
    if (prevVerdict === null) return null;
    if (Math.abs(verdict.score - prevVerdict.score) < config.convergenceThreshold) {
      return 'accept';
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Layer 4: Issue decay
// ---------------------------------------------------------------------------

/**
 * Applies a progressive filter to issues across rounds.
 * Round 1: critical + major issues remain actionable.
 * Round 2: only critical issues remain actionable.
 * Round 3+: no issues are considered actionable — accept.
 */
class IssueDecayCheck extends ConvergenceCheck {
  evaluate(
    roundNum: number,
    verdict: Verdict,
    _prevVerdict: Verdict | null,
    _config: AgentConfig,
    _history: RoundRecord[],
  ): Decision | null {
    const remaining = this.filterActionableIssues(verdict.issues, roundNum);
    if (remaining.length === 0) {
      return 'accept';
    }
    return null;
  }

  /**
   * Determine which issues are still actionable at a given round.
   * Round 1: keep critical + major.
   * Round 2: keep critical only.
   * Round 3+: nothing is actionable.
   */
  private filterActionableIssues(
    issues: { severity: string }[],
    roundNum: number,
  ): { severity: string }[] {
    if (roundNum >= 3) return [];
    if (roundNum === 2) return issues.filter((i) => i.severity === 'critical');
    // Round 1
    return issues.filter((i) => i.severity === 'critical' || i.severity === 'major');
  }
}

// ---------------------------------------------------------------------------
// Layer 5: ROI (return-on-investment) check
// ---------------------------------------------------------------------------

/**
 * Accepts when the improvement between rounds is smaller than
 * a decaying threshold: 0.05 * (roiDecayFactor^(roundNum-1)).
 *
 * This models diminishing returns — each additional round is expected
 * to yield exponentially less improvement.
 */
class ROICheck extends ConvergenceCheck {
  evaluate(
    roundNum: number,
    verdict: Verdict,
    prevVerdict: Verdict | null,
    config: AgentConfig,
    _history: RoundRecord[],
  ): Decision | null {
    if (prevVerdict === null) return null;
    const improvement = verdict.score - prevVerdict.score;
    const threshold = 0.05 * Math.pow(config.roiDecayFactor, roundNum - 1);
    if (improvement < threshold) {
      return 'accept';
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Layer 6: Semantic loop detection
// ---------------------------------------------------------------------------

/**
 * Detects semantic loops by delegating to the {@link SemanticLoopDetector}.
 * When a loop is detected and escalation is enabled, returns 'escalate'.
 * When a loop is detected and escalation is disabled, returns 'accept'.
 */
class SemanticLoopCheck extends ConvergenceCheck {
  private loopDetector: SemanticLoopDetector;

  constructor(loopDetector: SemanticLoopDetector) {
    super();
    this.loopDetector = loopDetector;
  }

  evaluate(
    _roundNum: number,
    verdict: Verdict,
    _prevVerdict: Verdict | null,
    config: AgentConfig,
    _history: RoundRecord[],
  ): Decision | null {
    // Feed the verdict's suggestion (or a combo of content) into the loop detector.
    // We primarily check the suggestion text, which captures what the Critic wants changed.
    const checkText =
      verdict.suggestion ??
      verdict.issues.map((i) => i.description).join(' ') ??
      '';

    if (checkText.length === 0) return null;

    if (this.loopDetector.isLooping(checkText)) {
      return config.enableEscalation ? 'escalate' : 'accept';
    }

    // Also register this round's text so future checks can compare against it.
    this.loopDetector.add(checkText);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Convergence Engine
// ---------------------------------------------------------------------------

/**
 * The ConvergenceEngine orchestrates the 6-layer chain-of-responsibility
 * convergence protocol. Each layer is checked in order; the first layer
 * that returns a non-null {@link Decision} short-circuits the chain.
 *
 * Layers:
 * 1. Hard ceiling — forced accept at maxRounds.
 * 2. Quality threshold — accept if score meets threshold and no blockers.
 * 3. Score convergence — accept if score delta is tiny.
 * 4. Issue decay — accept if no actionable issues remain by round.
 * 5. ROI check — accept if improvement is below diminishing-returns threshold.
 * 6. Semantic loop — escalate to meta-judge if the agents are repeating.
 */
export class ConvergenceEngine {
  private checks: ConvergenceCheck[];
  private loopDetector: SemanticLoopDetector;

  constructor(config: AgentConfig) {
    this.loopDetector = new SemanticLoopDetector(config.loopSimilarityThreshold);
    this.checks = [
      new HardCeilingCheck(),
      new QualityThresholdCheck(),
      new ScoreConvergenceCheck(),
      new IssueDecayCheck(),
      new ROICheck(),
      new SemanticLoopCheck(this.loopDetector),
    ];
  }

  /**
   * Evaluate all convergence checks in priority order.
   *
   * @param roundNum - Current round number (1-based).
   * @param verdict - The Critic's verdict for this round.
   * @param prevVerdict - The Critic's verdict from the previous round (null on round 1).
   * @param config - The active agent configuration.
   * @param history - All round records accumulated so far.
   * @returns The first non-null decision, or 'continue' if no check triggers.
   */
  evaluate(
    roundNum: number,
    verdict: Verdict,
    prevVerdict: Verdict | null,
    config: AgentConfig,
    history: RoundRecord[],
  ): Decision {
    for (const check of this.checks) {
      const decision = check.evaluate(roundNum, verdict, prevVerdict, config, history);
      if (decision !== null) {
        return decision;
      }
    }
    return 'continue';
  }

  /**
   * Expose the underlying loop detector for external inspection or reset.
   */
  get detector(): SemanticLoopDetector {
    return this.loopDetector;
  }
}
