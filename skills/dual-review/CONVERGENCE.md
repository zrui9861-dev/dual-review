# Dual-Review Convergence Protocol — Full Reference

## Why Convergence Matters

Without strict termination rules, a self-review loop can cycle indefinitely:
- "This has an issue" → "Fixed" → "The fix introduced a new issue" → "Fixed again" → ...

The 5+1 layer protocol guarantees the loop always terminates.

## Layer Details

### L0 — User Interrupt (always available)
The user can stop the review at any point. Always present the current best result alongside the critique so the user can decide.

### L1 — Hard Ceiling (round ≥ 3)
Single-model self-review has diminishing returns faster than dual-model. Three rounds is the sweet spot:
- Round 1: Generate + critique (most value)
- Round 2: Address critical + major issues (significant improvement)
- Round 3: Address critical only, then accept regardless

### L2 — Quality Gate (score ≥ 0.9, no blocking)
If self-critique gives ≥ 0.9 and finds no blocking issues, the output is good enough. Don't nitpick.

### L3 — Score Convergence (Δ < 0.05)
If the score barely changes between rounds, further review won't help. Example:
- Round 1 score: 0.70 → Round 2 score: 0.73 → Δ = 0.03 < 0.05 → ACCEPT

### L4 — Issue Decay (severity filter)
Each round raises the bar for what's worth addressing:
- Round 1 → Round 2: only **critical + major** issues
- Round 2 → Round 3: only **critical** issues
- Round 3+: no issues are actionable → ACCEPT

This prevents "one more round just to fix a comma."

### L5 — Semantic Loop Detection
If the same issues appear across multiple rounds (the fix didn't help or created a ping-pong), accept the current version. A meta-review might help more than another round.

## Edge Cases

### What if I find a critical issue late?
In Round 3, if a new critical issue is found that was NOT present before, mention it explicitly and fix it in the same round. L1 still applies — return the fixed version.

### What if the task is genuinely unsolvable in 3 rounds?
Acknowledge this in the final output. Mark uncertain parts clearly. The user can always re-invoke `/dual-review` on the uncertain parts.

### What if the critique finds zero issues?
Accept immediately (L2 triggers if score ≥ 0.9, otherwise L4 triggers — no issues means no actionable issues).

## Comparison: Self-Review vs Dual-Model

| Aspect | Self-Review (this skill) | Dual-Model (SDK) |
|--------|--------------------------|-------------------|
| Reviewer | Same model, different prompt | Separate model |
| Max rounds | 3 | 5 |
| Blind spots | Model can't see its own blind spots well | Different models catch different issues |
| Escalation | Accept + flag uncertainty | Meta-judge (third model) |
| Cost | Free (same session) | 2× token cost |
| Best for | Quick review, solo work | Critical output, adversarial check |
