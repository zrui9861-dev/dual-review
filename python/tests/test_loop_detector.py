"""Tests for the SemanticLoopDetector."""

import pytest

from dual_agent_sdk.loop_detector import SemanticLoopDetector


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


class TestConstruction:
    def test_default_threshold(self):
        detector = SemanticLoopDetector()
        assert detector.threshold == 0.92
        assert detector.window_size == 3

    def test_custom_values(self):
        detector = SemanticLoopDetector(threshold=0.5, window_size=5)
        assert detector.threshold == 0.5
        assert detector.window_size == 5

    def test_threshold_boundary_zero(self):
        detector = SemanticLoopDetector(threshold=0.0)
        assert detector.threshold == 0.0

    def test_threshold_boundary_one(self):
        detector = SemanticLoopDetector(threshold=1.0)
        assert detector.threshold == 1.0

    def test_invalid_threshold_high_raises(self):
        with pytest.raises(ValueError, match="between 0.0 and 1.0"):
            SemanticLoopDetector(threshold=1.1)

    def test_invalid_threshold_negative_raises(self):
        with pytest.raises(ValueError, match="between 0.0 and 1.0"):
            SemanticLoopDetector(threshold=-0.1)

    def test_invalid_window_size_raises(self):
        with pytest.raises(ValueError, match="window_size"):
            SemanticLoopDetector(window_size=0)

    def test_window_size_one_is_valid(self):
        detector = SemanticLoopDetector(window_size=1)
        assert detector.window_size == 1


# ---------------------------------------------------------------------------
# is_looping
# ---------------------------------------------------------------------------


class TestIsLooping:
    def test_empty_history_not_looping(self):
        detector = SemanticLoopDetector()
        assert not detector.is_looping("some text")

    def test_identical_text_is_looping(self):
        detector = SemanticLoopDetector(threshold=0.5)
        detector.add("The sky is blue and the sun is bright.")
        assert detector.is_looping("The sky is blue and the sun is bright.")

    def test_similar_text_is_looping(self):
        detector = SemanticLoopDetector(threshold=0.5)
        detector.add("The function should implement a caching layer.")
        assert detector.is_looping("The function should implement a caching strategy.")
        # Overlapping words: the, function, should, implement, a, caching
        # Similarity should be high.

    def test_different_text_not_looping(self):
        detector = SemanticLoopDetector(threshold=0.9)
        detector.add("Implement a Redis-based rate limiter.")
        assert not detector.is_looping("Create a PostgreSQL connection pool.")

    def test_below_threshold_not_looping(self):
        detector = SemanticLoopDetector(threshold=0.95)
        detector.add("happy cat")
        assert not detector.is_looping("angry dog")
        # Only common word sets have zero overlap → 0.0 < 0.95

    def test_multiple_items_in_window(self):
        detector = SemanticLoopDetector(threshold=0.3, window_size=5)
        detector.add("Topic A: design the API")
        detector.add("Topic B: database schema")
        detector.add("Topic C: authentication")
        detector.add("Topic D: logging")
        # New text similar to one item in the window
        assert detector.is_looping("Topic A: design the API endpoint")
        # Overlap: Topic, A:, design, the, API → high similarity > 0.3

    def test_window_boundary_behavior(self):
        detector = SemanticLoopDetector(threshold=0.3, window_size=2)
        detector.add("alpha beta gamma")
        detector.add("delta epsilon zeta")
        # window only has [alpha beta gamma, delta epsilon zeta]
        # Adding a third item pushes "alpha beta gamma" out of the deque
        detector.add("eta theta iota")
        # Now window has [delta epsilon zeta, eta theta iota]
        # Check against "alpha beta gamma" — should no longer match (different words)
        assert not detector.is_looping("alpha beta gamma")


# ---------------------------------------------------------------------------
# Jaccard similarity
# ---------------------------------------------------------------------------


class TestJaccard:
    def test_perfect_match(self):
        sim = SemanticLoopDetector._jaccard_similarity(
            {"a", "b", "c"}, {"a", "b", "c"}
        )
        assert sim == 1.0

    def test_no_overlap(self):
        sim = SemanticLoopDetector._jaccard_similarity(
            {"a", "b"}, {"c", "d"}
        )
        assert sim == 0.0

    def test_partial_overlap(self):
        sim = SemanticLoopDetector._jaccard_similarity(
            {"a", "b", "c"}, {"b", "c", "d"}
        )
        # intersection = {b, c} size 2
        # union = {a, b, c, d} size 4
        # similarity = 2/4 = 0.5
        assert sim == 0.5

    def test_both_empty(self):
        sim = SemanticLoopDetector._jaccard_similarity(set(), set())
        assert sim == 1.0

    def test_one_empty(self):
        sim = SemanticLoopDetector._jaccard_similarity({"a"}, set())
        # intersection 0, union 1 → 0.0
        assert sim == 0.0


