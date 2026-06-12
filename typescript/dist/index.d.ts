import { z } from 'zod';

/**
 * Options that can be passed to the adapter's generate methods.
 * Extensible — providers may accept additional keys.
 */
interface GenerateOptions {
    /** Sampling temperature (typically 0.0–2.0). */
    temperature?: number;
    /** Maximum tokens to generate. */
    maxTokens?: number;
    /** Allow provider-specific extensions. */
    [key: string]: unknown;
}
/**
 * Abstract base class for LLM adapters.
 *
 * Implementations handle provider-specific API calls so that the
 * orchestrator can remain provider-agnostic.
 */
declare abstract class BaseAdapter {
    /**
     * Human-readable identifier for the model being used
     * (e.g. "claude-sonnet-4-6", "gpt-4o").
     */
    abstract get modelName(): string;
    /**
     * Generate free-form text from the model.
     *
     * @param systemPrompt - The system-level instruction.
     * @param userPrompt - The user-level message / task description.
     * @param options - Optional generation parameters.
     * @returns The model's text response.
     */
    abstract generate(systemPrompt: string, userPrompt: string, options?: GenerateOptions): Promise<string>;
    /**
     * Generate structured (typed) output from the model.
     *
     * @param systemPrompt - The system-level instruction.
     * @param userPrompt - The user-level message.
     * @param outputSchema - A JSON Schema object describing the desired output shape.
     * @param options - Optional generation parameters.
     * @returns A parsed object matching the schema type T.
     */
    abstract generateStructured<T>(systemPrompt: string, userPrompt: string, outputSchema: Record<string, unknown>, options?: GenerateOptions): Promise<T>;
}

/**
 * Severity levels for issues found during critique.
 * - critical: The solution is wrong, unsafe, or would not work at all.
 * - major: Significant flaw that would cause problems in many cases.
 * - minor: Improvement that would make the solution better but isn't required.
 * - style: Cosmetic or preference-based feedback.
 */
declare const SeverityEnum: z.ZodEnum<["critical", "major", "minor", "style"]>;
type Severity = z.infer<typeof SeverityEnum>;
/**
 * A single issue identified by the Critic agent.
 * Contains severity, description, optional location, and an optional fix hint.
 */
declare const IssueSchema: z.ZodObject<{
    severity: z.ZodEnum<["critical", "major", "minor", "style"]>;
    description: z.ZodString;
    location: z.ZodOptional<z.ZodString>;
    fixHint: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    severity: "critical" | "major" | "minor" | "style";
    description: string;
    location?: string | undefined;
    fixHint?: string | undefined;
}, {
    severity: "critical" | "major" | "minor" | "style";
    description: string;
    location?: string | undefined;
    fixHint?: string | undefined;
}>;
type Issue = z.infer<typeof IssueSchema>;
/**
 * An artifact produced by the Generator agent.
 * Contains the generated content, the Generator's reasoning chain,
 * a confidence score, and any parts the Generator is uncertain about.
 */
declare const ArtifactSchema: z.ZodObject<{
    content: z.ZodString;
    reasoning: z.ZodString;
    confidence: z.ZodNumber;
    uncertainParts: z.ZodDefault<z.ZodArray<z.ZodString, "many">>;
}, "strip", z.ZodTypeAny, {
    content: string;
    reasoning: string;
    confidence: number;
    uncertainParts: string[];
}, {
    content: string;
    reasoning: string;
    confidence: number;
    uncertainParts?: string[] | undefined;
}>;
type Artifact = z.infer<typeof ArtifactSchema>;
/**
 * A verdict produced by the Critic agent after reviewing an artifact.
 * Contains an overall score, a list of issues, a blocking flag,
 * an optional consolidated suggestion, and an agreement level.
 */
declare const VerdictSchema: z.ZodObject<{
    score: z.ZodNumber;
    issues: z.ZodArray<z.ZodObject<{
        severity: z.ZodEnum<["critical", "major", "minor", "style"]>;
        description: z.ZodString;
        location: z.ZodOptional<z.ZodString>;
        fixHint: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        severity: "critical" | "major" | "minor" | "style";
        description: string;
        location?: string | undefined;
        fixHint?: string | undefined;
    }, {
        severity: "critical" | "major" | "minor" | "style";
        description: string;
        location?: string | undefined;
        fixHint?: string | undefined;
    }>, "many">;
    isBlocking: z.ZodBoolean;
    suggestion: z.ZodOptional<z.ZodString>;
    agreementLevel: z.ZodNumber;
}, "strip", z.ZodTypeAny, {
    issues: {
        severity: "critical" | "major" | "minor" | "style";
        description: string;
        location?: string | undefined;
        fixHint?: string | undefined;
    }[];
    score: number;
    isBlocking: boolean;
    agreementLevel: number;
    suggestion?: string | undefined;
}, {
    issues: {
        severity: "critical" | "major" | "minor" | "style";
        description: string;
        location?: string | undefined;
        fixHint?: string | undefined;
    }[];
    score: number;
    isBlocking: boolean;
    agreementLevel: number;
    suggestion?: string | undefined;
}>;
type Verdict = z.infer<typeof VerdictSchema>;
/**
 * A record of one complete round (generate + critique).
 */
