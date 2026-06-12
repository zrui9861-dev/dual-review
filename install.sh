#!/usr/bin/env bash
# ============================================================================
# Dual-Review Skill — One-Line Installer (macOS / Linux)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/install.sh | bash
#
# What it does:
#   1. Creates ~/.claude/skills/dual-review/
#   2. Downloads SKILL.md + scripts
#   3. Asks for model name + API key → writes config.env
#   4. Done
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

# --- Ensure stdin is the terminal (not the pipe) for interactive prompts ---
TTY="${TTY:-/dev/tty}"

echo ""
echo -e "${BOLD}Dual-Review Skill Installer${RESET}"
echo "==============================="
echo ""

# Detect OS
case "$(uname -s)" in
    Darwin)  OS="macOS" ;;
    Linux)   OS="Linux" ;;
    *)       OS="Unknown" ;;
esac

echo -e "OS:     ${CYAN}${OS}${RESET}"
echo -e "Dir:    ${CYAN}${SKILL_DIR}${RESET}"

# Create directories
mkdir -p "${SKILL_DIR}" "${SCRIPT_DIR}"

# Download skill files
echo ""
echo "Downloading..."

download() {
    local name="$1"
    local url="$2"
    local dest="$3"
    printf "  %-30s" "${name}"
    if curl -fL --progress-bar "${url}" -o "${dest}" 2>&1; then
        echo -e " ${GREEN}OK${RESET}"
    else
        echo -e " ${RED}FAIL${RESET}"
        echo -e "  ${RED}Error: ${url}${RESET}"
        return 1
    fi
}

