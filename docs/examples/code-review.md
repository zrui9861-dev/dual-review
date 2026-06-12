# Code Review Tutorial

A narrative walkthrough of using Dual Agent SDK to automatically generate and review code. We will submit a real programming task, observe the Generator-Critic interaction across rounds, and interpret the results.

---

## Scenario

We want to generate a Python module that implements a **thread-safe, size-bounded LRU cache** with the following requirements:

- O(1) get and put operations.
- Thread safety using locks.
- A configurable maximum size that evicts the least-recently-used entry.
- Type hints and docstrings.
- No third-party dependencies (stdlib only).

This is a moderately complex task -- enough that the first attempt is unlikely to be perfect, but not so complex that convergence takes many rounds.

---

## Setup

Create a file called `lru_cache_demo.py`:

```python
import asyncio
from dual_agent_sdk import (
    DualAgentOrchestrator,
    AnthropicAdapter,
    OpenAIAdapter,
    AgentConfig,
)

TASK = """\
Write a Python class ThreadSafeLRUCache with the following requirements:

1. O(1) get(key) and put(key, value) operations.
2. Thread safety -- use threading.Lock, not asyncio.
3. A configurable max_size in the constructor.
4. When max_size is exceeded, evict the least-recently-used entry.
5. Implement __len__ to return the current number of entries.
6. Implement __contains__ for key membership testing.
7. Include type hints and a module docstring.
8. Use only the Python standard library.
9. Write the code as a complete, runnable module with a short
   demo in the `if __name__ == "__main__"` block.
"""

async def main():
    generator = AnthropicAdapter(model="claude-sonnet-4-6")
    critic = OpenAIAdapter(model="gpt-4o")

    config = AgentConfig(
        max_rounds=5,
        quality_threshold=0.88,
        convergence_threshold=0.02,
        enable_escalation=True,
    )

    orch = DualAgentOrchestrator(generator, critic, config)
    result = await orch.run(TASK)

    print("=" * 60)
    print("FINAL ARTIFACT")
    print("=" * 60)
    print(result.content)

asyncio.run(main())
```

Run it:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
python lru_cache_demo.py
```

---

## What to Expect: A Typical Run

Here is an annotated example of what a real run might look like.

### Round 1

**Generator produces:**

```python
import threading
from collections import OrderedDict
from typing import TypeVar, Generic, Optional

K = TypeVar("K")
V = TypeVar("V")

class ThreadSafeLRUCache(Generic[K, V]):
    """A thread-safe, size-bounded LRU cache."""

    def __init__(self, max_size: int = 128) -> None:
        self._max_size = max_size
        self._cache: OrderedDict[K, V] = OrderedDict()
        self._lock = threading.Lock()

    def get(self, key: K) -> Optional[V]:
        with self._lock:
            if key not in self._cache:
                return None
            self._cache.move_to_end(key)
            return self._cache[key]

    def put(self, key: K, value: V) -> None:
        with self._lock:
            if key in self._cache:
                self._cache.move_to_end(key)
            self._cache[key] = value
            if len(self._cache) > self._max_size:
                self._cache.popitem(last=False)

    def __len__(self) -> int:
        with self._lock:
            return len(self._cache)

    def __contains__(self, key: K) -> bool:
        with self._lock:
            return key in self._cache
```

**Critic reviews and finds:**

- Score: 0.78
- Issues:
  - `[major]` `move_to_end` on `get` for a missing key should not be called. The code correctly guards this, but the ordering is fragile. (location: `get` method)
  - `[minor]` Missing `__repr__` or `__str__` for debugging.
  - `[style]` TypeVar bounds could be more specific.
- Blocking: False
- Suggestion: "Guard the move_to_end call properly, add a repr method, and tighten type bounds."

**Convergence evaluation:** Score (0.78) is below threshold (0.88), and there are actionable issues (major + minor). Decision: **continue**.

The issues are filtered: critical and major issues are forwarded to the Generator (minor and style are dropped for round 1).

### Round 2

**Generator receives feedback and revises:**

```python
class ThreadSafeLRUCache(Generic[K, V]):
    # ... same structure, with improvements:

    def __repr__(self) -> str:
        with self._lock:
            return f"ThreadSafeLRUCache(size={len(self._cache)}, max_size={self._max_size})"