# ---------------------------------------------------------------------------
# Tokenization
# ---------------------------------------------------------------------------


class TestTokenization:
    def test_lowercases(self):
        tokens = SemanticLoopDetector._tokenize("Hello WORLD")
        assert tokens == {"hello", "world"}

    def test_splits_on_whitespace(self):
        tokens = SemanticLoopDetector._tokenize("a   b\tc\nd")
        assert tokens == {"a", "b", "c", "d"}

    def test_punctuation_included_in_tokens(self):
        tokens = SemanticLoopDetector._tokenize("hello!")
        # "!" is attached to "hello!" since split() splits on whitespace
        assert tokens == {"hello!"}

    def test_empty_string(self):
        tokens = SemanticLoopDetector._tokenize("")
        assert tokens == set()


# ---------------------------------------------------------------------------
# add behavior
# ---------------------------------------------------------------------------


class TestAdd:
    def test_add_stores_item(self):
        detector = SemanticLoopDetector(window_size=3)
        detector.add("hello")
        detector.add("world")
        assert len(detector._history) == 2

    def test_windows_trims_oldest(self):
        detector = SemanticLoopDetector(window_size=2)
        detector.add("a")
        detector.add("b")
        detector.add("c")  # pushes "a" out
        assert len(detector._history) == 2
        # deque contents should be ["b", "c"]
        assert detector._history[0] == "b"
        assert detector._history[1] == "c"


# ---------------------------------------------------------------------------
# Cosine similarity
# ---------------------------------------------------------------------------


class TestCosineSimilarity:
    def test_identical_vectors(self):
        sim = SemanticLoopDetector._cosine_similarity(
            [1.0, 2.0, 3.0], [1.0, 2.0, 3.0]
        )
        assert sim == pytest.approx(1.0)

    def test_orthogonal_vectors(self):
        sim = SemanticLoopDetector._cosine_similarity(
            [1.0, 0.0], [0.0, 1.0]
        )
        assert sim == pytest.approx(0.0)

    def test_opposite_vectors(self):
        sim = SemanticLoopDetector._cosine_similarity(
            [1.0, 0.0], [-1.0, 0.0]
        )
        assert sim == pytest.approx(-1.0)

    def test_zero_vector(self):
        sim = SemanticLoopDetector._cosine_similarity(
            [0.0, 0.0], [1.0, 2.0]
        )
        assert sim == 0.0


# ---------------------------------------------------------------------------
# check_with_embedding (sync simulation)
# ---------------------------------------------------------------------------


class TestCheckWithEmbedding:
    @pytest.mark.asyncio
    async def test_returns_false_for_empty_history(self):
        detector = SemanticLoopDetector(threshold=0.9)

        async def get_embedding(text: str) -> list[float]:
            return [1.0, 0.0]

        result = await detector.check_with_embedding("new text", get_embedding)
        assert result is False

    @pytest.mark.asyncio
    async def test_detects_similar_embeddings(self):
        detector = SemanticLoopDetector(threshold=0.9)
        detector.add("some content")

        async def get_embedding(text: str) -> list[float]:
            # Always return the same vector → cosine similarity = 1.0
            return [1.0, 2.0, 3.0]

        result = await detector.check_with_embedding("similar content", get_embedding)
        assert result is True

    @pytest.mark.asyncio
    async def test_passes_dissimilar_embeddings(self):
        detector = SemanticLoopDetector(threshold=0.9)
        detector.add("some content")

        call_count = 0

        async def get_embedding(text: str) -> list[float]:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return [1.0, 0.0, 0.0]  # new text embedding
            else:
                return [0.0, 1.0, 0.0]  # stored text embedding (orthogonal)

        result = await detector.check_with_embedding("different", get_embedding)
        assert result is False


# ---------------------------------------------------------------------------
# Integration: full flow
# ---------------------------------------------------------------------------


class TestIntegration:
    def test_sequential_rounds_no_loop(self):
        detector = SemanticLoopDetector(threshold=0.9)
        detector.add("def rate_limiter_v1(): ...")
        detector.add("def rate_limiter_v2(): ...")
        assert not detector.is_looping("def rate_limiter_v3(): ...")
        # All three are fairly similar but short enough to test.

    def test_sequential_rounds_with_loop(self):
        detector = SemanticLoopDetector(threshold=0.3)
        detector.add("Fix the bug in authentication module")
        detector.add("The authentication bug needs fixing")
        # Very similar — both about authentication bug fix
        assert detector.is_looping("Fix the bug in authentication module again")
