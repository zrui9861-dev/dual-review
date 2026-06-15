---
name: dual-review
description: Dual-agent review. Discuss approach first, then implement. Use when user says "/dr", "/dual-review", "dual review", "review yourself", "self-critique".
---

# Dual-Review — TWO-PHASE WORKFLOW

**先讨论设计方案 → 达成共识 → 再写代码。**
Discuss first, code second. Never skip the design phase.

## Step 0: Detect available models & let user pick (MANDATORY)

**If user already passed `--critic <M>` flag → skip this step, use M.**

**Step 0a: Scan for available API keys**

Run this to detect which models the user can actually use:

```bash
source ~/.claude/skills/dual-review/config.env 2>/dev/null

# Check which keys are available
[[ -n "${DEEPSEEK_API_KEY:-}" ]] && echo "deepseek ✅" && DEEPSEEK_OK=1 || DEEPSEEK_OK=0
[[ -n "${DASHSCOPE_API_KEY:-}" ]]  && echo "qwen ✅"    && QWEN_OK=1    || QWEN_OK=0
[[ -n "${OPENAI_API_KEY:-}" ]]     && echo "openai ✅"  && OPENAI_OK=1  || OPENAI_OK=0
[[ -n "${ANTHROPIC_API_KEY:-}" ]]  && echo "anthropic ✅" && ANTHROPIC_OK=1 || ANTHROPIC_OK=0
[[ -n "${ZHIPU_API_KEY:-}" ]]      && echo "glm ✅"     && GLM_OK=1     || GLM_OK=0
[[ -n "${GEMINI_API_KEY:-}" ]]     && echo "gemini ✅"  && GEMINI_OK=1  || GEMINI_OK=0
[[ -n "${TRAE_API_KEY:-}" ]]       && echo "trae ✅"    && TRAE_OK=1    || TRAE_OK=0
[[ -n "${WORKBUDDY_API_KEY:-}" ]]  && echo "workbuddy ✅" && WORKBUDDY_OK=1 || WORKBUDDY_OK=0
```

**Step 0b: Show ONLY available models**

Build a dynamic menu from the scan results. Only show models the user has keys for:

```
🔍 选审查模型（只显示你已配置 API key 的模型）

  ✅ 可用模型:
  1. deepseek-chat      2. qwen-max
  3. gpt-4o             4. claude-sonnet-4-6
  5. gemini-2.5-pro

  0. 自审模式（Claude 自己审，不用 API）

💾 上次: qwen3.7-max（回车直接用）

输入数字、模型名，或回车=自审 >
```

If NO keys are configured at all:
```
🔍 未检测到任何 API key。

  要使用外部模型审查，请先配置 API key：
    export DEEPSEEK_API_KEY=你的key    # DeepSeek
    export OPENAI_API_KEY=你的key      # OpenAI / Codex
    export ANTHROPIC_API_KEY=你的key   # Anthropic / Claude
    ...（或其他 provider）

  当前可用: 自审模式（Claude 自己审）

  回车继续自审，或输入模型名后手动提供 key >
```

**Step 0c: Handle user choice**

- 输入数字 → 用对应模型
- 输入模型名（如 `gpt-4o`）→ 检测是否有对应 key，有则用，无则提示
- 回车 / 输入 `0` → 自审模式
- 如果只有一个可用模型 → 自动选中，不询问

After selection: `✅ 审查模型: <model>` or `✅ 自审模式`

### Flags (parsed after model selection)

| Flag | Effect |
|------|--------|
| `--review` | User provides code, Claude reviews |
| `--gen <M>` | M generates, Claude reviews |
| `--gen <M> --critic <C>` | M generates, C reviews, Claude orchestrates |

### Conflict detection:
- `--review` + `--gen` → ❌ Error
- `--review` + `--critic` → ⚠️ Ignored
- `--gen X` + `--critic X` → ⚠️ Warning

## Step 1: Load API keys
```bash
source ~/.claude/skills/dual-review/config.env 2>/dev/null
```
If the chosen model needs an API key that isn't set → tell user which env var to set and abort.

---

# PHASE 1: 🧭 Design Discussion

**Goal: Agree on approach BEFORE writing any code.** Save tokens by discussing the plan, not the implementation.

## 1a: Claude proposes design

Output a BRIEF structured design (5-10 lines, no code):

```
## 🧭 Design Proposal

**Approach:** <1-line summary>
**Key decisions:**
1. <decision 1 — one sentence>
2. <decision 2 — one sentence>
3. <decision 3 — one sentence>
**Trade-offs:** <1-line: what we gain vs what we risk>
**Confidence:** <0.0-1.0>
```

If `--gen` specified: send task to external model via generate.sh, extract the design from its output.
**⚠️ Fallback:** If generate.sh exits 75 (EX_TEMPFAIL), Claude takes over design. Show `## 🧭 Design Proposal — Claude (fallback)`.

## 1b: Critic reviews the design

**If external critic:** Send ONLY the design proposal (not the task again):

