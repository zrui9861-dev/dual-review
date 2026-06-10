# ============================================================================
# Dual-Review Skill — One-Line Installer (Windows PowerShell)
#
# Usage:
#   Invoke-WebRequest -Uri https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/install.ps1 | Invoke-Expression
#
# What it does:
#   1. Creates ~/.claude/skills/dual-review/
#   2. Downloads SKILL.md + PowerShell scripts
#   3. Prints setup instructions
# ============================================================================

$ErrorActionPreference = "Stop"

$Repo = "https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/skills/dual-review"
$SkillDir = "$env:USERPROFILE\.claude\skills\dual-review"
$ScriptDir = "$SkillDir\scripts"

Write-Host ""
Write-Host "🤖 Dual-Review Skill Installer (Windows)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 Install dir: $SkillDir"

# Create directories
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptDir | Out-Null

# Download skill files
Write-Host "⬇️  Downloading SKILL.md..."
Invoke-WebRequest -Uri "$Repo/SKILL.md" -OutFile "$SkillDir\SKILL.md"

Write-Host "⬇️  Downloading CONVERGENCE.md..."
Invoke-WebRequest -Uri "$Repo/CONVERGENCE.md" -OutFile "$SkillDir\CONVERGENCE.md"

Write-Host "⬇️  Downloading EXAMPLES.md..."
Invoke-WebRequest -Uri "$Repo/EXAMPLES.md" -OutFile "$SkillDir\EXAMPLES.md"

Write-Host "⬇️  Downloading PowerShell scripts..."
Invoke-WebRequest -Uri "$Repo/scripts/critique.ps1" -OutFile "$ScriptDir\critique.ps1"
Invoke-WebRequest -Uri "$Repo/scripts/discuss.ps1" -OutFile "$ScriptDir\discuss.ps1"

# Done
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✅ Dual-Review Skill installed!" -ForegroundColor Green
Write-Host ""
Write-Host "📁 $SkillDir"
Write-Host ""
Write-Host "🚀 Quick start:"
Write-Host ""
Write-Host "   # Set your API key (PowerShell):"
Write-Host '   $env:DEEPSEEK_API_KEY = "sk-..."'
Write-Host ""
Write-Host "   # Then in Claude Code, just type:"
Write-Host "   /dual-review `"your task`""
Write-Host "   /dual-review --dual `"complex task`""
Write-Host "   /dual-review --dual --discuss `"architecture design`""
Write-Host ""
Write-Host "📖 Docs: https://github.com/zrui9861-dev/dual-agent-sdk" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
