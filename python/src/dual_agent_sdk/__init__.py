"""dual-agent-sdk -- Generator-Critic dual-agent orchestration framework.

A Python SDK for orchestrating two LLMs in a structured collaboration loop:
one generates, one reviews.  A six-layer convergence protocol prevents
infinite loops, and semantic loop detection triggers meta-judge escalation
when the agents deadlock.

Quick start::

    import asyncio
    from dual_agent_sdk import (
        DualAgentOrchestrator, AnthropicAdapter, OpenAIAdapter, AgentConfig,
    )

    async def main():
        gen = AnthropicAdapter(model="claude-sonnet-4-6")
        crit = OpenAIAdapter(model="gpt-4o")
        orch = DualAgentOrchestrator(gen, crit)
        result = await orch.run("Write a Python function that ...")
        print(result.content)

    asyncio.run(main())
"""

from .adapters import AnthropicAdapter, BaseAdapter, OpenAIAdapter
from .convergence import ConvergenceEngine
from .loop_detector import SemanticLoopDetector
from .models import (
    AgentConfig,
    Artifact,
    DisputeRecord,
    Issue,
    RoundRecord,
    Verdict,
)
from .orchestrator import DualAgentOrchestrator
from .prompts import CRITIC_SYSTEM_PROMPT, GENERATOR_SYSTEM_PROMPT

__all__ = [
    # Orchestrator
    "DualAgentOrchestrator",
    # Configuration
    "AgentConfig",
    # Domain models
    "Artifact",
    "Verdict",
    "Issue",
    "RoundRecord",
    "DisputeRecord",
    # Adapters
    "BaseAdapter",
    "AnthropicAdapter",
    "OpenAIAdapter",
    # Convergence
    "ConvergenceEngine",
    # Loop detection
    "SemanticLoopDetector",
    # Prompts
    "GENERATOR_SYSTEM_PROMPT",
    "CRITIC_SYSTEM_PROMPT",
]
