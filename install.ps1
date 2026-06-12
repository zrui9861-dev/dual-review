# ============================================================================
# Dual-Review Skill — One-Line Installer (Windows PowerShell)
#
# Usage:
#   Invoke-WebRequest -Uri https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-agent-sdk@main/install.ps1 | Invoke-Expression
#
# Steps:
#   1. Download skill files (with progress + size)
#   2. Choose model + enter API key
#   3. Write config, done
# ============================================================================

$ErrorActionPreference = "Continue"

$Repo = "https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-agent-sdk@main/skills/dual-review"
$SkillDir = "$env:USERPROFILE\.claude\skills\dual-review"
$ScriptDir = "$SkillDir\scripts"
$ConfigFile = "$SkillDir\config.ps1"

Write-Host ""
Write-Host "=== Dual-Review Skill Installer (Windows) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Dir: $SkillDir"

New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptDir | Out-Null

# =============================================================================
# Step 1/3: Download files
# =============================================================================
Write-Host ""
Write-Host "Step 1/3: Downloading files" -ForegroundColor Yellow
Write-Host ""

$Files = @(
    @{N="SKILL.md";         U="$Repo/SKILL.md";         D="$SkillDir\SKILL.md"}
    @{N="CONVERGENCE.md";   U="$Repo/CONVERGENCE.md";   D="$SkillDir\CONVERGENCE.md"}
    @{N="EXAMPLES.md";      U="$Repo/EXAMPLES.md";      D="$SkillDir\EXAMPLES.md"}
    @{N="scripts/critique.ps1"; U="$Repo/scripts/critique.ps1"; D="$ScriptDir\critique.ps1"}
    @{N="scripts/discuss.ps1";  U="$Repo/scripts/discuss.ps1";  D="$ScriptDir\discuss.ps1"}
)

$Failed = 0
foreach ($f in $Files) {
    Write-Host ("  {0,-28} " -f $f.N) -NoNewline
    try {
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $f.U -OutFile $f.D -ErrorAction Stop | Out-Null
        $size = (Get-Item $f.D).Length
        $sizeKB = [Math]::Max(1, [Math]::Round($size / 1024))
        Write-Host "OK ($sizeKB KB)" -ForegroundColor Green
    } catch {
        Write-Host "FAIL" -ForegroundColor Red
        $Failed++
    }
}

if ($Failed -gt 0) {
    Write-Host ""
    Write-Host "$Failed file(s) failed. Check your network." -ForegroundColor Red
}

# =============================================================================
# Step 2/3: Configure model + API key
# =============================================================================
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "Step 2/3: Configure model" -ForegroundColor Yellow
Write-Host ""
Write-Host "The skill sends your code to a second model for review."
Write-Host "Enter a model name below. Common choices:"
Write-Host ""
Write-Host "  deepseek-chat       DeepSeek V3 (cheap, good for review)" -ForegroundColor Cyan
Write-Host "  deepseek-reasoner   DeepSeek R1 (slower, thorough)" -ForegroundColor Cyan
Write-Host "  qwen-max            Qwen (Alibaba)" -ForegroundColor Cyan
Write-Host "  moonshot-v1         Moonshot / Kimi" -ForegroundColor Cyan
Write-Host "  glm-4               Zhipu / ChatGLM" -ForegroundColor Cyan
Write-Host "  gpt-4o              OpenAI" -ForegroundColor Cyan
Write-Host "  claude-sonnet-4-6   Anthropic" -ForegroundColor Cyan
Write-Host ""

$ModelId = Read-Host "Model name"

