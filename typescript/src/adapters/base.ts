/**
 * Options that can be passed to the adapter's generate methods.
 * Extensible — providers may accept additional keys.
 */
export interface GenerateOptions {
  /** Sampling temperature (typically 0.0–2.0). */
  temperature?: number;
  /** Maximum tokens to generate. */
  maxTokens?: number;
  /** Allow provider-specific extensions. */
  [key: string]: unknown;
}

/**
 * Abstract base class for LLM adapters.
 *
 * Implementations handle provider-specific API calls so that the
 * orchestrator can remain provider-agnostic.
 */
export abstract class BaseAdapter {
  /**
   * Human-readable identifier for the model being used
   * (e.g. "claude-sonnet-4-6", "gpt-4o").
   */
  abstract get modelName(): string;

  /**
   * Generate free-form text from the model.
   *
   * @param systemPrompt - The system-level instruction.
   * @param userPrompt - The user-level message / task description.
   * @param options - Optional generation parameters.
   * @returns The model's text response.
   */
  abstract generate(
    systemPrompt: string,
    userPrompt: string,
    options?: GenerateOptions,
  ): Promise<string>;

  /**
   * Generate structured (typed) output from the model.
   *
   * @param systemPrompt - The system-level instruction.
   * @param userPrompt - The user-level message.
   * @param outputSchema - A JSON Schema object describing the desired output shape.
   * @param options - Optional generation parameters.
   * @returns A parsed object matching the schema type T.
   */
  abstract generateStructured<T>(
    systemPrompt: string,
    userPrompt: string,
    outputSchema: Record<string, unknown>,
    options?: GenerateOptions,
  ): Promise<T>;
}
