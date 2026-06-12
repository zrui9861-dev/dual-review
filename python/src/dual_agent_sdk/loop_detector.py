"""Semantic loop detection for the dual-agent orchestration SDK.

Provides :class:`SemanticLoopDetector`, a lightweight sliding-window detector
that flags when the Generator is producing near-identical output across
successive rounds.  Used by :class:`ConvergenceEngine` to trigger escalation.
"""

from __future__ import annotations

from collections import deque
from typing import Callable


class SemanticLoopDetector:
    """Detects semantic repetition in a stream of text strings.

    Maintains a fixed-size FIFO window of recent outputs.  Each time a new
    output arrives it is compared against every item in the window via Jaccard
    word-set similarity.  If any pairwise similarity exceeds *threshold* the
    output is considered a loop.

    When an embedding function is available, :meth:`check_with_embedding`
    provides a higher-quality cosine-similarity alternative.
    """

    # ------------------------------------------------------------------
    # Construction
    # ------------------------------------------------------------------

    def __init__(self, threshold: float = 0.92, window_size: int = 3) -> None:
        """Create a new loop detector.

        Args:
            threshold: Jaccard similarity above which two texts are
                considered semantically identical.  Range ``[0, 1]``.
            window_size: Maximum number of recent texts to retain for
                comparison.  Default is 3.
        """
        if not 0.0 <= threshold <= 1.0:
            raise ValueError("threshold must be between 0.0 and 1.0")
        if window_size < 1:
            raise ValueError("window_size must be at least 1")

        self.threshold = threshold
        self.window_size = window_size
        self._history: deque[str] = deque(maxlen=window_size)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def add(self, text: str) -> None:
        """Append *text* to the comparison window.

        Should be called after each round's artifact is accepted or the
        verdict is recorded so that the next round can compare against it.
        """
        self._history.append(text)

    def is_looping(self, new_text: str) -> bool:
        """Check whether *new_text* is too similar to recent history.

        Returns:
            ``True`` if any item in the window has Jaccard similarity
            >= *threshold* with *new_text*.
        """
        if not self._history:
            return False

        tokens_new = self._tokenize(new_text)
        for past in self._history:
            if self._jaccard_similarity(tokens_new, self._tokenize(past)) >= self.threshold:
                return True
        return False

    async def check_with_embedding(
        self, new_text: str, get_embedding_fn: Callable[[str], list[float]]
    ) -> bool:
        """Loop check powered by cosine similarity of text embeddings.

        Useful when the caller has access to an embedding model (e.g.
        ``text-embedding-3-small``).  The function is expected to be
        a coroutine / async callable.

        Args:
            new_text: Candidate text to check.
            get_embedding_fn: Async callable that maps a string to a
                fixed-length embedding vector.

        Returns:
            ``True`` if the maximum cosine similarity with any window
            entry exceeds *threshold*.
        """
        if not self._history:
            return False

        emb_new = await get_embedding_fn(new_text)
        for past in self._history:
            emb_past = await get_embedding_fn(past)
            cos_sim = self._cosine_similarity(emb_new, emb_past)
            if cos_sim >= self.threshold:
                return True
        return False

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _tokenize(text: str) -> set[str]:
        """Lowercase whitespace tokenisation into a set."""
        return set(text.lower().split())

    @staticmethod
    def _jaccard_similarity(a: set[str], b: set[str]) -> float:
        """Jaccard coefficient of two token sets."""
        if not a and not b:
            return 1.0
        intersection = len(a & b)
        union = len(a | b)
        return intersection / union if union > 0 else 0.0

    @staticmethod
    def _cosine_similarity(a: list[float], b: list[float]) -> float:
        """Cosine similarity between two equal-length vectors."""
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sum(x * x for x in a) ** 0.5
        norm_b = sum(y * y for y in b) ** 0.5
        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
        return dot / (norm_a * norm_b)
