/**
 * code-generation.ts -- Advanced dual-agent code generation example (TypeScript).
 *
 * Shows a realistic scenario where the Generator writes a complete REST API
 * client and the Critic reviews it for correctness, error handling, and
 * idiomatic style.  The example demonstrates:
 *
 * - Configuring different models per role.
 * - Running a multi-round refinement loop.
 * - Inspecting round-by-round progress and persistent disputes.
 * - How the six-layer convergence protocol prevents infinite loops.
 *
 * Prerequisites:
 *   $ export ANTHROPIC_API_KEY="sk-ant-..."
 *   $ export OPENAI_API_KEY="sk-..."
 *
 * Run:
 *   # With tsx (recommended):
 *   $ npx tsx typescript/examples/code-generation.ts
 *
 *   # Or compile first:
 *   $ npx tsc && node typescript/dist/examples/code-generation.js
 */

import {
  DualAgentOrchestrator,
  AnthropicAdapter,
  OpenAIAdapter,
  AgentConfig,
  Severity,
} from '../src/index.js';

const TASK = `Write a REST API client for GitHub's "/users/{username}" endpoint.
The client must:

1. Accept a GitHub username and return a typed User interface
   with fields: login, name, avatarUrl, publicRepos, followers.
2. Include exponential backoff retry logic (3 retries, base delay 1s).
3. Handle these error cases explicitly:
   - HTTP 404 (user not found) -- throw UserNotFoundError
   - HTTP 403 (rate limited) -- throw RateLimitedError and include
     the Retry-After header value if present
   - HTTP 5xx -- retry with backoff, then throw ServiceUnavailableError
4. Add a configurable request timeout (default 30s).
5. Follow TypeScript best practices: strict types, JSDoc comments,
   async/await.
6. Write the code as a complete, runnable module (no stubs).

Use the native fetch API (Node 18+).  Do NOT use third-party GitHub SDKs.`;

async function main(): Promise<void> {
  // ------------------------------------------------------------------
  // Adapters: assign capable models to each role.
  // ------------------------------------------------------------------
  const generator = new AnthropicAdapter('claude-sonnet-4-6');
  const critic = new OpenAIAdapter('gpt-4o');

  // ------------------------------------------------------------------
  // Configuration: allow up to 5 rounds of revision.
  // ------------------------------------------------------------------
  const config: Partial<AgentConfig> = {
    maxRounds: 5,
    qualityThreshold: 0.88,
    convergenceThreshold: 0.02,
    roiDecayFactor: 2.0,
    loopSimilarityThreshold: 0.92,
    enableEscalation: true,
  };

  const orch = new DualAgentOrchestrator(generator, critic, config);

  // ------------------------------------------------------------------
  // Run
  // ------------------------------------------------------------------
  console.log('='.repeat(70));
  console.log('TASK: GitHub Users API Client (TypeScript)');
  console.log('='.repeat(70));
  console.log();

  const result = await orch.run(TASK);

  // ------------------------------------------------------------------
  // Final artifact
  // ------------------------------------------------------------------
  console.log('='.repeat(70));
  console.log('BEST ARTIFACT (final)');
  console.log('='.repeat(70));
  console.log(result.content);

  console.log('\n' + '-'.repeat(70));
  console.log(`Confidence: ${result.confidence.toFixed(2)}`);
  console.log(
    `Uncertain parts: ${result.uncertainParts.length > 0 ? result.uncertainParts.join(', ') : '(none)'}`,
  );
  console.log('-'.repeat(70));

  // ------------------------------------------------------------------
  // Round-by-round summary
  // ------------------------------------------------------------------
  console.log(`\n${'='.repeat(70)}`);
  console.log(`ROUND HISTORY (${orch.history.length} round(s))`);
  console.log(`${'='.repeat(70)}`);

  for (const rec of orch.history) {
    console.log(`\n--- Round ${rec.roundNum} ---`);
    console.log(`  Score:          ${rec.verdict.score.toFixed(3)}`);
    console.log(`  Blocking:       ${rec.verdict.isBlocking}`);
    console.log(`  Agreement:      ${rec.verdict.agreementLevel.toFixed(3)}`);
    console.log(`  Issue count:    ${rec.verdict.issues.length}`);

    // Summarise issues by severity
    const bySeverity: Record<string, number> = {};
    for (const issue of rec.verdict.issues) {
      bySeverity[issue.severity] = (bySeverity[issue.severity] ?? 0) + 1;
    }
    if (Object.keys(bySeverity).length > 0) {
      console.log(`  By severity:    ${JSON.stringify(bySeverity)}`);
    }

    if (rec.verdict.suggestion) {
      console.log(
        `  Suggestion:     ${rec.verdict.suggestion.slice(0, 120)}...`,
      );
    }

    // Show a snippet of the artifact
    const snippet = rec.artifact.content.slice(0, 200).replace(/\n/g, ' ');
    console.log(`  Artifact (200): ${snippet}...`);
  }

  // ------------------------------------------------------------------
  // Dispute summary (if any persistent disagreements)
  // ------------------------------------------------------------------
  if (orch.activeDisputes.length > 0) {
    console.log(`\n${'='.repeat(70)}`);
    console.log(`DISPUTES (${orch.activeDisputes.length} tracked)`);
    console.log(`${'='.repeat(70)}`);
    for (const d of orch.activeDisputes) {
      console.log(`\n  Topic:              ${d.topic}`);
      console.log(`  Rounds unresolved:  ${d.roundsUnresolved}`);
      console.log(
        `  Generator position: ${d.generatorPosition.slice(0, 120)}...`,
      );
      console.log(
        `  Critic position:    ${d.criticPosition.slice(0, 120)}...`,
      );
    }
  } else {
    console.log('\n(No disputes persisted across rounds.)');
  }
}

main().catch((err) => {
  console.error('Orchestration failed:', err);
  process.exit(1);
});
