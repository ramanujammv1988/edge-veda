import EdgeVedaInstance from './EdgeVeda';
import { ChatMessage, ChatRole, SystemPromptPreset, getSystemPrompt } from './ChatTypes';
import { ChatTemplate, formatMessages } from './ChatTemplate';
import { ToolRegistry, ToolDefinition, ToolCall, ToolResult } from './ToolRegistry';
import { ToolTemplate, ToolTemplateFormat } from './ToolTemplate';
import { GbnfBuilder } from './GbnfBuilder';
import { SchemaValidator } from './SchemaValidator';
import { CancelToken, GenerateOptions, GenerationError, TokenCallback } from './types';

/**
 * EdgeVeda SDK instance type
 */
type EdgeVeda = typeof EdgeVedaInstance;

/**
 * Manages a multi-turn chat conversation with context tracking.
 *
 * ChatSession wraps an EdgeVeda instance and manages conversation history
 * automatically. Supports plain generation, tool calling, and structured
 * (grammar-constrained) JSON output. Mirrors Flutter SDK's ChatSession.
 *
 * Context overflow is handled by automatic summarization — when the
 * estimated token count exceeds 70% of the context window, older messages
 * are compressed into a summary to keep inference within budget.
 */
export class ChatSession {
  private edgeVeda: EdgeVeda;
  private messages: ChatMessage[] = [];
  private maxContextLength: number;
  private maxResponseTokens: number;
  private template: ChatTemplate;
  private systemPromptText: string | null;
  private _tools: ToolRegistry | null;
  private _toolFormat: ToolTemplateFormat;
  private _isSummarizing = false;

