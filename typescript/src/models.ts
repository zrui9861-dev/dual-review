import { z } from 'zod';

/**
 * Severity levels for issues found during critique.
 * - critical: The solution is wrong, unsafe, or would not work at all.
 * - major: Significant flaw that would cause problems in many cases.
 * - minor: Improvement that would make the solution better but isn't required.
 * - style: Cosmetic or preference-based feedback.
 */
export const SeverityEnum = z.enum(['critical', 'major', 'minor', 'style']);
export type Severity = z.infer<typeof SeverityEnum>;

/**
 * A single issue identified by the Critic agent.
 * Contains severity, description, optional location, and an optional fix hint.
 */
export const IssueSchema = z.object({
  severity: SeverityEnum,
  description: z.string(),
  location: z.string().optional(),
  fixHint: z.string().optional(),
});
export type Issue = z.infer<typeof IssueSchema>;

/**
 * An artifact produced by the Generator agent.
 * Contains the generated content, the Generator's reasoning chain,
 * a confidence score, and any parts the Generator is uncertain about.
 */
export const ArtifactSchema = z.object({
  content: z.string(),
  reasoning: z.string(),
  confidence: z.number().min(0).max(1),
  uncertainParts: z.array(z.string()).default([]),
});
export type Artifact = z.infer<typeof ArtifactSchema>;

/**
 * A verdict produced by the Critic agent after reviewing an artifact.
 * Contains an overall score, a list of issues, a blocking flag,
 * an optional consolidated suggestion, and an agreement level.
 */
export const VerdictSchema = z.object({
  score: z.number().min(0).max(1),
  issues: z.array(IssueSchema),
  isBlocking: z.boolean(),
  suggestion: z.string().optional(),
  agreementLevel: z.number().min(0).max(1),
});
export type Verdict = z.infer<typeof VerdictSchema>;

/**
 * A record of one complete round (generate + critique).
 */
export const RoundRecordSchema = z.object({
  roundNum: z.number(),
  artifact: ArtifactSchema,
  verdict: VerdictSchema,
  timestamp: z.number(),
});
export type RoundRecord = z.infer<typeof RoundRecordSchema>;

/**
 * A record of a persistent disagreement between Generator and Critic.
 */
export const DisputeRecordSchema = z.object({
  topic: z.string(),
  generatorPosition: z.string(),
  criticPosition: z.string(),
  roundsUnresolved: z.number().default(0),
});
export type DisputeRecord = z.infer<typeof DisputeRecordSchema>;

/**
 * Configuration for the dual-agent orchestration.
 *
 * @property maxRounds - Maximum number of generate-critique rounds before forced acceptance.
 * @property qualityThreshold - Minimum score to accept an artifact outright.
 * @property convergenceThreshold - Score delta below which we consider convergence reached.
 * @property roiDecayFactor - Exponent base for diminishing-returns calculation.
 * @property loopSimilarityThreshold - Jaccard/cosine threshold for semantic loop detection.
 * @property enableEscalation - Whether to escalate to meta-judge when a loop is detected.
 */
export const AgentConfigSchema = z.object({
  maxRounds: z.number().default(5),
  qualityThreshold: z.number().default(0.85),
  convergenceThreshold: z.number().default(0.02),
  roiDecayFactor: z.number().default(2.0),
  loopSimilarityThreshold: z.number().default(0.92),
  enableEscalation: z.boolean().default(true),
});
export type AgentConfig = z.infer<typeof AgentConfigSchema>;

/**
 * The decision made by the convergence engine after each round.
 * - accept: The artifact is good enough; stop iterating.
 * - continue: Another round should be attempted.
 * - escalate: A semantic loop is detected; invoke meta-judge.
 */
export const DecisionEnum = z.enum(['accept', 'continue', 'escalate']);
export type Decision = z.infer<typeof DecisionEnum>;