if (-not $ModelId) {
    Write-Host ""
    Write-Host "Skipped. Edit $ConfigFile later." -ForegroundColor Yellow
} else {
    Write-Host $ModelId

    $ModelLower = $ModelId.ToLower()
    $Provider = ""
    $EnvVar = "CRITIC_API_KEY"
    $KeyUrl = ""
    $CustomUrl = ""

    if ($ModelLower.StartsWith("deepseek")) {
        $Provider = "DeepSeek"
        $EnvVar = "DEEPSEEK_API_KEY"
        $KeyUrl = "https://platform.deepseek.com/api_keys"
    }
    elseif ($ModelLower.StartsWith("qwen") -or $ModelLower.StartsWith("tongyi")) {
        $Provider = "Qwen (DashScope)"
        $EnvVar = "DASHSCOPE_API_KEY"
        $KeyUrl = "https://dashscope.console.aliyun.com/apiKey"
    }
    elseif ($ModelLower.StartsWith("moonshot") -or $ModelLower.StartsWith("kimi")) {
        $Provider = "Moonshot/Kimi"
        $EnvVar = "MOONSHOT_API_KEY"
        $KeyUrl = "https://platform.moonshot.cn/console/api-keys"
    }
    elseif ($ModelLower.StartsWith("glm") -or $ModelLower.StartsWith("zhipu") -or $ModelLower.StartsWith("chatglm")) {
        $Provider = "Zhipu/GLM"
        $EnvVar = "ZHIPU_API_KEY"
        $KeyUrl = "https://open.bigmodel.cn/usercenter/apikeys"
    }
    elseif ($ModelLower.StartsWith("gpt") -or $ModelLower.StartsWith("o1") -or $ModelLower.StartsWith("o3") -or $ModelLower.StartsWith("o4")) {
        $Provider = "OpenAI"
        $EnvVar = "OPENAI_API_KEY"
        $KeyUrl = "https://platform.openai.com/api-keys"
    }
    elseif ($ModelLower.StartsWith("claude")) {
        $Provider = "Anthropic"
        $EnvVar = "ANTHROPIC_API_KEY"
        $KeyUrl = "https://console.anthropic.com/settings/keys"
    }

    if ($Provider) {
        Write-Host "  -> $Provider" -ForegroundColor Cyan
    } else {
        Write-Host "  -> Unknown provider" -ForegroundColor Yellow
        Write-Host ""
        $CustomUrl = Read-Host "API endpoint URL"
        if ($CustomUrl) {
            Write-Host $CustomUrl
        }
    }

    # --- API key ---
    Write-Host ""
    Write-Host "Step 3/3: API key" -ForegroundColor Yellow
    Write-Host ""

    if ($Provider) {
        Write-Host "  Provider: $Provider"
    }
    if ($KeyUrl) {
        Write-Host "  Get key:  $KeyUrl" -ForegroundColor Cyan
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
        Write-Host "No key entered. Edit $ConfigFile later." -ForegroundColor Yellow
    } else {
        $Masked = $ApiKeyValue.Substring(0, [Math]::Min(8, $ApiKeyValue.Length)) + "..." + $ApiKeyValue.Substring([Math]::Max(0, $ApiKeyValue.Length - 4))
        Write-Host "  $Masked" -ForegroundColor Green
    }
}

# =============================================================================
# Write config
# =============================================================================
Write-Host ""
if ($ModelId -and $ApiKeyValue) {
    if (Test-Path $ConfigFile) {
        Copy-Item $ConfigFile "$ConfigFile.bak"
    }

    $ConfigContent = @"
# Dual-Review Skill Config (PowerShell)
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

`$env:CRITIC_MODEL = "$ModelId"
"@

    if ($CustomUrl) {
        $ConfigContent += @"

`$env:CRITIC_BASE_URL = "$CustomUrl"
"@
    }

    $ConfigContent += @"

`$env:$EnvVar = "$ApiKeyValue"
"@

    Set-Content -Path $ConfigFile -Value $ConfigContent
    Write-Host "Config saved: $ConfigFile" -ForegroundColor Green

    # Auto-load in PowerShell profile
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
    Write-Host "Skipped. Edit $ConfigFile to configure." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "Done. Files installed to: $SkillDir" -ForegroundColor Green
Write-Host ""
Write-Host "Usage in Claude Code:"
Write-Host '  /dr "task"'
Write-Host '  /dr discuss "task"'
Write-Host ""
Write-Host "/dr works without key (self-review)."
Write-Host "With key, dual-model review runs by default."
Write-Host ""
Write-Host "Re-run this script to change model or key."
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
