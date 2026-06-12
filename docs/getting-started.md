# Getting Started

This guide walks you through installing Dual Agent SDK and running your first Generator-Critic collaboration.

---

## Prerequisites

- **Python 3.10+** (for the Python package) or **Node 18+** (for TypeScript)
- An **Anthropic API key** (set as `ANTHROPIC_API_KEY`) for the Generator role
- An **OpenAI API key** (set as `OPENAI_API_KEY`) for the Critic role

You can use the same provider for both roles, but using different providers reduces correlated errors and increases review diversity. You can also use any combination of models -- e.g., Claude Opus for generation and Claude Haiku for critique.

---

## Installation

### Python

```bash
pip install dual-agent-sdk
```

The Python package depends on `pydantic>=2.0`, `anthropic>=0.30.0`, and `openai>=1.0.0`.

### TypeScript

```bash
npm install dual-agent-sdk
```

The TypeScript package depends on `@anthropic-ai/sdk`, `openai`, and `zod`.

---

## Set Environment Variables

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
```

---

## 5-Minute Quickstart (Python)

Create a file called `quickstart.py`:

```python
import asyncio
from dual_agent_sdk import (
    DualAgentOrchestrator,
    AnthropicAdapter,
    OpenAIAdapter,
    AgentConfig,
)

async def main():
    # Step 1: Create adapters
    generator = AnthropicAdapter(model="claude-sonnet-4-6")
    critic = OpenAIAdapter(model="gpt-4o")

    # Step 2: Configure the orchestrator (optional)
    config = AgentConfig(
        max_rounds=3,
        quality_threshold=0.85,
    )

    # Step 3: Create and run
    orch = DualAgentOrchestrator(generator, critic, config)
    result = await orch.run(
        "Write a Python function to parse ISO 8601 date strings."
    )

    # Step 4: Use the result
    print(result.content)
    print(f"\nConfidence: {result.confidence:.2f}")

    # Step 5: Inspect what happened
    for rec in orch.round_history:
        print(
            f"Round {rec.round_num}: "
            f"score={rec.verdict.score:.2f}, "
            f"issues={len(rec.verdict.issues)}"
        )

asyncio.run(main())
```

Run it:

```bash
python quickstart.py
```

You should see the Generator produce a solution, the Critic review it, and the orchestrator return the best version. If the first attempt is already high-quality (score >= 0.85 with no blocking issues), the loop stops after one round.

---

## 5-Minute Quickstart (TypeScript)

Create a file called `quickstart.ts`:

```typescript
import {
  DualAgentOrchestrator,
  AnthropicAdapter,
  OpenAIAdapter,
  AgentConfig,
} from 'dual-agent-sdk';

async function main() {
  // Step 1: Create adapters
  const generator = new AnthropicAdapter('claude-sonnet-4-6');
  const critic = new OpenAIAdapter('gpt-4o');

  // Step 2: Configure (optional)
  const config: Partial<AgentConfig> = {
    maxRounds: 3,
    qualityThreshold: 0.85,
  };

  // Step 3: Create and run
  const orch = new DualAgentOrchestrator(generator, critic, config);
  const result = await orch.run(
    'Write a TypeScript function to parse ISO 8601 date strings.',
  );

  // Step 4: Use the result
  console.log(result.content);
  console.log(`\nConfidence: ${result.confidence.toFixed(2)}`);

  // Step 5: Inspect what happened
  for (const rec of orch.history) {
    console.log(
      `Round ${rec.roundNum}: score=${rec.verdict.score.toFixed(2)}, issues=${rec.verdict.issues.length}`,
    );
  }
}

main().catch(console.error);
```

Run it:

```bash
npx tsx quickstart.ts
```

---

## Common Configuration Options

The `AgentConfig` (Python) / `AgentConfig` (TypeScript) model controls every aspect of the convergence protocol:

| Parameter | Default | Description |
|---|---|---|
| `max_rounds` / `maxRounds` | 5 | Hard ceiling on generate-critique cycles. |
| `quality_threshold` / `qualityThreshold` | 0.85 | If the verdict score meets this AND there are no blocking issues, accept immediately. |
| `convergence_threshold` / `convergenceThreshold` | 0.02 | If the score delta between rounds is below this, accept. |
| `roi_decay_factor` / `roiDecayFactor` | 2.0 | Exponent base for diminishing-returns acceptance. Higher = more willing to stop early. |
| `loop_similarity_threshold` / `loopSimilarityThreshold` | 0.92 | Jaccard similarity above which two outputs are considered a semantic loop. |
| `enable_escalation` / `enableEscalation` | `true` | Whether to invoke the meta-judge on deadlock. |

Example tuning for a fast, low-cost run:

```python
config = AgentConfig(max_rounds=2, quality_threshold=0.75, enable_escalation=False)
```

Example tuning for maximum quality (at higher cost):

```python
config = AgentConfig(
    max_rounds=10,
    quality_threshold=0.95,
    convergence_threshold=0.005,
    roi_decay_factor=1.5,
)
```

---

## Using Different Models Per Role

You are not limited to the defaults. Any combination of adapters is valid:

```python
# Powerful generator, fast critic
gen = AnthropicAdapter(model="claude-opus-4-6")
crit = AnthropicAdapter(model="claude-haiku-4-6")

# OpenAI generator, Anthropic critic
gen = OpenAIAdapter(model="gpt-4o")
crit = AnthropicAdapter(model="claude-sonnet-4-6")

# Same provider, same model (discouraged but possible)
gen = OpenAIAdapter(model="gpt-4o")
crit = OpenAIAdapter(model="gpt-4o")  # different instance!
```

The only hard rule: the generator and critic must be **distinct adapter instances**. Passing the same instance to both roles raises a `ValueError`.

---

## What Happens Under the Hood

1. The **Generator** receives the task (plus any previous critic feedback) and produces an `Artifact` -- the solution content, a reasoning chain, a confidence score, and a list of uncertain parts.

2. The **Critic** receives the task and the artifact. It returns a `Verdict` -- an overall score, a list of `Issue` objects (each with severity, description, location, and fix hint), a blocking flag, and an agreement level.

3. The **ConvergenceEngine** runs six checks in order:
   - Hard ceiling (round limit)
   - Quality threshold
   - Score convergence
   - Issue decay
   - ROI check
   - Semantic loop detection

4. If the decision is `"continue"`, the issues are filtered by severity (more aggressive filtering in later rounds) and fed back to the Generator for the next round.

5. If the decision is `"accept"`, the best artifact across all rounds is returned.

6. If the decision is `"escalate"`, a meta-judge (the Critic in tie-breaker mode) reviews all rounds and selects or synthesizes the best result.

---

## Next Steps

- Read the **[Architecture](./architecture.md)** document to understand the state machine in depth.
- Explore the **[API Reference](./api-reference.md)** for every class and method.
- Learn how to **[tune the convergence protocol](./convergence-protocol.md)** for your use case.
- See how to **[write custom adapters](./adapters.md)** for your own LLM backends.
- Walk through the **[Code Review Tutorial](./examples/code-review.md)**.
