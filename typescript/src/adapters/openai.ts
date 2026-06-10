import OpenAI from 'openai';
import { BaseAdapter, GenerateOptions } from './base.js';

/**
 * Adapter for OpenAI's chat models (GPT-4o, GPT-4.1, etc.).
 *
 * Uses the `openai` SDK client. Structured output is achieved via
 * OpenAI's `response_format` with `json_schema` mode, which guarantees
 * the model produces JSON conforming to the provided schema.
 */
export class OpenAIAdapter extends BaseAdapter {
  private client: OpenAI;
  private _model: string;
  private defaultOptions: GenerateOptions;

  /**
   * @param model - OpenAI model ID (default `'gpt-4o'`).
   * @param apiKey - OpenAI API key. Falls back to `OPENAI_API_KEY` env var.
   * @param options - Default generation options applied to every call.
   */
  constructor(
    model: string = 'gpt-4o',
    apiKey?: string,
    options?: GenerateOptions,
  ) {
    super();
    this._model = model;
    this.client = new OpenAI({ apiKey: apiKey ?? process.env['OPENAI_API_KEY'] });
    this.defaultOptions = options ?? {};
  }

  /** The model identifier used for API calls. */
  get modelName(): string {
    return this._model;
  }

  /**
   * Generate free-form text.
   *
   * @param systemPrompt - System-level instruction.
   * @param userPrompt - User message.
   * @param options - Per-call overrides merged over constructor defaults.
   * @returns The text content of the assistant's response.
   */
  async generate(
    systemPrompt: string,
    userPrompt: string,
    options?: GenerateOptions,
  ): Promise<string> {
    const merged = { ...this.defaultOptions, ...options };
    const response = await this.client.chat.completions.create({
      model: this._model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: merged.maxTokens,
      temperature: merged.temperature,
    });

    return response.choices[0]?.message?.content ?? '';
  }

  /**
   * Generate structured (typed) output using OpenAI's `json_schema` response format.
   *
   * The model is constrained to produce a JSON object matching the provided schema.
   * The result is parsed with a simple `JSON.parse` helper.
   *
   * @typeParam T - The expected output type.
   * @param systemPrompt - System-level instruction.
   * @param userPrompt - User message.
   * @param outputSchema - JSON Schema object describing the desired output shape.
   * @param options - Per-call overrides.
   * @returns A parsed object of type T.
   */
  async generateStructured<T>(
    systemPrompt: string,
    userPrompt: string,
    outputSchema: Record<string, unknown>,
    options?: GenerateOptions,
  ): Promise<T> {
    const merged = { ...this.defaultOptions, ...options };

    const response = await this.client.chat.completions.create({
      model: this._model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt },
      ],
      max_tokens: merged.maxTokens,
      temperature: merged.temperature,
      response_format: {
        type: 'json_schema',
        json_schema: {
          name: 'output',
          strict: true,
          schema: outputSchema as Record<string, unknown>,
        },
      },
    });

    const raw = response.choices[0]?.message?.content ?? '{}';
    return this.parse<T>(raw);
  }

  /**
   * Safely parse a JSON string into type T.
   * Logs a warning and returns an empty object on parse failure.
   */
  private parse<T>(raw: string): T {
    try {
      return JSON.parse(raw) as T;
    } catch {
      console.warn('OpenAIAdapter: failed to parse structured output, returning empty object');
      return {} as T;
    }
  }
}
