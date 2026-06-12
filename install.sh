#!/usr/bin/env bash
# ============================================================================
# Dual-Review Skill — One-Line Installer (macOS / Linux)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/install.sh | bash
#
# What it does:
#   1. Creates ~/.claude/skills/dual-review/
#   2. Downloads SKILL.md + scripts (critique + discuss)
#   3. Interactive: select model + enter API key → writes config.env
#   4. Prints setup instructions
# ============================================================================

set -euo pipefail

REPO="https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/skills/dual-review"
SKILL_DIR="${HOME}/.claude/skills/dual-review"
SCRIPT_DIR="${SKILL_DIR}/scripts"
CONFIG_FILE="${SKILL_DIR}/config.env"

# --- Colors ---
BOLD="\033[1m"
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

echo ""
echo -e "${BOLD}🤖 Dual-Review Skill Installer${RESET}"
echo "==============================="
echo ""

# Detect OS
case "$(uname -s)" in
    Darwin)  OS="macOS" ;;
    Linux)   OS="Linux" ;;
    *)       OS="Unknown" ;;
esac

echo -e "📍 OS detected: ${CYAN}${OS}${RESET}"
echo -e "📁 Install dir: ${CYAN}${SKILL_DIR}${RESET}"

# Create directories
mkdir -p "${SKILL_DIR}" "${SCRIPT_DIR}"

# Download skill files
echo ""
echo "⬇️  Downloading skill files..."

download() {
    local name="$1"
    local url="$2"
    local dest="$3"
    printf "   %-30s" "${name}..."
    # --progress-bar shows a progress bar, -L follows redirects, -f fails on HTTP errors
    if curl -fL --progress-bar "${url}" -o "${dest}" 2>&1; then
        echo -e " ${GREEN}OK${RESET}"
    else
        echo -e " ${RED}FAILED${RESET}"
        echo -e "   ${RED}Error: Could not download ${url}${RESET}"
        return 1
    fi
}

