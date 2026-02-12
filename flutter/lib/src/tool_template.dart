/// Model-specific tool prompt formatting and tool call parsing
///
/// [ToolTemplate] provides static methods to:
/// - Format tool definitions into model-specific system prompts
/// - Parse tool calls from model output
/// - Detect potential tool calls in streaming output
///
/// Supports Qwen3 (Hermes-style XML) and Gemma3 (JSON-style) formats.
/// ChatTemplate handles message role formatting; ToolTemplate handles
/// tool definition injection and tool call extraction.
library;

import 'dart:convert';

import 'chat_template.dart';
import 'tool_types.dart';

/// Formats tool definitions for model prompts and parses tool calls
/// from model output.
///
/// This class bridges between developer [ToolDefinition] objects and
/// model-specific prompt formats. It does NOT format conversation messages
/// (that is [ChatTemplate]'s job). Instead, it builds the tool-aware
/// system prompt that gets passed to [ChatTemplate.format].
///
/// Example:
/// ```dart
/// final toolPrompt = ToolTemplate.formatToolSystemPrompt(
///   format: ChatTemplateFormat.qwen3,
///   tools: [weatherTool, searchTool],
///   systemPrompt: 'You are a helpful assistant.',
/// );
/// // toolPrompt contains Hermes-style tool definitions + system prompt
/// // Pass to ChatTemplate.format() as the systemPrompt parameter
/// ```
class ToolTemplate {
  /// Format tool definitions into a model-specific system prompt.
  ///
  /// Builds a system prompt string that includes tool definitions in the
  /// format expected by the target model family, plus an optional
  /// developer-provided [systemPrompt].
  ///
  /// - [ChatTemplateFormat.qwen3]: Hermes-style XML with `<tools>` tags
  /// - [ChatTemplateFormat.gemma3]: JSON array of tool definitions
  /// - Other formats: Returns [systemPrompt] only (tools not supported)
  ///
  /// The returned string should be passed as the `systemPrompt` parameter
  /// to [ChatTemplate.format].
  static String formatToolSystemPrompt({
    required ChatTemplateFormat format,
    required List<ToolDefinition> tools,
    String? systemPrompt,
  }) {
    switch (format) {
      case ChatTemplateFormat.qwen3:
        return _formatQwen3ToolPrompt(tools, systemPrompt);
      case ChatTemplateFormat.gemma3:
        return _formatGemma3ToolPrompt(tools, systemPrompt);
      case ChatTemplateFormat.llama3Instruct:
      case ChatTemplateFormat.chatML:
      case ChatTemplateFormat.generic:
        // Tools not natively supported by these formats
        return systemPrompt ?? '';
    }
  }

  /// Parse tool calls from model output.
  ///
  /// Extracts structured [ToolCall] objects from the raw model output
  /// string. Returns `null` if no valid tool calls are found.
  ///
  /// - [ChatTemplateFormat.qwen3]: Looks for `<tool_call>` XML tags
  /// - [ChatTemplateFormat.gemma3]: Parses JSON object with `name` field
  /// - Other formats: Tries Qwen3 parsing first, then Gemma3 as fallback
  ///
  /// Malformed entries are silently skipped. If all entries are malformed,
  /// returns `null`.
  static List<ToolCall>? parseToolCalls({
    required ChatTemplateFormat format,
    required String output,
  }) {
    switch (format) {
      case ChatTemplateFormat.qwen3:
        return _parseQwen3ToolCalls(output);
      case ChatTemplateFormat.gemma3:
        return _parseGemma3ToolCalls(output);
      case ChatTemplateFormat.llama3Instruct:
      case ChatTemplateFormat.chatML:
      case ChatTemplateFormat.generic:
        // Try Qwen3 (most common) first, then Gemma3 as fallback
        return _parseQwen3ToolCalls(output) ?? _parseGemma3ToolCalls(output);
    }
  }

  /// Quick check whether output looks like it contains a tool call.
  ///
  /// This is a lightweight heuristic for streaming use -- it does NOT
  /// validate the content. Use [parseToolCalls] for actual extraction.
  ///
  /// Useful for deciding whether to buffer streaming output instead of
  /// emitting tokens to the user.
  static bool looksLikeToolCall({
    required ChatTemplateFormat format,
    required String output,
  }) {
    switch (format) {
      case ChatTemplateFormat.qwen3:
        return output.contains('<tool_call>');
      case ChatTemplateFormat.gemma3:
        final trimmed = output.trimLeft();
        return trimmed.startsWith('{') && trimmed.contains('"name"');
      case ChatTemplateFormat.llama3Instruct:
      case ChatTemplateFormat.chatML:
      case ChatTemplateFormat.generic:
        // Check both formats
        if (output.contains('<tool_call>')) return true;
        final trimmed = output.trimLeft();
        return trimmed.startsWith('{') && trimmed.contains('"name"');
    }
  }

