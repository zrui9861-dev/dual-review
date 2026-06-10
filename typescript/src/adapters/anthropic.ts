import Anthropic from '@anthropic-ai/sdk';
import { BaseAdapter, GenerateOptions } from './base.js';

/**
 * Adapter for Anthropic's Claude models.
 *
 * Uses the `@anthropic-ai/sdk` client. Structured output is achieved via
 * Anthropic's tool-use mechanism: a single tool is defined whose
 * `input_schema` matches the desired output schema, and `tool_choice`
 * forces the model to call that tool.
 */
export class AnthropicAdapter extends BaseAdapter {
  private client: Anthropic;
  private _model: string;
  private defaultOptions: GenerateOptions;

  /**
   * @param model - Anthropic model ID (default `'claude-sonnet-4-6'`).
   * @param apiKey - Anthropic API key. Falls back to `ANTHROPIC_API_KEY` env var.
   * @param options - Default generation options applied to every call.
   */
  constructor(
    model: string = 'claude-sonnet-4-6',
    apiKey?: string,
    options?: GenerateOptions,
  ) {
    super();
    this._model = model;
    this.client = new Anthropic({ apiKey: apiKey ?? process.env['ANTHROPIC_API_KEY'] });
    this.defaultOptions = options ?? {};
  }

  /** The model identifier used for API calls. */
  get modelName(): string {
    return this._model;
  }

  /**
   * Generate free-form text.
   *
   * @param systemPrompt - System-level instruction (passed as the `system` param).
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
    const response = await this.client.messages.create({
      model: this._model,
      system: systemPrompt,
      max_tokens: merged.maxTokens ?? 4096,
      temperature: merged.temperature,
      messages: [
        {
          role: 'user',
          content: userPrompt,
        },
      ],
    });

    // Return the first text block content
    const textBlock = response.content.find((block) => block.type === 'text');
    return textBlock && 'text' in textBlock ? textBlock.text : '';
  }

  /**
   * Generate structured (typed) output using Anthropic's tool-use pattern.
   *
   * The desired output schema is wrapped as a tool named `"output"`.
   * `tool_choice` is set to force the model to invoke that tool,
   * guaranteeing a JSON response matching the schema.
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

    const response = await this.client.messages.create({
      model: this._model,
      system: systemPrompt,
      max_tokens: merged.maxTokens ?? 4096,
      temperature: merged.temperature,
      tools: [
        {
          name: 'output',
          description: 'Output the structured result',
          input_schema: outputSchema as Anthropic.Tool.InputSchema,
        },
      ],
      tool_choice: { type: 'tool', name: 'output' },
      messages: [
        {
          role: 'user',
          content: userPrompt,
        },
      ],
    });

    // Extract the tool_use block that contains the structured output
    const toolBlock = response.content.find((block) => block.type === 'tool_use');
    if (!toolBlock || !('input' in toolBlock)) {
      throw new Error('AnthropicAdapter: no tool_use block returned from structured generation');
    }

    return toolBlock.input as T;
  }
}