declare const RoundRecordSchema: z.ZodObject<{
    roundNum: z.ZodNumber;
    artifact: z.ZodObject<{
        content: z.ZodString;
        reasoning: z.ZodString;
        confidence: z.ZodNumber;
        uncertainParts: z.ZodDefault<z.ZodArray<z.ZodString, "many">>;
    }, "strip", z.ZodTypeAny, {
        content: string;
        reasoning: string;
        confidence: number;
        uncertainParts: string[];
    }, {
        content: string;
        reasoning: string;
        confidence: number;
        uncertainParts?: string[] | undefined;
    }>;
    verdict: z.ZodObject<{
        score: z.ZodNumber;
        issues: z.ZodArray<z.ZodObject<{
            severity: z.ZodEnum<["critical", "major", "minor", "style"]>;
            description: z.ZodString;
            location: z.ZodOptional<z.ZodString>;
            fixHint: z.ZodOptional<z.ZodString>;
        }, "strip", z.ZodTypeAny, {
            severity: "critical" | "major" | "minor" | "style";
            description: string;
            location?: string | undefined;
            fixHint?: string | undefined;
        }, {
            severity: "critical" | "major" | "minor" | "style";
            description: string;
            location?: string | undefined;
            fixHint?: string | undefined;
        }>, "many">;
        isBlocking: z.ZodBoolean;
        suggestion: z.ZodOptional<z.ZodString>;
        agreementLevel: z.ZodNumber;
    }, "strip", z.ZodTypeAny, {
        issues: {
            severity: "critical" | "major" | "minor" | "style";
            description: string;
            location?: string | undefined;
            fixHint?: string | undefined;
        }[];
        score: number;
        isBlocking: boolean;
        agreementLevel: number;
        suggestion?: string | undefined;
    }, {
        issues: {
            severity: "critical" | "major" | "minor" | "style";
            description: string;
            location?: string | undefined;
            fixHint?: string | undefined;
        }[];
        score: number;
        isBlocking: boolean;
        agreementLevel: number;
        suggestion?: string | undefined;
    }>;
    timestamp: z.ZodNumber;
}, "strip", z.ZodTypeAny, {
    roundNum: number;
    artifact: {
        content: string;
        reasoning: string;
        confidence: number;
        uncertainParts: string[];
    };
    verdict: {
        issues: {
            severity: "critical" | "major" | "minor" | "style";
            description: string;
            location?: string | undefined;
            fixHint?: string | undefined;
        }[];
        score: number;
        isBlocking: boolean;
        agreementLevel: number;
        suggestion?: string | undefined;
    };
    timestamp: number;
}, {
    roundNum: number;
    artifact: {
        content: string;
        reasoning: string;
        confidence: number;
        uncertainParts?: string[] | undefined;
    };
    verdict: {
        issues: {
            severity: "critical" | "major" | "minor" | "style";
            description: string;
            location?: string | undefined;
            fixHint?: string | undefined;
        }[];
        score: number;
        isBlocking: boolean;
        agreementLevel: number;
        suggestion?: string | undefined;
    };
    timestamp: number;
}>;
type RoundRecord = z.infer<typeof RoundRecordSchema>;
/**
 * A record of a persistent disagreement between Generator and Critic.
 */
