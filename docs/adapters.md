# Adapters

How to use built-in adapters, build custom ones, and compose multi-provider pipelines.

---

## How Adapters Work

Adapters are the **provider abstraction layer** in Dual Agent SDK. The orchestrator never calls LLM APIs directly -- it always goes through a `BaseAdapter` instance. This design means:

- The orchestrator is 100% provider-agnostic.
- You can swap AI backends without changing your orchestration code.
- You can use different providers for the Generator and Critic roles.
- You can create mock/test adapters that don't call any API.

Every adapter implements this minimal interface:

```
generate(system_prompt, user_prompt, **kwargs) -> str
generate_structured(system_prompt, user_prompt, output_schema, **kwargs) -> dict
model_name -> str  (property)
```

---

## Built-in Adapters

### AnthropicAdapter

Wraps the Anthropic Messages API via the `anthropic` Python SDK or `@anthropic-ai/sdk` TypeScript SDK.

**Python:**
```python
from dual_agent_sdk import AnthropicAdapter

# Minimal: uses ANTHROPIC_API_KEY env var, claude-sonnet-4-6
adapter = AnthropicAdapter()

# Explicit:
adapter = AnthropicAdapter(
    model="claude-opus-4-6",
    api_key="sk-ant-...",
    max_retries=3,        # forwarded to AsyncAnthropic
)
```

**TypeScript:**
```typescript
import { AnthropicAdapter } from 'dual-agent-sdk';

const adapter = new AnthropicAdapter(
  'claude-opus-4-6',
  'sk-ant-...',
  { temperature: 0.7 },
);
```

**Structured generation:** Uses Anthropic's tool-use mechanism. A tool named `"output"` is defined with `input_schema` matching the desired output schema, and `tool_choice` forces the model to invoke it. This guarantees a JSON response conforming to the schema.

**Supported models:** All Claude models that support tool-use (Claude 3 Opus, Sonnet, Haiku; Claude 4 Opus, Sonnet, Haiku).

---

### OpenAIAdapter

Wraps the OpenAI Chat Completions API via the `openai` Python SDK or `openai` TypeScript SDK.

**Python:**
```python
from dual_agent_sdk import OpenAIAdapter

# Minimal: uses OPENAI_API_KEY env var, gpt-4o
adapter = OpenAIAdapter()

# Explicit:
adapter = OpenAIAdapter(
    model="gpt-4.1",
    api_key="sk-...",
    organization="org-...",  # forwarded to AsyncOpenAI
)
```

**TypeScript:**
```typescript
import { OpenAIAdapter } from 'dual-agent-sdk';

const adapter = new OpenAIAdapter(
  'gpt-4.1',
  'sk-...',
  { temperature: 0.3 },
);
```

**Structured generation:** Uses OpenAI's `response_format` with `json_schema` mode. The adapter sets `strict: true` to guarantee schema conformance. Falls back to text generation with JSON extraction if the model does not support `json_schema` (older models).

**Supported models:** GPT-4o, GPT-4.1, GPT-4 Turbo, and any model that supports `response_format` with `json_schema`.

---

## Implementing Custom Adapters

### Step-by-Step Guide

To add a new LLM provider (Groq, Together, Ollama, a local model, etc.), subclass `BaseAdapter` and implement three members.

#### 1. Create the class

**Python:**
```python
from dual_agent_sdk import BaseAdapter

class GroqAdapter(BaseAdapter):
    def __init__(self, model: str = "llama-3.1-70b", api_key: str | None = None):
        self._model = model
        self._api_key = api_key or os.environ["GROQ_API_KEY"]
        # Initialize your provider's async client here.
        from groq import AsyncGroq
        self._client = AsyncGroq(api_key=self._api_key)

    @property
    def model_name(self) -> str:
        return self._model
```

**TypeScript:**
```typescript
import { BaseAdapter, GenerateOptions } from 'dual-agent-sdk';

class GroqAdapter extends BaseAdapter {
  private model: string;
  private client: Groq; // Your provider's client

  constructor(model = 'llama-3.1-70b') {
    super();
    this.model = model;
    this.client = new Groq({ apiKey: process.env['GROQ_API_KEY'] });
  }

  get modelName(): string { return this.model; }
}
```

