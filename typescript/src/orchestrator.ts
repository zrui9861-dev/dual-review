import { BaseAdapter, GenerateOptions } from './adapters/base.js';
import { ConvergenceEngine } from './convergence.js';
import { SemanticLoopDetector } from './loop-detector.js';
import { GENERATOR_SYSTEM_PROMPT } from './prompts/generator.js';
import { CRITIC_SYSTEM_PROMPT } from './prompts/critic.js';
import {
  Artifact,
  Verdict,
  Issue,
  AgentConfig,
  Decision,
  RoundRecord,
  DisputeRecord,
  AgentConfigSchema,
  IssueSchema,
  VerdictSchema,
  ArtifactSchema,
} from './models.js';

/**
 * Default agent configuration used when none is provided.
 */
const DEFAULT_CONFIG: AgentConfig = AgentConfigSchema.parse({});

/**
 * Core orchestrator for the Generator-Critic dual-agent pattern.
 *
 * ## State Machine
 *
 * ```
 *                    ┌─────────────────┐
 *                    │   START (task)  │
 *                    └────────┬────────┘
 *                             ▼
 *                   ┌──────────────────┐
 *              ┌───►│  GENERATE        │◄──────────────┐
 *              │    └────────┬─────────┘               │
 *              │             ▼                          │
 *              │    ┌──────────────────┐               │
 *              │    │  CRITIQUE        │               │
 *              │    └────────┬─────────┘               │
 *              │             ▼                          │
 *              │    ┌──────────────────┐               │
 *              │    │  EVALUATE        │               │
 *              │    └───┬──┬──┬────────┘               │
 *              │        │  │  │                         │
 *              │  ┌─────┘  │  └──────────┐             │
 *              │  ▼        ▼             ▼              │
 *              │ accept  continue    escalate           │
 *              │  │        │             │              │
 *              │  │        └─────────────┘              │
 *              │  │   (filter issues,                   │
 *              │  │    next round)                      │
 *              ▼  ▼                                    ▼
 *         ┌────────────────┐              ┌──────────────────┐
 *         │  RETURN BEST   │              │  META-JUDGE      │
 *         │  ARTIFACT      │              │  (uses Critic)   │
 *         └────────────────┘              └────────┬─────────┘
 *                                                  ▼
 *                                         ┌──────────────────┐
 *                                         │  RETURN BEST     │
 *                                         │  ARTIFACT        │
 *                                         └──────────────────┘
 * ```
 *
 * ## Convergence Protocol
 *
 * Six layers are evaluated in order after each round:
 * 1. Hard ceiling (maxRounds) → accept
 * 2. Quality threshold (score + no blockers) → accept
 * 3. Score convergence (delta < threshold) → accept
 * 4. Issue decay (no actionable issues by round) → accept
 * 5. ROI check (improvement < diminishing returns) → accept
 * 6. Semantic loop detection → escalate or accept
 *
 * If no layer fires, the orchestrator continues to the next round.
 */
export class DualAgentOrchestrator {
  private generator: BaseAdapter;
  private critic: BaseAdapter;
  private config: AgentConfig;
  private convergence: ConvergenceEngine;
  private loopDetector: SemanticLoopDetector;
  private roundHistory: RoundRecord[] = [];
  private disputes: DisputeRecord[] = [];

