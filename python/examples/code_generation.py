"""code_generation.py -- Advanced dual-agent code generation example.

Shows a realistic scenario where the Generator writes a complete REST API
client and the Critic reviews it for correctness, error handling, and
idiomatic style.  The example demonstrates:

- How to configure different models per role.
- How to run the orchestrator with a complex, multi-paragraph task.
- How to inspect round-by-round progress and persistent disputes.
- How the six-layer convergence protocol prevents infinite loops.

Prerequisites:
    $ export ANTHROPIC_API_KEY="sk-ant-..."
    $ export OPENAI_API_KEY="sk-..."

Run:
    $ python python/examples/code_generation.py
"""

import asyncio
import textwrap

from dual_agent_sdk import (
    AgentConfig,
    AnthropicAdapter,
    DualAgentOrchestrator,
    OpenAIAdapter,
)


TASK = textwrap.dedent("""\
    Write a REST API client for GitHub's "/users/{username}" endpoint.
    The client must:

    1. Accept a GitHub username and return a typed User dataclass/dict
       with fields: login, name, avatar_url, public_repos, followers.
    2. Include exponential backoff retry logic (3 retries, base delay 1s).
    3. Handle these error cases explicitly:
       - HTTP 404 (user not found) -- raise UserNotFoundError
       - HTTP 403 (rate limited) -- raise RateLimitedError and include
         the Retry-After header value if present
       - HTTP 5xx -- retry with backoff, then raise ServiceUnavailableError
    4. Add a configurable request timeout (default 30s).
    5. Follow Python best practices: type hints, docstrings, context
       managers for HTTP sessions.
    6. Write the code as a complete, runnable module (no stubs).

    Use only the stdlib + the ``requests`` library (you may assume it is
    available).  Do NOT use third-party GitHub SDKs.
""")


async def main() -> None:
    # ------------------------------------------------------------------
    # Adapters: assign a capable models to each role.
    # ------------------------------------------------------------------
    # Generator — Claude Sonnet is well-suited for writing coherent,
    # long-form Python code with proper error handling.
    generator = AnthropicAdapter(model="claude-sonnet-4-6")

    # Critic — GPT-4o is used as the reviewer.  Using a different
    # provider / model family reduces correlated errors (both models
    # making the same mistake) and increases review diversity.
    critic = OpenAIAdapter(model="gpt-4o")

    # ------------------------------------------------------------------
    # Configuration: allow a few rounds of revision.
    # ------------------------------------------------------------------
    config = AgentConfig(
        max_rounds=5,                # up to 5 generate→critique cycles
        quality_threshold=0.88,      # strict quality bar
        convergence_threshold=0.02,  # stop if score barely improves
        roi_decay_factor=2.0,        # diminishing-returns base exponent
        loop_similarity_threshold=0.92,  # semantic loop detection sensitivity
        enable_escalation=True,      # invoke meta-judge on deadlock
    )

    orch = DualAgentOrchestrator(generator, critic, config)

    # ------------------------------------------------------------------
    # Run
    # ------------------------------------------------------------------
    print("=" * 70)
    print("TASK: GitHub Users API Client")
    print("=" * 70)
    print()

    result = await orch.run(TASK)

    # ------------------------------------------------------------------
    # Final artifact
    # ------------------------------------------------------------------
    print("=" * 70)
    print("BEST ARTIFACT (final)")
    print("=" * 70)
    print(result.content)

    print("\n" + "-" * 70)
    print(f"Confidence: {result.confidence:.2f}")
    print(f"Uncertain parts: {result.uncertain_parts or '(none)'}")
    print("-" * 70)

    # ------------------------------------------------------------------
    # Round-by-round summary
    # ------------------------------------------------------------------
    print(f"\n{'='*70}")
    print(f"ROUND HISTORY ({len(orch.round_history)} round(s))")
    print(f"{'='*70}")

    for rec in orch.round_history:
        print(f"\n--- Round {rec.round_num} ---")
        print(f"  Score:          {rec.verdict.score:.3f}")
        print(f"  Blocking:       {rec.verdict.is_blocking}")
        print(f"  Agreement:      {rec.verdict.agreement_level:.3f}")
        print(f"  Issue count:    {len(rec.verdict.issues)}")

        # Summarise issues by severity
        by_severity: dict[str, int] = {}
        for issue in rec.verdict.issues:
            by_severity[issue.severity] = by_severity.get(issue.severity, 0) + 1
        if by_severity:
            print(f"  By severity:    {by_severity}")

        if rec.verdict.suggestion:
            print(f"  Suggestion:     {rec.verdict.suggestion[:120]}...")

        # Show a snippet of the artifact
        snippet = rec.artifact.content[:200].replace("\n", " ")
        print(f"  Artifact (200): {snippet}...")

    # ------------------------------------------------------------------
    # Dispute summary (if any persistent disagreements)
    # ------------------------------------------------------------------
    if orch.disputes:
        print(f"\n{'='*70}")
        print(f"DISPUTES ({len(orch.disputes)} tracked)")
        print(f"{'='*70}")
        for d in orch.disputes:
            print(f"\n  Topic:              {d.topic}")
            print(f"  Rounds unresolved:  {d.rounds_unresolved}")
            print(f"  Generator position: {d.generator_position[:120]}...")
            print(f"  Critic position:    {d.critic_position[:120]}...")
    else:
        print("\n(No disputes persisted across rounds.)")


if __name__ == "__main__":
    asyncio.run(main())
