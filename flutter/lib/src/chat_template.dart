/// Chat template formatting for multi-turn conversations
///
/// Formats conversation history into model-specific prompt strings.
/// The primary format is [ChatTemplateFormat.llama3Instruct] for
/// Llama 3.x models. [ChatTemplateFormat.chatML] supports models
/// using the ChatML format. [ChatTemplateFormat.generic] provides
/// a simple fallback for unknown models.
///
/// ChatSession uses these templates to convert message history into
/// a single prompt string that the model understands as multi-turn
/// conversation.
library;

import 'chat_types.dart';

/// Supported chat template formats
///
/// Each format defines how system prompts, user messages, and assistant
/// responses are delimited in the prompt string. Using the wrong template
/// for a model will produce garbage output.
enum ChatTemplateFormat {
  /// Llama 3 Instruct format (default for Llama-3.x-Instruct models)
  ///
  /// Uses `<|begin_of_text|>`, `<|start_header_id|>`, `<|end_header_id|>`,
  /// and `<|eot_id|>` special tokens.
  llama3Instruct,

  /// ChatML format (used by many open models)
  ///
  /// Uses `<|im_start|>` and `<|im_end|>` special tokens.
  chatML,

  /// Generic fallback format using markdown-style headers
  ///
  /// Uses `### System:`, `### User:`, `### Assistant:` markers.
  /// Works as a reasonable default when the exact template is unknown.
  generic,
}

/// Formats multi-turn conversations into model-specific prompt strings
///
/// This class applies chat templates in pure Dart, avoiding the need for
/// new C API symbols. The templates match the formats expected by
/// llama.cpp's tokenizer for each model family.
///
/// Example:
/// ```dart
/// final prompt = ChatTemplate.format(
///   template: ChatTemplateFormat.llama3Instruct,
///   systemPrompt: 'You are a helpful assistant.',
///   messages: [
///     ChatMessage(role: ChatRole.user, content: 'Hello!', timestamp: DateTime.now()),
///   ],
/// );
/// ```
class ChatTemplate {
  /// Format a conversation into a prompt string using the specified template
  ///
  /// [template] determines which special tokens and delimiters to use.
  /// [systemPrompt] is optional and placed at the beginning of the prompt.
  /// [messages] is the conversation history to format.
  ///
  /// Returns a complete prompt string ready to pass to the model, ending
  /// with the assistant turn marker to prompt a response.
  static String format({
    required ChatTemplateFormat template,
    String? systemPrompt,
    required List<ChatMessage> messages,
  }) {
    switch (template) {
      case ChatTemplateFormat.llama3Instruct:
        return _formatLlama3Instruct(systemPrompt, messages);
      case ChatTemplateFormat.chatML:
        return _formatChatML(systemPrompt, messages);
      case ChatTemplateFormat.generic:
        return _formatGeneric(systemPrompt, messages);
    }
  }

  /// Format using Llama 3 Instruct template
  ///
  /// Produces:
  /// ```
  /// <|begin_of_text|><|start_header_id|>system<|end_header_id|>
  ///
  /// {system prompt}<|eot_id|><|start_header_id|>user<|end_header_id|>
  ///
  /// {user message}<|eot_id|><|start_header_id|>assistant<|end_header_id|>
  ///
  /// ```
  static String _formatLlama3Instruct(
    String? systemPrompt,
    List<ChatMessage> messages,
  ) {
    final buffer = StringBuffer();

    buffer.write('<|begin_of_text|>');

    // System prompt (optional)
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.write('<|start_header_id|>system<|end_header_id|>\n\n');
      buffer.write(systemPrompt);
      buffer.write('<|eot_id|>');
    }

    // Conversation turns
    for (final msg in messages) {
      if (msg.role == ChatRole.summary) {
        // Treat summaries as system messages with a prefix
        buffer.write('<|start_header_id|>system<|end_header_id|>\n\n');
        buffer.write('Previous conversation summary: ${msg.content}');
        buffer.write('<|eot_id|>');
      } else {
        buffer.write('<|start_header_id|>${msg.role.name}<|end_header_id|>\n\n');
        buffer.write(msg.content);
        buffer.write('<|eot_id|>');
      }
    }

    // Prompt for assistant response
    buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');

    return buffer.toString();
  }

  /// Format using ChatML template
  ///
  /// Produces:
  /// ```
  /// <|im_start|>system
  /// {system prompt}<|im_end|>
  /// <|im_start|>user
  /// {user message}<|im_end|>
  /// <|im_start|>assistant
  /// ```
  static String _formatChatML(
    String? systemPrompt,
    List<ChatMessage> messages,
  ) {
    final buffer = StringBuffer();

    // System prompt (optional)
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.write('<|im_start|>system\n');
      buffer.write(systemPrompt);
      buffer.write('<|im_end|>\n');
    }

    // Conversation turns
    for (final msg in messages) {
      if (msg.role == ChatRole.summary) {
        // Treat summaries as system messages with a prefix
        buffer.write('<|im_start|>system\n');
        buffer.write('Previous conversation summary: ${msg.content}');
        buffer.write('<|im_end|>\n');
      } else {
        buffer.write('<|im_start|>${msg.role.name}\n');
        buffer.write(msg.content);
        buffer.write('<|im_end|>\n');
      }
    }

    // Prompt for assistant response
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }

  /// Format using generic markdown-style template
  ///
  /// Produces:
  /// ```
  /// ### System:
  /// {system prompt}
  ///
  /// ### User:
  /// {user message}
  ///
  /// ### Assistant:
  /// ```
  static String _formatGeneric(
    String? systemPrompt,
    List<ChatMessage> messages,
  ) {
    final buffer = StringBuffer();

    // System prompt (optional)
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.write('### System:\n');
      buffer.write(systemPrompt);
      buffer.write('\n\n');
    }

    // Conversation turns
    for (final msg in messages) {
      if (msg.role == ChatRole.summary) {
        buffer.write('### System:\n');
        buffer.write('Previous conversation summary: ${msg.content}');
        buffer.write('\n\n');
      } else {
        // Capitalize role name for display
        final roleName = msg.role.name[0].toUpperCase() + msg.role.name.substring(1);
        buffer.write('### $roleName:\n');
        buffer.write(msg.content);
        buffer.write('\n\n');
      }
    }

    // Prompt for assistant response
    buffer.write('### Assistant:\n');

    return buffer.toString();
  }
}