download "SKILL.md"         "${REPO}/SKILL.md"         "${SKILL_DIR}/SKILL.md"
download "CONVERGENCE.md"   "${REPO}/CONVERGENCE.md"   "${SKILL_DIR}/CONVERGENCE.md"
download "EXAMPLES.md"      "${REPO}/EXAMPLES.md"      "${SKILL_DIR}/EXAMPLES.md"
download "scripts/critique.sh"   "${REPO}/scripts/critique.sh"   "${SCRIPT_DIR}/critique.sh"
download "scripts/discuss.sh"    "${REPO}/scripts/discuss.sh"    "${SCRIPT_DIR}/discuss.sh"
download "scripts/test-critique.sh" "${REPO}/scripts/test-critique.sh" "${SCRIPT_DIR}/test-critique.sh"
chmod +x "${SCRIPT_DIR}"/*.sh

# Check deps
echo ""
echo "🔍 Checking dependencies..."

MISSING=""
command -v curl >/dev/null 2>&1 || MISSING="${MISSING} curl"
command -v jq   >/dev/null 2>&1 || MISSING="${MISSING} jq"

if [[ -n "$MISSING" ]]; then
    echo -e "⚠️  Missing:${RED}${MISSING}${RESET}"
    echo ""
    if [[ "$OS" == "macOS" ]]; then
        echo "   Fix: brew install jq"
    elif [[ "$OS" == "Linux" ]]; then
        echo "   Fix: sudo apt install curl jq"
    fi
else
    echo -e "✅ curl + jq — ${GREEN}OK${RESET}"
fi

# =========================================================================
# Interactive: Model name + API key
# =========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BOLD}⚙️  Configure your Critic Model${RESET}"
echo ""
echo "The dual-review skill needs a second model to review Claude's output."
echo "You can set this up now, or skip and configure later."
echo ""

echo -e "${BOLD}Common models (for reference):${RESET}"
echo ""
echo "  deepseek-chat / deepseek-reasoner     → DeepSeek"
echo "  qwen-max / qwen-plus                  → Qwen (DashScope)"
echo "  moonshot-v1                           → Moonshot/Kimi"
echo "  glm-4                                 → Zhipu/GLM"
echo "  gpt-4o / gpt-4-turbo                  → OpenAI"
echo "  claude-sonnet-4-6 / claude-opus-4-8   → Anthropic"
echo ""
echo "  Or type any other model name → we'll ask for the API endpoint."
echo ""

# --- Ask for model name (free text) ---
MODEL_ID=""
while true; do
    printf "${BOLD}Model name${RESET} (press Enter to skip): "
    read -r MODEL_ID

    if [[ -z "$MODEL_ID" ]]; then
        echo ""
        echo -e "${YELLOW}⏭️  Skipped. You can configure later: edit ${CONFIG_FILE}${RESET}"
        break
    fi

    echo -e "   Model: ${GREEN}${MODEL_ID}${RESET}"
    break
done

# --- Auto-detect provider from model prefix ---
if [[ -n "$MODEL_ID" ]]; then
    # Normalize to lowercase for matching
    MODEL_LOWER="$(echo "$MODEL_ID" | tr '[:upper:]' '[:lower:]')"

    case "$MODEL_LOWER" in
        deepseek-*)
            PROVIDER_NAME="DeepSeek"
            DEFAULT_API_URL="https://api.deepseek.com/v1/chat/completions"
            ENV_VAR="DEEPSEEK_API_KEY"
            KEY_URL="https://platform.deepseek.com/api_keys"
            ;;
        qwen-*|qwen-*|tongyi-*)
            PROVIDER_NAME="Qwen (DashScope)"
            DEFAULT_API_URL="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
            ENV_VAR="DASHSCOPE_API_KEY"
            KEY_URL="https://dashscope.console.aliyun.com/apiKey"
            ;;
        moonshot-*|kimi-*)
            PROVIDER_NAME="Moonshot/Kimi"
            DEFAULT_API_URL="https://api.moonshot.cn/v1/chat/completions"
            ENV_VAR="MOONSHOT_API_KEY"
            KEY_URL="https://platform.moonshot.cn/console/api-keys"
            ;;
        glm-*|zhipu-*|chatglm-*)
            PROVIDER_NAME="Zhipu/GLM"
            DEFAULT_API_URL="https://open.bigmodel.cn/api/paas/v4/chat/completions"
            ENV_VAR="ZHIPU_API_KEY"
            KEY_URL="https://open.bigmodel.cn/usercenter/apikeys"
            ;;
        gpt-*|o1-*|o3-*|o4-*|gpt-*)
            PROVIDER_NAME="OpenAI"
            DEFAULT_API_URL="https://api.openai.com/v1/chat/completions"
            ENV_VAR="OPENAI_API_KEY"
            KEY_URL="https://platform.openai.com/api-keys"
            ;;
        claude-*)
            PROVIDER_NAME="Anthropic"
            DEFAULT_API_URL="https://api.anthropic.com/v1/messages"
            ENV_VAR="ANTHROPIC_API_KEY"
            KEY_URL="https://console.anthropic.com/settings/keys"
            ;;
        *)
            PROVIDER_NAME=""
            DEFAULT_API_URL=""
            ENV_VAR="CRITIC_API_KEY"
            KEY_URL=""
            ;;
    esac

    if [[ -n "$PROVIDER_NAME" ]]; then
        echo -e "   Detected: ${CYAN}${PROVIDER_NAME}${RESET}"
    else
        echo -e "   ${YELLOW}Unknown provider — will configure as custom endpoint${RESET}"
    fi

    # --- Ask for API base URL (only if provider not auto-detected) ---
    API_URL=""
    if [[ -z "$DEFAULT_API_URL" ]]; then
        echo ""
        printf "${BOLD}API endpoint URL${RESET} (e.g., https://api.example.com/v1/chat/completions): "
        read -r API_URL
        if [[ -n "$API_URL" ]]; then
            echo -e "   Endpoint: ${GREEN}${API_URL}${RESET}"
        fi
    else
        API_URL="$DEFAULT_API_URL"
        echo -e "   Endpoint: ${CYAN}${API_URL}${RESET}"
    fi

    # --- Ask for API key ---
    echo ""
    if [[ -n "$PROVIDER_NAME" ]]; then
        echo -e "${BOLD}Enter your ${PROVIDER_NAME} API key${RESET}"
    else
        echo -e "${BOLD}Enter your API key${RESET}"
    fi
    if [[ -n "$KEY_URL" ]]; then
        echo ""
        echo -e "   Get one at: ${CYAN}${KEY_URL}${RESET}"
    fi
    echo ""

    printf "${BOLD}API key (input hidden): ${RESET}"

    API_KEY_VALUE=""
    if [[ "${OS}" == "macOS" ]] || [[ "${OS}" == "Linux" ]]; then
        stty -echo 2>/dev/null || true
        read -r API_KEY_VALUE
        stty echo 2>/dev/null || true
        echo ""
    else
        read -r API_KEY_VALUE
    fi

    if [[ -z "$API_KEY_VALUE" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  No API key entered. You can add it later in ${CONFIG_FILE}${RESET}"
    else
        MASKED="${API_KEY_VALUE:0:8}...${API_KEY_VALUE: -4}"
        echo -e "   Key saved: ${GREEN}${MASKED}${RESET}"
    fi
fi

# Write config.env
echo ""
if [[ -n "$MODEL_ID" ]] && [[ -n "$API_KEY_VALUE" ]]; then
    # Backup existing config
    if [[ -f "${CONFIG_FILE}" ]]; then
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
        echo -e "${YELLOW}📋 Backed up existing config → config.env.bak${RESET}"
    fi

    cat > "${CONFIG_FILE}" << EOF
# ============================================================================
# Dual-Review Skill Configuration
# Auto-generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Source this file to load settings: source ${CONFIG_FILE}
# ============================================================================

# --- Model ---
CRITIC_MODEL="${MODEL_ID}"
EOF

    # Only write CRITIC_BASE_URL if it differs from the default (custom/unknown provider)
    if [[ -z "${DEFAULT_API_URL:-}" ]] && [[ -n "${API_URL:-}" ]]; then
        cat >> "${CONFIG_FILE}" << EOF
CRITIC_BASE_URL="${API_URL}"
EOF
    fi

    cat >> "${CONFIG_FILE}" << EOF

# --- API Key ---
${ENV_VAR}="${API_KEY_VALUE}"

# --- Optional overrides ---
# CRITIC_MAX_TOKENS=4096
# CRITIC_TEMPERATURE=0.3
# CRITIC_TIMEOUT=60
# DISCUSS_MAX_ROUNDS=5
EOF

    chmod 600 "${CONFIG_FILE}"
    echo -e "✅ Configuration saved → ${GREEN}${CONFIG_FILE}${RESET}"

    # Also add sourcing to shell profiles so it's always available
    SHELL_PROFILE=""
    if [[ -f "${HOME}/.zshrc" ]]; then
        SHELL_PROFILE="${HOME}/.zshrc"
    elif [[ -f "${HOME}/.bashrc" ]]; then
        SHELL_PROFILE="${HOME}/.bashrc"
    fi

    if [[ -n "$SHELL_PROFILE" ]]; then
        SOURCE_LINE="source ${CONFIG_FILE} 2>/dev/null  # dual-review skill config"
        if ! grep -qF "dual-review skill config" "$SHELL_PROFILE" 2>/dev/null; then
            echo "" >> "$SHELL_PROFILE"
            echo "$SOURCE_LINE" >> "$SHELL_PROFILE"
            echo -e "✅ Auto-loaded in ${CYAN}${SHELL_PROFILE}${RESET}"
        fi
    else
        echo ""
        echo -e "${YELLOW}💡 To auto-load the config, add this to your shell profile:${RESET}"
        echo -e "   ${CYAN}source ${CONFIG_FILE}${RESET}"
    fi
else
    echo -e "${YELLOW}⏭️  Config skipped. Set up later by editing ${CONFIG_FILE}${RESET}"
fi

# Done
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}${BOLD}✅ Dual-Review Skill installed!${RESET}"
echo ""
echo -e "📁 ${CYAN}${SKILL_DIR}${RESET}"
echo ""

if [[ -n "$MODEL_ID" ]] && [[ -n "$API_KEY_VALUE" ]]; then
    echo -e "${GREEN}🚀 You're all set! Start using it now:${RESET}"
    echo ""
    echo "   /dual-review \"你的任务\"                 # self-review (free)"
    echo "   /dual-review --dual \"审查这份代码\"       # dual-model review"
    echo "   /dual-review --dual --discuss \"架构设计\"  # multi-turn debate"
else
    echo -e "${YELLOW}🚀 Quick start (config needed):${RESET}"
    echo ""
    echo "   # 1. Edit config or set env var:"
    echo "   export DEEPSEEK_API_KEY=\"sk-...\""
    echo ""
    echo "   # 2. Then in Claude Code:"
    echo "   /dual-review \"你的任务\""
    echo "   /dual-review --dual \"复杂任务\""
    echo "   /dual-review --dual --discuss \"架构设计\""
fi

echo ""
echo -e "📖 Docs: ${CYAN}https://github.com/zrui9861-dev/dual-agent-sdk${RESET}"
echo ""
echo -e "${YELLOW}💡 To reconfigure: re-run this script or edit ${CONFIG_FILE}${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
