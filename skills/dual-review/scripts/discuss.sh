#!/usr/bin/env bash
# ============================================================================
# dual-review discuss script — multi-turn debate between two models.
#
# The Critic model receives Claude's position + current disputes and:
# 1. Evaluates each dispute (resolved / still active)
# 2. Raises new concerns if any
# 3. Updates agreement_level
# 4. Determines if the debate has converged
#
# Usage:
#   echo '{"task":"...","claude_position":"...","disputes":[...]}' | ./discuss.sh
#
# Input JSON:
#   task              — original problem
#   round             — current debate round number
#   claude_position   — Claude's latest statement / rebuttal / fix
#   disputes          — [{topic, claude_view, critic_view, status, rounds_active}]
#   history           — brief summary of previous rounds
#
# Output JSON:
#   agreement_level   — 0-1, how much consensus
#   disputes          — updated dispute list with status changes
#   new_issues        — newly raised issues
#   is_converged      — critic believes debate should end
#   summary           — free-text summary
# ============================================================================

set -euo pipefail

# --- Source config file if present -----------------------------------------
CONFIG_ENV="${HOME}/.claude/skills/dual-review/config.env"
if [[ -f "${CONFIG_ENV}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_ENV}"
fi

MODEL="${CRITIC_MODEL:-deepseek-chat}"
MAX_TOKENS="${CRITIC_MAX_TOKENS:-2048}"
TEMPERATURE="${CRITIC_TEMPERATURE:-0.3}"
API_TIMEOUT="${CRITIC_TIMEOUT:-60}"
INPUT="$(cat)"

# Resolve provider (same logic as critique.sh)
resolve_provider() {
    local model="$1"
    if [[ -n "${CRITIC_BASE_URL:-}" ]]; then
        echo "custom|${CRITIC_BASE_URL}|${CRITIC_API_KEY:-${DEEPSEEK_API_KEY:-${OPENAI_API_KEY:-}}}"
        return
    fi
    case "$model" in
        deepseek-*) echo "DeepSeek|https://api.deepseek.com/v1/chat/completions|${DEEPSEEK_API_KEY:-}" ;;
        moonshot-*) echo "Moonshot|https://api.moonshot.cn/v1/chat/completions|${MOONSHOT_API_KEY:-}" ;;
        qwen-*)     echo "Qwen|https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions|${DASHSCOPE_API_KEY:-}" ;;
        glm-*)      echo "Zhipu|https://open.bigmodel.cn/api/paas/v4/chat/completions|${ZHIPU_API_KEY:-}" ;;
        gpt-*|o1*|o3*|o4*) echo "OpenAI|https://api.openai.com/v1/chat/completions|${OPENAI_API_KEY:-}" ;;
        claude-*)   echo "Anthropic|https://api.anthropic.com/v1/messages|${ANTHROPIC_API_KEY:-}" ;;
        *)          echo "unknown||" ;;
    esac
}

IFS='|' read -r PROVIDER API_URL API_KEY <<< "$(resolve_provider "$MODEL")"

if [[ "$PROVIDER" == "unknown" ]]; then
    echo "{\"error\":\"Unknown model: $MODEL\"}" >&2; exit 1
fi
if [[ -z "$API_KEY" ]]; then
    echo "{\"error\":\"API key not set for $PROVIDER\"}" >&2; exit 1
fi

# Proxy
CURL_OPTS="-s --connect-timeout 10 --max-time ${API_TIMEOUT}"
[[ -n "${HTTPS_PROXY:-}" ]] && CURL_OPTS="$CURL_OPTS --proxy ${HTTPS_PROXY}"
[[ -n "${https_proxy:-}" ]] && CURL_OPTS="$CURL_OPTS --proxy ${https_proxy}"

# --- System prompt for debate judge ---
SYSTEM_PROMPT="You are a DEBATE JUDGE in a dual-agent discussion. Another AI (Claude) has proposed a position. Your job:

## Rules of Engagement
1. **Be fair**: If Claude makes a good point, acknowledge it. Don't argue for the sake of arguing.
2. **Be specific**: Don't say \"needs improvement\" — say exactly what and how.
3. **Concede when wrong**: If Claude's rebuttal is valid, mark the dispute RESOLVED.
4. **Stand ground when right**: If you still believe your original concern is valid, say why — but acknowledge Claude's counter-arguments.
5. **Aim for convergence**: The goal is to REACH AGREEMENT, not to win every point.

## Output Format
Return ONLY JSON (no markdown):
{
  \"agreement_level\": <0-1, overall consensus>,
  \"disputes\": [
    {
      \"topic\": \"<dispute topic>\",
      \"status\": \"resolved|still_active|new\",
      \"resolution\": \"<how it was resolved, or why still active>\",
      \"claude_conceded\": <bool>,
      \"critic_conceded\": <bool>
    }
  ],
  \"new_issues\": [
    {\"severity\": \"critical|major|minor|style\", \"description\": \"...\", \"fix_hint\": \"...\"}
  ],
  \"is_converged\": <bool, true if you believe further discussion is unproductive>,
  \"summary\": \"<one paragraph summarizing the current state of the debate>\"
}

IMPORTANT:
- If Claude has genuinely addressed your concern, set status=\"resolved\" and critic_conceded=true.
- Do NOT keep disputes active just to \"win\".
- If the same arguments repeat with no progress, set is_converged=true.
- Match response language to input."

USER_PROMPT="## Debate Context
${INPUT}

## Instructions
As the debate judge, evaluate Claude's position. Be honest — concede where Claude is right, push back where Claude is wrong. Aim for resolution."

# --- Call API ---
if [[ "$PROVIDER" == "Anthropic" ]]; then
    RESPONSE=$(curl $CURL_OPTS "$API_URL" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -d "$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" --argjson max_tokens "$MAX_TOKENS" \
            '{model:$model, system:$system, messages:[{role:"user",content:$user}], max_tokens:$max_tokens}')")
    echo "$RESPONSE" | jq -r '.content[0].text // .error.message'
else
    RESPONSE=$(curl $CURL_OPTS "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg user "$USER_PROMPT" --argjson max_tokens "$MAX_TOKENS" --argjson temperature "$TEMPERATURE" \
            '{model:$model, messages:[{role:"system",content:$system},{role:"user",content:$user}], max_tokens:$max_tokens, temperature:$temperature}')")
    echo "$RESPONSE" | jq -r '.choices[0].message.content // .error.message'
fi
