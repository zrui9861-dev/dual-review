#!/usr/bin/env bash
# ============================================================================
# dual-review critique script — calls a second LLM to review Claude's output.
#
# Supports: OpenAI, DeepSeek, Moonshot/Kimi, Qwen/Tongyi, Zhipu/GLM
#           All use OpenAI-compatible API format.
#
# Usage:
#   echo "$task_and_artifact" | ./critique.sh
#   echo "..." | CRITIC_MODEL=deepseek-chat ./critique.sh
#   echo "..." | CRITIC_MODEL=qwen-max ./critique.sh
#
# Environment (set one):
#   DEEPSEEK_API_KEY   — api.deepseek.com
#   MOONSHOT_API_KEY   — api.moonshot.cn
#   DASHSCOPE_API_KEY  — dashscope.aliyuncs.com (Qwen/Tongyi)
#   ZHIPU_API_KEY      — open.bigmodel.cn (GLM)
#   OPENAI_API_KEY     — api.openai.com
#
# Optional:
#   CRITIC_MODEL        — model name (default: deepseek-chat)
#   CRITIC_BASE_URL     — override base URL
# ============================================================================

set -euo pipefail

# --- Config ----------------------------------------------------------------
MODEL="${CRITIC_MODEL:-deepseek-chat}"
MAX_TOKENS="${CRITIC_MAX_TOKENS:-4096}"
TEMPERATURE="${CRITIC_TEMPERATURE:-0.3}"
API_TIMEOUT="${CRITIC_TIMEOUT:-60}"
INPUT="$(cat)"

# Proxy support
CURL_OPTS="-s --connect-timeout 10 --max-time ${API_TIMEOUT}"
if [[ -n "${HTTPS_PROXY:-}" ]]; then
    CURL_OPTS="$CURL_OPTS --proxy ${HTTPS_PROXY}"
elif [[ -n "${https_proxy:-}" ]]; then
    CURL_OPTS="$CURL_OPTS --proxy ${https_proxy}"
fi

# --- Resolve provider from model name --------------------------------------
# Provider format: NAME|PREFIX|BASE_URL|API_KEY_ENV_VAR
resolve_provider() {
    local model="$1"

    # Allow explicit base URL override
    if [[ -n "${CRITIC_BASE_URL:-}" ]]; then
        echo "custom|${CRITIC_BASE_URL}|${CRITIC_API_KEY:-${DEEPSEEK_API_KEY:-${OPENAI_API_KEY:-}}}"
        return
    fi

    case "$model" in
        deepseek-*)
            echo "DeepSeek|https://api.deepseek.com/v1/chat/completions|${DEEPSEEK_API_KEY:-}" ;;
        moonshot-*)
            echo "Moonshot|https://api.moonshot.cn/v1/chat/completions|${MOONSHOT_API_KEY:-}" ;;
        qwen-*|qwen-*)
            echo "Qwen|https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions|${DASHSCOPE_API_KEY:-}" ;;
        glm-*)
            echo "Zhipu|https://open.bigmodel.cn/api/paas/v4/chat/completions|${ZHIPU_API_KEY:-}" ;;
        gpt-*|o1*|o3*|o4*)
            echo "OpenAI|https://api.openai.com/v1/chat/completions|${OPENAI_API_KEY:-}" ;;
        claude-*)
            echo "Anthropic|https://api.anthropic.com/v1/messages|${ANTHROPIC_API_KEY:-}" ;;
        *)
            echo "unknown||" ;;
    esac
}

IFS='|' read -r PROVIDER API_URL API_KEY <<< "$(resolve_provider "$MODEL")"

if [[ "$PROVIDER" == "unknown" ]]; then
    echo "{\"error\":\"Unknown model: $MODEL. Use: deepseek-chat, qwen-max, glm-4, moonshot-v1, gpt-4o, claude-sonnet-4-6, or set CRITIC_BASE_URL\"}" >&2
    exit 1
fi

if [[ -z "$API_KEY" ]]; then
    # Map to user-friendly env var name
    case "$PROVIDER" in
        DeepSeek)  ENV="DEEPSEEK_API_KEY" ;;
        Moonshot)  ENV="MOONSHOT_API_KEY" ;;
        Qwen)      ENV="DASHSCOPE_API_KEY" ;;
        Zhipu)     ENV="ZHIPU_API_KEY" ;;
        OpenAI)    ENV="OPENAI_API_KEY" ;;
        Anthropic) ENV="ANTHROPIC_API_KEY" ;;
        *)         ENV="CRITIC_API_KEY" ;;
    esac
    echo "{\"error\":\"$ENV not set. Run: export $ENV=your-key\"}" >&2
    exit 1
fi

# --- System prompt (same for all models, language auto-adapts) -------------
SYSTEM_PROMPT="You are a CRITIC agent in a dual-agent review system. Your role is to RIGOROUSLY REVIEW the Generator's output.

## Your Task
1. Find factual errors, logical flaws, missing edge cases, and inefficiencies
2. Classify each issue: critical (wrong/unsafe), major (significant flaw), minor (improvement), style (cosmetic)
3. Provide SPECIFIC, ACTIONABLE fix hints for each issue
4. Score overall quality from 0.0 to 1.0
5. If critical or major issues exist, set is_blocking to true

## Output Format
Return ONLY a JSON object, no markdown, no extra text:
{
  \"score\": <float 0-1>,
  \"issues\": [
    {\"severity\": \"critical|major|minor|style\", \"description\": \"...\", \"fix_hint\": \"...\"}
  ],
  \"is_blocking\": <bool>,
  \"suggestion\": \"<one-paragraph improvement direction, or null if none>\",
  \"agreement_level\": <float 0-1>
}

Match the response language to the input language. 用中文回复如果输入是中文。"

USER_PROMPT="${INPUT}

Review the artifact above. Be thorough and adversarial.
Return ONLY JSON."

# --- Call API ---------------------------------------------------------------
if [[ "$PROVIDER" == "Anthropic" ]]; then
    # Anthropic has a different API format
    RESPONSE=$(curl $CURL_OPTS "$API_URL" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --arg system "$SYSTEM_PROMPT" \
            --arg user "$USER_PROMPT" \
            --argjson max_tokens "$MAX_TOKENS" \
            '{
                model: $model,
                system: $system,
                messages: [{role: "user", content: $user}],
                max_tokens: $max_tokens
            }')")

    echo "$RESPONSE" | jq -r '.content[0].text // .error.message'

else
    # OpenAI-compatible API (DeepSeek, Moonshot, Qwen, Zhipu, OpenAI)
    RESPONSE=$(curl $CURL_OPTS "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --arg system "$SYSTEM_PROMPT" \
            --arg user "$USER_PROMPT" \
            --argjson max_tokens "$MAX_TOKENS" \
            --argjson temperature "$TEMPERATURE" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: $max_tokens,
                temperature: $temperature
            }')")

    echo "$RESPONSE" | jq -r '.choices[0].message.content // .error.message'
fi
