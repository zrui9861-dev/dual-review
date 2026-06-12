/**
 * basic-usage.ts -- Quick-start example for dual-agent-sdk (TypeScript).
 *
 * Demonstrates the simplest Generator-Critic workflow:
 * 1. Create two LLM adapters (Anthropic Claude for generation, OpenAI for critique).
 * 2. Configure the orchestrator with custom settings.
 * 3. Run a task and inspect the result and round history.
 *
 * Prerequisites:
 *   $ export ANTHROPIC_API_KEY="sk-ant-..."
 *   $ export OPENAI_API_KEY="sk-..."
 *
 * Run:
 *   # With tsx (recommended):
 *   $ npx tsx typescript/examples/basic-usage.ts
 *
 *   # Or compile first:
 *   $ npx tsc && node typescript/dist/examples/basic-usage.js
 *
 *   # Or from the typescript directory with ts-node:
 *   $ cd typescript && npx tsx examples/basic-usage.ts
 */

import {
  DualAgentOrchestrator,
  AnthropicAdapter,
  OpenAIAdapter,
  AgentConfig,
} from '../src/index.js';

async function main(): Promise<void> {
  // ------------------------------------------------------------------
  // 1. Create adapters -- one for each role
  // ------------------------------------------------------------------
  // The Generator produces solutions.  Claude Sonnet excels at
  // long-form code generation and step-by-step reasoning.
  const generator = new AnthropicAdapter('claude-sonnet-4-6');

  // The Critic reviews the output.  GPT-4o is a strong reviewer that
  // catches edge cases, logic errors, and style issues.
  const critic = new OpenAIAdapter('gpt-4o');

  // ------------------------------------------------------------------
  // 2. (Optional) Tune behaviour via agent config
  // ------------------------------------------------------------------
  const config: Partial<AgentConfig> = {
    maxRounds: 3,             // stop after at most 3 rounds
    qualityThreshold: 0.85,   // auto-accept if score >= 0.85 & no blockers
    enableEscalation: true,   // let the meta-judge break deadlocks
  };

  // ------------------------------------------------------------------
  // 3. Create the orchestrator
  // ------------------------------------------------------------------
  const orch = new DualAgentOrchestrator(generator, critic, config);

  // ------------------------------------------------------------------
  // 4. Run a task
  // ------------------------------------------------------------------
  const task = 'Write a TypeScript function to validate email addresses.';

  console.log('='.repeat(60));
  console.log('Running dual-agent loop...');
  console.log('='.repeat(60));

  const result = await orch.run(task);

  // ------------------------------------------------------------------
  // 5. Inspect the result
  // ------------------------------------------------------------------
  console.log('\n--- Best Artifact ---');
  console.log(result.content);

  console.log(`\nConfidence: ${result.confidence.toFixed(2)}`);
  console.log(`Reasoning:  ${result.reasoning.slice(0, 200)}...`);

  if (result.uncertainParts.length > 0) {
    console.log(`Uncertain parts: ${result.uncertainParts.join(', ')}`);
  }

  // ------------------------------------------------------------------
  // 6. Inspect the round history
  // ------------------------------------------------------------------
  console.log(`\nRounds completed: ${orch.history.length}`);
  for (const record of orch.history) {
    console.log(
      `  Round ${record.roundNum}: ` +
      `score=${record.verdict.score.toFixed(2)}, ` +
      `issues=${record.verdict.issues.length}, ` +
      `blocking=${record.verdict.isBlocking}`,
    );
  }

  // ------------------------------------------------------------------
  // 7. Check for unresolved disputes
  // ------------------------------------------------------------------
  if (orch.activeDisputes.length > 0) {
    console.log(`\nDisputes tracked: ${orch.activeDisputes.length}`);
    for (const d of orch.activeDisputes) {
      console.log(
        `  - ${d.topic} (unresolved for ${d.roundsUnresolved} round(s))`,
      );
    }
  } else {
    console.log('\n(No unresolved disputes.)');
  }
}

main().catch((err) => {
  console.error('Orchestration failed:', err);
  process.exit(1);
});
