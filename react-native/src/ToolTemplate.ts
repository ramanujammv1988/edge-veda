/**
 * Model-specific tool prompt formatting and tool call parsing
 *
 * ToolTemplate provides methods to:
 * - Format tool definitions into model-specific system prompts
 * - Parse tool calls from model output
 * - Detect potential tool calls in streaming output
 *
 * Supports Qwen3 (Hermes-style XML) and Gemma3 (JSON-style) formats.
 * ChatTemplate handles message role formatting; ToolTemplate handles
 * tool definition injection and tool call extraction.
 */

import { ToolDefinition, ToolCall } from './ToolRegistry';

/**
 * Tool template formats for different model families
 */
export enum ToolTemplateFormat {
  /** Qwen3/Hermes-style XML format with <tool_call> tags */
  QWEN3 = 'qwen3',

  /** Gemma3/FunctionGemma JSON format */
  GEMMA3 = 'gemma3',

  /** Generic format (tries both Qwen3 and Gemma3 parsing) */
  GENERIC = 'generic',
}

/**
 * Formats tool definitions for model prompts and parses tool calls
 * from model output.
 *
 * This class bridges between developer ToolDefinition objects and
 * model-specific prompt formats. It does NOT format conversation messages
 * (that is ChatTemplate's job). Instead, it builds the tool-aware
 * system prompt that gets passed to ChatTemplate.formatMessages.
 *
 * @example
 * ```typescript
 * const toolPrompt = ToolTemplate.formatToolSystemPrompt(
 *   ToolTemplateFormat.QWEN3,
 *   [weatherTool, searchTool],
 *   'You are a helpful assistant.'
 * );
 * // Pass as system message to ChatTemplate.formatMessages()
 * ```
 */
export class ToolTemplate {
  /**
   * Format tool definitions into a model-specific system prompt.
   *
   * - ToolTemplateFormat.QWEN3: Hermes-style XML with <tools> tags
   * - ToolTemplateFormat.GEMMA3: JSON array of tool definitions
   * - ToolTemplateFormat.GENERIC: Returns systemPrompt only (tools not supported)
   */
  static formatToolSystemPrompt(
    format: ToolTemplateFormat,
    tools: ToolDefinition[],
    systemPrompt?: string
  ): string {
    switch (format) {
      case ToolTemplateFormat.QWEN3:
        return this._formatQwen3ToolPrompt(tools, systemPrompt);
      case ToolTemplateFormat.GEMMA3:
        return this._formatGemma3ToolPrompt(tools, systemPrompt);
      case ToolTemplateFormat.GENERIC:
        // Tools not natively supported by generic format
        return systemPrompt ?? '';
    }
  }

  /**
   * Parse tool calls from model output.
   *
   * - ToolTemplateFormat.QWEN3: Looks for <tool_call> XML tags
   * - ToolTemplateFormat.GEMMA3: Parses JSON object with name field
   * - ToolTemplateFormat.GENERIC: Tries Qwen3 parsing first, then Gemma3 as fallback
   *
   * Malformed entries are silently skipped. If all entries are malformed,
   * returns null.
   */
  static parseToolCalls(
    format: ToolTemplateFormat,
    output: string
  ): ToolCall[] | null {
    switch (format) {
      case ToolTemplateFormat.QWEN3:
        return this._parseQwen3ToolCalls(output);
      case ToolTemplateFormat.GEMMA3:
        return this._parseGemma3ToolCalls(output);
      case ToolTemplateFormat.GENERIC:
        // Try Qwen3 (most common) first, then Gemma3 as fallback
        return this._parseQwen3ToolCalls(output) ?? this._parseGemma3ToolCalls(output);
    }
  }

  /**
   * Quick check whether output looks like it contains a tool call.
   *
   * This is a lightweight heuristic for streaming use -- it does NOT
   * validate the content. Use parseToolCalls for actual extraction.
   */
  static looksLikeToolCall(
    format: ToolTemplateFormat,
    output: string
  ): boolean {
    switch (format) {
      case ToolTemplateFormat.QWEN3:
        return output.includes('<tool_call>');
      case ToolTemplateFormat.GEMMA3: {
        const trimmed = output.trimStart();
        return trimmed.startsWith('{') && trimmed.includes('"name"');
      }
      case ToolTemplateFormat.GENERIC:
        if (output.includes('<tool_call>')) return true;
        const trimmedGeneric = output.trimStart();
        return trimmedGeneric.startsWith('{') && trimmedGeneric.includes('"name"');
    }
  }

  // ---------------------------------------------------------------------------
  // Qwen3 / Hermes-style formatting
  // ---------------------------------------------------------------------------

  private static _formatQwen3ToolPrompt(
    tools: ToolDefinition[],
    systemPrompt?: string
  ): string {
    const lines: string[] = [];

    lines.push('# Tools');
    lines.push('');
    lines.push('You may call one or more functions to assist with the user query.');
    lines.push('');
    lines.push('You are provided with function signatures within <tools></tools> XML tags:');
    lines.push('<tools>');
    for (const tool of tools) {
      lines.push(JSON.stringify(tool.toFunctionJson()));
    }
    lines.push('</tools>');
    lines.push('');
    lines.push('For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:');
    lines.push('<tool_call>');
    lines.push('{"name": <function-name>, "arguments": <args-json-object>}');
    lines.push('</tool_call>');

    if (systemPrompt && systemPrompt.length > 0) {
      lines.push('');
      lines.push('');
      lines.push(systemPrompt);
    }

    return lines.join('\n');
  }

  private static _parseQwen3ToolCalls(output: string): ToolCall[] | null {
    const regex = /<tool_call>\s*(.*?)\s*<\/tool_call>/gs;
    const matches = Array.from(output.matchAll(regex));

    if (matches.length === 0) return null;

    const calls: ToolCall[] = [];
    for (const match of matches) {
      try {
        const json = JSON.parse(match[1]) as Record<string, any>;
        const name = json.name as string;
        const args = json.arguments as Record<string, any>;
        calls.push(new ToolCall({ name, arguments: args }));
      } catch (_) {
        // Malformed tool call -- skip silently
      }
    }

    return calls.length > 0 ? calls : null;
  }

  // ---------------------------------------------------------------------------
  // Gemma3 / JSON-style formatting
  // ---------------------------------------------------------------------------

  private static _formatGemma3ToolPrompt(
    tools: ToolDefinition[],
    systemPrompt?: string
  ): string {
    const lines: string[] = [];

    const toolJsonList = tools.map(t => t.toToolJson());
    lines.push('You are a helpful assistant with access to the following tools:');
    lines.push(JSON.stringify(toolJsonList));
    lines.push('');
    lines.push('If you decide to invoke any function(s), you MUST put it in the format of:');
    lines.push('{"name": function_name, "parameters": {"param_name": "value"}}');
    lines.push('You SHOULD NOT include any other text if you call a function.');

    if (systemPrompt && systemPrompt.length > 0) {
      lines.push('');
      lines.push('');
      lines.push(systemPrompt);
    }

    return lines.join('\n');
  }

  private static _parseGemma3ToolCalls(output: string): ToolCall[] | null {
    try {
      const json = JSON.parse(output.trim()) as Record<string, any>;
      if (typeof json === 'object' && json !== null && 'name' in json) {
        const name = json.name as string;
        const args = (json.parameters ?? json.arguments) as Record<string, any>;
        return [new ToolCall({ name, arguments: args })];
      }
    } catch (_) {
      // Not valid JSON or wrong structure -- return null
    }
    return null;
  }
}