```bash
INPUT=$(cat <<'CRITIQUE_EOF'
## Design Proposal
<Claude's design from 1a>

Review the DESIGN APPROACH only. Focus on:
- Architecture/algorithm choice risks
- Missing edge cases or constraints
- Better alternatives worth considering
Return ONLY JSON with score, issues, is_blocking, suggestion, agreement_level.
CRITIQUE_EOF
)
echo "$INPUT" | bash ~/.claude/skills/dual-review/scripts/critique.sh
```

**If Claude as critic:** Self-review the design with the same JSON format.

## 1c: Show design discussion — COMPACT FORMAT

Use this token-efficient visual format:

```
## 🧭 Design Review — <critic name>
📊 Score: 0.7 | 🚫 Blocking: yes

| # | 争议点 | 🤖立场 | 👁立场 | → |
|---|--------|--------|--------|---|
| 1 | 用Redis还是内存缓存 | Redis持久化 | 内存低延迟 | 🤝 Redis+本地L1 |
| 2 | API用REST还是gRPC | REST简单 | gRPC性能好 | 🔴 需讨论 |

🟢 共识: 1/2 | 🆕 新问题: 0 | 🟡 继续讨论
```

**Status icons:**
- 🤝 = agreed/resolved
- 🔴 = still disputed
- 🆕 = new concern
- 🟢 = ready to proceed
- 🟡 = needs more discussion
- 🔴 = blocking

**RULE:** Show design discussion in this compact table. Do NOT re-display full design text — only changes.

## 1d: Resolve design disputes

If score < 0.7 or blocking → discuss and converge:
- Claude responds to each dispute in the table (add a column showing Claude's counter)
- Critic re-evaluates
- Max 2 design rounds, then accept best-available approach

**When design converges (score ≥ 0.7, no blocking):**
```
## 🧭 Design Consensus ✅
<Final agreed approach in 2-3 lines>
🟢 进入实现阶段
```

---

# PHASE 2: 🔨 Implementation

**Only start AFTER design consensus.**

## 2a: Generate code

**Claude generates:** Full code/solution based on the AGREED design. Label `## 🔨 Implementation`.

**External model generates:** Same as before via generate.sh.

## 2b: Critic reviews the code

Same as before — send code to critic via critique.sh.

## 2c: Show code review — COMPACT FORMAT

```
## 🔍 Code Review — <critic name>
📊 Score: 0.65 | 🚫 Blocking: yes

| # | Sev | Issue | Fix |
|---|-----|-------|-----|
| 1 | 🔴 critical | SQL注入 risk at line 42 | Use parameterized query |
| 2 | 🟠 major | No request timeout | Add 30s timeout |
| 3 | 🟡 minor | Variable shadowing L15 | Rename inner `x` |

💡 Suggestion: Add input validation middleware.
🤝 Agreement: 0.5
```

**Severity icons:** 🔴 critical 🟠 major 🟡 minor ⚪ style

## 2d: Fix and re-review

Respond to issues in compact table:

```
## 🔧 Fixes — R2

| # | Verdict | Change |
|---|---------|--------|
| 1 | ✅ | Parameterized query |
| 2 | ✅ | 30s timeout added |
| 3 | ❌ no | `x` already scoped, safe |
```

Show only the DIFF for accepted fixes (not full code):
```diff
- cursor.execute(f"SELECT * FROM users WHERE id={uid}")
+ cursor.execute("SELECT * FROM users WHERE id=?", (uid,))
```

Re-critique if score < 0.7 or blocking. Max 3 implementation rounds.

---

# 📋 Final Result

```
## ✅ Final Result
🧭 Design: <critic> agreed | 🔨 Code: 0.62→0.88 | 2 design + 2 impl rounds
<full final code>
```

---

# Token-saving rules

| Rule | Phase 1 (Design) | Phase 2 (Impl) |
|------|-----------------|-----------------|
| Show full text | Only Claude's initial design (1a) | Only final code (once) |
| Changes shown as | Compact table | Diff only |
| Re-discussion | Table row update | Table row update |
| Critique output | Score + table + 1-line suggestion | Score + table + 1-line suggestion |
| Max rounds | 2 design | 3 implementation |

**NEVER re-display** the full design or full code in discussion rounds. Only show what CHANGED.

---

# Self-review mode (no API key)

1. `## 🧭 Design Proposal` — your approach
2. `## 🧭 Design Self-Review` — find issues in your design (min 2)
3. `## 🧭 Design Consensus` — your improved approach
4. `## 🔨 Implementation` — your code
5. `## 🔍 Self-Critique` — find issues (min 3)
6. `## 🔧 Fixes` — fix them
7. `## ✅ Final Result`

---

# Role cheat sheet

| Command | Designer | Coder | Reviewer |
|---------|----------|-------|----------|
| `/dr <task>` | Claude | Claude | **现场选择**（Step 0 选） |
| `/dr --critic X <task>` | Claude | Claude | X（跳过 Step 0） |
| `/dr --review <code>` | — | User | Claude |
| `/dr --gen X <task>` | X | X | Claude |
| `/dr --gen X --critic Y <task>` | X | X | Y |

---

# Config

`~/.claude/skills/dual-review/config.env`:
```bash
CRITIC_MODEL="deepseek-chat"
DEEPSEEK_API_KEY="sk-..."
```

Install: `curl -fsSL https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-review@main/install.sh | bash`
