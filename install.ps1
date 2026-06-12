# ============================================================================
# Dual-Review Skill — One-Line Installer (Windows PowerShell)
#
# Usage:
#   Invoke-WebRequest -Uri https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/install.ps1 | Invoke-Expression
#
# What it does:
#   1. Creates ~/.claude/skills/dual-review/
#   2. Downloads SKILL.md + PowerShell scripts (with progress bars)
#   3. Interactive: free-text model name + API key → writes config.ps1
#   4. Prints setup instructions
# ============================================================================

$ErrorActionPreference = "Stop"

$Repo = "https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/skills/dual-review"
$SkillDir = "$env:USERPROFILE\.claude\skills\dual-review"
$ScriptDir = "$SkillDir\scripts"
$ConfigFile = "$SkillDir\config.ps1"

Write-Host ""
Write-Host "🤖 Dual-Review Skill Installer (Windows)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 Install dir: $SkillDir"

# Create directories
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptDir | Out-Null

# Download skill files (with progress bars)
Write-Host ""
Write-Host "⬇️  Downloading skill files..."

function Download-File {
    param($Name, $Url, $Dest)
    Write-Host "   $Name " -NoNewline
    try {
        # Show progress bar during download
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $Url -OutFile $Dest -ErrorAction Stop | Out-Null
        Write-Host "OK" -ForegroundColor Green
    } catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "   Error: Could not download $Url" -ForegroundColor Red
    }
}

Download-File "SKILL.md"         "$Repo/SKILL.md"         "$SkillDir\SKILL.md"
Download-File "CONVERGENCE.md"   "$Repo/CONVERGENCE.md"   "$SkillDir\CONVERGENCE.md"
Download-File "EXAMPLES.md"      "$Repo/EXAMPLES.md"      "$SkillDir\EXAMPLES.md"
Download-File "scripts/critique.ps1" "$Repo/scripts/critique.ps1" "$ScriptDir\critique.ps1"
Download-File "scripts/discuss.ps1"  "$Repo/scripts/discuss.ps1"  "$ScriptDir\discuss.ps1"

# =========================================================================
# Interactive: Model name + API key
# =========================================================================
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "⚙️  Configure your Critic Model" -ForegroundColor Yellow
Write-Host ""
Write-Host "The dual-review skill needs a second model to review Claude's output."
Write-Host "You can set this up now, or skip and configure later."
Write-Host ""

Write-Host "Common models (for reference):" -ForegroundColor Yellow
Write-Host ""
Write-Host "  deepseek-chat / deepseek-reasoner     → DeepSeek"
Write-Host "  qwen-max / qwen-plus                  → Qwen (DashScope)"
Write-Host "  moonshot-v1                           → Moonshot/Kimi"
Write-Host "  glm-4                                 → Zhipu/GLM"
Write-Host "  gpt-4o / gpt-4-turbo                  → OpenAI"
Write-Host "  claude-sonnet-4-6 / claude-opus-4-8   → Anthropic"
Write-Host ""
Write-Host "  Or type any other model name → we'll ask for the API endpoint."
Write-Host ""

# --- Ask for model name (free text) ---
$ModelId = ""
while ($true) {
    $input = Read-Host "Model name (press Enter to skip)"
    if (-not $input) {
        Write-Host ""
        Write-Host "⏭️  Skipped. You can configure later: edit $ConfigFile" -ForegroundColor Yellow
        break
    }
    $ModelId = $input
    Write-Host "   Model: $ModelId" -ForegroundColor Green
    break
}

# --- Auto-detect provider from model prefix ---
$ProviderName = ""
$DefaultApiUrl = ""
$EnvVar = "CRITIC_API_KEY"
$KeyUrl = ""

