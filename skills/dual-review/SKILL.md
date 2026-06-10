---
name: dual-review
description: Dual-agent review protocol. Three modes: (1) Self-review — Claude critiques its own output. (2) Dual-model — Claude generates, second LLM critiques. (3) Discuss — two models debate back and forth on complex problems, converging via 6-layer protocol. Use when user says "dual review", "/dual-review", "review yourself", "self-critique", "generator critic", or when facing complex multi-step tasks that benefit from adversarial review.
---

# Dual-Review Protocol

## Quick start

```
/dual-review <task>                     → self-review (default, no setup)
/dual-review --dual "<task>"            → dual-model (generate + critique once)
/dual-review --discuss "<task>"         → discussion (two models debate)
/dual-review --dual --discuss "<task>"  → dual-model with discussion rounds
```

## Three Modes

### Mode 1: Self-Review
Claude generates, then self-critiques. No setup needed.

### Mode 2: Dual-Model
Claude generates → second model critiques. `export DEEPSEEK_API_KEY=...`

### Mode 3: Discussion (--discuss) ← for big problems

Two models **debate** until they agree. Not just one critique — they go back and forth:

```
Claude: "Here's my architecture design..."
  ↓
Critic: "I see 3 issues: X, Y, Z. Score: 0.55"
  ↓
Claude: "X is fair, I'll fix it. Y is intentional because [reason]. Z is wrong — [rebuttal]."
  ↓
Critic: "I accept your reasoning on Y and Z. X still needs work. Score: 0.72"
  ↓
Claude: "Fixed X. Here's the revised version."
  ↓
Critic: "X is resolved. Score: 0.91. I agree with the overall approach."
  ↓
✅ Converged after 3 exchanges
```

## Discussion Protocol (--discuss)

### When to use --discuss
- Architecture/design decisions with trade-offs
- Complex problems with no single correct answer
- Tasks where Claude is uncertain and wants adversarial feedback
- Security/safety critical work

### ⚡ Compact Format (token-efficient)

**DO NOT output full solution content in each round.** Only output:
1. Initial solution (Round 1 Generate) — full content
2. Discussion rounds — **scorecard only** (dispute status changes)
3. Final resolution — full accepted solution

### Round output format

```
## 💬 R1 Generate → [full solution, once]

## 💬 R2 Discuss
| # | Dispute | Claude | Critic | → |
|----|---------|--------|--------|---|
| 1 | 令牌桶 vs 滑动窗口 | 令牌桶更合适(内存+突发) | 滑动窗口更精确 | 🤝 各让一步 |
| 2 | 分布式一致性 | 独立限流+Redis同步 | 多节点会超限 | 🔴 无进展→升级 |

**Agreement**: 0.55→0.70 | **New issues**: 1 (major: 全局配额)

## 💬 R3 Discuss
| 1 | 分布式一致性 | 接受10%超限+监控告警 | 可接受,加熔断 | ✅ 解决 |

**Agreement**: 0.70→0.88 | **Converged** ✅
```

### Token-saving rules
1. **Only show disputes, not full text** — one-line summaries per position
2. **Skip artifact after R1** — unless content changed significantly
3. **Critic response**: extract only the JSON fields that changed (score, dispute statuses, new issue count)
4. **Max 3 lines per dispute** in the scorecard
5. **Script handles formatting** — Claude just parses the JSON and renders the compact view

### Discussion Convergence

| Layer | Rule | Action |
|-------|------|--------|
| **L1** | Max 5 debate rounds | Pick best version |
| **L2** | Agreement ≥ 0.9 AND no critical disputes | Accept |
| **L3** | Agreement change < 0.05 × 2 rounds | Accept — stalemate |
| **L4** | Only style/minor disputes remain | Accept |
| **L5** | Same dispute active 2+ rounds | **Escalate**: Claude decides, dissents noted |
| **L0** | User interrupts | Accept |

### Escalation (deadlock resolution)

When L5 triggers on a dispute:
```
⚖️ **Deadlock**: [topic]
Claude decides: [decision + brief reason]
Critic dissent: [one sentence]
→ Both views preserved in final output.
```

## Discussion Script

The script `scripts/discuss.sh` handles multi-turn debate:
- Takes the current dispute state + Claude's response as input
- Sends it to the Critic model with debate context
- Returns: updated disputes, new score, whether each point is resolved

```
echo '{"task":"...", "claude_position":"...", "disputes":[...]}' | ./scripts/discuss.sh
```

## Convergence Rules (for all modes)

| Layer | Rule | Action |
|-------|------|--------|
| **L1** | Round 3 reached (review) / Round 5 (discuss) | **ACCEPT** |
| **L2** | Score ≥ 0.9 AND no blocking issues | **ACCEPT** |
| **L3** | Score change < 0.05 from previous round | **ACCEPT** |
| **L4** | Only minor/style issues remain | **ACCEPT** |
| **L5** | Same issues/arguments appear 2+ rounds | **ACCEPT** (review) / **ESCALATE** (discuss) |
| **L0** | User interrupts | **ACCEPT** immediately |

## Severity Guide

- **critical**: Wrong, unsafe, would not work
- **major**: Significant flaw, missing edge case
- **minor**: Improvement possible but not required
- **style**: Cosmetic, preference

## Configuration

| Env Var | Purpose | Default |
|----------|---------|---------|
| `DEEPSEEK_API_KEY` | DeepSeek API key | — |
| `DASHSCOPE_API_KEY` | Qwen/Tongyi API key | — |
| `MOONSHOT_API_KEY` | Moonshot/Kimi API key | — |
| `ZHIPU_API_KEY` | Zhipu/GLM API key | — |
| `OPENAI_API_KEY` | OpenAI API key | — |
| `CRITIC_MODEL` | Second model name | `deepseek-chat` |
| `CRITIC_BASE_URL` | Custom API endpoint (any OpenAI-compatible) | — |
| `DISCUSS_MAX_ROUNDS` | Max debate rounds (discuss mode) | `5` |

## Scripts

- `scripts/critique.sh` — Critique (macOS/Linux bash)
- `scripts/discuss.sh` — Discuss (macOS/Linux bash)
- `scripts/critique.ps1` — Critique (Windows PowerShell)
- `scripts/discuss.ps1` — Discuss (Windows PowerShell)
- `scripts/test-critique.sh` — Test pipeline

See [CONVERGENCE.md](CONVERGENCE.md) for the full convergence protocol.
See [EXAMPLES.md](EXAMPLES.md) for usage examples in all modes.
