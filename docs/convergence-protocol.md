# Convergence Protocol

A deep dive into the anti-loop mechanism that guarantees termination while maximizing output quality.

---

## Why Convergence Matters

In a naive dual-agent loop, the Generator produces output, the Critic finds issues, the Generator revises, the Critic finds new issues, and so on **forever**. Without a convergence protocol, three failure modes emerge:

1. **Infinite refinement**: The Critic always finds *something* to improve, no matter how minor. The loop never terminates.

2. **Semantic looping**: The Generator makes changes, the Critic suggests reverting them, the Generator reverts, the Critic suggests the original change. The agents oscillate without progress.

3. **Quality degradation**: The Generator overcorrects in response to criticism and accidentally breaks previously working parts. Later rounds produce *worse* output than earlier rounds.

The convergence protocol addresses all three with a six-layer chain of checks.

---

## The Six Layers in Detail

### Layer 1: Hard Ceiling

```
Condition: round_num >= max_rounds
Action:    accept (return best artifact so far)
```

**The safety valve.** This layer exists to guarantee termination -- no matter what else happens, the loop stops after `max_rounds`. It is not a quality gate; it is a circuit breaker.

**When it fires:** The Generator and Critic have gone back and forth for `max_rounds` cycles without any other layer triggering.

**Tuning:** Increase `max_rounds` if your task genuinely benefits from many rounds of refinement. Decrease it for cost-sensitive applications. Most tasks converge within 2-3 rounds.

**Example:**
```
Round 1: score=0.62 (quality threshold 0.85 not met)
Round 2: score=0.71 (still below threshold, small improvement)
Round 3: score=0.72 (diminishing returns, but ROI check hasn't fired yet)
Round 4: score=0.73
Round 5: max_rounds reached → accept score=0.73 artifact
```

---

### Layer 2: Quality Threshold

```
Condition: verdict.score >= quality_threshold AND NOT verdict.is_blocking
Action:    accept
```

**The fast path.** If the output is already good enough, stop immediately. This is the most common termination condition for straightforward tasks.

**Why `is_blocking` matters:** A high score with blocking issues means the Critic sees a fundamental problem despite otherwise good output. For example, a well-written function that has a security vulnerability might score 0.82 but still be blocked. Accepting it would be wrong.

**Tuning:**
- `quality_threshold=0.95`: Strict. Only near-perfect output is accepted. More rounds, higher cost, potentially higher quality.
- `quality_threshold=0.75`: Lenient. Good enough is good enough. Fewer rounds, lower cost.
- `quality_threshold=0.85` (default): Balanced for most use cases.

**Example:**
```
Round 1: score=0.88, is_blocking=False
→ Accept immediately. No need for further rounds.
```

---

### Layer 3: Score Convergence

```
Condition: abs(verdict.score - prev_verdict.score) < convergence_threshold
Action:    accept
```

**Diminishing returns, version 1.** If the score barely changed from the previous round, investing in another round is unlikely to help. The improvement has plateaued.

**Tuning:**
- `convergence_threshold=0.01`: Only stop when improvement is truly negligible.
- `convergence_threshold=0.05`: Stop as soon as improvement slows noticeably.
- `convergence_threshold=0.02` (default): Balanced.

**Example:**
```
Round 2: score=0.78
Round 3: score=0.79
Delta: 0.01 < 0.02 → Accept.
```

---

### Layer 4: Issue Decay

```
Condition: No issues remain at the actionable severity for the current round
Action:    accept
```

**Progressive filtering.** The set of issues that are considered "actionable" shrinks across rounds:

| Round | Actionable Severities | Rationale |
|---|---|---|
| 1 | `critical`, `major` | The Generator should address significant problems. Minor/style issues can wait. |
| 2 | `critical` | By now, major issues should be resolved. Only critical problems justify another round. |
| 3+ | *(none)* | The Generator has had two full rounds of feedback. If it still cannot produce acceptable output, further rounds with filtered feedback won't help. Accept. |

**Why this layer exists:** Without issue decay, a pedantic Critic could keep the loop running indefinitely by finding stylistic issues. For example:

```
Round 1: Critical issue A, Major issue B → Generator fixes both.
Round 2: Minor issue C (naming), Style issue D (formatting) → Generator adjusts.
Round 3: Style issue E (a different naming convention) → Generator renames again.
Round 4: Style issue F (suggest reverting E) → Loop!
```

