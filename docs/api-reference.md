# API Reference

Complete reference for every public class, method, and type in Dual Agent SDK. Covers both Python and TypeScript.

---

## DualAgentOrchestrator

The main entry point. Manages the Generator-Critic state machine.

### Constructor

**Python:**
```python
DualAgentOrchestrator(
    generator: BaseAdapter,
    critic: BaseAdapter,
    config: AgentConfig | None = None,
)
```

**TypeScript:**
```typescript
new DualAgentOrchestrator(
    generator: BaseAdapter,
    critic: BaseAdapter,
    config?: Partial<AgentConfig>,
)
```

| Parameter | Type | Description |
|---|---|---|
| `generator` | `BaseAdapter` | LLM adapter for the Generator role. |
| `critic` | `BaseAdapter` | LLM adapter for the Critic role. Must be a different instance. |
| `config` | `AgentConfig` (optional) | Convergence and loop control parameters. Defaults are used if omitted. |

Raises `ValueError` if `generator is critic` (Python) or both arguments reference the same object.

### run()

**Python:**
```python
async def run(self, task: str, context: str | None = None) -> Artifact
```

**TypeScript:**
```typescript
async run(task: string, context?: string): Promise<Artifact>
```

Executes the full Generator-Critic loop until convergence. Returns the best `Artifact` produced.

| Parameter | Type | Description |
|---|---|---|
| `task` | `str` | The problem statement or task description. |
| `context` | `str` (optional) | Additional context: previous work, constraints, domain knowledge. |

### round_history / history

**Python:** `orchestrator.round_history: list[RoundRecord]`

**TypeScript:** `orchestrator.history: ReadonlyArray<RoundRecord>`

The complete audit trail of all Generator-Critic rounds. Each entry contains the round number, the artifact produced, the verdict received, and a timestamp.

### disputes / activeDisputes

**Python:** `orchestrator.disputes: list[DisputeRecord]`

**TypeScript:** `orchestrator.activeDisputes: ReadonlyArray<DisputeRecord>`

Persistent disagreements between Generator and Critic that span multiple rounds.

---

## AgentConfig

Tunable parameters for the convergence protocol.

**Python:**
```python
from dual_agent_sdk import AgentConfig

config = AgentConfig(
    max_rounds=5,
    quality_threshold=0.85,
    convergence_threshold=0.02,
    roi_decay_factor=2.0,
    loop_similarity_threshold=0.92,
    enable_escalation=True,
)
```

**TypeScript:**
```typescript
const config: Partial<AgentConfig> = {
  maxRounds: 5,
  qualityThreshold: 0.85,
  convergenceThreshold: 0.02,
  roiDecayFactor: 2.0,
  loopSimilarityThreshold: 0.92,
  enableEscalation: true,
};
```

| Parameter | Python / TypeScript | Default | Description |
|---|---|---|---|
| Max rounds | `max_rounds` / `maxRounds` | `5` | Hard ceiling on Generate-Critique cycles (min 1). |
| Quality threshold | `quality_threshold` / `qualityThreshold` | `0.85` | Score at which artifact is auto-accepted (if no blockers). Range 0-1. |
| Convergence threshold | `convergence_threshold` / `convergenceThreshold` | `0.02` | Score delta below which loop terminates (diminishing returns). |
| ROI decay factor | `roi_decay_factor` / `roiDecayFactor` | `2.0` | Exponent base for diminishing-returns acceptance (min 1.0). |
| Loop similarity | `loop_similarity_threshold` / `loopSimilarityThreshold` | `0.92` | Jaccard similarity above which output is considered a semantic loop. Range 0-1. |
| Enable escalation | `enable_escalation` / `enableEscalation` | `True` | Whether to invoke meta-judge when a semantic loop is detected. |

---

## Artifact

The Generator's output for a single round.

