"""Anthropic (Claude) adapter.

Provides :class:`AnthropicAdapter`, which calls the Anthropic Messages API
via the official ``anthropic`` SDK.  Structured generation is implemented
via tool-use with forced tool calling.
"""

from __future__ import annotations

import json
import os
from typing import Any

from anthropic import AsyncAnthropic

from .base import BaseAdapter


class AnthropicAdapter(BaseAdapter):
    """Adapter for Anthropic's Claude models.

    Parameters:
        model: Anthropic model ID (default ``"claude-sonnet-4-6"``).
        api_key: Anthropic API key.  If ``None`` the adapter reads the
            ``ANTHROPIC_API_KEY`` environment variable.
        **kwargs: Extra keyword arguments forwarded to
            :class:`anthropic.AsyncAnthropic` (e.g. ``base_url``).
    """

    def __init__(
        self,
        model: str = "claude-sonnet-4-6",
        api_key: str | None = None,
        **kwargs: Any,
    ) -> None:
        resolved_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not resolved_key:
            raise ValueError(
                "Anthropic API key must be provided or set via "
                "the ANTHROPIC_API_KEY environment variable"
            )
        self._model = model
        self._client = AsyncAnthropic(api_key=resolved_key, **kwargs)

    # ------------------------------------------------------------------
    # BaseAdapter interface
    # ------------------------------------------------------------------

    async def generate(
        self, system_prompt: str, user_prompt: str, **kwargs: Any
    ) -> str:
        """Generate a text completion via the Messages API."""
        response = await self._client.messages.create(
            model=self._model,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
            max_tokens=kwargs.pop("max_tokens", 4096),
            **kwargs,
        )
        # The response content is a list of blocks; extract the first text block.
        for block in response.content:
            if block.type == "text":
                return block.text
        # Fallback: concatenate all text blocks.
        return "".join(
            block.text for block in response.content if block.type == "text"
        )

    async def generate_structured(
        self,
        system_prompt: str,
        user_prompt: str,
        output_schema: dict[str, Any],
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Generate a structured response via tool-use forcing.

        We define a single tool whose input schema matches *output_schema*
        and instruct the model to call it.  The returned JSON is parsed
        and returned as a dict.
        """
        tool_name = kwargs.pop("tool_name", "output")

        response = await self._client.messages.create(
            model=self._model,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
            max_tokens=kwargs.pop("max_tokens", 4096),
            tools=[
                {
                    "name": tool_name,
                    "description": "Deliver the structured output.",
                    "input_schema": output_schema,
                }
            ],
            tool_choice={"type": "tool", "name": tool_name},
            **kwargs,
        )

        # Extract the tool-use result.
        for block in response.content:
            if block.type == "tool_use":
                return block.input  # type: ignore[return-value]

        raise RuntimeError(
            "Anthropic did not return a tool_use block; "
            "structured generation failed."
        )

    @property
    def model_name(self) -> str:
        return self._model
