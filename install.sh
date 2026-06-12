#!/usr/bin/env bash
# ============================================================================
# Dual-Review Skill — One-Line Installer (macOS / Linux)
#
# Usage:
#   curl -fsSL https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-agent-sdk@main/install.sh | bash
#
# Steps:
#   1. Download skill files (with progress + size)
#   2. Choose model + enter API key
#   3. Write config, done
# ============================================================================

set -u

REPO="https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-agent-sdk@main/skills/dual-review"
SKILL_DIR="${HOME}/.claude/skills/dual-review"
SCRIPT_DIR="${SKILL_DIR}/scripts"
CONFIG_FILE="${SKILL_DIR}/config.env"

BOLD="$(printf '\033[1m')"
CYAN="$(printf '\033[0;36m')"
GREEN="$(printf '\033[0;32m')"
YELLOW="$(printf '\033[0;33m')"
RED="$(printf '\033[0;31m')"
RESET="$(printf '\033[0m')"

echo ""
echo "${BOLD}=== Dual-Review Skill Installer ===${RESET}"
echo ""

case "$(uname -s)" in
    Darwin) OS="macOS" ;;
    Linux)  OS="Linux" ;;
    *)      OS="Unknown" ;;
esac

echo "OS:  ${OS}"
echo "Dir: ${SKILL_DIR}"

mkdir -p "${SKILL_DIR}" "${SCRIPT_DIR}"

# =============================================================================
# Step 1/3: Download files
# =============================================================================
echo ""
echo "${BOLD}Step 1/3: Downloading files${RESET}"
echo ""

FILES=(
    "SKILL.md"
    "CONVERGENCE.md"
    "EXAMPLES.md"
    "scripts/critique.sh"
    "scripts/discuss.sh"
    "scripts/test-critique.sh"
)

FAILED=0
for file in "${FILES[@]}"; do
    url="${REPO}/${file}"
    dest="${SKILL_DIR}/${file}"

    printf "  %-28s " "${file}"

    # Get file size first
    size=$(curl -fsLI "${url}" 2>/dev/null | grep -i content-length | tail -1 | awk '{print $2}' | tr -d '\r')
    if [[ -n "$size" ]]; then
        size_kb=$((size / 1024))
        [[ $size_kb -lt 1 ]] && size_kb=1
    else
        size_kb="?"
    fi

    # Download with progress bar
    if curl -fL --progress-bar "${url}" -o "${dest}" 2>&1; then
        echo -e "${GREEN}OK${RESET} (${size_kb} KB)"
    else
        echo -e "${RED}FAIL${RESET}"
        FAILED=$((FAILED + 1))
    fi
done

chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo -e "${RED}${FAILED} file(s) failed to download.${RESET}"
    echo "Check your network or try again later."
    echo "You can also clone the repo and run: ./install.sh"
fi

# =============================================================================
# Step 2/3: Configure model + API key
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "${BOLD}Step 2/3: Configure model${RESET}"
echo ""
echo "The skill sends your code to a second model for review."
echo "Enter a model name below. Common choices:"
echo ""
echo "  ${CYAN}deepseek-chat${RESET}       DeepSeek V3 (cheap, good for review)"
echo "  ${CYAN}deepseek-reasoner${RESET}   DeepSeek R1 (slower, thorough)"
echo "  ${CYAN}qwen-max${RESET}            Qwen (Alibaba)"
echo "  ${CYAN}moonshot-v1${RESET}         Moonshot / Kimi"
echo "  ${CYAN}glm-4${RESET}               Zhipu / ChatGLM"
echo "  ${CYAN}gpt-4o${RESET}              OpenAI"
echo "  ${CYAN}claude-sonnet-4-6${RESET}   Anthropic"
echo ""

TTY="${TTY:-/dev/tty}"

printf "${BOLD}Model name: ${RESET}" > "${TTY}"
read -r MODEL_ID < "${TTY}"

if [[ -z "${MODEL_ID}" ]]; then
    echo ""
    echo -e "${YELLOW}Skipped. You can edit ${CONFIG_FILE} later.${RESET}"