| Field | Python | TypeScript | Type | Description |
|---|---|---|---|---|
| Content | `content` | `content` | `str` / `string` | The complete solution content. |
| Reasoning | `reasoning` | `reasoning` | `str` / `string` | The Generator's reasoning chain. |
| Confidence | `confidence` | `confidence` | `float` / `number` | Self-assessed confidence (0.0 to 1.0). |
| Uncertain parts | `uncertain_parts` | `uncertainParts` | `list[str]` / `string[]` | Parts the Generator is unsure about. |

**Python usage:**
```python
artifact = await orch.run("Write a sorting function.")
print(artifact.content)        # The solution
print(artifact.confidence)     # e.g. 0.87
print(artifact.uncertain_parts)  # ["edge case: empty list", "performance for large N"]
```

**TypeScript usage:**
```typescript
const artifact = await orch.run('Write a sorting function.');
console.log(artifact.content);
console.log(artifact.uncertainParts);
```

---

## Verdict

The Critic's structured review of one artifact.

| Field | Python | TypeScript | Type | Description |
|---|---|---|---|---|
| Score | `score` | `score` | `float` / `number` | Overall quality (0.0 to 1.0). |
| Issues | `issues` | `issues` | `list[Issue]` / `Issue[]` | Specific problems found. |
| Blocking | `is_blocking` | `isBlocking` | `bool` / `boolean` | Whether issues fundamentally block acceptance. |
| Suggestion | `suggestion` | `suggestion` | `str` (optional) / `string \| undefined` | Consolidated improvement suggestion. |
| Agreement | `agreement_level` | `agreementLevel` | `float` / `number` | How much Critic agrees with Generator's approach. Range 0-1. |

---

## Issue

A single finding reported by the Critic.

| Field | Python | TypeScript | Type | Description |
|---|---|---|---|---|
| Severity | `severity` | `severity` | `Severity` | One of `critical`, `major`, `minor`, `style`. |
| Description | `description` | `description` | `str` / `string` | What the problem is. |
| Location | `location` | `location` | `str` (optional) / `string \| undefined` | Where in the artifact the problem occurs. |
| Fix hint | `fix_hint` | `fixHint` | `str` (optional) / `string \| undefined` | How to fix it. |

---

## Severity Levels

The `Severity` type is a string literal union:

| Level | Meaning | Examples |
|---|---|---|
| `critical` | Wrong, unsafe, or would not work at all. | Security vulnerability, incorrect algorithm, syntax error that breaks the code. |
| `major` | Significant flaw that causes problems in many cases. | Missing error handling, O(n^2) where O(n log n) is expected, race condition. |
| `minor` | Improvement that would make the solution better but is not required. | Missing type hint, suboptimal variable name, could use a more idiomatic pattern. |
| `style` | Cosmetic or preference-based feedback. | Line length, whitespace, comment formatting, naming conventions. |

The severity determines how the issue is filtered across rounds (see [Convergence Protocol](./convergence-protocol.md)).

---

## Decision

The state-machine outcome after a convergence check.

| Value | Meaning |
|---|---|
| `"accept"` | Stop the loop and return the best artifact. |
| `"continue"` | Proceed to the next generator-critique round. |
| `"escalate"` | Invoke meta-judge deadlock resolution. |

---

## RoundRecord

An immutable audit-trail entry for one complete round.

| Field | Python | TypeScript | Type | Description |
|---|---|---|---|---|
| Round number | `round_num` | `roundNum` | `int` / `number` | 1-based round index. |
| Artifact | `artifact` | `artifact` | `Artifact` | The Generator's output. |
| Verdict | `verdict` | `verdict` | `Verdict` | The Critic's review. |
| Timestamp | `timestamp` | `timestamp` | `float` / `number` | Unix timestamp when the round completed. |

---

## DisputeRecord

Captures a persistent disagreement between Generator and Critic.

