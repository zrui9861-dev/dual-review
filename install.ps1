# ============================================================================
# Dual-Review Skill — One-Line Installer (Windows PowerShell)
#
# Usage:
#   Invoke-WebRequest -Uri https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/install.ps1 | Invoke-Expression
#
# What it does:
#   1. Creates ~/.claude/skills/dual-review/
#   2. Downloads SKILL.md + PowerShell scripts
#   3. Asks for model name + API key → writes config.ps1
#   4. Done
# ============================================================================

$ErrorActionPreference = "Stop"

$Repo = "https://raw.githubusercontent.com/zrui9861-dev/dual-agent-sdk/main/skills/dual-review"
$SkillDir = "$env:USERPROFILE\.claude\skills\dual-review"
$ScriptDir = "$SkillDir\scripts"
$ConfigFile = "$SkillDir\config.ps1"

Write-Host ""
Write-Host "Dual-Review Skill Installer (Windows)" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Dir: $SkillDir"

# Create directories
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptDir | Out-Null

# Download skill files
Write-Host ""
Write-Host "Downloading..."

function Download-File {
    param($Name, $Url, $Dest)
    Write-Host "  $Name " -NoNewline
    try {
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $Url -OutFile $Dest -ErrorAction Stop | Out-Null
        Write-Host "OK" -ForegroundColor Green
    } catch {
        Write-Host "FAIL" -ForegroundColor Red
        Write-Host "  Error: $Url" -ForegroundColor Red
    }
}

Download-File "SKILL.md"               "$Repo/SKILL.md"               "$SkillDir\SKILL.md"
Download-File "CONVERGENCE.md"         "$Repo/CONVERGENCE.md"         "$SkillDir\CONVERGENCE.md"
Download-File "EXAMPLES.md"            "$Repo/EXAMPLES.md"            "$SkillDir\EXAMPLES.md"
Download-File "scripts/critique.ps1"   "$Repo/scripts/critique.ps1"   "$ScriptDir\critique.ps1"
Download-File "scripts/discuss.ps1"    "$Repo/scripts/discuss.ps1"    "$ScriptDir\discuss.ps1"

# =========================================================================
# Interactive: Model name + API key
# =========================================================================
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "Critic Model Setup" -ForegroundColor Yellow
Write-Host ""
Write-Host "The skill needs a second model to review output."
Write-Host "Enter a model name, or press Enter to skip."
Write-Host ""
Write-Host "Examples:"
Write-Host "  deepseek-chat / deepseek-reasoner"
Write-Host "  qwen-max / qwen-plus"
Write-Host "  moonshot-v1"
Write-Host "  glm-4"
Write-Host "  gpt-4o"
Write-Host "  claude-sonnet-4-6"
Write-Host ""

# --- Ask for model name ---
$ModelId = Read-Host "Model"
if (-not $ModelId) {
    Write-Host ""
    Write-Host "Skipped. Edit $ConfigFile later." -ForegroundColor Yellow
} else {
    Write-Host "  $ModelId" -ForegroundColor Green

    # Auto-detect provider
    $ModelLower = $ModelId.ToLower()
    $ProviderName = ""
    $DefaultApiUrl = ""
    $EnvVar = "CRITIC_API_KEY"
    $KeyUrl = ""

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
        Write-Host "  Provider: $ProviderName" -ForegroundColor Cyan
    } else {
        Write-Host "  Unknown provider - need API endpoint." -ForegroundColor Yellow
    }

    $ApiUrl = ""
    if (-not $DefaultApiUrl) {
        Write-Host ""
        $ApiUrl = Read-Host "API URL"
        if ($ApiUrl) {
            Write-Host "  $ApiUrl" -ForegroundColor Green
        }
    } else {
        $ApiUrl = $DefaultApiUrl
    }

    # --- Ask for API key ---
    Write-Host ""
    if ($ProviderName) {
        Write-Host "$ProviderName API key" -ForegroundColor Yellow
    } else {
        Write-Host "API key" -ForegroundColor Yellow
    }
    if ($KeyUrl) {
        Write-Host "  Get one: $KeyUrl" -ForegroundColor Cyan
    }
    Write-Host ""

    $SecureKey = Read-Host "Key" -AsSecureString
    $Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    try {
        $ApiKeyValue = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
    }

    if (-not $ApiKeyValue) {
        Write-Host ""
        Write-Host "No key entered. Add it later in $ConfigFile" -ForegroundColor Yellow
    } else {
        $Masked = $ApiKeyValue.Substring(0, [Math]::Min(8, $ApiKeyValue.Length)) + "..." + $ApiKeyValue.Substring([Math]::Max(0, $ApiKeyValue.Length - 4))
        Write-Host "  $Masked" -ForegroundColor Green
    }
}

# Write config.ps1
Write-Host ""
if ($ModelId -and $ApiKeyValue) {
    if (Test-Path $ConfigFile) {
        Copy-Item $ConfigFile "$ConfigFile.bak"
        Write-Host "Backed up: config.ps1.bak" -ForegroundColor Yellow
    }

    $ConfigContent = @"
# Dual-Review Skill Configuration (PowerShell)
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Load: . "$ConfigFile"

`$env:CRITIC_MODEL = "$ModelId"
"@

    if (-not $DefaultApiUrl -and $ApiUrl) {
        $ConfigContent += @"

`$env:CRITIC_BASE_URL = "$ApiUrl"
"@
    }

    $ConfigContent += @"

`$env:$EnvVar = "$ApiKeyValue"

# `$env:CRITIC_MAX_TOKENS = "4096"
# `$env:CRITIC_TEMPERATURE = "0.3"
# `$env:DISCUSS_MAX_ROUNDS = "5"
"@

    Set-Content -Path $ConfigFile -Value $ConfigContent
    Write-Host "Config saved: $ConfigFile" -ForegroundColor Green

    # Add to PowerShell profile
    $ProfileDir = Split-Path $PROFILE -Parent
    if (-not (Test-Path $ProfileDir)) {
        New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
    }

    $SourceLine = ". `"$ConfigFile`" 2>`$null  # dual-review"
    if (-not (Select-String -Path $PROFILE -Pattern "dual-review" -ErrorAction SilentlyContinue)) {
        Add-Content -Path $PROFILE -Value ""
        Add-Content -Path $PROFILE -Value $SourceLine
        Write-Host "Auto-loaded in PowerShell profile" -ForegroundColor Green
    }
} else {
    Write-Host "Config skipped. Edit $ConfigFile to set up." -ForegroundColor Yellow
}

# Done
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "Installed: $SkillDir" -ForegroundColor Green
Write-Host ""

if ($ModelId -and $ApiKeyValue) {
    Write-Host "Usage:"
    Write-Host '  /dual-review "task"'
    Write-Host '  /dual-review --dual "task"'
    Write-Host '  /dual-review --dual --discuss "task"'
} else {
    Write-Host "First set an API key, then:"
    Write-Host '  /dual-review "task"'
    Write-Host '  /dual-review --dual "task"'
    Write-Host '  /dual-review --dual --discuss "task"'
}

Write-Host ""
Write-Host "Docs: https://github.com/zrui9861-dev/dual-agent-sdk" -ForegroundColor Cyan
Write-Host ""
Write-Host "Re-run this script to change config." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
