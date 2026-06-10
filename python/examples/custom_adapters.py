"""custom_adapters.py -- Building your own LLM adapter.

The dual-agent SDK is provider-agnostic.  You can plug in any LLM or
even a mock agent by subclassing ``BaseAdapter`` and implementing two
async methods: ``generate`` and ``generate_structured``.

This example shows:

1. **ConsoleAdapter** -- a human-in-the-loop adapter that reads from
   stdin.  Useful for testing orchestration logic without burning API
   credits, or for building interactive demos.

2. **LoggingAdapter** -- a decorator/wrapper that logs every prompt and
   response.  Demonstrates the decorator pattern for cross-cutting
   concerns like audit trails, cost tracking, or response caching.

The ``BaseAdapter`` interface is intentionally minimal:
    - ``generate(system_prompt, user_prompt, **kwargs) -> str``
    - ``generate_structured(system_prompt, user_prompt, output_schema, **kwargs) -> dict``
    - ``model_name`` (property) -> str

Run:
    $ python python/examples/custom_adapters.py

No API keys needed -- this example uses the console for input.
"""

import asyncio
import json
import sys
from typing import Any

from dual_agent_sdk import (
    AgentConfig,
    BaseAdapter,
    DualAgentOrchestrator,
)


# =========================================================================
# 1. ConsoleAdapter -- human-in-the-loop via stdin
# =========================================================================

class ConsoleAdapter(BaseAdapter):
    """An adapter that reads responses from the terminal.

    For each call to ``generate`` or ``generate_structured``, it prints
    the prompt to stdout and waits for the user to type a response.
    Press Ctrl-D on a new line to finish input.

    This is invaluable during development: you can step through the
    orchestrator's state machine manually to verify its control flow
    before wiring up real LLMs.
    """

    def __init__(self, name: str = "console") -> None:
        self._name = name

    @property
    def model_name(self) -> str:
        return self._name

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        **kwargs: Any,
    ) -> str:
        print("\n" + "=" * 60)
        print(f"[{self._name}] System prompt:")
        print(system_prompt[:500])
        print(f"\n[{self._name}] User prompt:")
        print(user_prompt[:1000])
        print("-" * 60)
        print("Enter your response (Ctrl-D to finish):")

        lines: list[str] = []
        for line in sys.stdin:
            lines.append(line)
        return "".join(lines).strip()

    async def generate_structured(
        self,
        system_prompt: str,
        user_prompt: str,
        output_schema: dict[str, Any],
        **kwargs: Any,
    ) -> dict[str, Any]:
        print("\n" + "=" * 60)
        print(f"[{self._name}] Structured generation requested.")
        print(f"Expected schema keys: {list(output_schema.get('properties', {}).keys())}")
        print("-" * 60)

        # For structured output, prompt for JSON.
        print("Enter JSON response matching the schema (Ctrl-D to finish):")
        text = ""
        for line in sys.stdin:
            text += line

        try:
            return json.loads(text.strip())
        except json.JSONDecodeError:
            print("Invalid JSON.  Returning empty dict as fallback.")
            return {}


# =========================================================================
# 2. LoggingAdapter -- decorator/wrapper with request logging
# =========================================================================

class LoggingAdapter(BaseAdapter):
    """Wraps any ``BaseAdapter`` and logs every interaction.

    Use this to:
    - Build an audit trail of every LLM call.
    - Track token usage and latency.
    - Debug prompts and responses without modifying the original adapter.

    The class delegates all actual work to the inner adapter.
    """

    def __init__(self, inner: BaseAdapter, log_file: str | None = None) -> None:
        self._inner = inner
        self._log_file = log_file
        self.call_count: int = 0

    @property
    def model_name(self) -> str:
        return f"log[{self._inner.model_name}]"

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        **kwargs: Any,
    ) -> str:
        self.call_count += 1
        call_id = self.call_count

        self._log(call_id, "generate", f"system={system_prompt[:100]}...")
        self._log(call_id, "generate", f"user={user_prompt[:200]}...")

        response = await self._inner.generate(system_prompt, user_prompt, **kwargs)

        self._log(call_id, "generate", f"response={response[:300]}...")
        return response

    async def generate_structured(
        self,
        system_prompt: str,
        user_prompt: str,
        output_schema: dict[str, Any],
        **kwargs: Any,
    ) -> dict[str, Any]:
        self.call_count += 1
        call_id = self.call_count

        self._log(call_id, "generate_structured",
                  f"system={system_prompt[:100]}...")
        self._log(call_id, "generate_structured",
                  f"user={user_prompt[:200]}...")

        result = await self._inner.generate_structured(
            system_prompt, user_prompt, output_schema, **kwargs
        )

        self._log(call_id, "generate_structured",
                  f"result_keys={list(result.keys())}")
        return result

    def _log(self, call_id: int, method: str, message: str) -> None:
        line = f"[call #{call_id}] [{method}] {message}"
        print(line)
        if self._log_file:
            with open(self._log_file, "a") as f:
                f.write(line + "\n")


# =========================================================================
# Demo: wire everything together
# =========================================================================

async def main() -> None:
    print("=" * 70)
    print("CUSTOM ADAPTERS DEMO")
    print("=" * 70)
    print()
    print("This demo uses a ConsoleAdapter so you can play the role of")
    print("both Generator and Critic.  Type your responses interactively.")
    print()
    print("Alternatively, swap in LoggingAdapter-wrapped real adapters")
    print("by editing the demo.")
    print()

    # Wrap console adapters with logging so we can see all interactions.
    gen_raw = ConsoleAdapter(name="Human-Generator")
    crit_raw = ConsoleAdapter(name="Human-Critic")

    generator: BaseAdapter = LoggingAdapter(gen_raw)
    critic: BaseAdapter = LoggingAdapter(crit_raw)

    config = AgentConfig(max_rounds=2)
    orch = DualAgentOrchestrator(generator, critic, config)

    result = await orch.run("Write a haiku about programming.")

    print("\n" + "=" * 60)
    print("FINAL RESULT")
    print("=" * 60)
    print(result.content)
    print(f"\nRounds: {len(orch.round_history)}")
    print(f"LoggingAdapter calls: generator={gen_raw.call_count}")


if __name__ == "__main__":
    asyncio.run(main())
