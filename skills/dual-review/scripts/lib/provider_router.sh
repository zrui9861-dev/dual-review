#!/usr/bin/env bash
# ============================================================================
# Shared provider router — sourced by critique.sh, discuss.sh, generate.sh
# Resolves model name → provider name, API URL, and API key.
#
# Input:  $1 = model name (e.g. "deepseek-chat", "gpt-4o", "gemini-2.5-pro")
# Output: "ProviderName|https://api.example.com/v1/chat/completions|$API_KEY"
#         or "unknown||"
# ============================================================================

resolve_provider() {
    local model="$1"

    # Allow explicit base URL override (highest priority)
    if [[ -n "${CRITIC_BASE_URL:-}" ]]; then
        echo "custom|${CRITIC_BASE_URL}|${CRITIC_API_KEY:-${DEEPSEEK_API_KEY:-${OPENAI_API_KEY:-}}}"
        return
    fi

    case "$model" in
        deepseek-*)
            echo "DeepSeek|https://api.deepseek.com/v1/chat/completions|${DEEPSEEK_API_KEY:-}" ;;
        moonshot-*|kimi-*)
            echo "Moonshot|https://api.moonshot.cn/v1/chat/completions|${MOONSHOT_API_KEY:-}" ;;
        qwen-*|tongyi-*)
            echo "Qwen|https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions|${DASHSCOPE_API_KEY:-}" ;;
        glm-*|zhipu-*|chatglm-*)
            echo "Zhipu|https://open.bigmodel.cn/api/paas/v4/chat/completions|${ZHIPU_API_KEY:-}" ;;
        gpt-*|o1*|o3*|o4*)
            echo "OpenAI|https://api.openai.com/v1/chat/completions|${OPENAI_API_KEY:-}" ;;
        claude-*)
            echo "Anthropic|https://api.anthropic.com/v1/messages|${ANTHROPIC_API_KEY:-}" ;;
        codex-*)
            echo "Codex|https://api.openai.com/v1/chat/completions|${OPENAI_API_KEY:-}" ;;
        gemini-*)
            echo "Gemini|https://generativelanguage.googleapis.com/v1beta/openai/chat/completions|${GEMINI_API_KEY:-}" ;;
        trae-*)
            echo "Trae|${TRAE_BASE_URL:-https://api.trae.ai/v1/chat/completions}|${TRAE_API_KEY:-}" ;;
        workbuddy-*)
            echo "Workbuddy|${WORKBUDDY_BASE_URL:-http://127.0.0.1:11434/v1/chat/completions}|${WORKBUDDY_API_KEY:-}" ;;
        *)
            echo "unknown||" ;;
    esac
}

# Resolve API key env var name for a provider
# Input:  $1 = provider name
# Output: env var name (e.g. "DEEPSEEK_API_KEY")
provider_key_env() {
    case "$1" in
        DeepSeek)  echo "DEEPSEEK_API_KEY" ;;
        Moonshot)  echo "MOONSHOT_API_KEY" ;;
        Qwen)      echo "DASHSCOPE_API_KEY" ;;
        Zhipu)     echo "ZHIPU_API_KEY" ;;
        OpenAI)    echo "OPENAI_API_KEY" ;;
        Anthropic) echo "ANTHROPIC_API_KEY" ;;
        Codex)     echo "OPENAI_API_KEY" ;;
        Gemini)    echo "GEMINI_API_KEY" ;;
        Trae)      echo "TRAE_API_KEY" ;;
        Workbuddy) echo "WORKBUDDY_API_KEY" ;;
        *)         echo "CRITIC_API_KEY" ;;
    esac
}

# All supported model prefixes (for error messages)
KNOWN_MODELS="deepseek-chat, qwen-max, glm-4, moonshot-v1, gpt-4o, codex-*, claude-sonnet-4-6, gemini-*, trae-*, workbuddy-*"
