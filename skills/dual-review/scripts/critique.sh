#!/usr/bin/env bash
# ============================================================================
# dual-review critique script — calls a second LLM to review output.
#
# Usage:
#   echo "$task_and_artifact" | ./critique.sh
#   echo "..." | CRITIC_MODEL=deepseek-chat ./critique.sh
#
# Env: CRITIC_MODEL, CRITIC_BASE_URL, CRITIC_MAX_TOKENS (4096),
#      CRITIC_TEMPERATURE (0.3), CRITIC_TIMEOUT (60)
#
# API keys: DEEPSEEK_API_KEY, MOONSHOT_API_KEY, DASHSCOPE_API_KEY,
#           ZHIPU_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY,
#           GEMINI_API_KEY, TRAE_API_KEY, WORKBUDDY_API_KEY
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load config + shared libraries ---------------------------------------
CONFIG_ENV="${HOME}/.claude/skills/dual-review/config.env"
[[ -f "${CONFIG_ENV}" ]] && source "${CONFIG_ENV}"
source "${SCRIPT_DIR}/lib/provider_router.sh" || { echo "FATAL: provider_router.sh missing" >&2; exit 1; }
source "${SCRIPT_DIR}/lib/api_call.sh"       || { echo "FATAL: api_call.sh missing" >&2; exit 1; }

# --- Config ----------------------------------------------------------------
MODEL="${CRITIC_MODEL:-deepseek-chat}"
MAX_TOKENS="${CRITIC_MAX_TOKENS:-4096}"
TEMPERATURE="${CRITIC_TEMPERATURE:-0.3}"
API_TIMEOUT="${CRITIC_TIMEOUT:-60}"
INPUT="$(cat)"

# --- Resolve provider ------------------------------------------------------
IFS='|' read -r PROVIDER API_URL API_KEY <<< "$(resolve_provider "$MODEL")"

if [[ "$PROVIDER" == "unknown" ]]; then
    echo "{\"error\":\"Unknown model: $MODEL. Use: ${KNOWN_MODELS}, or set CRITIC_BASE_URL\"}" >&2
    exit 1
fi
if [[ -z "$API_KEY" ]]; then
    echo "{\"error\":\"$(provider_key_env "$PROVIDER") not set. Run: export $(provider_key_env "$PROVIDER")=your-key\"}" >&2
    exit 1
fi

# --- System prompt ---------------------------------------------------------
SYSTEM_PROMPT="You are a CRITIC agent in a dual-agent review system. RIGOROUSLY REVIEW the Generator's output.

## Your Task
1. Find factual errors, logical flaws, missing edge cases, and inefficiencies
2. Classify each issue: critical (wrong/unsafe), major (significant flaw), minor (improvement), style (cosmetic)
3. Provide SPECIFIC, ACTIONABLE fix hints for each issue
4. Score overall quality from 0.0 to 1.0
5. If critical or major issues exist, set is_blocking to true

## Output Format — ONLY JSON, no markdown:
{
  \"score\": <float 0-1>,
  \"issues\": [
    {\"severity\": \"critical|major|minor|style\", \"description\": \"...\", \"fix_hint\": \"...\"}
  ],
  \"is_blocking\": <bool>,
  \"suggestion\": \"<one-paragraph or null>\",
  \"agreement_level\": <float 0-1>
}

Match the response language to the input language. 用中文回复如果输入是中文。"

USER_PROMPT="${INPUT}

Review the artifact above. Be thorough and adversarial.
Return ONLY JSON."

# --- Call API --------------------------------------------------------------
call_api "$PROVIDER" "$API_URL" "$API_KEY" "$MODEL" "$SYSTEM_PROMPT" "$USER_PROMPT" "$MAX_TOKENS" "$TEMPERATURE"
