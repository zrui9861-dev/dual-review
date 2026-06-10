#!/usr/bin/env bash
# ============================================================================
# Test the dual-review critique pipeline with a sample artifact.
# Usage: ./test-critique.sh
# ============================================================================

set -euo pipefail

echo "=== Testing dual-review critique pipeline ==="
echo ""

# Check API key
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "⚠️  OPENAI_API_KEY not set. Skipping dual-model test."
    echo "   Set it with: export OPENAI_API_KEY=sk-..."
    exit 0
fi

echo "✅ OPENAI_API_KEY is set"
echo "   Model: ${CRITIC_MODEL:-gpt-4o} (default)"
echo ""

# Sample input
SAMPLE=$(cat <<'EOF'
## Task
Write a Python function to validate email addresses.

## Artifact
```python
import re

def validate_email(email: str) -> bool:
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))
```

## Generator's Reasoning
Used a standard regex pattern for email validation. Simple and covers most cases.

## Generator's Confidence
0.85
EOF
)

echo "📤 Sending artifact to critic..."
echo ""

RESULT=$(echo "$SAMPLE" | bash "$(dirname "$0")/critique.sh" 2>&1)

echo "📥 Critic response:"
echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"

echo ""
echo "=== Test complete ==="
