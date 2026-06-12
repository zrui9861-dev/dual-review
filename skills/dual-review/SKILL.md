---
name: dual-review
description: Dual-agent review. Generate solution, call second model to critique, fix issues, repeat until converged. Use when user says "/dr", "/dual-review", "dual review", "review yourself", "self-critique".
---

# Dual-Review — REQUIRED WORKFLOW

When user invokes `/dr <task>` you MUST follow this workflow. Do NOT skip steps.
Do NOT just answer the task directly.

## Mandatory Steps

### Step 1: Check config

Load config file. If it exists, use the configured model for critique.

```bash
source ~/.claude/skills/dual-review/config.env 2>/dev/null
```

If no config and no API key env vars → fallback to self-review mode (Step 2 only, then output result directly).

### Step 2: Generate (Claude)

Produce the solution. This is your normal response — write code, answer the question, etc.
Format your output with `## R1: Solution` header so the user can see what you generated.

### Step 3: Critique (call second model)

You MUST call the critique script. Do not skip this. Take your solution from Step 2 and pipe it to critique.sh:

```bash
source ~/.claude/skills/dual-review/config.env 2>/dev/null
echo '## Task
<the original task>

## Artifact
<your solution from Step 2>

## Generator Confidence
<0.0-1.0>' | bash ~/.claude/skills/dual-review/scripts/critique.sh
```

The script returns a JSON with score, issues, is_blocking, suggestion, agreement_level.

### Step 4: Show critique results

Display the critique results to the user in a compact format:

```
## R1: Critique — <Model Name>

Score: <score> | Blocking: <yes/no>

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| 1 | critical | ... | ... |
| 2 | major    | ... | ... |
```

### Step 5: Address issues

Fix all critical and major issues from the critique. Show what you changed:

```
## R2: Fixes

| # | Issue | Action |
|---|-------|--------|
| 1 | X | Fixed by Y |
```

If no critical/major issues remain, skip to Step 6.

### Step 6: Final output

Present the final improved solution. If working with code, show the updated files.

## Self-Review Mode (no API key)

If no config.env and no API key env vars are set, run self-review instead:

1. Generate solution (Step 2)
2. Review your own output critically — find at least 3 issues
3. Show the issues in critique format
4. Fix the issues
5. Output final version

## Convergence (multi-round)

If the critic's score is below 0.7 or is_blocking is true after your fixes, run critique again (Step 3-5) for up to 3 rounds maximum. Each round show:
- The updated critique score
- Which issues were resolved
- What remains

Stop when: score ≥ 0.85, or no blocking issues remain, or 3 rounds reached.

## Config

Config is at `~/.claude/skills/dual-review/config.env`:
```bash
CRITIC_MODEL="deepseek-chat"
DEEPSEEK_API_KEY="sk-..."
# or OPENAI_API_KEY / DASHSCOPE_API_KEY / MOONSHOT_API_KEY / ZHIPU_API_KEY / ANTHROPIC_API_KEY
# or CRITIC_BASE_URL + CRITIC_API_KEY for custom endpoint
```

Installed via: `curl -fsSL https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-review@main/install.sh | bash`
