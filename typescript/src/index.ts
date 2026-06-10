// ---------------------------------------------------------------------------
// Dual-Agent SDK — Unified exports
// ---------------------------------------------------------------------------

// Core orchestrator
export { DualAgentOrchestrator } from './orchestrator.js';

// Convergence engine (6-layer anti-loop protocol)
export { ConvergenceEngine } from './convergence.js';

// Semantic loop detector (standalone, reusable)
export { SemanticLoopDetector } from './loop-detector.js';

// LLM adapters
export { BaseAdapter } from './adapters/base.js';
export { AnthropicAdapter } from './adapters/anthropic.js';
export { OpenAIAdapter } from './adapters/openai.js';

// System prompts
export { GENERATOR_SYSTEM_PROMPT } from './prompts/generator.js';
export { CRITIC_SYSTEM_PROMPT } from './prompts/critic.js';

// Zod schemas (for runtime validation)
export {
  ArtifactSchema,
  VerdictSchema,
  IssueSchema,
  RoundRecordSchema,
  DisputeRecordSchema,
  AgentConfigSchema,
  SeverityEnum,
  DecisionEnum,
} from './models.js';

// TypeScript types (derived from schemas)
export type {
  Artifact,
  Verdict,
  Issue,
  RoundRecord,
  DisputeRecord,
  AgentConfig,
  Severity,
  Decision,
} from './models.js';

// Utility types
export type { GenerateOptions } from './adapters/base.js';
