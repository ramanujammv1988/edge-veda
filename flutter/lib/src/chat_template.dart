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

  /// Qwen3 format (ChatML + Hermes-style XML tool calls)
  ///
  /// Uses `<|im_start|>` and `<|im_end|>` special tokens with
  /// `<tool_call>` / `<tool_response>` XML tags for tool messages.
  qwen3,

  /// Gemma3 format with JSON-style tool calls
  ///
  /// Uses `<start_of_turn>` and `<end_of_turn>` special tokens.
  /// Uses "model" role instead of "assistant".
  gemma3,
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
      case ChatTemplateFormat.qwen3:
        return _formatQwen3(systemPrompt, messages);
      case ChatTemplateFormat.gemma3:
        return _formatGemma3(systemPrompt, messages);
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
      switch (msg.role) {
        case ChatRole.summary:
          // Treat summaries as system messages with a prefix
          buffer.write('<|start_header_id|>system<|end_header_id|>\n\n');
          buffer.write('Previous conversation summary: ${msg.content}');
          buffer.write('<|eot_id|>');
        case ChatRole.toolCall:
          // Tool calls are assistant-generated
          buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
          buffer.write(msg.content);
          buffer.write('<|eot_id|>');
        case ChatRole.toolResult:
          // Tool results are developer-provided (treat as user input)
          buffer.write('<|start_header_id|>user<|end_header_id|>\n\n');
          buffer.write(msg.content);
          buffer.write('<|eot_id|>');
        case ChatRole.user:
        case ChatRole.assistant:
        case ChatRole.system:
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
      switch (msg.role) {
        case ChatRole.summary:
          // Treat summaries as system messages with a prefix
          buffer.write('<|im_start|>system\n');
          buffer.write('Previous conversation summary: ${msg.content}');
          buffer.write('<|im_end|>\n');
        case ChatRole.toolCall:
          // Tool calls are assistant-generated
          buffer.write('<|im_start|>assistant\n');
          buffer.write(msg.content);
          buffer.write('<|im_end|>\n');
        case ChatRole.toolResult:
          // Tool results are developer-provided (treat as user input)
          buffer.write('<|im_start|>user\n');
          buffer.write(msg.content);
          buffer.write('<|im_end|>\n');
        case ChatRole.user:
        case ChatRole.assistant:
        case ChatRole.system:
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
      switch (msg.role) {
        case ChatRole.summary:
          buffer.write('### System:\n');
          buffer.write('Previous conversation summary: ${msg.content}');
          buffer.write('\n\n');
        case ChatRole.toolCall:
          // Tool calls are assistant-generated
          buffer.write('### Assistant:\n');
          buffer.write(msg.content);
          buffer.write('\n\n');
        case ChatRole.toolResult:
          // Tool results are developer-provided (treat as user input)
          buffer.write('### User:\n');
          buffer.write(msg.content);
          buffer.write('\n\n');
        case ChatRole.user:
        case ChatRole.assistant:
        case ChatRole.system:
          // Capitalize role name for display
          final roleName =
              msg.role.name[0].toUpperCase() + msg.role.name.substring(1);
          buffer.write('### $roleName:\n');
          buffer.write(msg.content);
          buffer.write('\n\n');
      }
    }

    // Prompt for assistant response
    buffer.write('### Assistant:\n');

    return buffer.toString();
  }

  /// Format using Qwen3 template (ChatML with Hermes-style XML tool calls)
  ///
  /// Uses ChatML delimiters (`<|im_start|>`, `<|im_end|>`) with
  /// `<tool_call>` and `<tool_response>` XML tags for tool messages.
  ///
  /// Produces:
  /// ```
  /// <|im_start|>system
  /// {system prompt}<|im_end|>
  /// <|im_start|>user
  /// {user message}<|im_end|>
  /// <|im_start|>assistant
  /// <tool_call>
  /// {tool call json}
  /// </tool_call><|im_end|>
  /// <|im_start|>user
  /// <tool_response>
  /// {tool result json}
  /// </tool_response><|im_end|>
  /// <|im_start|>assistant
  /// ```
  static String _formatQwen3(
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
      switch (msg.role) {
        case ChatRole.summary:
          // Treat summaries as system messages with a prefix
          buffer.write('<|im_start|>system\n');
          buffer.write('Previous conversation summary: ${msg.content}');
          buffer.write('<|im_end|>\n');
        case ChatRole.toolCall:
          // Tool call wrapped in XML tags within assistant turn
          buffer.write('<|im_start|>assistant\n');
          buffer.write('<tool_call>\n${msg.content}\n</tool_call>');
          buffer.write('<|im_end|>\n');
        case ChatRole.toolResult:
          // Tool result wrapped in XML tags within user turn
          buffer.write('<|im_start|>user\n');
          buffer.write('<tool_response>\n${msg.content}\n</tool_response>');
          buffer.write('<|im_end|>\n');
        case ChatRole.user:
        case ChatRole.assistant:
        case ChatRole.system:
          buffer.write('<|im_start|>${msg.role.name}\n');
          buffer.write(msg.content);
          buffer.write('<|im_end|>\n');
      }
    }

    // Prompt for assistant response
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }

  /// Format using Gemma3 template
  ///
  /// Uses `<start_of_turn>` and `<end_of_turn>` special tokens.
  /// Gemma3 uses "model" instead of "assistant" as the role name.
  /// System prompt is prepended to the first user turn.
  ///
  /// Produces:
  /// ```
  /// <start_of_turn>user
  /// {system prompt}
  ///
  /// {user message}<end_of_turn>
  /// <start_of_turn>model
  /// {assistant message}<end_of_turn>
  /// <start_of_turn>model
  /// ```
  static String _formatGemma3(
    String? systemPrompt,
    List<ChatMessage> messages,
  ) {
    final buffer = StringBuffer();

    // Gemma3 doesn't have a dedicated system turn. System prompt is
    // prepended to the first user turn.
    var systemPending = systemPrompt != null && systemPrompt.isNotEmpty;

    // Conversation turns
    for (final msg in messages) {
      switch (msg.role) {
        case ChatRole.summary:
          // Summaries rendered as user turn with prefix
          buffer.write('<start_of_turn>user\n');
          if (systemPending) {
            buffer.write('$systemPrompt\n\n');
            systemPending = false;
          }
          buffer.write('Previous conversation summary: ${msg.content}');
          buffer.write('<end_of_turn>\n');
        case ChatRole.user:
          buffer.write('<start_of_turn>user\n');
          if (systemPending) {
            buffer.write('$systemPrompt\n\n');
            systemPending = false;
          }
          buffer.write(msg.content);
          buffer.write('<end_of_turn>\n');
        case ChatRole.toolResult:
          // Tool results rendered as user turn with prefix
          buffer.write('<start_of_turn>user\n');
          if (systemPending) {
            buffer.write('$systemPrompt\n\n');
            systemPending = false;
          }
          buffer.write('Tool result: ${msg.content}');
          buffer.write('<end_of_turn>\n');
        case ChatRole.assistant:
        case ChatRole.toolCall:
          // Both assistant and toolCall are model turns
          buffer.write('<start_of_turn>model\n');
          buffer.write(msg.content);
          buffer.write('<end_of_turn>\n');
        case ChatRole.system:
          // Standalone system messages become user turns
          buffer.write('<start_of_turn>user\n');
          if (systemPending) {
            buffer.write('$systemPrompt\n\n');
            systemPending = false;
          }
          buffer.write(msg.content);
          buffer.write('<end_of_turn>\n');
      }
    }

    // If system prompt was provided but no user message came,
    // emit it as a standalone user turn
    if (systemPending) {
      buffer.write('<start_of_turn>user\n');
      buffer.write(systemPrompt);
      buffer.write('<end_of_turn>\n');
    }

    // Prompt for model response
    buffer.write('<start_of_turn>model\n');

    return buffer.toString();
  }
}