declare const DisputeRecordSchema: z.ZodObject<{
    topic: z.ZodString;
    generatorPosition: z.ZodString;
    criticPosition: z.ZodString;
    roundsUnresolved: z.ZodDefault<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    topic: string;
    generatorPosition: string;
    criticPosition: string;
    roundsUnresolved: number;
}, {
    topic: string;
    generatorPosition: string;
    criticPosition: string;
    roundsUnresolved?: number | undefined;
}>;
type DisputeRecord = z.infer<typeof DisputeRecordSchema>;
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
declare const AgentConfigSchema: z.ZodObject<{
    maxRounds: z.ZodDefault<z.ZodNumber>;
    qualityThreshold: z.ZodDefault<z.ZodNumber>;
    convergenceThreshold: z.ZodDefault<z.ZodNumber>;
    roiDecayFactor: z.ZodDefault<z.ZodNumber>;
    loopSimilarityThreshold: z.ZodDefault<z.ZodNumber>;
    enableEscalation: z.ZodDefault<z.ZodBoolean>;
}, "strip", z.ZodTypeAny, {
    maxRounds: number;
    qualityThreshold: number;
    convergenceThreshold: number;
    roiDecayFactor: number;
    loopSimilarityThreshold: number;
    enableEscalation: boolean;
}, {
    maxRounds?: number | undefined;
    qualityThreshold?: number | undefined;
    convergenceThreshold?: number | undefined;
    roiDecayFactor?: number | undefined;
    loopSimilarityThreshold?: number | undefined;
    enableEscalation?: boolean | undefined;
}>;
type AgentConfig = z.infer<typeof AgentConfigSchema>;
/**
 * The decision made by the convergence engine after each round.
 * - accept: The artifact is good enough; stop iterating.
 * - continue: Another round should be attempted.
 * - escalate: A semantic loop is detected; invoke meta-judge.
 */
declare const DecisionEnum: z.ZodEnum<["accept", "continue", "escalate"]>;
type Decision = z.infer<typeof DecisionEnum>;

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
declare class DualAgentOrchestrator {
    private generator;
    private critic;
    private config;
    private convergence;
    private loopDetector;
    private roundHistory;
    private disputes;
    /**
     * @param generator - Adapter for the Generator LLM.
     * @param critic - Adapter for the Critic LLM (can be the same or different model).
     * @param config - Partial configuration merged with sensible defaults.
     */
    constructor(generator: BaseAdapter, critic: BaseAdapter, config?: Partial<AgentConfig>);
    /**
     * Run the full Generator-Critic loop for a given task.
     *
     * @param task - The task description / prompt for the Generator.
     * @param context - Optional additional context (e.g. codebase info, constraints).
     * @returns The best {@link Artifact} produced across all rounds.
     */
    run(task: string, context?: string): Promise<Artifact>;
    /**
     * Return the round history for inspection.
     */
    get history(): ReadonlyArray<RoundRecord>;
    /**
     * Return tracked disputes for inspection.
     */
    get activeDisputes(): ReadonlyArray<DisputeRecord>;
    /**
     * Evaluate convergence based on the current state.
     *
     * @param roundNum - Current round number (1-based).
     * @param verdict - The Critic's verdict for this round.
     * @param prevVerdict - The previous round's verdict (null on round 1).
     */
    private evaluate;
    /**
     * Escalate to a meta-judge when the convergence engine detects a loop.
     *
     * Constructs a special prompt summarizing all rounds and asks the Critic
     * to act as a tie-breaker, selecting or synthesizing the best result.
     *
     * Falls back to {@link bestArtifact} if the meta-judge call fails.
     */
    private escalate;
    /**
     * Try to parse the meta-judge response as a JSON artifact or
     * extract content as a plain-text artifact.
     */
    private parseMetaJudgeResponse;
    /**
     * Select the highest-scoring artifact from the round history.
     */
    private bestArtifact;
    /**
     * Filter issues for the Generator based on the current round number.
     *
     * Round 1: only critical + major issues are fed back.
     * Round 2: only critical issues are fed back.
     * Round 3+: no issues are fed back (Generator works independently).
     */
    private filterIssues;
    /**
     * Build the user prompt for the Generator.
     *
     * Includes the task, optional context, and any issues from the previous
     * round that need to be addressed.
     */
    private buildGeneratorPrompt;
    /**
     * Build the user prompt for the Critic.
     *
     * Includes the artifact to review and any relevant history context.
     */
    private buildCriticPrompt;
    /**
     * Build the meta-judge prompt used during escalation.
     *
     * Summarizes all rounds and asks the Critic to select or synthesize
     * the best result.
     */
    private buildMetaJudgePrompt;
    /**
     * Call the Generator to produce an artifact.
     * Wraps the LLM call in try/catch so a single failure does not crash the run.
     */
    private generateArtifact;
    /**
     * Call the Critic to produce a verdict.
     * Wraps the LLM call in try/catch so a single failure does not crash the run.
     */
    private critiqueArtifact;
    /**
     * Track persistent disagreements between Generator and Critic.
     *
     * A dispute is recorded when:
     * - The agreement level is low (< 0.3).
     * - The verdict has blocking issues AND the Generator's confidence is high (> 0.7).
     */
    private trackDisputes;
}