#### 2. Implement free-form generation

**Python:**
```python
async def generate(
    self, system_prompt: str, user_prompt: str, **kwargs
) -> str:
    response = await self._client.chat.completions.create(
        model=self._model,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        max_tokens=kwargs.pop("max_tokens", 4096),
        **kwargs,
    )
    return response.choices[0].message.content or ""
```

**TypeScript:**
```typescript
async generate(
  systemPrompt: string,
  userPrompt: string,
  options?: GenerateOptions,
): Promise<string> {
  const response = await this.client.chat.completions.create({
    model: this.model,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: options?.maxTokens ?? 4096,
  });
  return response.choices[0]?.message?.content ?? '';
}
```

#### 3. Implement structured generation

This is the trickier method. Your provider must return JSON that conforms to `output_schema`. Common strategies:

- **Native structured output** (like OpenAI's `json_schema` or Anthropic's tool-use): The provider guarantees schema conformance.
- **Prompt-based** (for providers without native support): Append the schema to the prompt as instructions and parse the response.
- **Retry-based**: Call `generate`, try `json.loads()`, retry with stronger prompting if it fails.

**Python example (prompt-based fallback):**
```python
import json

async def generate_structured(
    self, system_prompt: str, user_prompt: str,
    output_schema: dict, **kwargs,
) -> dict:
    # Append schema as instructions.
    schema_str = json.dumps(output_schema, indent=2)
    full_prompt = (
        f"{user_prompt}\n\n"
        f"Respond with a JSON object matching this schema:\n{schema_str}\n"
        "Do NOT wrap in markdown fences. Output ONLY the JSON object."
    )
    text = await self.generate(system_prompt, full_prompt, **kwargs)

    # Best-effort JSON extraction.
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        import re
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if match:
            return json.loads(match.group(0))
        raise ValueError(f"Could not parse JSON from: {text[:200]}")
```

#### 4. Use your adapter

```python
gen = GroqAdapter(model="llama-3.1-70b")
crit = OpenAIAdapter(model="gpt-4o")
orch = DualAgentOrchestrator(gen, crit)
result = await orch.run("Write a recursive descent parser.")
```

---

## Adapter Best Practices

### Error Handling

The orchestrator wraps adapter calls in try/except and falls back gracefully. However, you should still handle transient errors (rate limits, timeouts) inside your adapter with retry logic:

```python
import asyncio

async def generate(self, system_prompt: str, user_prompt: str, **kwargs) -> str:
    max_retries = 3
    for attempt in range(max_retries):
        try:
            response = await self._client.messages.create(...)
            return extract_text(response)
        except RateLimitError:
            if attempt == max_retries - 1:
                raise
            await asyncio.sleep(2 ** attempt)
```

### Structured Output Robustness

Not all providers support native structured output. When implementing a prompt-based approach:

1. **Be explicit** -- tell the model exactly what JSON shape you expect.
2. **Request raw JSON** -- explicitly instruct the model not to wrap in markdown fences.
3. **Provide examples** -- include a one-shot example in the prompt showing the exact format.
4. **Fall back gracefully** -- try regex extraction, then return a safe default if all parsing fails.
5. **Log parse failures** -- structured output failures are valuable signals for debugging prompts.

### Temperature and Determinism

- **Generator**: Use moderate temperature (0.6-0.8) for creative, diverse solutions. Lower for factual/code tasks.
- **Critic**: Use low temperature (0.2-0.4) for consistent, reliable reviews. The Critic should be deterministic -- you do not want it to give different scores to the same artifact.
- These are passed via `**kwargs` (Python) or `options` (TypeScript) to the adapter at call time, or set as defaults in the adapter constructor.

### Max Tokens

The orchestrator uses `max_tokens=4096` by default. For tasks that produce very long output (e.g., full module generation), you may need to increase this:

