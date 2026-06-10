/**
 * Semantic loop detector that tracks generation history and detects
 * when the agents are repeating themselves without making progress.
 *
 * Uses two similarity strategies:
 * 1. Jaccard similarity (word-overlap) — fast, no external API needed.
 * 2. Cosine similarity over embeddings — more accurate, requires an embedding provider.
 */
export class SemanticLoopDetector {
  private history: string[] = [];
  private threshold: number;
  private windowSize: number;

  /**
   * @param threshold - Similarity score above which two texts are considered a loop (default 0.92).
   * @param windowSize - How many recent items to compare against (default 3).
   */
  constructor(threshold: number = 0.92, windowSize: number = 3) {
    this.threshold = threshold;
    this.windowSize = windowSize;
  }

  /**
   * Record a text in the history buffer.
   * Automatically prunes old entries beyond `windowSize * 2` to bound memory usage.
   */
  add(text: string): void {
    this.history.push(text);
    // Keep only recent history to bound memory
    if (this.history.length > this.windowSize * 2) {
      this.history = this.history.slice(-this.windowSize * 2);
    }
  }

  /**
   * Check whether `newText` is semantically too similar to any recent entry
   * using Jaccard (word-overlap) similarity.
   *
   * @returns true if a loop is detected.
   */
  isLooping(newText: string): boolean {
    const recentHistory = this.history.slice(-this.windowSize);
    for (const prev of recentHistory) {
      if (this.jaccardSimilarity(prev, newText) > this.threshold) {
        return true;
      }
    }
    return false;
  }

  /**
   * Check whether `newText` is semantically too similar to any recent entry
   * using cosine similarity over embeddings. More accurate but requires an
   * async embedding provider.
   *
   * @param newText - The new text to check.
   * @param getEmbedding - Async function that returns an embedding vector for a given text.
   * @returns true if a loop is detected.
   */
  async isLoopingWithEmbedding(
    newText: string,
    getEmbedding: (text: string) => Promise<number[]>,
  ): Promise<boolean> {
    const recentHistory = this.history.slice(-this.windowSize);
    if (recentHistory.length === 0) return false;

    const newEmb = await getEmbedding(newText);
    for (const prev of recentHistory) {
      const prevEmb = await getEmbedding(prev);
      if (this.cosineSimilarity(newEmb, prevEmb) > this.threshold) {
        return true;
      }
    }
    return false;
  }

  /**
   * Compute Jaccard similarity between two strings at the word level.
   * Ranges from 0 (no overlap) to 1 (identical word sets).
   */
  private jaccardSimilarity(a: string, b: string): number {
    const wordsA = new Set(a.toLowerCase().split(/\s+/));
    const wordsB = new Set(b.toLowerCase().split(/\s+/));
    const intersection = new Set([...wordsA].filter((x) => wordsB.has(x)));
    const union = new Set([...wordsA, ...wordsB]);
    if (union.size === 0) return 0;
    return intersection.size / union.size;
  }

  /**
   * Compute cosine similarity between two embedding vectors.
   * Ranges from -1 (opposite) to 1 (identical direction).
   */
  private cosineSimilarity(a: number[], b: number[]): number {
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    const denom = Math.sqrt(normA) * Math.sqrt(normB);
    if (denom === 0) return 0;
    return dot / denom;
  }

  /**
   * Clear the entire history buffer.
   */
  reset(): void {
    this.history = [];
  }

  /**
   * Return the current number of entries in the history buffer.
   */
  get size(): number {
    return this.history.length;
  }
}