```

**Critic reviews:**

- Score: 0.89
- Issues:
  - `[minor]` The `__repr__` could include a few sample keys for better debugging.
  - `[style]` Consider renaming `_cache` to `_store` for clarity.
- Blocking: False
- Suggestion: "Add sample keys to repr; minor naming suggestion."

**Convergence evaluation:** Score (0.89) meets quality threshold (0.88) AND `is_blocking=False`. Decision: **accept**.

The loop terminates after 2 rounds. The orchestrator returns the round 2 artifact.

---

## Inspecting the Round History

After the run, `orch.round_history` contains detailed records:

```python
for rec in orch.round_history:
    print(f"Round {rec.round_num}:")
    print(f"  Score:     {rec.verdict.score:.3f}")
    print(f"  Blocking:  {rec.verdict.is_blocking}")
    print(f"  Agreement: {rec.verdict.agreement_level:.3f}")
    for issue in rec.verdict.issues:
        print(f"  - [{issue.severity}] {issue.description}")
    print(f"  Timestamp: {rec.timestamp}")
```

Example output:

```
Round 1:
  Score:     0.78
  Blocking:  False
  Agreement: 0.65
  - [major] Guard the move_to_end call and validate the approach
  - [minor] Missing __repr__ method for debugging
  - [style] TypeVar bounds could be more specific
  Timestamp: 1718234567.891

Round 2:
  Score:     0.89
  Blocking:  False
  Agreement: 0.92
  - [minor] Add sample keys to __repr__
  - [style] Consider renaming _cache to _store
  Timestamp: 1718234575.234
```

Notice how the `agreement_level` rose from 0.65 to 0.92 -- the Critic agreed much more with the Generator's approach after the major issue was addressed.

---

## Understanding Convergence Decisions

Each round's outcome is determined by the convergence engine. You can trace which layer fired:

| Round | Score | Blocking | Prev Score | Decision | Likely Layer |
|---|---|---|---|---|---|
| 1 | 0.78 | False | N/A | continue | *(none fired)* |
| 2 | 0.89 | False | 0.78 | accept | Layer 2 (Quality Threshold) |

If the score had been 0.87 in round 2 (below threshold), the loop would have continued because there was still a minor issue (but only critical issues are actionable in round 2, so Layer 4 would have fired: no actionable issues -> accept).

---

## Handling Edge Cases

### The Generator Refuses to Change

Sometimes the Generator disagrees with the Critic and stands its ground. The `reasoning` field captures this:

```
"I considered the Critic's suggestion to use an RWLock instead of a simple Lock,
 but for a cache where reads dominate and the critical section is O(1), a simple
 Lock is more appropriate. RWLock overhead would exceed any concurrency benefit."
```

If the Generator is correct, the agreement level will rise in the next round (the Critic acknowledges the reasoning). If the Generator is wrong, the issue will persist, and the dispute will be tracked in `orch.disputes`.

### The Critic is Overly Harsh

If the Critic assigns very low scores and blocking verdicts for minor issues, the quality threshold layer (Layer 2) will never fire. The loop will proceed through the remaining layers and terminate via score convergence or the hard ceiling. The best-scored artifact is still returned.

### Semantic Loop

If the Generator keeps producing nearly identical code despite feedback, the semantic loop detector fires. With escalation enabled, the meta-judge reviews all rounds and picks the best version. Without escalation, the loop accepts the current artifact and terminates.

---

## Customizing for Your Workflow

### Adding Context

The `context` parameter passes domain knowledge, existing code, or constraints:

```python
result = await orch.run(
    task="Optimize the database query in the fetch_users function.",
    context="""
    Current code (users/db.py):
    def fetch_users(status=None):
        with engine.connect() as conn:
            if status:
                return conn.execute(
                    select(User).where(User.status == status)
                ).all()
            return conn.execute(select(User)).all()

    The User table has 2M rows with indexes on id, email, and status.
    Query latency is currently 800ms for unfiltered queries.
    """,
)
```

The context is included in the Generator's prompt, giving it the information needed to produce a relevant solution.

### Different Models for Different Task Types

- **Code generation:** Claude Sonnet (generator) + GPT-4o (critic) is a strong combination.
- **Creative writing:** Claude Opus (generator) + Claude Sonnet (critic) for stylistic consistency.
- **Data analysis:** GPT-4o (generator) + Claude Sonnet (critic) -- GPT-4o's code generation is solid, and Claude's code review catches statistical errors.
- **Cost-sensitive:** Claude Haiku (generator) + Claude Haiku (critic) for fast, cheap iterations on simple tasks.

---

## Summary

A typical dual-agent code review flow:

1. **Submit a detailed task** with clear requirements.
2. **The Generator produces a first attempt.** It is usually 60-80% correct.
3. **The Critic identifies issues** with severity levels and fix hints.
4. **The Generator revises** based on filtered feedback (only critical + major in round 1).
5. **Convergence is reached** in 1-3 rounds for most tasks.
6. **You receive the best artifact** along with a full audit trail.

The key takeaway: **you do not need to manually review LLM output**. The Critic does it for you, and the convergence protocol ensures the loop terminates with the best possible result.