```python
# Python: pass via kwargs in adapter constructor
adapter = AnthropicAdapter(model="claude-sonnet-4-6", max_tokens=8192)

# TypeScript: pass via options
const adapter = new AnthropicAdapter('claude-sonnet-4-6', undefined, { maxTokens: 8192 });
```

---

## Multi-Provider Patterns

### Different Models Per Role (Recommended)

The most common pattern: a strong model generates, a different model reviews.

```python
gen = AnthropicAdapter(model="claude-sonnet-4-6")
crit = OpenAIAdapter(model="gpt-4o")
orch = DualAgentOrchestrator(gen, crit)
```

**Why:** Different model families have different biases, training data, and failure modes. A bug that Claude misses, GPT-4o might catch, and vice versa. This diversity is the key value proposition of the dual-agent pattern.

### Same Provider, Different Models

Use a powerful model for generation and a faster/cheaper one for critique:

```python
gen = AnthropicAdapter(model="claude-opus-4-6")
crit = AnthropicAdapter(model="claude-haiku-4-6")
orch = DualAgentOrchestrator(gen, crit)
```

This gives you the best generation quality while keeping review costs low. Haiku is fast and cheap but still capable of thorough code review.

### Same Model, Different Instances (Discouraged)

```python
gen = OpenAIAdapter(model="gpt-4o")
crit = OpenAIAdapter(model="gpt-4o")
orch = DualAgentOrchestrator(gen, crit)
```

This works and the orchestrator accepts it (different instances are allowed), but it provides less review diversity than using different models or providers. The Critic may share the Generator's blind spots.

### Custom Adapter + Built-in

```python
from my_adapters import OllamaAdapter

gen = OllamaAdapter(model="llama3:70b", base_url="http://localhost:11434")
crit = AnthropicAdapter(model="claude-sonnet-4-6")
orch = DualAgentOrchestrator(gen, crit)
```

Run the Generator locally (no API cost, full privacy) and use a cloud model for high-quality critique.

---

## Wrapping Adapters (Decorator Pattern)

You can wrap any adapter to add cross-cutting concerns without modifying the original:

```python
class LoggingAdapter(BaseAdapter):
    """Logs every prompt and response."""

    def __init__(self, inner: BaseAdapter):
        self._inner = inner

    @property
    def model_name(self) -> str:
        return f"logged[{self._inner.model_name}]"

    async def generate(self, system_prompt, user_prompt, **kwargs):
        print(f"[LOG] generate: {user_prompt[:100]}...")
        result = await self._inner.generate(system_prompt, user_prompt, **kwargs)
        print(f"[LOG] response: {result[:100]}...")
        return result

    async def generate_structured(self, system_prompt, user_prompt, schema, **kwargs):
        print(f"[LOG] generate_structured: {user_prompt[:100]}...")
        result = await self._inner.generate_structured(
            system_prompt, user_prompt, schema, **kwargs
        )
        print(f"[LOG] result keys: {list(result.keys())}")
        return result
```

Usage:

```python
raw_gen = AnthropicAdapter(model="claude-sonnet-4-6")
raw_crit = OpenAIAdapter(model="gpt-4o")

orch = DualAgentOrchestrator(
    generator=LoggingAdapter(raw_gen),
    critic=LoggingAdapter(raw_crit),
)
```

This pattern is also useful for caching (check a cache before calling the real adapter), rate-limiting (throttle calls), and cost tracking (log token counts).

---

## Testing with Mock Adapters

For unit tests and development, you can create adapters that return canned responses:

```python
class MockAdapter(BaseAdapter):
    """Returns hardcoded responses.  Never calls an API."""

    def __init__(self, name: str = "mock", response: str = "{}"):
        self._name = name
        self._response = response

    @property
    def model_name(self) -> str:
        return self._name

    async def generate(self, system_prompt, user_prompt, **kwargs):
        return self._response

    async def generate_structured(self, system_prompt, user_prompt, schema, **kwargs):
        import json
        try:
            return json.loads(self._response)
        except json.JSONDecodeError:
            return {"content": self._response, "reasoning": "", "confidence": 0.5}
```

This lets you test the orchestrator's state machine and convergence logic without any API calls or costs.
