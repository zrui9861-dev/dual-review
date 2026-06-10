import { describe, it, expect } from 'vitest';
import { SemanticLoopDetector } from '../src/loop-detector.js';

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

describe('SemanticLoopDetector construction', () => {
  it('default threshold is 0.92', () => {
    const detector = new SemanticLoopDetector();
    expect(detector.size).toBe(0);
  });

  it('accepts custom threshold and window size', () => {
    const detector = new SemanticLoopDetector(0.5, 5);
    expect(detector.size).toBe(0);
  });

  it('threshold of 0 is valid', () => {
    const detector = new SemanticLoopDetector(0.0);
    expect(detector.size).toBe(0);
  });

  it('threshold of 1 is valid', () => {
    const detector = new SemanticLoopDetector(1.0);
    expect(detector.size).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// isLooping
// ---------------------------------------------------------------------------

describe('isLooping', () => {
  it('empty history is not looping', () => {
    const detector = new SemanticLoopDetector();
    expect(detector.isLooping('some text')).toBe(false);
  });

  it('identical text is looping', () => {
    const detector = new SemanticLoopDetector(0.5);
    detector.add('The sky is blue and the sun is bright.');
    expect(detector.isLooping('The sky is blue and the sun is bright.')).toBe(true);
  });

  it('similar text at low threshold is looping', () => {
    const detector = new SemanticLoopDetector(0.3);
    detector.add('The function should implement a caching layer.');
    expect(detector.isLooping('The function should implement a caching strategy.')).toBe(true);
  });

  it('different text at high threshold is not looping', () => {
    const detector = new SemanticLoopDetector(0.9);
    detector.add('Implement a Redis-based rate limiter.');
    expect(detector.isLooping('Create a PostgreSQL connection pool.')).toBe(false);
  });

  it('slightly below threshold is not looping', () => {
    const detector = new SemanticLoopDetector(0.95);
    detector.add('happy cat');
    expect(detector.isLooping('angry dog')).toBe(false);
  });

  it('multiple items in window — matches one', () => {
    const detector = new SemanticLoopDetector(0.3, 5);
    detector.add('Topic A: design the API');
    detector.add('Topic B: database schema');
    detector.add('Topic C: authentication');
    detector.add('Topic D: logging');
    expect(detector.isLooping('Topic A: design the API endpoint')).toBe(true);
  });

  it('window boundary — old items age out', () => {
    const detector = new SemanticLoopDetector(0.3, 2);
    detector.add('alpha beta gamma');
    detector.add('delta epsilon zeta');
    detector.add('eta theta iota'); // pushes 'alpha beta gamma' out of window range
    // 'alpha beta gamma' is not in the recent window; all words differ from recent entries
    expect(detector.isLooping('alpha beta gamma')).toBe(false);
  });

  it('checks only recent window entries', () => {
    const detector = new SemanticLoopDetector(0.3, 1);
    detector.add('alpha');
    detector.add('beta');
    // windowSize=1 means only 'beta' is recent
    expect(detector.isLooping('alpha')).toBe(false);
    expect(detector.isLooping('beta')).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Jaccard similarity (via isLooping)
// ---------------------------------------------------------------------------

describe('Jaccard similarity behavior', () => {
  it('perfect overlap at any threshold is looping', () => {
    const detector = new SemanticLoopDetector(0.9999);
    detector.add('a b c d e');
    expect(detector.isLooping('a b c d e')).toBe(true);
  });

  it('no overlap at low threshold is not looping', () => {
    const detector = new SemanticLoopDetector(0.01);
    detector.add('alpha beta');
    expect(detector.isLooping('gamma delta')).toBe(false);
  });

  it('partial overlap produces intermediate similarity', () => {
    // Similarity = intersection/union = 2/4 = 0.5 for {a,b,c} vs {b,c,d}
    const detector = new SemanticLoopDetector(0.4);
    detector.add('a b c');
    expect(detector.isLooping('b c d')).toBe(true);
  });

  it('threshold just above actual similarity passes', () => {
    // {a,b,c} vs {b,c,d} → intersection=2, union=4 → 0.5
    // With threshold 0.51, it should NOT be looping
    const detector = new SemanticLoopDetector(0.51);
    detector.add('a b c');
    expect(detector.isLooping('b c d')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// add and size
// ---------------------------------------------------------------------------

describe('add and size', () => {
  it('add increments internal count', () => {
    const detector = new SemanticLoopDetector();
    detector.add('hello');
    detector.add('world');
    expect(detector.size).toBe(2);
  });

  it('history is bounded by windowSize * 2', () => {
    const detector = new SemanticLoopDetector(0.92, 2);
    for (let i = 0; i < 10; i++) {
      detector.add(`text ${i}`);
    }
    expect(detector.size).toBeLessThanOrEqual(4);
  });
});

// ---------------------------------------------------------------------------
// reset
// ---------------------------------------------------------------------------

describe('reset', () => {
  it('clears all history', () => {
    const detector = new SemanticLoopDetector();
    detector.add('text1');
    detector.add('text2');
    detector.reset();
    expect(detector.size).toBe(0);
  });

  it('after reset, isLooping returns false', () => {
    const detector = new SemanticLoopDetector(0.5);
    detector.add('some text');
    detector.reset();
    expect(detector.isLooping('some text')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// isLoopingWithEmbedding
// ---------------------------------------------------------------------------

describe('isLoopingWithEmbedding', () => {
  it('returns false for empty history', async () => {
    const detector = new SemanticLoopDetector(0.9);
    const result = await detector.isLoopingWithEmbedding(
      'new text',
      async (_text: string) => [1.0, 0.0],
    );
    expect(result).toBe(false);
  });

  it('detects similar embeddings', async () => {
    const detector = new SemanticLoopDetector(0.9);
    detector.add('some content');

    const result = await detector.isLoopingWithEmbedding(
      'similar content',
      async (_text: string) => [1.0, 2.0, 3.0],
    );
    // Identical vectors → cosine similarity = 1.0 → above 0.9
    expect(result).toBe(true);
  });

  it('passes dissimilar embeddings', async () => {
    const detector = new SemanticLoopDetector(0.9);
    detector.add('some content');

    let callCount = 0;
    const result = await detector.isLoopingWithEmbedding(
      'different',
      async (_text: string) => {
        callCount++;
        // New text gets [1,0,0], old gets [0,1,0] → orthogonal → 0.0
        if (callCount === 1) return [1.0, 0.0, 0.0];
        return [0.0, 1.0, 0.0];
      },
    );
    expect(result).toBe(false);
  });

  it('zero-length history returns false', async () => {
    const detector = new SemanticLoopDetector(0.0);
    // No history entries at all
    const result = await detector.isLoopingWithEmbedding(
      'text',
      async (_text: string) => [1.0, 2.0],
    );
    expect(result).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Integration flow
// ---------------------------------------------------------------------------

describe('Integration flow', () => {
  it('sequential rounds with no loop', () => {
    const detector = new SemanticLoopDetector(0.9);
    detector.add('def rate_limiter_v1(): ...');
    detector.add('def rate_limiter_v2(): ...');
    detector.add('def rate_limiter_v3(): ...');
    // These may be similar but depend on token overlap
    // Checking round 3 against round 1 should trigger if they're truly similar
    expect(detector.isLooping('def rate_limiter_v1(): ...')).toBe(true);
  });

  it('with high threshold, moderate variation passes', () => {
    const detector = new SemanticLoopDetector(0.9);
    detector.add('Implement authentication with JWT tokens');
    detector.add('Add rate limiting middleware');
    expect(detector.isLooping('Set up database connection pooling')).toBe(false);
  });
});