else
    echo "${MODEL_ID}"

    # Auto-detect provider
    MODEL_LOWER="$(echo "${MODEL_ID}" | tr '[:upper:]' '[:lower:]')"

    case "${MODEL_LOWER}" in
        deepseek-*)
            PROVIDER="DeepSeek"
            ENV_VAR="DEEPSEEK_API_KEY"
            KEY_URL="https://platform.deepseek.com/api_keys"
            ;;
        qwen-*|tongyi-*)
            PROVIDER="Qwen (DashScope)"
            ENV_VAR="DASHSCOPE_API_KEY"
            KEY_URL="https://dashscope.console.aliyun.com/apiKey"
            ;;
        moonshot-*|kimi-*)
            PROVIDER="Moonshot/Kimi"
            ENV_VAR="MOONSHOT_API_KEY"
            KEY_URL="https://platform.moonshot.cn/console/api-keys"
            ;;
        glm-*|zhipu-*|chatglm-*)
            PROVIDER="Zhipu/GLM"
            ENV_VAR="ZHIPU_API_KEY"
            KEY_URL="https://open.bigmodel.cn/usercenter/apikeys"
            ;;
        gpt-*|o1-*|o3-*|o4-*)
            PROVIDER="OpenAI"
            ENV_VAR="OPENAI_API_KEY"
            KEY_URL="https://platform.openai.com/api-keys"
            ;;
        claude-*)
            PROVIDER="Anthropic"
            ENV_VAR="ANTHROPIC_API_KEY"
            KEY_URL="https://console.anthropic.com/settings/keys"
            ;;
        *)
            PROVIDER=""
            ENV_VAR="CRITIC_API_KEY"
            KEY_URL=""
            ;;
    esac

    if [[ -n "${PROVIDER}" ]]; then
        echo -e "  -> ${CYAN}${PROVIDER}${RESET}"
    else
        echo -e "  -> ${YELLOW}Unknown provider${RESET}"
        echo ""
        printf "${BOLD}API endpoint URL: ${RESET}" > "${TTY}"
        read -r CUSTOM_URL < "${TTY}"
        if [[ -n "${CUSTOM_URL}" ]]; then
            echo "${CUSTOM_URL}"
        fi
    fi

    # --- API key ---
    echo ""
    echo "${BOLD}Step 3/3: API key${RESET}"
    echo ""

    if [[ -n "${PROVIDER}" ]]; then
        echo "  Provider: ${PROVIDER}"
    fi
    if [[ -n "${KEY_URL}" ]]; then
        echo "  Get key:  ${CYAN}${KEY_URL}${RESET}"
    fi
    echo ""

    printf "${BOLD}API key (hidden input): ${RESET}" > "${TTY}"

    stty -echo < "${TTY}" 2>/dev/null || true
    read -r API_KEY_VALUE < "${TTY}"
    stty echo < "${TTY}" 2>/dev/null || true
    echo ""

    if [[ -z "${API_KEY_VALUE}" ]]; then
        echo -e "${YELLOW}No key entered. Edit ${CONFIG_FILE} later.${RESET}"
    else
        MASKED="${API_KEY_VALUE:0:8}...${API_KEY_VALUE: -4}"
        echo -e "  ${GREEN}${MASKED}${RESET}"
    fi
fi

# =============================================================================
# Write config
# =============================================================================
echo ""
if [[ -n "${MODEL_ID:-}" ]] && [[ -n "${API_KEY_VALUE:-}" ]]; then
    if [[ -f "${CONFIG_FILE}" ]]; then
        cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
    fi

    cat > "${CONFIG_FILE}" << EOF
# Dual-Review Skill Config
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

CRITIC_MODEL="${MODEL_ID}"
EOF

    if [[ -n "${CUSTOM_URL:-}" ]]; then
        echo "CRITIC_BASE_URL=\"${CUSTOM_URL}\"" >> "${CONFIG_FILE}"
    fi

    cat >> "${CONFIG_FILE}" << EOF

${ENV_VAR}="${API_KEY_VALUE}"
EOF

    chmod 600 "${CONFIG_FILE}"
    echo -e "${GREEN}Config saved: ${CONFIG_FILE}${RESET}"

    # Auto-load in shell profile
    SRC="source ${CONFIG_FILE} 2>/dev/null  # dual-review"
    for rc in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
        if [[ -f "${rc}" ]]; then
            if ! grep -qF "dual-review" "${rc}" 2>/dev/null; then
                echo "" >> "${rc}"
                echo "${SRC}" >> "${rc}"
                echo "Auto-loaded in ${rc}"
            fi
        fi
    done
else
    echo -e "${YELLOW}Skipped. Edit ${CONFIG_FILE} to configure.${RESET}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Done.${RESET} Files installed to: ${SKILL_DIR}"
echo ""
echo "Usage in Claude Code:"
echo "  /dual-review \"task\""
echo "  /dual-review --dual \"task\""
echo "  /dual-review --dual --discuss \"task\""
echo ""
echo "Self-review mode works without any API key."
echo "Dual-model mode needs the key you just configured."
echo ""
echo "Re-run this script to change model or key."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
