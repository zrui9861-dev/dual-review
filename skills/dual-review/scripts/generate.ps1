# ============================================================================
# dual-review generate script (PowerShell) — Windows compatible.
# Calls an LLM to GENERATE code/solutions.
# Supports DeepSeek, Qwen, Moonshot, GLM, OpenAI, Anthropic, Codex, Gemini, Trae, Workbuddy.
# Usage: Get-Content task.json | .\generate.ps1
# ============================================================================

param(
    [string]$Model = $env:CRITIC_MODEL,
    [string]$BaseUrl = $env:CRITIC_BASE_URL,
    [string]$ApiKey = "",
    [int]$MaxTokens = 8192,
    [double]$Temperature = 0.7
)

# --- Source config file if present -----------------------------------------
$ConfigFile = "$env:USERPROFILE\.claude\skills\dual-review\config.ps1"
if (Test-Path $ConfigFile) {
    . $ConfigFile
    if (-not $Model -and $env:CRITIC_MODEL) { $Model = $env:CRITIC_MODEL }
    if (-not $BaseUrl -and $env:CRITIC_BASE_URL) { $BaseUrl = $env:CRITIC_BASE_URL }
}

$input_json = $input | Out-String
if (-not $Model) { $Model = "deepseek-chat" }

# Resolve provider
$providers = @{
    "deepseek" = @{ Name="DeepSeek"; Url="https://api.deepseek.com/v1/chat/completions"; KeyEnv="DEEPSEEK_API_KEY" }
    "moonshot" = @{ Name="Moonshot"; Url="https://api.moonshot.cn/v1/chat/completions"; KeyEnv="MOONSHOT_API_KEY" }
    "qwen"     = @{ Name="Qwen"; Url="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"; KeyEnv="DASHSCOPE_API_KEY" }
    "glm"      = @{ Name="Zhipu"; Url="https://open.bigmodel.cn/api/paas/v4/chat/completions"; KeyEnv="ZHIPU_API_KEY" }
    "gpt"      = @{ Name="OpenAI"; Url="https://api.openai.com/v1/chat/completions"; KeyEnv="OPENAI_API_KEY" }
    "o1"       = @{ Name="OpenAI"; Url="https://api.openai.com/v1/chat/completions"; KeyEnv="OPENAI_API_KEY" }
    "o3"       = @{ Name="OpenAI"; Url="https://api.openai.com/v1/chat/completions"; KeyEnv="OPENAI_API_KEY" }
    "o4"       = @{ Name="OpenAI"; Url="https://api.openai.com/v1/chat/completions"; KeyEnv="OPENAI_API_KEY" }
    "codex"    = @{ Name="Codex"; Url="https://api.openai.com/v1/chat/completions"; KeyEnv="OPENAI_API_KEY" }
    "gemini"   = @{ Name="Gemini"; Url="https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"; KeyEnv="GEMINI_API_KEY" }
    "trae"     = @{ Name="Trae"; Url="https://api.trae.ai/v1/chat/completions"; KeyEnv="TRAE_API_KEY" }
    "workbuddy"= @{ Name="Workbuddy"; Url="http://127.0.0.1:11434/v1/chat/completions"; KeyEnv="WORKBUDDY_API_KEY" }
}

$provider = $null
foreach ($prefix in $providers.Keys) {
    if ($Model.StartsWith($prefix)) { $provider = $providers[$prefix]; break }
}

if (-not $provider -and -not $BaseUrl) {
    Write-Error "Unknown model: $Model"
    exit 1
}

if ($BaseUrl) {
    $apiUrl = $BaseUrl
    if (-not $ApiKey) { $ApiKey = $env:CRITIC_API_KEY }
} else {
    $apiUrl = $provider.Url
    if (-not $ApiKey) { $ApiKey = [Environment]::GetEnvironmentVariable($provider.KeyEnv) }
}

if (-not $ApiKey) {
    Write-Error "API key not set."
    exit 1
}

$systemPrompt = @"
You are a GENERATOR agent in a dual-agent system. Your role is to WRITE THE BEST SOLUTION for the given task.

## Your Task
1. Understand the user's requirement thoroughly
2. Write a complete, working solution
3. Include explanations where helpful
4. Handle edge cases and errors
5. Write clean, well-structured code

## Output Format
Output the complete solution with explanation. No JSON wrapper needed.
If writing code, include the full code with imports and usage examples.
"@

$body = @{
    model = $Model
    messages = @(
        @{ role = "system"; content = $systemPrompt }
        @{ role = "user"; content = $input_json }
    )
    max_tokens = $MaxTokens
    temperature = $Temperature
} | ConvertTo-Json -Depth 5

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post `
        -Headers @{ "Authorization" = "Bearer $ApiKey"; "Content-Type" = "application/json" } `
        -Body $body -TimeoutSec 120
    $content = $response.choices[0].message.content
    Write-Output $content
} catch {
    Write-Error "API call failed: $_"
    exit 1
}
