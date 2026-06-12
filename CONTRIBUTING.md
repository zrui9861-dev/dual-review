# Contributing to Dual Agent SDK

Thank you for your interest in contributing! This guide covers everything you need to set up, develop, test, and submit changes.

## Code of Conduct

All contributors must follow our [Code of Conduct](CODE_OF_CONDUCT.md). Be respectful, be constructive, and assume good faith.

---

## Development Environment Setup

Dual Agent SDK is a dual-language project. You can contribute to either the Python or TypeScript package independently, or work on both.

### Prerequisites

| Tool | Minimum Version | Check |
|---|---|---|
| Python | 3.10+ | `python --version` |
| Node.js | 18+ | `node --version` |
| pnpm | 9+ | `pnpm --version` |
| Git | 2.30+ | `git --version` |

### Python Setup

```bash
cd python

# Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows

# Install in editable mode with dev dependencies
pip install -e ".[dev]"
```

Verify:

```bash
pytest -v
```

### TypeScript Setup

```bash
cd typescript

# Install dependencies
pnpm install

# Build
pnpm build
```

Verify:

```bash
pnpm test
pnpm exec tsc --noEmit
```

### Full Setup (Both Packages)

```bash
# Python
cd python && python -m venv .venv && source .venv/bin/activate && pip install -e ".[dev]" && cd ..

# TypeScript
cd typescript && pnpm install && pnpm build && cd ..
```

---

## Project Structure

```
dual-agent-sdk/
├── python/
│   ├── src/dual_agent_sdk/
│   │   ├── __init__.py            # Public API surface
│   │   ├── orchestrator.py        # DualAgentOrchestrator — main loop
│   │   ├── convergence.py         # ConvergenceEngine — 6-layer Chain of Responsibility
│   │   ├── loop_detector.py       # SemanticLoopDetector — cosine similarity checks
│   │   ├── models.py              # Pydantic models (Artifact, Verdict, Issue, etc.)
│   │   ├── adapters/
│   │   │   ├── __init__.py
│   │   │   ├── base.py            # BaseAdapter abstract class
│   │   │   ├── anthropic.py       # AnthropicAdapter
│   │   │   └── openai.py          # OpenAIAdapter
│   │   └── prompts/
│   │       ├── generator.py       # GENERATOR_SYSTEM_PROMPT
│   │       └── critic.py          # CRITIC_SYSTEM_PROMPT
│   ├── tests/
│   │   ├── test_orchestrator.py
│   │   ├── test_convergence.py
│   │   ├── test_loop_detector.py
│   │   └── test_adapters.py
│   └── pyproject.toml
├── typescript/
│   ├── src/
│   │   ├── index.ts               # Public API surface
│   │   ├── orchestrator.ts        # DualAgentOrchestrator — main loop
│   │   ├── convergence.ts         # ConvergenceEngine — 6-layer Chain of Responsibility
│   │   ├── loop-detector.ts       # SemanticLoopDetector — cosine similarity checks
│   │   ├── models.ts              # Zod schemas + inferred types
│   │   ├── adapters/
│   │   │   ├── base.ts            # BaseAdapter abstract class
│   │   │   ├── anthropic.ts       # AnthropicAdapter
│   │   │   └── openai.ts          # OpenAIAdapter
│   │   └── prompts/
│   │       ├── generator.ts       # GENERATOR_SYSTEM_PROMPT
│   │       └── critic.ts          # CRITIC_SYSTEM_PROMPT
│   ├── tests/
│   │   ├── orchestrator.test.ts
│   │   ├── convergence.test.ts
│   │   ├── loop-detector.test.ts
│   │   └── adapters.test.ts
│   ├── package.json
│   └── tsconfig.json
├── docs/
│   ├── getting-started.md
│   ├── architecture.md
│   ├── api-reference.md
│   ├── convergence-protocol.md
│   └── adapters.md
├── .github/
│   ├── workflows/
│   │   ├── python-ci.yml
│   │   ├── typescript-ci.yml
│   │   └── docs.yml
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── README.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
└── LICENSE
```

### Architecture Notes

- Both packages follow the **same architecture** — identical class names, method signatures, and convergence logic. If you change one, check whether the other needs the same change.
- The **Chain of Responsibility** pattern in `ConvergenceEngine` means each layer decides independently whether to accept, continue, or escalate. Adding a new layer means inserting into the chain — do not modify existing layers' logic unless you are fixing a bug.
- **Structured output** is enforced via Pydantic (Python) and Zod (TypeScript). Adapters return raw strings; the orchestrator parses and validates them.

---

## Development Workflow

### 1. Pick an Issue

Start with an issue labeled `good first issue` or `help wanted`. Comment on the issue to let others know you are working on it.

### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or: git checkout -b fix/your-bug-fix
```

Branch naming convention:
- `feature/<name>` — new feature
- `fix/<name>` — bug fix
- `docs/<name>` — documentation
- `refactor/<name>` — refactoring

### 3. Make Changes

- Write code that is clear, well-typed, and documented.
- Add or update tests for your changes.
- Keep Python and TypeScript implementations synchronized where applicable.

### 4. Run the Full Test Suite

**Python:**

```bash
cd python
ruff check src/        # Lint
ruff format --check src/  # Format check
pytest -v --tb=short   # Tests
```

**TypeScript:**

```bash
cd typescript
pnpm exec tsc --noEmit  # Type check
pnpm lint               # Lint
pnpm test               # Tests
```

### 5. Commit

Write clear commit messages in the conventional format:

```
feat: add rate-limiting to convergence engine
fix: handle null response in Anthropic adapter
docs: update convergence protocol examples
```

### 6. Open a Pull Request

Push your branch and open a PR against `main`. Fill out the PR template completely. A maintainer will review your PR.

---

## Coding Standards

### General

- **Readability over cleverness.** The next contributor should understand your code without reading a paper.
- **Docstrings on public APIs.** Python uses Google-style docstrings; TypeScript uses JSDoc.
- **Type everything.** Python: type hints on all public functions. TypeScript: no `any` without a comment explaining why.
- **No dead code.** Delete commented-out blocks before submitting.

### Python

- Follow [PEP 8](https://peps.python.org/pep-0008/) with 100-character lines (configured in `pyproject.toml`).
- Use `ruff` for linting and formatting.
- Use Pydantic for all data models.
- `async/await` throughout — the SDK is async-first.

### TypeScript

- Follow the existing ESLint and Prettier configuration.
- Use Zod for schema definitions; export inferred types with `z.infer<>`.
- No `eslint-disable` without a comment explaining the exception.
- Prefer `const` over `let`; never use `var`.

---

## Adding a New LLM Adapter

The adapter interface is intentionally minimal so you can focus on the LLM integration, not the orchestration logic.

### Python

1. Create `python/src/dual_agent_sdk/adapters/my_provider.py`.
2. Subclass `BaseAdapter` and implement three methods:

```python
from dual_agent_sdk.adapters.base import BaseAdapter

class MyProviderAdapter(BaseAdapter):
    """Adapter for MyProvider API."""

    def __init__(self, model: str, api_key: str | None = None):
        self.model = model
        self.api_key = api_key

    async def generate(self, prompt: str, system_prompt: str) -> str:
        """Call MyProvider API and return the text response."""
        # Implement API call with error handling and retries
        ...

    def get_model_name(self) -> str:
        return self.model

    def get_provider_name(self) -> str:
        return "my_provider"
```

3. Export it in `python/src/dual_agent_sdk/adapters/__init__.py`.
4. Add to `__all__` in `python/src/dual_agent_sdk/__init__.py`.
5. Add tests in `python/tests/test_adapters.py`.

### TypeScript

1. Create `typescript/src/adapters/my-provider.ts`.
2. Extend `BaseAdapter`:

```typescript
import { BaseAdapter } from './base.js';

export class MyProviderAdapter extends BaseAdapter {
  constructor(private model: string, private apiKey?: string) {
    super();
  }

  async generate(prompt: string, systemPrompt: string): Promise<string> {
    // Implement API call with error handling and retries
    ...
  }

  getModelName(): string {
    return this.model;
  }

  getProviderName(): string {
    return 'my_provider';
  }
}
```

3. Export in `typescript/src/index.ts`.
4. Add tests in `typescript/tests/adapters.test.ts`.

---

## Testing Guidelines

### What to Test

- **Orchestrator**: Round lifecycle, convergence decisions, escalation pathways.
- **ConvergenceEngine**: Each layer independently (unit tests), then integration with the full chain.
- **SemanticLoopDetector**: Similarity thresholds, edge cases (empty strings, identical content, single-word differences).
- **Adapters**: Mock the HTTP layer. Test successful responses, error responses, retries, and timeouts.
- **Models**: Serialization and deserialization. Validation of required fields. Type coercion.

### Mock Adapters

Both packages include a `MockAdapter` in tests that returns predetermined responses. Use it to test orchestrator logic without calling real LLMs:

```python
# Python
class MockAdapter(BaseAdapter):
    def __init__(self, responses: list[str]):
        self.responses = responses
        self.call_count = 0

    async def generate(self, prompt: str, system_prompt: str) -> str:
        response = self.responses[self.call_count % len(self.responses)]
        self.call_count += 1
        return response
```

---

## Documentation

Documentation lives in `docs/`. When adding or changing features:

1. Update the relevant doc file(s).
2. If you added a new public API, add it to `docs/api-reference.md`.
3. If you changed convergence behavior, update `docs/convergence-protocol.md`.
4. Update the `README.md` if the change affects the quick start or configuration tables.

---

## Release Process

Releases are handled by maintainers. The process:

1. Update version in `python/pyproject.toml` and `typescript/package.json`.
2. Update `CHANGELOG.md` — move items from `[Unreleased]` to the new version section.
3. Create a git tag: `git tag v0.2.0`.
4. Push the tag: `git push origin v0.2.0`.
5. The CI/CD pipeline publishes to PyPI and npm.

---

## Getting Help

- **Questions?** Open a [Discussion](https://github.com/dual-agent-sdk/discussions) (if enabled) or an issue with the `question` label.
- **Stuck on a PR?** Mention a maintainer in the PR comments.
- **Security issue?** Do **not** open a public issue. Email the maintainers directly.

---

Thank you for contributing to Dual Agent SDK!