  /**
   * Creates a new chat session.
   *
   * @param edgeVeda - Initialized EdgeVeda instance
   * @param options.systemPrompt - Pre-configured system prompt preset
   * @param options.systemPromptText - Custom system prompt string (overrides preset)
   * @param options.maxContextLength - Context window size (default 2048)
   * @param options.maxResponseTokens - Tokens reserved for model reply (default 512)
   * @param options.template - Chat template format (default LLAMA3)
   * @param options.tools - ToolRegistry for function calling support
   * @param options.toolFormat - Tool call format (default derived from template)
   */
  constructor(
    edgeVeda: EdgeVeda,
    options: {
      systemPrompt?: SystemPromptPreset;
      systemPromptText?: string;
      maxContextLength?: number;
      maxResponseTokens?: number;
      template?: ChatTemplate;
      tools?: ToolRegistry;
      toolFormat?: ToolTemplateFormat;
    } = {}
  ) {
    this.edgeVeda = edgeVeda;
    this.maxContextLength = options.maxContextLength ?? 2048;
    this.maxResponseTokens = options.maxResponseTokens ?? 512;
    this.template = options.template ?? ChatTemplate.LLAMA3;
    this._tools = options.tools ?? null;
    this._toolFormat = options.toolFormat ?? this._deriveToolFormat();

    // Resolve system prompt: explicit string takes priority over preset
    if (options.systemPromptText) {
      this.systemPromptText = options.systemPromptText;
    } else if (options.systemPrompt) {
      this.systemPromptText = getSystemPrompt(options.systemPrompt);
    } else {
      this.systemPromptText = null;
    }

    if (this.systemPromptText) {
      this.messages.push({
        role: ChatRole.SYSTEM,
        content: this.systemPromptText,
        timestamp: new Date(),
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  /** Whether a context summarization is currently in progress */
  get isSummarizing(): boolean {
    return this._isSummarizing;
  }

  /** The tool registry for this session, or null if no tools registered */
  get toolRegistry(): ToolRegistry | null {
    return this._tools;
  }

  /** Number of user turns in the conversation */
  get turnCount(): number {
    return this.messages.filter((m) => m.role === ChatRole.USER).length;
  }

  /**
   * Estimated context window usage as a fraction (0.0 to 1.0+).
   *
   * Uses a rough heuristic of ~4 characters per token.
   * Values above 0.7 trigger automatic summarization on the next send().
   */
  get contextUsage(): number {
    const totalTokens = this.estimateTokens();
    return totalTokens / this.maxContextLength;
  }

  /** All messages in the conversation (read-only copy) */
  get allMessages(): ChatMessage[] {
    return [...this.messages];
  }

  /** Returns the last N messages in the conversation */
  lastMessages(count: number): ChatMessage[] {
    const startIndex = Math.max(0, this.messages.length - count);
    return this.messages.slice(startIndex);
  }

  // ---------------------------------------------------------------------------
  // Core send methods
  // ---------------------------------------------------------------------------

  /**
   * Sends a message and returns the complete response.
   *
   * Adds the user message to history, checks for context overflow
   * (triggering summarization if needed), generates a response, and
   * adds the assistant reply to history.
   *
   * On error, the user message is rolled back to keep conversation consistent.
   */
  async send(
    message: string,
    options?: GenerateOptions,
    cancelToken?: CancelToken
  ): Promise<string> {
    cancelToken?.throwIfCancelled();

    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });

    try {
      await this._summarizeIfNeeded(cancelToken);
      cancelToken?.throwIfCancelled();

      const prompt = this.formatPrompt();
      const responseText = await this.edgeVeda.generate(prompt, options);

      this.messages.push({
        role: ChatRole.ASSISTANT,
        content: responseText,
        timestamp: new Date(),
      });

      return responseText;
    } catch (e) {
      // Roll back user message on error
      if (
        this.messages.length > 0 &&
        this.messages[this.messages.length - 1].role === ChatRole.USER
      ) {
        this.messages.pop();
      }
      throw e;
    }
  }

  /**
   * Sends a message and streams the response token by token.
   *
   * On error, the user message is rolled back from history.
   */
  async sendStream(
    message: string,
    onToken: TokenCallback,
    options?: GenerateOptions,
    cancelToken?: CancelToken
  ): Promise<void> {
    cancelToken?.throwIfCancelled();

    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });

    try {
      await this._summarizeIfNeeded(cancelToken);
      cancelToken?.throwIfCancelled();

      const prompt = this.formatPrompt();
      let fullResponse = '';

      await this.edgeVeda.generateStream(
        prompt,
        (token, done) => {
          if (cancelToken?.isCancelled) return;
          fullResponse += token;
          onToken(token, done);

          if (done) {
            this.messages.push({
              role: ChatRole.ASSISTANT,
              content: fullResponse,
              timestamp: new Date(),
            });
          }
        },
        options
      );
    } catch (e) {
      // Roll back user message on error
      if (
        this.messages.length > 0 &&
        this.messages[this.messages.length - 1].role === ChatRole.USER
      ) {
        this.messages.pop();
      }
      throw e;
    }
  }

  // ---------------------------------------------------------------------------
  // Tool calling
  // ---------------------------------------------------------------------------

