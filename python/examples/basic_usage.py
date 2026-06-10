"""basic_usage.py -- Quick-start example for dual-agent-sdk.

Demonstrates the simplest possible Generator-Critic workflow:
1. Configure two LLM adapters (Anthropic Claude for generation, OpenAI GPT-4o for critique).
2. Define a task.
3. Run the orchestrator and inspect the result.

Prerequisites:
    $ export ANTHROPIC_API_KEY="sk-ant-..."
    $ export OPENAI_API_KEY="sk-..."

Run:
    $ python python/examples/basic_usage.py
"""

import asyncio

from dual_agent_sdk import (
    AgentConfig,
    AnthropicAdapter,
    DualAgentOrchestrator,
    OpenAIAdapter,
)


async def main() -> None:
    # ------------------------------------------------------------------
    # 1. Create adapters -- one for each role
    # ------------------------------------------------------------------
    # The Generator produces solutions.  Here we give it Claude Sonnet,
    # which excels at long-form code generation and reasoning.
    generator = AnthropicAdapter(model="claude-sonnet-4-6")

    # The Critic reviews the Generator's output.  GPT-4o is a strong
    # reviewer that catches edge cases and logic errors.
    critic = OpenAIAdapter(model="gpt-4o")

    # ------------------------------------------------------------------
    # 2. (Optional) Tune behaviour via AgentConfig
    # ------------------------------------------------------------------
    config = AgentConfig(
        max_rounds=3,             # stop after at most 3 rounds
        quality_threshold=0.85,   # auto-accept if score >= 0.85 & no blockers
        enable_escalation=True,   # let the meta-judge break deadlocks
    )

    # ------------------------------------------------------------------
    # 3. Create the orchestrator
    # ------------------------------------------------------------------
    orch = DualAgentOrchestrator(
        generator=generator,
        critic=critic,
        config=config,
    )

    # ------------------------------------------------------------------
    # 4. Run a task
    # ------------------------------------------------------------------
    task = "Write a Python function to validate email addresses."

    print("=" * 60)
    print("Running dual-agent loop...")
    print("=" * 60)

    result = await orch.run(task)

    # ------------------------------------------------------------------
    # 5. Inspect the result
    # ------------------------------------------------------------------
    print("\n--- Best Artifact ---")
    print(result.content)

    print(f"\nConfidence: {result.confidence:.2f}")
    print(f"Reasoning:  {result.reasoning[:200]}...")

    # ------------------------------------------------------------------
    # 6. Inspect the round history
    # ------------------------------------------------------------------
    print(f"\nRounds completed: {len(orch.round_history)}")
    for record in orch.round_history:
        print(
            f"  Round {record.round_num}: "
            f"score={record.verdict.score:.2f}, "
            f"issues={len(record.verdict.issues)}, "
            f"blocking={record.verdict.is_blocking}"
        )

    # ------------------------------------------------------------------
    # 7. Check for unresolved disputes
    # ------------------------------------------------------------------
    if orch.disputes:
        print(f"\nDisputes tracked: {len(orch.disputes)}")
        for d in orch.disputes:
            print(f"  - {d.topic} (unresolved for {d.rounds_unresolved} round(s))")


if __name__ == "__main__":
    asyncio.run(main())