With issue decay, only critical + major are actionable in round 1. In round 2, only critical. By round 3, no issues are actionable -- the loop terminates.

**Example:**
```
Round 2 verdict: issues=[{severity: "minor", ...}, {severity: "style", ...}]
→ No critical issues. All issues filtered out. → Accept.
```

---

### Layer 5: ROI (Return on Investment) Check

```
Condition: improvement < 0.05 * (roi_decay_factor ^ (round_num - 1))
Action:    accept
```

**Diminishing returns, version 2.** This layer models the economic reality that each additional round should yield proportionally larger improvements to justify its cost. The required improvement threshold grows exponentially:

| Round | Required Improvement (roi_decay_factor=2.0) |
|---|---|
| 2 | 0.10 |
| 3 | 0.20 |
| 4 | 0.40 |
| 5 | 0.80 |

In practice, this means:
- A small improvement from round 2→3 (e.g., 0.72 to 0.78, delta=0.06) is accepted because the required minimum is 0.20 -- the improvement is not worth another round.
- A large improvement from round 1→2 (e.g., 0.50 to 0.72, delta=0.22) passes the check (0.22 >= 0.10), so the loop continues.

**Tuning:**
- `roi_decay_factor=1.5`: Slower decay, more willing to accept marginal gains. More rounds.
- `roi_decay_factor=2.0` (default): Balanced.
- `roi_decay_factor=3.0`: Steep decay, only very large improvements justify continuation. Fewer rounds.

**Example:**
```
Round 2: score=0.71 (prev=0.62, improvement=0.09)
ROI threshold for round 2: 0.05 * 2.0^1 = 0.10
0.09 < 0.10 → Accept.
```

---

### Layer 6: Semantic Loop Detection

```
Condition: Jaccard similarity between current and any recent output >= threshold
Action:    escalate (if enable_escalation=True) or accept (if False)
```

**The deadlock detector.** This is the most sophisticated layer. It detects when the Generator is producing near-identical output across rounds -- a sign that the feedback loop is stuck.

**How it works:**

1. A sliding window of the last N outputs is maintained (default N=3).
2. Each new output is tokenized (lowercase, whitespace-split) into a word set.
3. Jaccard similarity is computed pairwise: `|A ∩ B| / |A ∪ B|`.
4. If any pairwise similarity >= `loop_similarity_threshold` (default 0.92), a loop is declared.

**Jaccard example:**
```
Output A: "def validate_email address str bool return"
Output B: "def validate_email string bool return"
Intersection: {def, validate_email, bool, return} = 4
Union: {def, validate_email, address, str, string, bool, return} = 7
Similarity: 4/7 = 0.57 → Not a loop (below 0.92)
```

```
Output A: "def validate_email email str bool return true false"
Output B: "def validate_email email str bool return true false pattern"
Intersection: {def, validate_email, email, str, bool, return, true, false} = 8
Union: {def, validate_email, email, str, bool, return, true, false, pattern} = 9
Similarity: 8/9 = 0.89 → Close but still below 0.92
```

**When escalation is enabled**, the loop triggers the meta-judge instead of an unconditional accept. This is almost always better because the meta-judge can pick the best version from across all rounds, including earlier rounds that may have been higher quality.

**Tuning:**
- `loop_similarity_threshold=0.98`: Only flag near-identical output. May miss some loops.
- `loop_similarity_threshold=0.85`: More sensitive, catches loops earlier. May have false positives on short outputs.
- `loop_similarity_threshold=0.92` (default): Balanced for most code and text tasks.

---

## Layer Execution Order and Why It Matters

The six layers are executed in **priority order**, and the first match wins. The order is deliberate:

1. **Hard ceiling first** -- it is the safety valve. Everything else is a heuristic.
2. **Quality threshold second** -- if the output is already excellent, stop immediately.
3. **Score convergence third** -- check for plateau before diving into issue-specific logic.
4. **Issue decay fourth** -- filter issues before assessing ROI (since ROI compares scores, and fewer issues affects future scores).
5. **ROI fifth** -- economic check on whether continuing is worth it.
6. **Semantic loop last** -- the most expensive check (requires maintaining a window and computing similarities), so it runs only if nothing else has triggered.

