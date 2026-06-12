// src/loop-detector.ts
var SemanticLoopDetector = class {
  history = [];
  threshold;
  windowSize;
  /**
   * @param threshold - Similarity score above which two texts are considered a loop (default 0.92).
   * @param windowSize - How many recent items to compare against (default 3).
   */
  constructor(threshold = 0.92, windowSize = 3) {
    this.threshold = threshold;
    this.windowSize = windowSize;
  }
  /**
   * Record a text in the history buffer.
   * Automatically prunes old entries beyond `windowSize * 2` to bound memory usage.
   */
  add(text) {
    this.history.push(text);
    if (this.history.length > this.windowSize * 2) {
      this.history = this.history.slice(-this.windowSize * 2);
    }
  }
  /**
   * Check whether `newText` is semantically too similar to any recent entry
   * using Jaccard (word-overlap) similarity.
   *
   * @returns true if a loop is detected.
   */
  isLooping(newText) {
    const recentHistory = this.history.slice(-this.windowSize);
    for (const prev of recentHistory) {
      if (this.jaccardSimilarity(prev, newText) > this.threshold) {
        return true;
      }
    }
    return false;
  }
  /**
   * Check whether `newText` is semantically too similar to any recent entry
   * using cosine similarity over embeddings. More accurate but requires an
   * async embedding provider.
   *
   * @param newText - The new text to check.
   * @param getEmbedding - Async function that returns an embedding vector for a given text.
   * @returns true if a loop is detected.
   */
  async isLoopingWithEmbedding(newText, getEmbedding) {
    const recentHistory = this.history.slice(-this.windowSize);
    if (recentHistory.length === 0) return false;
    const newEmb = await getEmbedding(newText);
    for (const prev of recentHistory) {
      const prevEmb = await getEmbedding(prev);
      if (this.cosineSimilarity(newEmb, prevEmb) > this.threshold) {
        return true;
      }
    }
    return false;
  }
  /**
   * Compute Jaccard similarity between two strings at the word level.
   * Ranges from 0 (no overlap) to 1 (identical word sets).
   */
  jaccardSimilarity(a, b) {
    const wordsA = new Set(a.toLowerCase().split(/\s+/));
    const wordsB = new Set(b.toLowerCase().split(/\s+/));
    const intersection = new Set([...wordsA].filter((x) => wordsB.has(x)));
    const union = /* @__PURE__ */ new Set([...wordsA, ...wordsB]);
    if (union.size === 0) return 0;
    return intersection.size / union.size;
  }
  /**
   * Compute cosine similarity between two embedding vectors.
   * Ranges from -1 (opposite) to 1 (identical direction).
   */
  cosineSimilarity(a, b) {
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    const denom = Math.sqrt(normA) * Math.sqrt(normB);
    if (denom === 0) return 0;
    return dot / denom;
  }
  /**
   * Clear the entire history buffer.
   */
  reset() {
    this.history = [];
  }
  /**
   * Return the current number of entries in the history buffer.
   */
  get size() {
    return this.history.length;
  }
};