  /**
   * @param generator - Adapter for the Generator LLM.
   * @param critic - Adapter for the Critic LLM (can be the same or different model).
   * @param config - Partial configuration merged with sensible defaults.
   */
  constructor(
    generator: BaseAdapter,
    critic: BaseAdapter,
    config?: Partial<AgentConfig>,
  ) {
    this.generator = generator;
    this.critic = critic;
    this.config = AgentConfigSchema.parse({ ...DEFAULT_CONFIG, ...config });
    this.convergence = new ConvergenceEngine(this.config);
    this.loopDetector = this.convergence.detector;
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /**
   * Run the full Generator-Critic loop for a given task.
   *
   * @param task - The task description / prompt for the Generator.
   * @param context - Optional additional context (e.g. codebase info, constraints).
   * @returns The best {@link Artifact} produced across all rounds.
   */
  async run(task: string, context?: string): Promise<Artifact> {
    // Reset state for a fresh run
    this.roundHistory = [];
    this.disputes = [];
    this.loopDetector.reset();

    let prevVerdict: Verdict | null = null;
    let issuesForGenerator: Issue[] = [];

    for (let roundNum = 1; roundNum <= this.config.maxRounds; roundNum++) {
      // --- GENERATE ---
      const generatorPrompt = this.buildGeneratorPrompt(task, context, issuesForGenerator);
      const artifact = await this.generateArtifact(generatorPrompt);

      // --- CRITIQUE ---
      const criticPrompt = this.buildCriticPrompt(artifact, roundNum);
      const verdict = await this.critiqueArtifact(criticPrompt);

      // --- RECORD ---
      const record: RoundRecord = {
        roundNum,
        artifact,
        verdict,
        timestamp: Date.now(),
      };
      this.roundHistory.push(record);
      this.trackDisputes(artifact, verdict, roundNum);

      // --- EVALUATE ---
      const decision = this.evaluate(roundNum, verdict, prevVerdict);

      if (decision === 'accept') {
        return artifact;
      }

      if (decision === 'escalate') {
        return await this.escalate(task);
      }

      // decision === 'continue' — prepare for next round
      issuesForGenerator = this.filterIssues(verdict.issues, roundNum);
      prevVerdict = verdict;
    }

    // Hard ceiling reached — return best artifact
    return this.bestArtifact();
  }

  /**
   * Return the round history for inspection.
   */
  get history(): ReadonlyArray<RoundRecord> {
    return this.roundHistory;
  }

  /**
   * Return tracked disputes for inspection.
   */
  get activeDisputes(): ReadonlyArray<DisputeRecord> {
    return this.disputes;
  }

  // -----------------------------------------------------------------------
  // Internal: Evaluation
  // -----------------------------------------------------------------------

  /**
   * Evaluate convergence based on the current state.
   *
   * @param roundNum - Current round number (1-based).
   * @param verdict - The Critic's verdict for this round.
   * @param prevVerdict - The previous round's verdict (null on round 1).
   */
  private evaluate(
    roundNum: number,
    verdict: Verdict,
    prevVerdict: Verdict | null,
  ): Decision {
    return this.convergence.evaluate(
      roundNum,
      verdict,
      prevVerdict,
      this.config,
      this.roundHistory,
    );
  }

  // -----------------------------------------------------------------------
  // Internal: Escalation / Meta-Judge
  // -----------------------------------------------------------------------

  /**
   * Escalate to a meta-judge when the convergence engine detects a loop.
   *
   * Constructs a special prompt summarizing all rounds and asks the Critic
   * to act as a tie-breaker, selecting or synthesizing the best result.
   *
   * Falls back to {@link bestArtifact} if the meta-judge call fails.
   */
  private async escalate(task: string): Promise<Artifact> {
    const metaPrompt = this.buildMetaJudgePrompt(task);

    try {
      const response = await this.critic.generate(
        CRITIC_SYSTEM_PROMPT,
        metaPrompt,
        { temperature: 0.3, maxTokens: 2048 },
      );
      return this.parseMetaJudgeResponse(response);
    } catch (error) {
      console.warn('DualAgentOrchestrator: meta-judge escalation failed, falling back to best artifact.', error);
      return this.bestArtifact();
    }
  }

  /**
   * Try to parse the meta-judge response as a JSON artifact or
   * extract content as a plain-text artifact.
   */
  private parseMetaJudgeResponse(response: string): Artifact {
    try {
      const parsed = JSON.parse(response);
      return ArtifactSchema.parse(parsed);
    } catch {
      // Not valid JSON — wrap the response itself as an artifact
      return {
        content: response,
        reasoning: 'Meta-judge selected this as the best resolution.',
        confidence: 0.8,
        uncertainParts: [],
      };
    }
  }

  /**
   * Select the highest-scoring artifact from the round history.
   */
  private bestArtifact(): Artifact {
    if (this.roundHistory.length === 0) {
      return {
        content: '',
        reasoning: 'No rounds completed.',
        confidence: 0,
        uncertainParts: [],
      };
    }

    let best = this.roundHistory[0]!;
    for (const record of this.roundHistory) {
      if (record.verdict.score > best.verdict.score) {
        best = record;
      }
    }
    return best.artifact;
  }

  // -----------------------------------------------------------------------
  // Internal: Issue filtering
  // -----------------------------------------------------------------------

  /**
   * Filter issues for the Generator based on the current round number.
   *
   * Round 1: only critical + major issues are fed back.
   * Round 2: only critical issues are fed back.
   * Round 3+: no issues are fed back (Generator works independently).
   */
  private filterIssues(issues: Issue[], roundNum: number): Issue[] {
    if (roundNum >= 3) return [];
    if (roundNum === 2) return issues.filter((i) => i.severity === 'critical');
    // Round 1
    return issues.filter(
      (i) => i.severity === 'critical' || i.severity === 'major',
    );
  }

  // -----------------------------------------------------------------------
  // Internal: Prompt builders
  // -----------------------------------------------------------------------

  /**
   * Build the user prompt for the Generator.
   *
   * Includes the task, optional context, and any issues from the previous
   * round that need to be addressed.
   */
  private buildGeneratorPrompt(
    task: string,
    context: string | undefined,
    issues: Issue[],
  ): string {
    const parts: string[] = [`## Task\n${task}`];

    if (context) {
      parts.push(`## Context\n${context}`);
    }

    if (issues.length > 0) {
      const issueLines = issues.map(
        (issue, idx) =>
          `${idx + 1}. [${issue.severity}] ${issue.description}${
            issue.location ? ` (at ${issue.location})` : ''
          }${issue.fixHint ? `\n   Fix hint: ${issue.fixHint}` : ''}`,
      );
      parts.push(
        `## Issues to Address from Previous Round\n${issueLines.join('\n')}`,
      );
    }

    parts.push(
      `\nProvide your solution in the following JSON format:\n` +
      `{\n  "content": "<your complete solution>",\n  "reasoning": "<your step-by-step reasoning>",\n  "confidence": <0.0-1.0>,\n  "uncertainParts": ["<area1>", "<area2>"]\n}`,
    );

    return parts.join('\n\n');
  }

  /**
   * Build the user prompt for the Critic.
   *
   * Includes the artifact to review and any relevant history context.
   */
  private buildCriticPrompt(artifact: Artifact, roundNum: number): string {
    const parts: string[] = [
      `## Artifact to Review (Round ${roundNum})\n\n### Content\n${artifact.content}`,
      `\n### Generator's Reasoning\n${artifact.reasoning}`,
      `\n### Generator's Confidence\n${artifact.confidence}`,
    ];

    if (artifact.uncertainParts.length > 0) {
      parts.push(
        `\n### Areas the Generator is Uncertain About\n${artifact.uncertainParts.map((p) => `- ${p}`).join('\n')}`,
      );
    }

    if (roundNum > 1 && this.roundHistory.length >= 2) {
      const prevRecord = this.roundHistory[this.roundHistory.length - 2];
      if (prevRecord) {
        parts.push(
          `\n## Previous Round Summary\n- Round ${prevRecord.roundNum} score: ${prevRecord.verdict.score}\n- Previous issues: ${prevRecord.verdict.issues.length}`,
        );
      }
    }

    parts.push(
      `\nProvide your review in the following JSON format:\n` +
      `{\n  "score": <0.0-1.0>,\n  "issues": [{"severity": "critical|major|minor|style", "description": "...", "location": "...", "fixHint": "..."}],\n  "isBlocking": <true|false>,\n  "suggestion": "<consolidated improvement suggestion or null>",\n  "agreementLevel": <0.0-1.0>\n}`,
    );

    return parts.join('\n');
  }

  /**
   * Build the meta-judge prompt used during escalation.
   *
   * Summarizes all rounds and asks the Critic to select or synthesize
   * the best result.
   */
  private buildMetaJudgePrompt(task: string): string {
    const roundSummaries = this.roundHistory
      .map(
        (r) =>
          `### Round ${r.roundNum}\n- Score: ${r.verdict.score}\n- Issues: ${r.verdict.issues.length}\n- Blocking: ${r.verdict.isBlocking}\n- Agreement: ${r.verdict.agreementLevel}\n- Content excerpt: ${r.artifact.content.slice(0, 300)}...`,
      )
      .join('\n\n');

    return `## META-JUDGE ESCALATION

The Generator-Critic loop has been detected to be repeating without convergence.

### Original Task
${task}

### All Rounds
${roundSummaries}

### Instructions
As the meta-judge, your role is to break the deadlock. Choose the best version from the rounds above, or synthesize the best parts from multiple rounds. Explain your reasoning clearly.

Provide your decision as a JSON object:
{
  "content": "<the best or synthesized solution>",
  "reasoning": "<why you chose this>",
  "confidence": <0.0-1.0>,
  "uncertainParts": []
}`;
  }

  // -----------------------------------------------------------------------
  // Internal: LLM calls
  // -----------------------------------------------------------------------

  /**
   * Call the Generator to produce an artifact.
   * Wraps the LLM call in try/catch so a single failure does not crash the run.
   */
  private async generateArtifact(prompt: string): Promise<Artifact> {
    try {
      // Build the JSON schema for the artifact output
      const artifactSchema = {
        type: 'object',
        properties: {
          content: { type: 'string' },
          reasoning: { type: 'string' },
          confidence: { type: 'number', minimum: 0, maximum: 1 },
          uncertainParts: {
            type: 'array',
            items: { type: 'string' },
          },
        },
        required: ['content', 'reasoning', 'confidence', 'uncertainParts'],
        additionalProperties: false,
      };

      const result = await this.generator.generateStructured<Artifact>(
        GENERATOR_SYSTEM_PROMPT,
        prompt,
        artifactSchema,
        { temperature: 0.7, maxTokens: 4096 },
      );

      return ArtifactSchema.parse(result);
    } catch (error) {
      console.warn('DualAgentOrchestrator: generateArtifact failed, returning fallback artifact.', error);
      return {
        content: '',
        reasoning: `Generation failed: ${error instanceof Error ? error.message : 'unknown error'}`,
        confidence: 0,
        uncertainParts: ['entire output'],
      };
    }
  }

  /**
   * Call the Critic to produce a verdict.
   * Wraps the LLM call in try/catch so a single failure does not crash the run.
   */
  private async critiqueArtifact(prompt: string): Promise<Verdict> {
    try {
      const verdictSchema = {
        type: 'object',
        properties: {
          score: { type: 'number', minimum: 0, maximum: 1 },
          issues: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                severity: { type: 'string', enum: ['critical', 'major', 'minor', 'style'] },
                description: { type: 'string' },
                location: { type: 'string' },
                fixHint: { type: 'string' },
              },
              required: ['severity', 'description'],
              additionalProperties: false,
            },
          },
          isBlocking: { type: 'boolean' },
          suggestion: { type: 'string' },
          agreementLevel: { type: 'number', minimum: 0, maximum: 1 },
        },
        required: ['score', 'issues', 'isBlocking', 'agreementLevel'],
        additionalProperties: false,
      };