/**
 * Semantic loop detector that tracks generation history and detects
 * when the agents are repeating themselves without making progress.
 *
 * Uses two similarity strategies:
 * 1. Jaccard similarity (word-overlap) — fast, no external API needed.
 * 2. Cosine similarity over embeddings — more accurate, requires an embedding provider.
 */
declare class SemanticLoopDetector {
    private history;
    private threshold;
    private windowSize;
    /**
     * @param threshold - Similarity score above which two texts are considered a loop (default 0.92).
     * @param windowSize - How many recent items to compare against (default 3).
     */
    constructor(threshold?: number, windowSize?: number);
    /**
     * Record a text in the history buffer.
     * Automatically prunes old entries beyond `windowSize * 2` to bound memory usage.
     */
    add(text: string): void;
    /**
     * Check whether `newText` is semantically too similar to any recent entry
     * using Jaccard (word-overlap) similarity.
     *
     * @returns true if a loop is detected.
     */
    isLooping(newText: string): boolean;
    /**
     * Check whether `newText` is semantically too similar to any recent entry
     * using cosine similarity over embeddings. More accurate but requires an
     * async embedding provider.
     *
     * @param newText - The new text to check.
     * @param getEmbedding - Async function that returns an embedding vector for a given text.
     * @returns true if a loop is detected.
     */
    isLoopingWithEmbedding(newText: string, getEmbedding: (text: string) => Promise<number[]>): Promise<boolean>;
    /**
     * Compute Jaccard similarity between two strings at the word level.
     * Ranges from 0 (no overlap) to 1 (identical word sets).
     */
    private jaccardSimilarity;
    /**
     * Compute cosine similarity between two embedding vectors.
     * Ranges from -1 (opposite) to 1 (identical direction).
     */
    private cosineSimilarity;
    /**
     * Clear the entire history buffer.
     */
    reset(): void;
    /**
     * Return the current number of entries in the history buffer.
     */
    get size(): number;
}

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
declare class ConvergenceEngine {
    private checks;
    private loopDetector;
    constructor(config: AgentConfig);
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
    evaluate(roundNum: number, verdict: Verdict, prevVerdict: Verdict | null, config: AgentConfig, history: RoundRecord[]): Decision;
    /**
     * Expose the underlying loop detector for external inspection or reset.
     */
    get detector(): SemanticLoopDetector;
}

/**
 * Adapter for Anthropic's Claude models.
 *
 * Uses the `@anthropic-ai/sdk` client. Structured output is achieved via
 * Anthropic's tool-use mechanism: a single tool is defined whose
 * `input_schema` matches the desired output schema, and `tool_choice`
 * forces the model to call that tool.
 */
declare class AnthropicAdapter extends BaseAdapter {
    private client;
    private _model;
    private defaultOptions;
    /**
     * @param model - Anthropic model ID (default `'claude-sonnet-4-6'`).
     * @param apiKey - Anthropic API key. Falls back to `ANTHROPIC_API_KEY` env var.
     * @param options - Default generation options applied to every call.
     */
    constructor(model?: string, apiKey?: string, options?: GenerateOptions);
    /** The model identifier used for API calls. */
    get modelName(): string;
    /**
     * Generate free-form text.
     *
     * @param systemPrompt - System-level instruction (passed as the `system` param).
     * @param userPrompt - User message.
     * @param options - Per-call overrides merged over constructor defaults.
     * @returns The text content of the assistant's response.
     */
    generate(systemPrompt: string, userPrompt: string, options?: GenerateOptions): Promise<string>;
    /**
     * Generate structured (typed) output using Anthropic's tool-use pattern.
     *
     * The desired output schema is wrapped as a tool named `"output"`.
     * `tool_choice` is set to force the model to invoke that tool,
     * guaranteeing a JSON response matching the schema.
     *
     * @typeParam T - The expected output type.
     * @param systemPrompt - System-level instruction.
     * @param userPrompt - User message.
     * @param outputSchema - JSON Schema object describing the desired output shape.
     * @param options - Per-call overrides.
     * @returns A parsed object of type T.
     */
    generateStructured<T>(systemPrompt: string, userPrompt: string, outputSchema: Record<string, unknown>, options?: GenerateOptions): Promise<T>;
}

/**
 * Adapter for OpenAI's chat models (GPT-4o, GPT-4.1, etc.).
 *
 * Uses the `openai` SDK client. Structured output is achieved via
 * OpenAI's `response_format` with `json_schema` mode, which guarantees
 * the model produces JSON conforming to the provided schema.
 */