| Field | Python | TypeScript | Type | Description |
|---|---|---|---|---|
| Topic | `topic` | `topic` | `str` / `string` | What the disagreement is about (from verdict's suggestion). |
| Generator position | `generator_position` | `generatorPosition` | `str` / `string` | The Generator's stance (from reasoning). |
| Critic position | `critic_position` | `criticPosition` | `str` / `string` | The Critic's stance (from feedback). |
| Rounds unresolved | `rounds_unresolved` | `roundsUnresolved` | `int` / `number` | How many rounds this dispute has persisted. |

---

## BaseAdapter

Abstract base class for LLM adapters. Implement this to add a new provider.

**Python:**
```python
from dual_agent_sdk import BaseAdapter

class MyAdapter(BaseAdapter):
    @property
    def model_name(self) -> str:
        return "my-model"

    async def generate(self, system_prompt: str, user_prompt: str, **kwargs) -> str:
        ...  # Your implementation

    async def generate_structured(
        self, system_prompt: str, user_prompt: str,
        output_schema: dict, **kwargs,
    ) -> dict:
        ...  # Your implementation
```

**TypeScript:**
```typescript
import { BaseAdapter, GenerateOptions } from 'dual-agent-sdk';

class MyAdapter extends BaseAdapter {
  get modelName(): string { return 'my-model'; }

  async generate(
    systemPrompt: string, userPrompt: string, options?: GenerateOptions
  ): Promise<string> { /* ... */ }

  async generateStructured<T>(
    systemPrompt: string, userPrompt: string,
    outputSchema: Record<string, unknown>, options?: GenerateOptions
  ): Promise<T> { /* ... */ }
}
```

### Methods

| Method | Python | TypeScript | Returns |
|---|---|---|---|
| Free-form generation | `generate(system_prompt, user_prompt, **kwargs)` | `generate(systemPrompt, userPrompt, options?)` | `str` / `Promise<string>` |
| Structured generation | `generate_structured(system_prompt, user_prompt, output_schema, **kwargs)` | `generateStructured<T>(systemPrompt, userPrompt, outputSchema, options?)` | `dict` / `Promise<T>` |
| Model name | `model_name` (property) | `modelName` (getter) | `str` / `string` |

---

## AnthropicAdapter

Built-in adapter for Anthropic's Claude models.

**Python:**
```python
from dual_agent_sdk import AnthropicAdapter

adapter = AnthropicAdapter(
    model="claude-sonnet-4-6",   # default
    api_key=None,                 # reads ANTHROPIC_API_KEY env var if None
    # **kwargs forwarded to anthropic.AsyncAnthropic()
)
```

**TypeScript:**
```typescript
import { AnthropicAdapter } from 'dual-agent-sdk';

const adapter = new AnthropicAdapter(
  'claude-sonnet-4-6',  // default
  undefined,            // reads ANTHROPIC_API_KEY env var if undefined
  {},                   // default GenerateOptions
);
```

Structured generation uses Anthropic's tool-use mechanism: a single tool is defined whose `input_schema` matches the desired output schema, and `tool_choice` forces the model to call it.

---

## OpenAIAdapter

Built-in adapter for OpenAI's GPT models.

**Python:**
```python
from dual_agent_sdk import OpenAIAdapter

adapter = OpenAIAdapter(
    model="gpt-4o",      # default
    api_key=None,         # reads OPENAI_API_KEY env var if None
    # **kwargs forwarded to openai.AsyncOpenAI()
)
```

**TypeScript:**
```typescript
import { OpenAIAdapter } from 'dual-agent-sdk';

const adapter = new OpenAIAdapter(
  'gpt-4o',     // default
  undefined,    // reads OPENAI_API_KEY env var if undefined
  {},           // default GenerateOptions
);
```

Structured generation uses OpenAI's `response_format` with `json_schema` mode. Falls back to text generation with JSON extraction if the model does not support `json_schema`.

---

## ConvergenceEngine

The chain-of-responsibility engine that evaluates the six convergence layers.

**Python:**
```python
from dual_agent_sdk import ConvergenceEngine

engine = ConvergenceEngine()
decision = engine.evaluate(round_num, verdict, prev_verdict, config, history)
# Returns: "accept", "continue", or "escalate"
```

**TypeScript:**
```typescript
import { ConvergenceEngine } from 'dual-agent-sdk';

const engine = new ConvergenceEngine(config);
const decision = engine.evaluate(roundNum, verdict, prevVerdict, config, history);
```

Most users will never interact with `ConvergenceEngine` directly -- the orchestrator manages it internally. It is exposed for advanced use cases like custom orchestrators or testing individual layers.

---

## SemanticLoopDetector

Sliding-window detector for semantic repetition.

**Python:**
```python
from dual_agent_sdk import SemanticLoopDetector

detector = SemanticLoopDetector(threshold=0.92, window_size=3)
detector.add("some text from round 1")
detector.add("some text from round 2")
is_loop = detector.is_looping("similar text from round 3")  # True/False

# Embedding-based check (higher accuracy):
is_loop = await detector.check_with_embedding(text, my_embed_fn)
```

**TypeScript:**
```typescript
import { SemanticLoopDetector } from 'dual-agent-sdk';

const detector = new SemanticLoopDetector(0.92, 3);
detector.add('some text from round 1');
detector.add('some text from round 2');
const isLoop = detector.isLooping('similar text from round 3'); // boolean
```

### Methods

| Method | Python | TypeScript | Description |
|---|---|---|---|
| Add text | `add(text: str)` | `add(text: string)` | Append text to the comparison window. |
| Jaccard check | `is_looping(new_text: str) -> bool` | `isLooping(newText: string): boolean` | Check if `new_text` is too similar to recent history (word-level Jaccard). |
| Embedding check | `check_with_embedding(new_text, fn) -> bool` | *(async, see Python)* | Cosine-similarity check using embedding vectors. |
| Reset | `_history.clear()` (manual) | `reset()` | Clear the comparison window. |

---

## System Prompts

Built-in system prompts for the Generator and Critic roles.

**Python:**
```python
from dual_agent_sdk import GENERATOR_SYSTEM_PROMPT, CRITIC_SYSTEM_PROMPT

# Use them directly, or override with custom prompts:
adapter.generate(system_prompt=GENERATOR_SYSTEM_PROMPT, user_prompt="...")
```

**TypeScript:**
```typescript
import { GENERATOR_SYSTEM_PROMPT, CRITIC_SYSTEM_PROMPT } from 'dual-agent-sdk';
```

These are the prompts used internally by the orchestrator. You can import them for use in custom orchestrators or when building standalone generator/critic flows outside the full loop.

### GENERATOR_SYSTEM_PROMPT

Instructs the LLM to act as the Generator: produce complete solutions, mark uncertain parts, make substantive changes when receiving feedback, and stand ground against incorrect criticism.

### CRITIC_SYSTEM_PROMPT

Instructs the LLM to act as the Critic: find factual errors, logical flaws, and inefficiencies; classify by severity; provide specific fix hints; acknowledge when feedback was addressed; mark blocking disagreements.

---

## TypeScript: GenerateOptions

Options passed to adapter `generate`/`generateStructured` methods.

```typescript
export interface GenerateOptions {
  temperature?: number;   // Sampling temperature (0.0–2.0)
  maxTokens?: number;     // Maximum tokens to generate
  [key: string]: unknown; // Provider-specific extensions
}
```

---

## TypeScript: Zod Schemas

Runtime validation schemas are exported for use in custom code:

```typescript
import {
  ArtifactSchema,
  VerdictSchema,
  IssueSchema,
  RoundRecordSchema,
  DisputeRecordSchema,
  AgentConfigSchema,
  SeverityEnum,
  DecisionEnum,
} from 'dual-agent-sdk';

// Validate external data:
const parsed = ArtifactSchema.parse(someUntrustedData);

// Infer types:
type MyArtifact = z.infer<typeof ArtifactSchema>;
```
