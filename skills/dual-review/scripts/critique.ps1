# ============================================================================
# dual-review critique script (PowerShell) — Windows compatible.
# Supports DeepSeek, Qwen, Moonshot, GLM, OpenAI, Anthropic.
# Usage: Get-Content artifact.json | .\critique.ps1
# ============================================================================

param(
    [string]$Model = $env:CRITIC_MODEL,
    [string]$BaseUrl = $env:CRITIC_BASE_URL,
    [string]$ApiKey = "",
    [int]$MaxTokens = 4096,
    [double]$Temperature = 0.3
)

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
}

$provider = $null
foreach ($prefix in $providers.Keys) {
    if ($Model.StartsWith($prefix)) { $provider = $providers[$prefix]; break }
}

if (-not $provider -and -not $BaseUrl) {
    Write-Error "Unknown model: $Model. Use deepseek-chat, qwen-max, glm-4, gpt-4o, or set CRITIC_BASE_URL"
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
    Write-Error "API key not set. Set environment variable or pass -ApiKey."
    exit 1
}

$systemPrompt = @"
You are a CRITIC agent in a dual-agent review system. Your job is to rigorously review the Generator's output.

## Your Task
1. Find factual errors, logical flaws, missing edge cases, and inefficiencies
2. Classify each issue: critical (wrong/unsafe), major (significant flaw), minor (improvement), style (cosmetic)
3. Provide SPECIFIC, ACTIONABLE fix hints
4. Score overall quality from 0.0 to 1.0
5. If critical or major issues exist, set is_blocking to true

## Output Format
Return ONLY a JSON object, no markdown, no extra text:
{
  "score": <float 0-1>,
  "issues": [{"severity": "critical|major|minor|style", "description": "...", "fix_hint": "..."}],
  "is_blocking": <bool>,
  "suggestion": "<one-paragraph or null>",
  "agreement_level": <float 0-1>
}
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
        -Body $body -TimeoutSec 60
    $content = $response.choices[0].message.content
    Write-Output $content
} catch {
    Write-Error "API call failed: $_"
    exit 1
}