      const result = await this.critic.generateStructured<Verdict>(
        CRITIC_SYSTEM_PROMPT,
        prompt,
        verdictSchema,
        { temperature: 0.3, maxTokens: 4096 },
      );

      return VerdictSchema.parse(result);
    } catch (error) {
      console.warn('DualAgentOrchestrator: critiqueArtifact failed, returning fallback verdict.', error);
      return {
        score: 0,
        issues: [
          {
            severity: 'critical',
            description: `Critique failed: ${error instanceof Error ? error.message : 'unknown error'}`,
          },
        ],
        isBlocking: true,
        agreementLevel: 0,
      };
    }
  }

  // -----------------------------------------------------------------------
  // Internal: Dispute tracking
  // -----------------------------------------------------------------------

  /**
   * Track persistent disagreements between Generator and Critic.
   *
   * A dispute is recorded when:
   * - The agreement level is low (< 0.3).
   * - The verdict has blocking issues AND the Generator's confidence is high (> 0.7).
   */
  private trackDisputes(
    artifact: Artifact,
    verdict: Verdict,
    roundNum: number,
  ): void {
    if (verdict.agreementLevel < 0.3) {
      // Check if a similar dispute already exists
      const existingTopic = verdict.suggestion ?? 'general disagreement';
      const existing = this.disputes.find((d) => d.topic === existingTopic);
      if (existing) {
        existing.roundsUnresolved += 1;
      } else {
        this.disputes.push({
          topic: existingTopic,
          generatorPosition: artifact.reasoning.slice(0, 200),
          criticPosition: verdict.issues.map((i) => i.description).join('; ').slice(0, 200),
          roundsUnresolved: 1,
        });
      }
    }

    // Clear resolved disputes (agreement level is high)
    if (verdict.agreementLevel > 0.8) {
      this.disputes = this.disputes.filter(
        (d) => d.roundsUnresolved === 0 || d.roundsUnresolved > roundNum,
      );
    }
  }
}