if ($ModelId) {
    $ModelLower = $ModelId.ToLower()

    if ($ModelLower.StartsWith("deepseek")) {
        $ProviderName = "DeepSeek"
        $DefaultApiUrl = "https://api.deepseek.com/v1/chat/completions"
        $EnvVar = "DEEPSEEK_API_KEY"
        $KeyUrl = "https://platform.deepseek.com/api_keys"
    }
    elseif ($ModelLower.StartsWith("qwen") -or $ModelLower.StartsWith("tongyi")) {
        $ProviderName = "Qwen (DashScope)"
        $DefaultApiUrl = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        $EnvVar = "DASHSCOPE_API_KEY"
        $KeyUrl = "https://dashscope.console.aliyun.com/apiKey"
    }
    elseif ($ModelLower.StartsWith("moonshot") -or $ModelLower.StartsWith("kimi")) {
        $ProviderName = "Moonshot/Kimi"
        $DefaultApiUrl = "https://api.moonshot.cn/v1/chat/completions"
        $EnvVar = "MOONSHOT_API_KEY"
        $KeyUrl = "https://platform.moonshot.cn/console/api-keys"
    }
    elseif ($ModelLower.StartsWith("glm") -or $ModelLower.StartsWith("zhipu") -or $ModelLower.StartsWith("chatglm")) {
        $ProviderName = "Zhipu/GLM"
        $DefaultApiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        $EnvVar = "ZHIPU_API_KEY"
        $KeyUrl = "https://open.bigmodel.cn/usercenter/apikeys"
    }
    elseif ($ModelLower.StartsWith("gpt") -or $ModelLower.StartsWith("o1") -or $ModelLower.StartsWith("o3") -or $ModelLower.StartsWith("o4")) {
        $ProviderName = "OpenAI"
        $DefaultApiUrl = "https://api.openai.com/v1/chat/completions"
        $EnvVar = "OPENAI_API_KEY"
        $KeyUrl = "https://platform.openai.com/api-keys"
    }
    elseif ($ModelLower.StartsWith("claude")) {
        $ProviderName = "Anthropic"
        $DefaultApiUrl = "https://api.anthropic.com/v1/messages"
        $EnvVar = "ANTHROPIC_API_KEY"
        $KeyUrl = "https://console.anthropic.com/settings/keys"
    }

    if ($ProviderName) {
        Write-Host "   Detected: $ProviderName" -ForegroundColor Cyan
    } else {
        Write-Host "   Unknown provider — will configure as custom endpoint" -ForegroundColor Yellow
    }

    # --- Ask for API base URL (only if provider not auto-detected) ---
    $ApiUrl = ""
    if (-not $DefaultApiUrl) {
        Write-Host ""
        $ApiUrl = Read-Host "API endpoint URL (e.g., https://api.example.com/v1/chat/completions)"
        if ($ApiUrl) {
            Write-Host "   Endpoint: $ApiUrl" -ForegroundColor Green
        }
    } else {
        $ApiUrl = $DefaultApiUrl
        Write-Host "   Endpoint: $ApiUrl" -ForegroundColor Cyan
    }

    # --- Ask for API key ---
    Write-Host ""
    if ($ProviderName) {
        Write-Host "Enter your $ProviderName API key" -ForegroundColor Yellow
    } else {
        Write-Host "Enter your API key" -ForegroundColor Yellow
    }
    if ($KeyUrl) {
        Write-Host ""
        Write-Host "   Get one at: $KeyUrl" -ForegroundColor Cyan
    }
    Write-Host ""

    $SecureKey = Read-Host "API key" -AsSecureString
    $Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    try {
        $ApiKeyValue = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
    }

    if (-not $ApiKeyValue) {
        Write-Host ""
        Write-Host "⚠️  No API key entered. You can add it later in $ConfigFile" -ForegroundColor Yellow
    } else {
        $Masked = $ApiKeyValue.Substring(0, [Math]::Min(8, $ApiKeyValue.Length)) + "..." + $ApiKeyValue.Substring([Math]::Max(0, $ApiKeyValue.Length - 4))
        Write-Host "   Key saved: $Masked" -ForegroundColor Green
    }
}

# Write config.ps1
Write-Host ""
if ($ModelId -and $ApiKeyValue) {
    # Backup existing config
    if (Test-Path $ConfigFile) {
        Copy-Item $ConfigFile "$ConfigFile.bak"
        Write-Host "📋 Backed up existing config → config.ps1.bak" -ForegroundColor Yellow
    }

    $ConfigContent = @"
# ============================================================================
# Dual-Review Skill Configuration (PowerShell)
# Auto-generated by install.ps1 on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Dot-source this file to load settings: . "$ConfigFile"
# ============================================================================

# --- Model ---
`$env:CRITIC_MODEL = "$ModelId"
"@

    # Only write CRITIC_BASE_URL for custom/unknown providers
    if (-not $DefaultApiUrl -and $ApiUrl) {
        $ConfigContent += @"

`$env:CRITIC_BASE_URL = "$ApiUrl"
"@
    }

    $ConfigContent += @"

# --- API Key ---
`$env:$EnvVar = "$ApiKeyValue"

# --- Optional overrides ---
# `$env:CRITIC_MAX_TOKENS = "4096"
# `$env:CRITIC_TEMPERATURE = "0.3"
# `$env:CRITIC_TIMEOUT = "60"
# `$env:DISCUSS_MAX_ROUNDS = "5"
"@

    Set-Content -Path $ConfigFile -Value $ConfigContent
    Write-Host "✅ Configuration saved → $ConfigFile" -ForegroundColor Green

    # Add to PowerShell profile for auto-loading
    $ProfileDir = Split-Path $PROFILE -Parent
    if (-not (Test-Path $ProfileDir)) {
        New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
    }

    $SourceLine = ". `"$ConfigFile`" 2>`$null  # dual-review skill config"
    if (-not (Select-String -Path $PROFILE -Pattern "dual-review skill config" -ErrorAction SilentlyContinue)) {
        Add-Content -Path $PROFILE -Value ""
        Add-Content -Path $PROFILE -Value $SourceLine
        Write-Host "✅ Auto-loaded in PowerShell profile" -ForegroundColor Green
    }
} else {
    Write-Host "⏭️  Config skipped. Set up later by editing $ConfigFile" -ForegroundColor Yellow
}

# Done
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "✅ Dual-Review Skill installed!" -ForegroundColor Green
Write-Host ""
Write-Host "📁 $SkillDir"
Write-Host ""

if ($ModelId -and $ApiKeyValue) {
    Write-Host "🚀 You're all set! Start using it now:" -ForegroundColor Green
    Write-Host ""
    Write-Host '   /dual-review "your task"                  # self-review (free)'
    Write-Host '   /dual-review --dual "review this code"     # dual-model review'
    Write-Host '   /dual-review --dual --discuss "architecture" # multi-turn debate'
} else {
    Write-Host "🚀 Quick start (config needed):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host '   # 1. Edit config or set env var:'
    Write-Host '   $env:DEEPSEEK_API_KEY = "sk-..."'
    Write-Host ""
    Write-Host '   # 2. Then in Claude Code:'
    Write-Host '   /dual-review "your task"'
    Write-Host '   /dual-review --dual "complex task"'
    Write-Host '   /dual-review --dual --discuss "architecture design"'
}

Write-Host ""
Write-Host "📖 Docs: https://github.com/zrui9861-dev/dual-agent-sdk" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 To reconfigure: re-run this script or edit $ConfigFile" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
