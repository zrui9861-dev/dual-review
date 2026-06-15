#!/usr/bin/env bash
# ============================================================================
# dual-review generate script — calls an LLM to GENERATE code/solutions.
#
# Usage:
#   echo "$task" | ./generate.sh
#   echo "..." | GENERATOR_MODEL=qwen-max ./generate.sh
#
# Env: GENERATOR_MODEL, GENERATOR_BASE_URL, GENERATOR_MAX_TOKENS (8192),
#      GENERATOR_TEMPERATURE (0.7), GENERATOR_TIMEOUT (120), GENERATOR_RETRIES (2)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load config + shared libraries ---------------------------------------
CONFIG_ENV="${HOME}/.claude/skills/dual-review/config.env"
[[ -f "${CONFIG_ENV}" ]] && source "${CONFIG_ENV}"
source "${SCRIPT_DIR}/lib/provider_router.sh" || { echo "FATAL: provider_router.sh missing" >&2; exit 1; }
source "${SCRIPT_DIR}/lib/api_call.sh"       || { echo "FATAL: api_call.sh missing" >&2; exit 1; }

# --- Config ----------------------------------------------------------------
MODEL="${GENERATOR_MODEL:-${CRITIC_MODEL:-deepseek-chat}}"
[[ -z "${GENERATOR_MODEL:-}" && -n "${CRITIC_MODEL:-}" ]] && \
    echo "⚠️  GENERATOR_MODEL not set, falling back to CRITIC_MODEL (${MODEL})" >&2

MAX_TOKENS="${GENERATOR_MAX_TOKENS:-8192}"
TEMPERATURE="${GENERATOR_TEMPERATURE:-0.7}"
API_TIMEOUT="${GENERATOR_TIMEOUT:-120}"
MAX_RETRIES="${GENERATOR_RETRIES:-2}"
INPUT="$(cat)"

# Allow GENERATOR_BASE_URL or CRITIC_BASE_URL override
if [[ -n "${GENERATOR_BASE_URL:-}" ]]; then
    CRITIC_BASE_URL="${GENERATOR_BASE_URL}"
fi

# --- Resolve provider ------------------------------------------------------
IFS='|' read -r PROVIDER API_URL API_KEY <<< "$(resolve_provider "$MODEL")"

if [[ "$PROVIDER" == "unknown" ]]; then
    echo "{\"error\":\"Unknown model: $MODEL. Use: ${KNOWN_MODELS}, or set GENERATOR_BASE_URL\"}" >&2
    exit 1
fi
if [[ -z "$API_KEY" ]]; then
    echo "{\"error\":\"$(provider_key_env "$PROVIDER") not set for $PROVIDER\"}" >&2
    exit 1
fi

# --- System prompt ---------------------------------------------------------
SYSTEM_PROMPT="You are a GENERATOR agent. Write the BEST solution for the given task.
1. Understand the requirement thoroughly
2. Write complete, working code with imports and examples
3. Handle edge cases and errors
4. Match response language to the input language. 用中文回复如果输入是中文。"

USER_PROMPT="${INPUT}

Write the complete solution above."

# --- Call with retry -------------------------------------------------------
ATTEMPT=0
WAIT=2
while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
    if OUTPUT=$(call_api "$PROVIDER" "$API_URL" "$API_KEY" "$MODEL" "$SYSTEM_PROMPT" "$USER_PROMPT" "$MAX_TOKENS" "$TEMPERATURE"); then
        echo "$OUTPUT"
        exit 0
    fi
    ATTEMPT=$((ATTEMPT + 1))
    if [[ $ATTEMPT -le $MAX_RETRIES ]]; then
        echo "{\"warning\":\"Attempt $ATTEMPT/$MAX_RETRIES failed, retry in ${WAIT}s...\"}" >&2
        sleep "$WAIT"
        WAIT=$((WAIT * 2))
    fi
done

echo "{\"error\":\"GENERATE_FAILED: All ${ATTEMPT} attempts to call ${MODEL} failed.\", \"fallback\":true}" >&2
exit 75  # EX_TEMPFAIL