// src/convergence.ts
var ConvergenceCheck = class {
};
var HardCeilingCheck = class extends ConvergenceCheck {
  evaluate(roundNum, _verdict, _prevVerdict, config, _history) {
    if (roundNum >= config.maxRounds) {
      return "accept";
    }
    return null;
  }
};
var QualityThresholdCheck = class extends ConvergenceCheck {
  evaluate(_roundNum, verdict, _prevVerdict, config, _history) {
    if (verdict.score >= config.qualityThreshold && !verdict.isBlocking) {
      return "accept";
    }
    return null;
  }
};
var ScoreConvergenceCheck = class extends ConvergenceCheck {
  evaluate(_roundNum, verdict, prevVerdict, config, _history) {
    if (prevVerdict === null) return null;
    if (Math.abs(verdict.score - prevVerdict.score) < config.convergenceThreshold) {
      return "accept";
    }
    return null;
  }
};
var IssueDecayCheck = class extends ConvergenceCheck {
  evaluate(roundNum, verdict, _prevVerdict, _config, _history) {
    const remaining = this.filterActionableIssues(verdict.issues, roundNum);
    if (remaining.length === 0) {
      return "accept";
    }
    return null;
  }
  /**
   * Determine which issues are still actionable at a given round.
   * Round 1: keep critical + major.
   * Round 2: keep critical only.
   * Round 3+: nothing is actionable.
   */
  filterActionableIssues(issues, roundNum) {
    if (roundNum >= 3) return [];
    if (roundNum === 2) return issues.filter((i) => i.severity === "critical");
    return issues.filter((i) => i.severity === "critical" || i.severity === "major");
  }
};
var ROICheck = class extends ConvergenceCheck {
  evaluate(roundNum, verdict, prevVerdict, config, _history) {
    if (prevVerdict === null) return null;
    const improvement = verdict.score - prevVerdict.score;
    const threshold = 0.05 * Math.pow(config.roiDecayFactor, roundNum - 1);
    if (improvement < threshold) {
      return "accept";
    }
    return null;
  }
};
var SemanticLoopCheck = class extends ConvergenceCheck {
  loopDetector;
  constructor(loopDetector) {
    super();
    this.loopDetector = loopDetector;
  }
  evaluate(_roundNum, verdict, _prevVerdict, config, _history) {
    const checkText = verdict.suggestion ?? verdict.issues.map((i) => i.description).join(" ") ?? "";
    if (checkText.length === 0) return null;
    if (this.loopDetector.isLooping(checkText)) {
      return config.enableEscalation ? "escalate" : "accept";
    }
    this.loopDetector.add(checkText);
    return null;
  }
};
var ConvergenceEngine = class {
  checks;
  loopDetector;
  constructor(config) {
    this.loopDetector = new SemanticLoopDetector(config.loopSimilarityThreshold);
    this.checks = [
      new HardCeilingCheck(),
      new QualityThresholdCheck(),
      new ScoreConvergenceCheck(),
      new IssueDecayCheck(),
      new ROICheck(),
      new SemanticLoopCheck(this.loopDetector)
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
  evaluate(roundNum, verdict, prevVerdict, config, history) {
    for (const check of this.checks) {
      const decision = check.evaluate(roundNum, verdict, prevVerdict, config, history);
      if (decision !== null) {
        return decision;
      }
    }
    return "continue";
  }
  /**
   * Expose the underlying loop detector for external inspection or reset.
   */
  get detector() {
    return this.loopDetector;
  }
};

// src/prompts/generator.ts
var GENERATOR_SYSTEM_PROMPT = `You are the GENERATOR agent in a dual-agent collaborative system. Your role is to PRODUCE the best possible solution.

## Your Responsibilities
1. Create complete, well-reasoned solutions to the given task
2. Mark any uncertain parts with [UNCERTAIN: ...] so the reviewer can focus on them
3. When you receive criticism from the previous round, make SUBSTANTIVE changes \u2014 not superficial rewording
4. If you believe a criticism is incorrect, clearly explain why in your reasoning and stand your ground

## Output Format
Always provide:
- The complete solution content
- Your reasoning chain (why you made each decision)
- A confidence score (0.0 to 1.0)
- Any parts you're uncertain about (as a list)
`;

// src/prompts/critic.ts
var CRITIC_SYSTEM_PROMPT = `You are the CRITIC agent in a dual-agent collaborative system. Your role is to RIGOROUSLY REVIEW the Generator's output.

## Your Responsibilities
1. Find factual errors, logical flaws, missing edge cases, and inefficiencies
2. Classify each issue by severity: critical (breaking/factually wrong), major (significant flaw), minor (improvement possible), style (cosmetic)
3. Provide SPECIFIC, ACTIONABLE fix hints \u2014 never vague suggestions
4. If the Generator correctly addressed your previous feedback, acknowledge this explicitly
5. If you fundamentally disagree with the Generator's approach, mark isBlocking=true and explain why

## Severity Guide
- **critical**: The solution is wrong, unsafe, or would not work at all
- **major**: Significant flaw that would cause problems in many cases
- **minor**: Improvement that would make the solution better but isn't required
- **style**: Cosmetic or preference-based

## Output Format
Always provide:
- A score (0.0 to 1.0) reflecting overall quality
- A list of issues with severity, description, location, and fix hints
- Whether the issues are blocking (isBlocking)
- If issues exist, a consolidated suggestion for improvement
- An agreementLevel (0.0 to 1.0) indicating how much you agree with the Generator's approach
`;

// src/models.ts
import { z } from "zod";
var SeverityEnum = z.enum(["critical", "major", "minor", "style"]);
var IssueSchema = z.object({
  severity: SeverityEnum,
  description: z.string(),
  location: z.string().optional(),
  fixHint: z.string().optional()
});
var ArtifactSchema = z.object({
  content: z.string(),
  reasoning: z.string(),
  confidence: z.number().min(0).max(1),
  uncertainParts: z.array(z.string()).default([])
});
var VerdictSchema = z.object({
  score: z.number().min(0).max(1),
  issues: z.array(IssueSchema),
  isBlocking: z.boolean(),
  suggestion: z.string().optional(),
  agreementLevel: z.number().min(0).max(1)
});
var RoundRecordSchema = z.object({
  roundNum: z.number(),
  artifact: ArtifactSchema,
  verdict: VerdictSchema,
  timestamp: z.number()
});
var DisputeRecordSchema = z.object({
  topic: z.string(),
  generatorPosition: z.string(),
  criticPosition: z.string(),
  roundsUnresolved: z.number().default(0)
});
var AgentConfigSchema = z.object({
  maxRounds: z.number().default(5),
  qualityThreshold: z.number().default(0.85),
  convergenceThreshold: z.number().default(0.02),
  roiDecayFactor: z.number().default(2),
  loopSimilarityThreshold: z.number().default(0.92),
  enableEscalation: z.boolean().default(true)
});
var DecisionEnum = z.enum(["accept", "continue", "escalate"]);

// src/orchestrator.ts
var DEFAULT_CONFIG = AgentConfigSchema.parse({});
var DualAgentOrchestrator = class {
  generator;
  critic;
  config;
  convergence;
  loopDetector;
  roundHistory = [];
  disputes = [];
  /**
   * @param generator - Adapter for the Generator LLM.
   * @param critic - Adapter for the Critic LLM (can be the same or different model).
   * @param config - Partial configuration merged with sensible defaults.
   */
  constructor(generator, critic, config) {
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
  async run(task, context) {
    this.roundHistory = [];
    this.disputes = [];
    this.loopDetector.reset();
    let prevVerdict = null;
    let issuesForGenerator = [];
    for (let roundNum = 1; roundNum <= this.config.maxRounds; roundNum++) {
      const generatorPrompt = this.buildGeneratorPrompt(task, context, issuesForGenerator);
      const artifact = await this.generateArtifact(generatorPrompt);
      const criticPrompt = this.buildCriticPrompt(artifact, roundNum);
      const verdict = await this.critiqueArtifact(criticPrompt);
      const record = {
        roundNum,
        artifact,
        verdict,
        timestamp: Date.now()
      };
      this.roundHistory.push(record);
      this.trackDisputes(artifact, verdict, roundNum);
      const decision = this.evaluate(roundNum, verdict, prevVerdict);
      if (decision === "accept") {
        return artifact;
      }
      if (decision === "escalate") {
        return await this.escalate(task);
      }
      issuesForGenerator = this.filterIssues(verdict.issues, roundNum);
      prevVerdict = verdict;
    }
    return this.bestArtifact();
  }
  /**
   * Return the round history for inspection.
   */
  get history() {
    return this.roundHistory;
  }
  /**
   * Return tracked disputes for inspection.
   */
  get activeDisputes() {
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
  evaluate(roundNum, verdict, prevVerdict) {
    return this.convergence.evaluate(
      roundNum,
      verdict,
      prevVerdict,
      this.config,
      this.roundHistory
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
  async escalate(task) {
    const metaPrompt = this.buildMetaJudgePrompt(task);
    try {
      const response = await this.critic.generate(
        CRITIC_SYSTEM_PROMPT,
        metaPrompt,
        { temperature: 0.3, maxTokens: 2048 }
      );
      return this.parseMetaJudgeResponse(response);
    } catch (error) {
      console.warn("DualAgentOrchestrator: meta-judge escalation failed, falling back to best artifact.", error);
      return this.bestArtifact();
    }
  }
  /**
   * Try to parse the meta-judge response as a JSON artifact or
   * extract content as a plain-text artifact.
   */
  parseMetaJudgeResponse(response) {
    try {
      const parsed = JSON.parse(response);
      return ArtifactSchema.parse(parsed);
    } catch {
      return {
        content: response,
        reasoning: "Meta-judge selected this as the best resolution.",
        confidence: 0.8,
        uncertainParts: []
      };
    }
  }
  /**
   * Select the highest-scoring artifact from the round history.
   */
  bestArtifact() {
    if (this.roundHistory.length === 0) {
      return {
        content: "",
        reasoning: "No rounds completed.",
        confidence: 0,
        uncertainParts: []
      };
    }
    let best = this.roundHistory[0];
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
  filterIssues(issues, roundNum) {
    if (roundNum >= 3) return [];
    if (roundNum === 2) return issues.filter((i) => i.severity === "critical");
    return issues.filter(
      (i) => i.severity === "critical" || i.severity === "major"
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
  buildGeneratorPrompt(task, context, issues) {
    const parts = [`## Task
${task}`];
    if (context) {
      parts.push(`## Context
${context}`);
    }
    if (issues.length > 0) {
      const issueLines = issues.map(
        (issue, idx) => `${idx + 1}. [${issue.severity}] ${issue.description}${issue.location ? ` (at ${issue.location})` : ""}${issue.fixHint ? `
   Fix hint: ${issue.fixHint}` : ""}`
      );
      parts.push(
        `## Issues to Address from Previous Round
${issueLines.join("\n")}`
      );
    }
    parts.push(
      `
Provide your solution in the following JSON format:
{
  "content": "<your complete solution>",
  "reasoning": "<your step-by-step reasoning>",
  "confidence": <0.0-1.0>,
  "uncertainParts": ["<area1>", "<area2>"]
}`
    );
    return parts.join("\n\n");
  }
  /**
   * Build the user prompt for the Critic.
   *
   * Includes the artifact to review and any relevant history context.
   */
  buildCriticPrompt(artifact, roundNum) {
    const parts = [
      `## Artifact to Review (Round ${roundNum})

### Content
${artifact.content}`,
      `
### Generator's Reasoning
${artifact.reasoning}`,
      `
### Generator's Confidence
${artifact.confidence}`
    ];
    if (artifact.uncertainParts.length > 0) {
      parts.push(
        `
### Areas the Generator is Uncertain About
${artifact.uncertainParts.map((p) => `- ${p}`).join("\n")}`
      );
    }
    if (roundNum > 1 && this.roundHistory.length >= 2) {
      const prevRecord = this.roundHistory[this.roundHistory.length - 2];
      if (prevRecord) {
        parts.push(
          `
## Previous Round Summary
- Round ${prevRecord.roundNum} score: ${prevRecord.verdict.score}
- Previous issues: ${prevRecord.verdict.issues.length}`
        );
      }
    }
    parts.push(
      `
Provide your review in the following JSON format:
{
  "score": <0.0-1.0>,
  "issues": [{"severity": "critical|major|minor|style", "description": "...", "location": "...", "fixHint": "..."}],
  "isBlocking": <true|false>,
  "suggestion": "<consolidated improvement suggestion or null>",
  "agreementLevel": <0.0-1.0>
}`
    );
    return parts.join("\n");
  }
  /**
   * Build the meta-judge prompt used during escalation.
   *
   * Summarizes all rounds and asks the Critic to select or synthesize
   * the best result.
   */
  buildMetaJudgePrompt(task) {
    const roundSummaries = this.roundHistory.map(
      (r) => `### Round ${r.roundNum}
- Score: ${r.verdict.score}
- Issues: ${r.verdict.issues.length}
- Blocking: ${r.verdict.isBlocking}
- Agreement: ${r.verdict.agreementLevel}
- Content excerpt: ${r.artifact.content.slice(0, 300)}...`
    ).join("\n\n");
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
  async generateArtifact(prompt) {
    try {
      const artifactSchema = {
        type: "object",
        properties: {
          content: { type: "string" },
          reasoning: { type: "string" },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          uncertainParts: {
            type: "array",
            items: { type: "string" }
          }
        },
        required: ["content", "reasoning", "confidence", "uncertainParts"],
        additionalProperties: false
      };
      const result = await this.generator.generateStructured(
        GENERATOR_SYSTEM_PROMPT,
        prompt,
        artifactSchema,
        { temperature: 0.7, maxTokens: 4096 }
      );
      return ArtifactSchema.parse(result);
    } catch (error) {
      console.warn("DualAgentOrchestrator: generateArtifact failed, returning fallback artifact.", error);
      return {
        content: "",
        reasoning: `Generation failed: ${error instanceof Error ? error.message : "unknown error"}`,
        confidence: 0,
        uncertainParts: ["entire output"]
      };
    }
  }
  /**
   * Call the Critic to produce a verdict.
   * Wraps the LLM call in try/catch so a single failure does not crash the run.
   */
  async critiqueArtifact(prompt) {
    try {
      const verdictSchema = {
        type: "object",
        properties: {
          score: { type: "number", minimum: 0, maximum: 1 },
          issues: {
            type: "array",
            items: {
              type: "object",
              properties: {
                severity: { type: "string", enum: ["critical", "major", "minor", "style"] },
                description: { type: "string" },
                location: { type: "string" },
                fixHint: { type: "string" }
              },
              required: ["severity", "description"],
              additionalProperties: false
            }
          },
          isBlocking: { type: "boolean" },
          suggestion: { type: "string" },
          agreementLevel: { type: "number", minimum: 0, maximum: 1 }
        },
        required: ["score", "issues", "isBlocking", "agreementLevel"],
        additionalProperties: false
      };
      const result = await this.critic.generateStructured(
        CRITIC_SYSTEM_PROMPT,
        prompt,
        verdictSchema,
        { temperature: 0.3, maxTokens: 4096 }
      );
      return VerdictSchema.parse(result);
    } catch (error) {
      console.warn("DualAgentOrchestrator: critiqueArtifact failed, returning fallback verdict.", error);
      return {
        score: 0,
        issues: [
          {
            severity: "critical",
            description: `Critique failed: ${error instanceof Error ? error.message : "unknown error"}`
          }
        ],
        isBlocking: true,
        agreementLevel: 0
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
  trackDisputes(artifact, verdict, roundNum) {
    if (verdict.agreementLevel < 0.3) {
      const existingTopic = verdict.suggestion ?? "general disagreement";
      const existing = this.disputes.find((d) => d.topic === existingTopic);
      if (existing) {
        existing.roundsUnresolved += 1;
      } else {
        this.disputes.push({
          topic: existingTopic,
          generatorPosition: artifact.reasoning.slice(0, 200),
          criticPosition: verdict.issues.map((i) => i.description).join("; ").slice(0, 200),
          roundsUnresolved: 1
        });
      }
    }
    if (verdict.agreementLevel > 0.8) {
      this.disputes = this.disputes.filter(
        (d) => d.roundsUnresolved === 0 || d.roundsUnresolved > roundNum
      );
    }
  }
};

// src/adapters/base.ts
var BaseAdapter = class {
};

// src/adapters/anthropic.ts
import Anthropic from "@anthropic-ai/sdk";
var AnthropicAdapter = class extends BaseAdapter {
  client;
  _model;
  defaultOptions;
  /**
   * @param model - Anthropic model ID (default `'claude-sonnet-4-6'`).
   * @param apiKey - Anthropic API key. Falls back to `ANTHROPIC_API_KEY` env var.
   * @param options - Default generation options applied to every call.
   */
  constructor(model = "claude-sonnet-4-6", apiKey, options) {
    super();
    this._model = model;
    this.client = new Anthropic({ apiKey: apiKey ?? process.env["ANTHROPIC_API_KEY"] });
    this.defaultOptions = options ?? {};
  }
  /** The model identifier used for API calls. */
  get modelName() {
    return this._model;
  }
  /**
   * Generate free-form text.
   *
   * @param systemPrompt - System-level instruction (passed as the `system` param).
   * @param userPrompt - User message.
   * @param options - Per-call overrides merged over constructor defaults.
   * @returns The text content of the assistant's response.
   */
  async generate(systemPrompt, userPrompt, options) {
    const merged = { ...this.defaultOptions, ...options };
    const response = await this.client.messages.create({
      model: this._model,
      system: systemPrompt,
      max_tokens: merged.maxTokens ?? 4096,
      temperature: merged.temperature,
      messages: [
        {
          role: "user",
          content: userPrompt
        }
      ]
    });
    const textBlock = response.content.find((block) => block.type === "text");
    return textBlock && "text" in textBlock ? textBlock.text : "";
  }
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
  async generateStructured(systemPrompt, userPrompt, outputSchema, options) {
    const merged = { ...this.defaultOptions, ...options };
    const response = await this.client.messages.create({
      model: this._model,
      system: systemPrompt,
      max_tokens: merged.maxTokens ?? 4096,
      temperature: merged.temperature,
      tools: [
        {
          name: "output",
          description: "Output the structured result",
          input_schema: outputSchema
        }
      ],
      tool_choice: { type: "tool", name: "output" },
      messages: [
        {
          role: "user",
          content: userPrompt
        }
      ]
    });
    const toolBlock = response.content.find((block) => block.type === "tool_use");
    if (!toolBlock || !("input" in toolBlock)) {
      throw new Error("AnthropicAdapter: no tool_use block returned from structured generation");
    }
    return toolBlock.input;
  }
};

// src/adapters/openai.ts
import OpenAI from "openai";
var OpenAIAdapter = class extends BaseAdapter {
  client;
  _model;
  defaultOptions;
  /**
   * @param model - OpenAI model ID (default `'gpt-4o'`).
   * @param apiKey - OpenAI API key. Falls back to `OPENAI_API_KEY` env var.
   * @param options - Default generation options applied to every call.
   */
  constructor(model = "gpt-4o", apiKey, options) {
    super();
    this._model = model;
    this.client = new OpenAI({ apiKey: apiKey ?? process.env["OPENAI_API_KEY"] });
    this.defaultOptions = options ?? {};
  }
  /** The model identifier used for API calls. */
  get modelName() {
    return this._model;
  }
  /**
   * Generate free-form text.
   *
   * @param systemPrompt - System-level instruction.
   * @param userPrompt - User message.
   * @param options - Per-call overrides merged over constructor defaults.
   * @returns The text content of the assistant's response.
   */
  async generate(systemPrompt, userPrompt, options) {
    const merged = { ...this.defaultOptions, ...options };
    const response = await this.client.chat.completions.create({
      model: this._model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt }
      ],
      max_tokens: merged.maxTokens,
      temperature: merged.temperature
    });
    return response.choices[0]?.message?.content ?? "";
  }
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
  async generateStructured(systemPrompt, userPrompt, outputSchema, options) {
    const merged = { ...this.defaultOptions, ...options };
    const response = await this.client.chat.completions.create({
      model: this._model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt }
      ],
      max_tokens: merged.maxTokens,
      temperature: merged.temperature,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "output",
          strict: true,
          schema: outputSchema
        }
      }
    });
    const raw = response.choices[0]?.message?.content ?? "{}";
    return this.parse(raw);
  }
  /**
   * Safely parse a JSON string into type T.
   * Logs a warning and returns an empty object on parse failure.
   */
  parse(raw) {
    try {
      return JSON.parse(raw);
    } catch {
      console.warn("OpenAIAdapter: failed to parse structured output, returning empty object");
      return {};
    }
  }
};
export {
  AgentConfigSchema,
  AnthropicAdapter,
  ArtifactSchema,
  BaseAdapter,
  CRITIC_SYSTEM_PROMPT,
  ConvergenceEngine,
  DecisionEnum,
  DisputeRecordSchema,
  DualAgentOrchestrator,
  GENERATOR_SYSTEM_PROMPT,
  IssueSchema,
  OpenAIAdapter,
  RoundRecordSchema,
  SemanticLoopDetector,
  SeverityEnum,
  VerdictSchema
};