  /**
   * Send a message with tool calling support.
   *
   * If the model responds with a tool call, `onToolCall` is invoked.
   * The developer executes the tool and returns a ToolResult. The result
   * is injected back into the conversation for a follow-up generation.
   *
   * If the model responds with plain text (no tool call detected),
   * it is returned as a normal assistant message.
   *
   * @param message - User message text
   * @param onToolCall - Async callback invoked for each tool call
   * @param options - Generation options
   * @param cancelToken - Optional cancellation token
   * @param maxToolRounds - Max tool call iterations (default 3)
   * @returns Final assistant response text
   */
  async sendWithTools(
    message: string,
    onToolCall: (toolCall: ToolCall) => Promise<ToolResult>,
    options?: GenerateOptions,
    cancelToken?: CancelToken,
    maxToolRounds: number = 3
  ): Promise<string> {
    cancelToken?.throwIfCancelled();

    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });

    try {
      await this._summarizeIfNeeded(cancelToken);

      for (let round = 0; round < maxToolRounds; round++) {
        cancelToken?.throwIfCancelled();

        const prompt = this._formatConversationWithTools();
        const responseText = await this.edgeVeda.generate(prompt, options);

        // Check if the response contains a tool call
        const toolCalls = ToolTemplate.parseToolCalls(this._toolFormat, responseText);

        if (!toolCalls || toolCalls.length === 0) {
          // No tool call — plain assistant response
          this.messages.push({
            role: ChatRole.ASSISTANT,
            content: responseText,
            timestamp: new Date(),
          });
          return responseText;
        }

        // Process the first tool call (single-call per round)
        const toolCall = toolCalls[0];

        // Record the tool call in history
        this.messages.push({
          role: ChatRole.TOOL_CALL,
          content: JSON.stringify({ name: toolCall.name, arguments: toolCall.arguments }),
          timestamp: new Date(),
        });

        // Invoke the developer's handler
        const toolResult = await onToolCall(toolCall);

        // Record the tool result in history
        this.messages.push({
          role: ChatRole.TOOL_RESULT,
          content: toolResult.isError
            ? JSON.stringify({ error: toolResult.error })
            : JSON.stringify(toolResult.data),
          timestamp: new Date(),
        });
      }

      // Max rounds exhausted — generate a final response without tool parsing
      cancelToken?.throwIfCancelled();
      const finalPrompt = this._formatConversationWithTools();
      const finalText = await this.edgeVeda.generate(finalPrompt, options);

      this.messages.push({
        role: ChatRole.ASSISTANT,
        content: finalText,
        timestamp: new Date(),
      });

      return finalText;
    } catch (e) {
      // Roll back user message on error
      if (
        this.messages.length > 0 &&
        this.messages[this.messages.length - 1].role === ChatRole.USER
      ) {
        this.messages.pop();
      }
      throw e;
    }
  }

  // ---------------------------------------------------------------------------
  // Structured (grammar-constrained) generation
  // ---------------------------------------------------------------------------

  /**
   * Send a message and get a structured JSON response validated against a schema.
   *
   * Uses GBNF grammar-constrained decoding to guarantee the output is valid
   * JSON conforming to `schema`. The response is validated before delivery.
   *
   * @param message - User message text
   * @param schema - JSON Schema object the response must conform to
   * @param options - Generation options (grammarStr/grammarRoot will be set automatically)
   * @param cancelToken - Optional cancellation token
   * @returns Validated JSON object
   * @throws GenerationError if model output fails schema validation
   */
  async sendStructured(
    message: string,
    schema: Record<string, unknown>,
    options?: GenerateOptions,
    cancelToken?: CancelToken
  ): Promise<Record<string, unknown>> {
    // Generate GBNF grammar from the JSON schema
    const grammarStr = GbnfBuilder.fromJsonSchema(schema);

    // Merge grammar into generation options
    const grammarOptions: GenerateOptions = {
      ...options,
      grammarStr,
      grammarRoot: 'root',
    };

    // Delegate to send() for history management and rollback
    const responseText = await this.send(message, grammarOptions, cancelToken);

    // Parse JSON response
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(responseText) as Record<string, unknown>;
    } catch {
      throw new GenerationError(
        'Model output is not valid JSON',
        `Output: "${responseText.length > 200 ? responseText.substring(0, 200) + '...' : responseText}"`
      );
    }

    // Validate against schema
    const validation = SchemaValidator.validate(parsed, schema);
    if (!validation.isValid) {
      throw new GenerationError(
        'Model output failed schema validation',
        `Errors: ${validation.errors.join(', ')}`
      );
    }

    return parsed;
  }

  // ---------------------------------------------------------------------------
  // Session management
  // ---------------------------------------------------------------------------

  /**
   * Resets the conversation, keeping only the system prompt.
   */
  async reset(): Promise<void> {
    const systemMsg = this.messages.find((m) => m.role === ChatRole.SYSTEM);
    this.messages = systemMsg ? [systemMsg] : [];
    await this.edgeVeda.resetContext();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private formatPrompt(): string {
    return formatMessages(this.template, this.messages);
  }

  private _formatConversationWithTools(): string {
    if (!this._tools || this._tools.tools.length === 0) {
      return this.formatPrompt();
    }

    const toolSystemPrompt = ToolTemplate.formatToolSystemPrompt(
      this._toolFormat,
      this._tools.tools as ToolDefinition[],
      this.systemPromptText ?? undefined
    );

    const systemMsg: ChatMessage = {
      role: ChatRole.SYSTEM,
      content: toolSystemPrompt,
      timestamp: new Date(),
    };
    const nonSystemMessages = this.messages.filter((m) => m.role !== ChatRole.SYSTEM);
    return formatMessages(this.template, [systemMsg, ...nonSystemMessages]);
  }

  /**
   * Check if context window is getting full and summarize if needed.
   *
   * Triggers when estimated token usage exceeds 70% of available capacity.
   * Keeps the last 2 user turns and their replies intact; older messages
   * are summarized by the model. Falls back to simple truncation on error.
   */
  private async _summarizeIfNeeded(cancelToken?: CancelToken): Promise<void> {
    const formatted = this.formatPrompt();
    const estimatedTokens = Math.floor(formatted.length / 4);
    const availableTokens = this.maxContextLength - this.maxResponseTokens;

    if (estimatedTokens < availableTokens * 0.7) return;

    this._isSummarizing = true;
    try {
      // Find split point: keep last 2 user turns + their assistant replies
      let userCount = 0;
      let splitIndex = this.messages.length;
      for (let i = this.messages.length - 1; i >= 0; i--) {
        if (this.messages[i].role === ChatRole.USER) {
          userCount++;
        }
        if (userCount >= 2) {
          splitIndex = i;
          break;
        }
      }

      if (splitIndex <= 0) return;

      const oldMessages = this.messages.slice(0, splitIndex);
      const recentMessages = this.messages.slice(splitIndex);

      // Build summarization prompt
      let summaryPrompt = 'Summarize this conversation concisely. Keep key facts and decisions:\n';
      for (const msg of oldMessages) {
        if (msg.role === ChatRole.SUMMARY) {
          summaryPrompt += `summary: ${msg.content}\n`;
        } else {
          summaryPrompt += `${msg.role}: ${msg.content}\n`;
        }
      }

      cancelToken?.throwIfCancelled();

      // Generate summary with the model (low temperature for factual accuracy)
      const summaryText = await this.edgeVeda.generate(summaryPrompt, {
        maxTokens: 128,
        temperature: 0.3,
      });

      // Replace old messages with summary + recent messages
      this.messages = [
        {
          role: ChatRole.SUMMARY,
          content: summaryText,
          timestamp: new Date(),
        },
        ...recentMessages,
      ];
    } catch (_e) {
      // Fallback: simple truncation if summarization fails
      const targetTokens = Math.floor(
        (this.maxContextLength - this.maxResponseTokens) * 0.6
      );

      while (this.messages.length > 2) {
        const currentFormatted = this.formatPrompt();
        const currentTokens = Math.floor(currentFormatted.length / 4);
        if (currentTokens <= targetTokens) break;
        this.messages.splice(0, 1);
      }
    } finally {
      this._isSummarizing = false;
    }
  }

  private estimateTokens(): number {
    const totalChars = this.messages.reduce((sum, msg) => sum + msg.content.length, 0);
    return Math.floor(totalChars / 4);
  }

  private _deriveToolFormat(): ToolTemplateFormat {
    switch (this.template) {
      case ChatTemplate.QWEN3:
        return ToolTemplateFormat.QWEN3;
      case ChatTemplate.GEMMA3:
        return ToolTemplateFormat.GEMMA3;
      default:
        return ToolTemplateFormat.GENERIC;
    }
  }
}
