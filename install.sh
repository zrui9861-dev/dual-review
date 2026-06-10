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
#   3. Prints setup instructions
# ============================================================================

set -euo pipefail

REPO="https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/skills/dual-review"
SKILL_DIR="${HOME}/.claude/skills/dual-review"
SCRIPT_DIR="${SKILL_DIR}/scripts"

echo ""
echo "🤖 Dual-Review Skill Installer"
echo "==============================="
echo ""

# Detect OS
case "$(uname -s)" in
    Darwin)  OS="macOS" ;;
    Linux)   OS="Linux" ;;
    *)       OS="Unknown" ;;
esac

echo "📍 OS detected: ${OS}"
echo "📁 Install dir: ${SKILL_DIR}"

# Create directories
mkdir -p "${SKILL_DIR}" "${SCRIPT_DIR}"

# Download skill files
echo "⬇️  Downloading SKILL.md..."
curl -fsSL "${REPO}/SKILL.md" -o "${SKILL_DIR}/SKILL.md"

echo "⬇️  Downloading CONVERGENCE.md..."
curl -fsSL "${REPO}/CONVERGENCE.md" -o "${SKILL_DIR}/CONVERGENCE.md"

echo "⬇️  Downloading EXAMPLES.md..."
curl -fsSL "${REPO}/EXAMPLES.md" -o "${SKILL_DIR}/EXAMPLES.md"

echo "⬇️  Downloading scripts..."
curl -fsSL "${REPO}/scripts/critique.sh" -o "${SCRIPT_DIR}/critique.sh"
curl -fsSL "${REPO}/scripts/discuss.sh" -o "${SCRIPT_DIR}/discuss.sh"
curl -fsSL "${REPO}/scripts/test-critique.sh" -o "${SCRIPT_DIR}/test-critique.sh"
chmod +x "${SCRIPT_DIR}"/*.sh

# Check deps
echo ""
echo "🔍 Checking dependencies..."

MISSING=""
command -v curl >/dev/null 2>&1 || MISSING="${MISSING} curl"
command -v jq   >/dev/null 2>&1 || MISSING="${MISSING} jq"

if [[ -n "$MISSING" ]]; then
    echo "⚠️  Missing:${MISSING}"
    echo ""
    if [[ "$OS" == "macOS" ]]; then
        echo "   Fix: brew install jq"
    elif [[ "$OS" == "Linux" ]]; then
        echo "   Fix: sudo apt install curl jq"
    fi
else
    echo "✅ curl + jq — OK"
fi

# Done
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Dual-Review Skill installed!"
echo ""
echo "📁 ${SKILL_DIR}"
echo ""
echo "🚀 Quick start:"
echo ""
echo "   # Set your API key (pick your provider)"
echo "   export DEEPSEEK_API_KEY=\"sk-...\""
echo "   # or: export OPENAI_API_KEY=\"sk-...\""
echo "   # or: export DASHSCOPE_API_KEY=\"sk-...\""
echo ""
echo "   # Then in Claude Code, just type:"
echo "   /dual-review \"你的任务\""
echo "   /dual-review --dual \"复杂任务\""
echo "   /dual-review --dual --discuss \"架构设计\""
echo ""
echo "📖 Docs: https://github.com/zrui9861-dev/dual-agent-sdk"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