download "SKILL.md"               "${REPO}/SKILL.md"               "${SKILL_DIR}/SKILL.md"
download "CONVERGENCE.md"         "${REPO}/CONVERGENCE.md"         "${SKILL_DIR}/CONVERGENCE.md"
download "EXAMPLES.md"            "${REPO}/EXAMPLES.md"            "${SKILL_DIR}/EXAMPLES.md"
download "scripts/critique.sh"    "${REPO}/scripts/critique.sh"    "${SCRIPT_DIR}/critique.sh"
download "scripts/discuss.sh"     "${REPO}/scripts/discuss.sh"     "${SCRIPT_DIR}/discuss.sh"
download "scripts/test-critique.sh" "${REPO}/scripts/test-critique.sh" "${SCRIPT_DIR}/test-critique.sh"
chmod +x "${SCRIPT_DIR}"/*.sh

# Check deps
echo ""
echo "Checking dependencies..."

MISSING=""
command -v curl >/dev/null 2>&1 || MISSING="${MISSING} curl"
command -v jq   >/dev/null 2>&1 || MISSING="${MISSING} jq"

if [[ -n "$MISSING" ]]; then
    echo -e "Missing:${RED}${MISSING}${RESET}"
    echo ""
    if [[ "$OS" == "macOS" ]]; then
        echo "  Fix: brew install jq"
    elif [[ "$OS" == "Linux" ]]; then
        echo "  Fix: sudo apt install curl jq"
    fi
else
    echo -e "curl + jq — ${GREEN}OK${RESET}"
fi

# =========================================================================
# Interactive: Model name + API key
# =========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BOLD}Critic Model Setup${RESET}"
echo ""
echo "The skill needs a second model to review output."
echo "Enter a model name, or press Enter to skip."
echo ""
echo "Examples:"
echo "  deepseek-chat / deepseek-reasoner"
echo "  qwen-max / qwen-plus"
echo "  moonshot-v1"
echo "  glm-4"
echo "  gpt-4o"
echo "  claude-sonnet-4-6"
echo ""

# --- Ask for model name (reads from /dev/tty so it works when piped) ---
MODEL_ID=""
printf "${BOLD}Model: ${RESET}" > "${TTY}"
read -r MODEL_ID < "${TTY}"

if [[ -z "$MODEL_ID" ]]; then
    echo ""
    echo -e "${YELLOW}Skipped. Edit ${CONFIG_FILE} later.${RESET}"
else
    echo -e "  ${GREEN}${MODEL_ID}${RESET}"

    # Auto-detect provider from model prefix
    MODEL_LOWER="$(echo "$MODEL_ID" | tr '[:upper:]' '[:lower:]')"

    case "$MODEL_LOWER" in
        deepseek-*)
            PROVIDER_NAME="DeepSeek"
            DEFAULT_API_URL="https://api.deepseek.com/v1/chat/completions"
            ENV_VAR="DEEPSEEK_API_KEY"
            KEY_URL="https://platform.deepseek.com/api_keys"
            ;;
        qwen-*|tongyi-*)
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
        gpt-*|o1-*|o3-*|o4-*)
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
        echo -e "  Provider: ${CYAN}${PROVIDER_NAME}${RESET}"
    else
        echo -e "  ${YELLOW}Unknown provider — need API endpoint.${RESET}"
    fi

    API_URL=""
    if [[ -z "$DEFAULT_API_URL" ]]; then
        echo ""
        printf "${BOLD}API URL: ${RESET}" > "${TTY}"
        read -r API_URL < "${TTY}"
        if [[ -n "$API_URL" ]]; then
            echo -e "  ${GREEN}${API_URL}${RESET}"
        fi
    else
        API_URL="$DEFAULT_API_URL"
    fi

    # --- Ask for API key ---
    echo ""
    if [[ -n "$PROVIDER_NAME" ]]; then
        echo -e "${BOLD}${PROVIDER_NAME} API key${RESET}"
    else
        echo -e "${BOLD}API key${RESET}"
    fi
    if [[ -n "$KEY_URL" ]]; then
        echo -e "  Get one: ${CYAN}${KEY_URL}${RESET}"
    fi
    echo ""

    printf "${BOLD}Key (hidden): ${RESET}" > "${TTY}"

    API_KEY_VALUE=""
    if [[ "${OS}" == "macOS" ]] || [[ "${OS}" == "Linux" ]]; then
        stty -echo < "${TTY}" 2>/dev/null || true
        read -r API_KEY_VALUE < "${TTY}"
        stty echo < "${TTY}" 2>/dev/null || true
        echo ""
    else
        read -r API_KEY_VALUE < "${TTY}"
    fi

    if [[ -z "$API_KEY_VALUE" ]]; then
        echo ""
        echo -e "${YELLOW}No key entered. Add it later in ${CONFIG_FILE}${RESET}"
    else
        MASKED="${API_KEY_VALUE:0:8}...${API_KEY_VALUE: -4}"
        echo -e "  ${GREEN}${MASKED}${RESET}"
    fi
fi

# Write config.env
echo ""
if [[ -n "${MODEL_ID:-}" ]] && [[ -n "${API_KEY_VALUE:-}" ]]; then
    if [[ -f "${CONFIG_FILE}" ]]; then
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
        echo -e "${YELLOW}Backed up: config.env.bak${RESET}"
    fi

    cat > "${CONFIG_FILE}" << EOF
# Dual-Review Skill Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Load: source ${CONFIG_FILE}

CRITIC_MODEL="${MODEL_ID}"
EOF

    if [[ -z "${DEFAULT_API_URL:-}" ]] && [[ -n "${API_URL:-}" ]]; then
        echo "CRITIC_BASE_URL=\"${API_URL}\"" >> "${CONFIG_FILE}"
    fi

    cat >> "${CONFIG_FILE}" << EOF

${ENV_VAR}="${API_KEY_VALUE}"

# CRITIC_MAX_TOKENS=4096
# CRITIC_TEMPERATURE=0.3
# DISCUSS_MAX_ROUNDS=5
EOF

    chmod 600 "${CONFIG_FILE}"
    echo -e "${GREEN}Config saved: ${CONFIG_FILE}${RESET}"

    # Auto-load in shell profile
    SHELL_PROFILE=""
    [[ -f "${HOME}/.zshrc" ]] && SHELL_PROFILE="${HOME}/.zshrc"
    [[ -f "${HOME}/.bashrc" ]] && SHELL_PROFILE="${HOME}/.bashrc"

    if [[ -n "$SHELL_PROFILE" ]]; then
        SOURCE_LINE="source ${CONFIG_FILE} 2>/dev/null  # dual-review"
        if ! grep -qF "dual-review" "$SHELL_PROFILE" 2>/dev/null; then
            echo "" >> "$SHELL_PROFILE"
            echo "$SOURCE_LINE" >> "$SHELL_PROFILE"
            echo -e "Auto-loaded in ${CYAN}${SHELL_PROFILE}${RESET}"
        fi
    fi
else
    echo -e "${YELLOW}Config skipped. Edit ${CONFIG_FILE} to set up.${RESET}"
fi

# Done
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Installed: ${SKILL_DIR}${RESET}"
echo ""

if [[ -n "${MODEL_ID:-}" ]] && [[ -n "${API_KEY_VALUE:-}" ]]; then
    echo "Usage:"
    echo "  /dual-review \"task\""
    echo "  /dual-review --dual \"task\""
    echo "  /dual-review --dual --discuss \"task\""
else
    echo "First set an API key, then:"
    echo "  /dual-review \"task\""
    echo "  /dual-review --dual \"task\""
    echo "  /dual-review --dual --discuss \"task\""
fi

echo ""
echo -e "Docs: ${CYAN}https://github.com/zrui9861-dev/dual-agent-sdk${RESET}"
echo ""
echo -e "Re-run this script to change config."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