---

## The Escalation Protocol (Meta-Judge)

When a semantic loop is detected and `enable_escalation=True`:

1. **Round summaries are built**: For each completed round, the orchestrator includes the artifact content, verdict score, issues, blocking status, and agreement level.

2. **The Critic is repurposed**: The Critic receives a special system prompt: *"You are a META-JUDGE. Your task is to break a deadlock between a Generator and Critic by selecting the single best artifact."*

3. **The meta-judge selects**: It reviews all rounds and returns the best artifact (or synthesizes one from multiple rounds).

4. **Fallback**: If the meta-judge API call fails, the orchestrator returns the artifact with the highest verdict score from the round history.

**Why use the Critic as meta-judge?** The Critic has already reviewed all artifacts. It has the most context to make an informed choice. Using a third model would add latency and cost without guaranteed benefit.

**When to disable escalation:** Set `enable_escalation=False` if you want deterministic behavior (always accept on loop detection) or if you are running in a cost-constrained environment where the extra meta-judge call is undesirable.

---

## Tuning Guide

### For maximum quality (cost-insensitive)

```python
AgentConfig(
    max_rounds=10,
    quality_threshold=0.95,
    convergence_threshold=0.005,
    roi_decay_factor=1.5,
    loop_similarity_threshold=0.95,
    enable_escalation=True,
)
```

### For minimum cost (speed-sensitive)

```python
AgentConfig(
    max_rounds=2,
    quality_threshold=0.70,
    convergence_threshold=0.05,
    roi_decay_factor=3.0,
    enable_escalation=False,
)
```

### For code generation (recommended defaults)

```python
AgentConfig(
    max_rounds=5,
    quality_threshold=0.88,
    convergence_threshold=0.02,
    roi_decay_factor=2.0,
    loop_similarity_threshold=0.92,
    enable_escalation=True,
)
```

### For creative writing (more rounds, lower thresholds)

```python
AgentConfig(
    max_rounds=7,
    quality_threshold=0.75,     # creative quality is subjective
    convergence_threshold=0.03,  # allow more fluctuation
    roi_decay_factor=1.8,
    enable_escalation=True,
)
```

---

## Edge Cases and How They Are Handled

### Empty output

If the Generator returns content that is empty or extremely short, the Critic will assign a low score and blocking issues, which triggers either another round (with clear feedback) or eventual acceptance via the hard ceiling.

### Critic always blocks

If the Critic marks every verdict as `is_blocking=True`, the quality threshold layer (Layer 2) will never fire. The loop will proceed through the remaining layers and eventually terminate via the hard ceiling. The best artifact (highest score despite blocking) is returned.

### Single round

If the Generator produces an artifact with `verdict.score >= quality_threshold` and `is_blocking=False`, the loop terminates after one round. This is the ideal case and is common for straightforward tasks.

### Structured generation failure

If either the Generator or Critic fails to produce valid structured output (API error, malformed JSON), the orchestrator falls back to free-form text generation and best-effort JSON extraction. If that also fails, a fallback artifact/verdict is constructed with neutral values.

### Disagreement without loop

The Generator and Critic may disagree persistently without producing semantically identical output. In this case, the semantic loop detector will not fire. The loop will eventually terminate via score convergence, ROI, issue decay, or the hard ceiling. The dispute is tracked and available for post-hoc inspection.

---

## Comparison with Simple Max-Rounds Approach

| Aspect | Simple Max-Rounds | 6-Layer Convergence Protocol |
|---|---|---|
| Termination guarantee | Yes (round limit) | Yes (Layer 1 hard ceiling) |
| Early exit for good output | No | Yes (Layer 2 quality threshold) |
| Diminishing returns detection | No | Yes (Layers 3 and 5) |
| Issue severity filtering | No | Yes (Layer 4) |
| Deadlock detection | No | Yes (Layer 6) |
| Deadlock resolution | No | Yes (escalation to meta-judge) |
| Cost efficiency | Poor (always runs max rounds) | Good (exits early when appropriate) |
| Tuning knobs | 1 | 6 |

A simple max-rounds approach either wastes money (running all rounds when the first was good enough) or risks low quality (stopping early when more rounds would have helped). The convergence protocol dynamically decides when to continue based on actual output quality.