declare class OpenAIAdapter extends BaseAdapter {
    private client;
    private _model;
    private defaultOptions;
    /**
     * @param model - OpenAI model ID (default `'gpt-4o'`).
     * @param apiKey - OpenAI API key. Falls back to `OPENAI_API_KEY` env var.
     * @param options - Default generation options applied to every call.
     */
    constructor(model?: string, apiKey?: string, options?: GenerateOptions);
    /** The model identifier used for API calls. */
    get modelName(): string;
    /**
     * Generate free-form text.
     *
     * @param systemPrompt - System-level instruction.
     * @param userPrompt - User message.
     * @param options - Per-call overrides merged over constructor defaults.
     * @returns The text content of the assistant's response.
     */
    generate(systemPrompt: string, userPrompt: string, options?: GenerateOptions): Promise<string>;
    /**
     * Generate structured (typed) output using OpenAI's `json_schema` response format.
     *
     * The model is constrained to produce a JSON object matching the provided schema.
     * The result is parsed with a simple `JSON.parse` helper.
     *
     * @typeParam T - The expected output type.
     * @param systemPrompt - System-level instruction.
     * @param userPrompt - User message.
     * @param outputSchema - JSON Schema object describing the desired output shape.
     * @param options - Per-call overrides.
     * @returns A parsed object of type T.
     */
    generateStructured<T>(systemPrompt: string, userPrompt: string, outputSchema: Record<string, unknown>, options?: GenerateOptions): Promise<T>;
    /**
     * Safely parse a JSON string into type T.
     * Logs a warning and returns an empty object on parse failure.
     */
    private parse;
}

/**
 * System prompt for the Generator agent.
 *
 * The Generator is responsible for producing creative, well-reasoned
 * solutions. It must mark uncertain parts so the Critic can focus
 * review effort where it matters most.
 */
declare const GENERATOR_SYSTEM_PROMPT = "You are the GENERATOR agent in a dual-agent collaborative system. Your role is to PRODUCE the best possible solution.\n\n## Your Responsibilities\n1. Create complete, well-reasoned solutions to the given task\n2. Mark any uncertain parts with [UNCERTAIN: ...] so the reviewer can focus on them\n3. When you receive criticism from the previous round, make SUBSTANTIVE changes \u2014 not superficial rewording\n4. If you believe a criticism is incorrect, clearly explain why in your reasoning and stand your ground\n\n## Output Format\nAlways provide:\n- The complete solution content\n- Your reasoning chain (why you made each decision)\n- A confidence score (0.0 to 1.0)\n- Any parts you're uncertain about (as a list)\n";

/**
 * System prompt for the Critic agent.
 *
 * The Critic is responsible for rigorous review of the Generator's output.
 * It must classify issues by severity, provide actionable fix hints,
 * and acknowledge when previous feedback has been addressed.
 */
declare const CRITIC_SYSTEM_PROMPT = "You are the CRITIC agent in a dual-agent collaborative system. Your role is to RIGOROUSLY REVIEW the Generator's output.\n\n## Your Responsibilities\n1. Find factual errors, logical flaws, missing edge cases, and inefficiencies\n2. Classify each issue by severity: critical (breaking/factually wrong), major (significant flaw), minor (improvement possible), style (cosmetic)\n3. Provide SPECIFIC, ACTIONABLE fix hints \u2014 never vague suggestions\n4. If the Generator correctly addressed your previous feedback, acknowledge this explicitly\n5. If you fundamentally disagree with the Generator's approach, mark isBlocking=true and explain why\n\n## Severity Guide\n- **critical**: The solution is wrong, unsafe, or would not work at all\n- **major**: Significant flaw that would cause problems in many cases\n- **minor**: Improvement that would make the solution better but isn't required\n- **style**: Cosmetic or preference-based\n\n## Output Format\nAlways provide:\n- A score (0.0 to 1.0) reflecting overall quality\n- A list of issues with severity, description, location, and fix hints\n- Whether the issues are blocking (isBlocking)\n- If issues exist, a consolidated suggestion for improvement\n- An agreementLevel (0.0 to 1.0) indicating how much you agree with the Generator's approach\n";

export { type AgentConfig, AgentConfigSchema, AnthropicAdapter, type Artifact, ArtifactSchema, BaseAdapter, CRITIC_SYSTEM_PROMPT, ConvergenceEngine, type Decision, DecisionEnum, type DisputeRecord, DisputeRecordSchema, DualAgentOrchestrator, GENERATOR_SYSTEM_PROMPT, type GenerateOptions, type Issue, IssueSchema, OpenAIAdapter, type RoundRecord, RoundRecordSchema, SemanticLoopDetector, type Severity, SeverityEnum, type Verdict, VerdictSchema };
