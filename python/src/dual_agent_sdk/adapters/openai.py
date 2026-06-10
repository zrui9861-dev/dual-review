"""OpenAI adapter.

Provides :class:`OpenAIAdapter`, which calls the OpenAI Chat Completions
API via the official ``openai`` SDK.  Structured generation leverages the
``response_format`` parameter with ``json_schema``.
"""

from __future__ import annotations

import json
import os
import re
from typing import Any

from openai import AsyncOpenAI

from .base import BaseAdapter


class OpenAIAdapter(BaseAdapter):
    """Adapter for OpenAI's chat models.

    Parameters:
        model: OpenAI model ID (default ``"gpt-4o"``).
        api_key: OpenAI API key.  If ``None`` the adapter reads the
            ``OPENAI_API_KEY`` environment variable.
        **kwargs: Extra keyword arguments forwarded to
            :class:`openai.AsyncOpenAI` (e.g. ``base_url``).
    """

    def __init__(
        self,
        model: str = "gpt-4o",
        api_key: str | None = None,
        **kwargs: Any,
    ) -> None:
        resolved_key = api_key or os.environ.get("OPENAI_API_KEY")
        if not resolved_key:
            raise ValueError(
                "OpenAI API key must be provided or set via "
                "the OPENAI_API_KEY environment variable"
            )
        self._model = model
        self._client = AsyncOpenAI(api_key=resolved_key, **kwargs)

    # ------------------------------------------------------------------
    # BaseAdapter interface
    # ------------------------------------------------------------------

    async def generate(
        self, system_prompt: str, user_prompt: str, **kwargs: Any
    ) -> str:
        """Generate a text completion via the Chat Completions API."""
        response = await self._client.chat.completions.create(
            model=self._model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            max_tokens=kwargs.pop("max_tokens", 4096),
            **kwargs,
        )
        content = response.choices[0].message.content
        return content or ""

    async def generate_structured(
        self,
        system_prompt: str,
        user_prompt: str,
        output_schema: dict[str, Any],
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Generate a structured response using ``response_format``.

        Uses the ``json_schema`` response format available in recent
        OpenAI models.  Falls back to JSON extraction from the text
        response if the API does not support this mode.
        """
        schema_name = kwargs.pop("schema_name", "output")

        try:
            response = await self._client.chat.completions.create(
                model=self._model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                max_tokens=kwargs.pop("max_tokens", 4096),
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": schema_name,
                        "schema": output_schema,
                        "strict": True,
                    },
                },
                **kwargs,
            )
            content = response.choices[0].message.content
            if content is None:
                raise RuntimeError("OpenAI returned empty content")
            return json.loads(content)
        except Exception:
            # Fallback: request text and extract JSON from the response.
            text = await self.generate(
                system_prompt=system_prompt,
                user_prompt=user_prompt
                + "\n\nRespond ONLY with a JSON object matching the schema. Do not wrap in markdown fences.",
                **kwargs,
            )
            return self._extract_json(text)

    @staticmethod
    def _extract_json(text: str) -> dict[str, Any]:
        """Best-effort JSON extraction from a text block.

        Strips optional markdown code fences and parses the first JSON
        object found.
        """
        # Remove markdown fences if present.
        cleaned = re.sub(r"^```(?:json)?\s*", "", text.strip())
        cleaned = re.sub(r"\s*```$", "", cleaned)

        # Try a direct parse first.
        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            pass

        # Attempt to find a JSON object via brace matching.
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass

        raise ValueError(f"Could not extract valid JSON from response: {text[:500]}")

    @property
    def model_name(self) -> str:
        return self._model
