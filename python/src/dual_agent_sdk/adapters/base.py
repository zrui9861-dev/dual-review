"""Abstract base class for LLM adapters.

Every provider adapter (Anthropic, OpenAI, …) inherits from
:class:`BaseAdapter` and implements its two generation methods.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, TypeVar

T = TypeVar("T")


class BaseAdapter(ABC):
    """Abstract base for LLM adapters.

    Subclasses translate the SDK's provider-agnostic interface into
    provider-specific API calls.  Both text generation and structured
    (JSON-schema-constrained) generation are supported.
    """

    @abstractmethod
    async def generate(
        self, system_prompt: str, user_prompt: str, **kwargs: Any
    ) -> str:
        """Generate a free-form text response.

        Args:
            system_prompt: System-level instruction for the model.
            user_prompt: User-level message / task description.
            **kwargs: Provider-specific extra parameters (temperature,
                max_tokens, etc.).

        Returns:
            The model's text response.
        """
        ...

    @abstractmethod
    async def generate_structured(
        self,
        system_prompt: str,
        user_prompt: str,
        output_schema: dict[str, Any],
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Generate a response that conforms to *output_schema*.

        Args:
            system_prompt: System-level instruction.
            user_prompt: User-level message / task description.
            output_schema: JSON Schema that the response must satisfy.
            **kwargs: Provider-specific extra parameters.

        Returns:
            A dictionary parsed from the structured model output.
        """
        ...

    @property
    @abstractmethod
    def model_name(self) -> str:
        """Human-readable identifier for the underlying model."""
        ...
