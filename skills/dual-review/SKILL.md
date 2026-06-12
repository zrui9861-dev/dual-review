---
name: dual-review
description: Dual-agent review. Generate solution, call second model to critique, fix issues, repeat until converged. Use when user says "/dr", "/dual-review", "dual review", "review yourself", "self-critique".
---

# Dual-Review — REQUIRED WORKFLOW

When user types `/dr`, you MUST follow every step below. Never skip the critique step.
The user wants to SEE the discussion process. Do not hide it.

## Step 1: Load config

Run:
```bash
source ~/.claude/skills/dual-review/config.env 2>/dev/null
```

If no config and no API key → self-review mode. Skip to Step 2, review your own output, show 3+ issues you found yourself, fix them, output final result.

## Step 2: Generate

Write your solution. Prefix with `## R1 Generate` so the user sees this is round 1.

## Step 3: Call the critic (MANDATORY)

Take your ENTIRE solution from Step 2 and send it to the second model:

```bash
source ~/.claude/skills/dual-review/config.env 2>/dev/null

INPUT=$(cat <<'CRITIQUE_EOF'
## Task
<the user's original request>

## Artifact
<your complete solution from Step 2, verbatim>

## Generator Confidence
<your confidence score 0.0-1.0>
CRITIQUE_EOF
)

echo "$INPUT" | bash ~/.claude/skills/dual-review/scripts/critique.sh
```

You MUST actually run this bash command. Do not simulate it.

## Step 4: Show the critique IN FULL

Display the complete critique results. Do not summarize. Show:

- The score
- Every issue with severity, description, and fix hint
- The suggestion
- The agreement level

Format as a readable table. Label it `## R1 Critique — <model name>`.

## Step 5: Respond to every issue

Go through each issue the critic found. For each one, say whether you:
- **Accept** → fix it immediately
- **Reject** → explain why the critic is wrong

Show this as a table. Label it `## R2 My Response`.

If you accepted any fixes, apply them and show the changed code.

## Step 6: Re-critique if needed

If score < 0.7 or blocking issues remain, go back to Step 3 with your improved solution.

Maximum 3 rounds. Each round must show:
- `## R<N> Critique` — the critic's full response
- `## R<N> My Response` — your reply to each issue

## Token-saving rules

Discussion MUST be visible. Code should be compact:

- **R1 Generate**: show full code once
- **Critique results**: show COMPLETE (score, every issue, suggestion, agreement) — never truncate
- **R2+ Response**: show only the code diff that changed, not the entire file again
- **Re-critique rounds**: show critique results in full, code changes as diffs only
- **Final Result**: show complete final code

Show the final solution. Label it `## Final Result`.

Summarize: starting score → ending score, issues found → issues resolved, rounds taken.

---

## Output example (what the user sees)

```
## R1 Generate
<Claude's solution>

## R1 Critique — DeepSeek Chat
Score: 0.55 | Blocking: yes

| # | Severity | Issue | Fix Hint |
|---|----------|-------|----------|
| 1 | critical | Missing error handling | Add try-catch around API calls |
| 2 | major    | No timeout       | Add 30s timeout to requests |
| 3 | minor    | Variable naming  | Use snake_case consistently |

Suggestion: Add error handling and timeouts before production use.
Agreement: 0.4

## R2 My Response

| # | Verdict  | Action |
|---|----------|--------|
| 1 | Accept   | Added try-catch for API failures and network errors |
| 2 | Accept   | Added 30s timeout to all requests |
| 3 | Reject   | Already snake_case throughout |

Changes:
```diff
- def ask_ai(question_text):
+ def ask_ai(question_text: str, timeout: int = 30) -> str:
+     try:
+         resp = requests.post(url, json=body, timeout=timeout)
+     except requests.Timeout:
+         return "Answer: Timeout"
+     except requests.RequestException as e:
+         return f"Answer: Error\n{e}"
```

## R2 Critique — DeepSeek Chat
Score: 0.85 | Blocking: no

| # | Severity | Issue | Fix Hint |
|---|----------|-------|----------|
| 1 | minor | Add retry logic | Exponential backoff |
| 2 | style | Docstring format | Google-style |

Agreement: 0.82

## R2 My Response

| # | Verdict | Action |
|---|----------|--------|
| 1 | Reject | Unnecessary complexity |
| 2 | Accept | Done |

## Final Result
0.55 → 0.85 | 4/5 resolved | 2 rounds
<full final code>
```

## Self-review mode (no API key)

If no config, self-review with same format:
1. `## R1 Generate` — your solution
2. `## R1 Self-Critique` — find your own issues (minimum 3)
3. `## R2 Fixes` — fix them
4. `## Final Result` — improved output

## Config

`~/.claude/skills/dual-review/config.env`:
```bash
CRITIC_MODEL="deepseek-chat"
DEEPSEEK_API_KEY="sk-..."
```

Install: `curl -fsSL https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-review@main/install.sh | bash`