  // ---------------------------------------------------------------------------
  // Qwen3 / Hermes-style formatting
  // ---------------------------------------------------------------------------

  /// Build Hermes-style tool system prompt for Qwen3 models.
  ///
  /// Format:
  /// ```
  /// # Tools
  ///
  /// You may call one or more functions to assist with the user query.
  ///
  /// You are provided with function signatures within <tools></tools> XML tags:
  /// <tools>
  /// {"type": "function", "function": {"name": "...", ...}}
  /// </tools>
  ///
  /// For each function call, return a json object with function name and
  /// arguments within <tool_call></tool_call> XML tags:
  /// <tool_call>
  /// {"name": <function-name>, "arguments": <args-json-object>}
  /// </tool_call>
  /// ```
  static String _formatQwen3ToolPrompt(
    List<ToolDefinition> tools,
    String? systemPrompt,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('# Tools');
    buffer.writeln();
    buffer.writeln(
        'You may call one or more functions to assist with the user query.');
    buffer.writeln();
    buffer.writeln(
        'You are provided with function signatures within <tools></tools> XML tags:');
    buffer.writeln('<tools>');
    for (final tool in tools) {
      buffer.writeln(jsonEncode(tool.toFunctionJson()));
    }
    buffer.writeln('</tools>');
    buffer.writeln();
    buffer.writeln(
        'For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:');
    buffer.writeln('<tool_call>');
    buffer.writeln(
        '{"name": <function-name>, "arguments": <args-json-object>}');
    buffer.write('</tool_call>');

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln();
      buffer.writeln();
      buffer.write(systemPrompt);
    }

    return buffer.toString();
  }

  /// Parse Qwen3/Hermes-style `<tool_call>` XML tags from model output.
  static List<ToolCall>? _parseQwen3ToolCalls(String output) {
    final regex =
        RegExp(r'<tool_call>\s*(.*?)\s*</tool_call>', dotAll: true);
    final matches = regex.allMatches(output);

    if (matches.isEmpty) return null;

    final calls = <ToolCall>[];
    for (final match in matches) {
      try {
        final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
        final name = json['name'] as String;
        final arguments = json['arguments'] as Map<String, dynamic>;
        calls.add(ToolCall(name: name, arguments: arguments));
      } catch (_) {
        // Malformed tool call -- skip silently
      }
    }

    return calls.isEmpty ? null : calls;
  }

  // ---------------------------------------------------------------------------
  // Gemma3 / JSON-style formatting
  // ---------------------------------------------------------------------------

  /// Build JSON-style tool prompt for Gemma3 models.
  ///
  /// Format:
  /// ```
  /// You are a helpful assistant with access to the following tools:
  /// [{"name": "...", "description": "...", "parameters": {...}}]
  ///
  /// If you decide to invoke any function(s), you MUST put it in the format of:
  /// {"name": function_name, "parameters": {"param_name": "value"}}
  /// You SHOULD NOT include any other text if you call a function.
  /// ```
  static String _formatGemma3ToolPrompt(
    List<ToolDefinition> tools,
    String? systemPrompt,
  ) {
    final buffer = StringBuffer();

    final toolJsonList = tools.map((t) => t.toToolJson()).toList();
    buffer.writeln(
        'You are a helpful assistant with access to the following tools:');
    buffer.writeln(jsonEncode(toolJsonList));
    buffer.writeln();
    buffer.writeln(
        'If you decide to invoke any function(s), you MUST put it in the format of:');
    buffer.writeln(
        '{"name": function_name, "parameters": {"param_name": "value"}}');
    buffer.write(
        'You SHOULD NOT include any other text if you call a function.');

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln();
      buffer.writeln();
      buffer.write(systemPrompt);
    }

    return buffer.toString();
  }

  /// Parse Gemma3 JSON-style tool call from model output.
  static List<ToolCall>? _parseGemma3ToolCalls(String output) {
    try {
      final json = jsonDecode(output.trim());
      if (json is Map<String, dynamic> && json.containsKey('name')) {
        final name = json['name'] as String;
        final arguments =
            (json['parameters'] ?? json['arguments']) as Map<String, dynamic>;
        return [ToolCall(name: name, arguments: arguments)];
      }
    } catch (_) {
      // Not valid JSON or wrong structure -- return null
    }
    return null;
  }
}
