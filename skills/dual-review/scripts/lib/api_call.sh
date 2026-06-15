#!/usr/bin/env bash
# ============================================================================
# Shared API caller — sourced by critique.sh, discuss.sh, generate.sh
# Handles both Anthropic (native) and OpenAI-compatible API formats.
#
# Usage: call_api <provider> <api_url> <api_key> <model> <system_prompt> <user_prompt> <max_tokens> [temperature]
# Returns: 0 + outputs response content on success
#          1 on failure (HTTP error, API error, or empty response)
# ============================================================================

call_api() {
    local provider="$1"
    local api_url="$2"
    local api_key="$3"
    local model="$4"
    local system_prompt="$5"
    local user_prompt="$6"
    local max_tokens="$7"
    local temperature="${8:-0.3}"
    local http_code response content

    # Build curl options (proxy-aware)
    local curl_opts="-s --connect-timeout 10 --max-time ${API_TIMEOUT:-60}"
    if [[ -n "${HTTPS_PROXY:-}" ]]; then
        curl_opts="$curl_opts --proxy ${HTTPS_PROXY}"
    elif [[ -n "${https_proxy:-}" ]]; then
        curl_opts="$curl_opts --proxy ${https_proxy}"
    fi

    if [[ "$provider" == "Anthropic" ]]; then
        # --- Anthropic native API ---
        response=$(curl $curl_opts -w "\n%{http_code}" "$api_url" \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${api_key}" \
            -H "anthropic-version: 2023-06-01" \
            -d "$(jq -n \
                --arg model "$model" \
                --arg system "$system_prompt" \
                --arg user "$user_prompt" \
                --argjson max_tokens "$max_tokens" \
                '{model: $model, system: $system, messages: [{role: "user", content: $user}], max_tokens: $max_tokens}')" 2>&1)

        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        if [[ "$http_code" -ge 400 ]] || echo "$response" | jq -e '.error' >/dev/null 2>&1; then
            echo "$response" | jq -r --arg code "$http_code" '.error.message // "HTTP \($code)"' >&2
            return 1
        fi

        content=$(echo "$response" | jq -r '.content[0].text // empty')
        if [[ -z "$content" ]]; then
            echo "Empty response from Anthropic (HTTP ${http_code})" >&2
            return 1
        fi
        echo "$content"

    else
        # --- OpenAI-compatible API ---
        response=$(curl $curl_opts -w "\n%{http_code}" "$api_url" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${api_key}" \
            -d "$(jq -n \
                --arg model "$model" \
                --arg system "$system_prompt" \
                --arg user "$user_prompt" \
                --argjson max_tokens "$max_tokens" \
                --argjson temperature "$temperature" \
                '{model: $model, messages: [{role: "system", content: $system}, {role: "user", content: $user}], max_tokens: $max_tokens, temperature: $temperature}')" 2>&1)

        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        if [[ "$http_code" -ge 400 ]] || echo "$response" | jq -e '.error' >/dev/null 2>&1; then
            echo "$response" | jq -r --arg code "$http_code" '.error.message // "HTTP \($code)"' >&2
            return 1
        fi

        content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
        if [[ -z "$content" ]]; then
            echo "Empty response from API (HTTP ${http_code})" >&2
            return 1
        fi
        echo "$content"
    fi
}
