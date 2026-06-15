#!/usr/bin/env bash
# ============================================================================
# dual-review discuss script — multi-turn debate between two models.
#
# Usage:
#   echo '{"task":"...","claude_position":"...","disputes":[...]}' | ./discuss.sh
#
# Env: CRITIC_MODEL, CRITIC_BASE_URL, CRITIC_MAX_TOKENS (2048),
#      CRITIC_TEMPERATURE (0.3), CRITIC_TIMEOUT (60)
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
MAX_TOKENS="${CRITIC_MAX_TOKENS:-2048}"
TEMPERATURE="${CRITIC_TEMPERATURE:-0.3}"
API_TIMEOUT="${CRITIC_TIMEOUT:-60}"
INPUT="$(cat)"

# --- Resolve provider ------------------------------------------------------
IFS='|' read -r PROVIDER API_URL API_KEY <<< "$(resolve_provider "$MODEL")"

if [[ "$PROVIDER" == "unknown" ]]; then
    echo "{\"error\":\"Unknown model: $MODEL\"}" >&2; exit 1
fi
if [[ -z "$API_KEY" ]]; then
    echo "{\"error\":\"API key not set for $PROVIDER\"}" >&2; exit 1
fi

# --- System prompt ---------------------------------------------------------
SYSTEM_PROMPT="You are a DEBATE JUDGE in a dual-agent discussion. Claude proposed a position. Your job:

## Rules
1. Be fair — acknowledge good points, don't argue just to argue
2. Be specific — say exactly what and how
3. Concede when wrong — if Claude's rebuttal is valid, mark RESOLVED
4. Stand ground when right — but acknowledge counter-arguments
5. Aim for convergence — goal is AGREEMENT, not winning

## Output Format — ONLY JSON:
{
  \"agreement_level\": <0-1>,
  \"disputes\": [
    {\"topic\": \"...\", \"status\": \"resolved|still_active|new\", \"resolution\": \"...\", \"claude_conceded\": <bool>, \"critic_conceded\": <bool>}
  ],
  \"new_issues\": [{\"severity\": \"critical|major|minor|style\", \"description\": \"...\", \"fix_hint\": \"...\"}],
  \"is_converged\": <bool>,
  \"summary\": \"<one paragraph>\"
}

If Claude genuinely addressed the concern → status=resolved, critic_conceded=true.
If same arguments repeat with no progress → is_converged=true.
Match response language to input."

USER_PROMPT="## Debate Context
${INPUT}

## Instructions
Evaluate Claude's position honestly. Concede where right, push back where wrong. Aim for resolution."

# --- Call API --------------------------------------------------------------
call_api "$PROVIDER" "$API_URL" "$API_KEY" "$MODEL" "$SYSTEM_PROMPT" "$USER_PROMPT" "$MAX_TOKENS" "$TEMPERATURE"
