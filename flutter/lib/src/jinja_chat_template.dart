/// Dynamic Jinja2 chat template evaluator
///
/// Evaluates Jinja2 template strings extracted from GGUF model metadata.
/// Replaces hardcoded per-model template formatting with dynamic evaluation.
///
/// The template is compiled once at construction time and reused for all
/// format() calls. Uses HuggingFace-compatible Environment settings:
/// trimBlocks=true, leftStripBlocks=true.
library;

import 'package:jinja/jinja.dart';

import 'chat_types.dart';

/// Evaluates Jinja2 chat templates from GGUF model metadata.
///
/// Construct with the raw Jinja2 template string from GGUF metadata.
/// Call [format] to render a conversation into a model-specific prompt.
///
/// Example:
/// ```dart
/// final tmpl = JinjaChatTemplate(templateString);
/// final prompt = tmpl.format(
///   messages: [ChatMessage(role: ChatRole.user, content: 'Hi', timestamp: DateTime.now())],
///   systemPrompt: 'You are helpful.',
/// );
/// ```
class JinjaChatTemplate {
  /// The raw Jinja2 template string from GGUF metadata.
  final String templateString;

  final Template _compiled;

  /// Create a JinjaChatTemplate from a raw Jinja2 template string.
  ///
  /// The template is compiled immediately. Throws if the template
  /// has syntax errors.
  JinjaChatTemplate(this.templateString)
    : _compiled = _createEnvironment().fromString(templateString);

  /// Format a conversation using the Jinja2 template.
  ///
  /// [messages] is the conversation history.
  /// [systemPrompt] is prepended as a system message if provided.
  /// [addGenerationPrompt] appends the assistant turn marker (default true).
  /// [tools] is an optional list of tool definitions in OpenAI-compatible
  /// format: `[{"type": "function", "function": {"name": ..., ...}}]`.
  /// [bosToken] and [eosToken] default to empty strings.
  String format({
    required List<ChatMessage> messages,
    String? systemPrompt,
    bool addGenerationPrompt = true,
    List<Map<String, dynamic>>? tools,
    String bosToken = '',
    String eosToken = '',
  }) {
    final jinjaMessages = _toJinjaMessages(messages, systemPrompt);
    return _compiled.render({
      'messages': jinjaMessages,
      'add_generation_prompt': addGenerationPrompt,
      'bos_token': bosToken,
      'eos_token': eosToken,
      if (tools != null) 'tools': tools,
    });
  }

  /// Convert EdgeVeda ChatMessage list to Jinja2-compatible message dicts.
  ///
  /// Maps ChatRole values to standard HuggingFace role strings.
  /// Prepends systemPrompt as a system message if provided.
  static List<Map<String, dynamic>> _toJinjaMessages(
    List<ChatMessage> messages,
    String? systemPrompt,
  ) {
    final result = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      result.add({'role': 'system', 'content': systemPrompt});
    }

    for (final msg in messages) {
      final role = switch (msg.role) {
        ChatRole.user => 'user',
        ChatRole.assistant => 'assistant',
        ChatRole.system => 'system',
        ChatRole.toolCall => 'assistant',
        ChatRole.toolResult => 'tool',
        ChatRole.summary => 'system',
      };

      final entry = <String, dynamic>{'role': role, 'content': msg.content};
      result.add(entry);
    }

    return result;
  }

  /// Create a Jinja2 Environment matching HuggingFace conventions.
  ///
  /// Settings:
  /// - trimBlocks: true (remove first newline after block tag)
  /// - leftStripBlocks: true (strip leading whitespace from block tags)
  ///
  /// Custom globals registered:
  /// - raise_exception(msg): throws an exception (used by some templates
  ///   to reject unsupported features)
  /// - strftime_now(fmt): returns empty string (placeholder; on-device
  ///   models rarely need real-time formatting)
  static Environment _createEnvironment() {
    return Environment(
      trimBlocks: true,
      leftStripBlocks: true,
      globals: {
        'raise_exception': (String message) {
          throw Exception('Template error: $message');
        },
        'strftime_now': (String format) {
          // Simplified: return empty string. Real implementation would
          // format DateTime.now() but this is rarely used in practice.
          return '';
        },
      },
    );
  }
}
