# ============================================================================
# dual-review discuss script (PowerShell) — Windows compatible.
# Multi-turn debate between two models.
# Usage: Get-Content debate.json | .\discuss.ps1
# ============================================================================

param(
    [string]$Model = $env:CRITIC_MODEL,
    [string]$BaseUrl = $env:CRITIC_BASE_URL,
    [string]$ApiKey = "",
    [int]$MaxTokens = 2048,
    [double]$Temperature = 0.3
)

$input_json = $input | Out-String
if (-not $Model) { $Model = "deepseek-chat" }

# Resolve provider (same logic as critique.ps1)
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
You are a DEBATE JUDGE in a dual-agent discussion. Another AI (Claude) has proposed a position. Your job:

## Rules of Engagement
1. Be fair: If Claude makes a good point, acknowledge it. Don't argue for the sake of arguing.
2. Be specific: Say exactly what and how.
3. Concede when wrong: If Claude's rebuttal is valid, mark the dispute RESOLVED.
4. Stand ground when right: If you still believe your concern is valid, say why — but acknowledge Claude's counter-arguments.
5. Aim for convergence: The goal is to REACH AGREEMENT, not to win every point.

## Output Format
Return ONLY JSON (no markdown):
{
  "agreement_level": <0-1>,
  "disputes": [
    {"topic": "...", "status": "resolved|still_active|new", "resolution": "...", "claude_conceded": <bool>, "critic_conceded": <bool>}
  ],
  "new_issues": [{"severity": "critical|major|minor|style", "description": "...", "fix_hint": "..."}],
  "is_converged": <bool>,
  "summary": "<one paragraph>"
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
