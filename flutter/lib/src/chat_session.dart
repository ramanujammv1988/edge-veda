/// Multi-turn conversation session management
///
/// [ChatSession] wraps an [EdgeVeda] instance and manages conversation
/// history automatically. Developers call [send] or [sendStream] with
/// a user prompt, and ChatSession handles:
/// - Formatting the full conversation history using the model's chat template
/// - Tracking user/assistant messages
/// - Summarizing older messages when the context window fills up
///
/// System prompts are set at creation time and remain immutable for the
/// session's lifetime. Use [reset] to start a fresh conversation while
/// keeping the model loaded.
///
/// Example:
/// ```dart
/// final session = ChatSession(
///   edgeVeda: edgeVeda,
///   preset: SystemPromptPreset.assistant,
/// );
///
/// // Full response
/// final reply = await session.send('What is Flutter?');
/// print(reply.content);
///
/// // Streaming response
/// await for (final chunk in session.sendStream('Tell me more')) {
///   stdout.write(chunk.token);
/// }
///
/// // Check context usage
/// print('Turns: ${session.turnCount}, Context: ${(session.contextUsage * 100).toInt()}%');
///
/// // Start fresh conversation (model stays loaded)
/// session.reset();
/// ```
library;

import 'chat_template.dart';
import 'chat_types.dart';
import 'edge_veda_impl.dart';
import 'types.dart'
    show
        CancelToken,
        ConfigurationException,
        GenerateOptions,
        TokenChunk;

/// Manages multi-turn conversation state on top of [EdgeVeda]
///
/// ChatSession is pure Dart -- it uses no new C API symbols. It formats
/// conversation history using chat templates and delegates inference to
/// the existing [EdgeVeda.generate] and [EdgeVeda.generateStream] methods.
class ChatSession {
  final EdgeVeda _edgeVeda;

  /// The system prompt for this session (immutable after creation)
  ///
  /// Set via constructor parameter or [SystemPromptPreset]. If both
  /// [systemPrompt] and [preset] are provided, [systemPrompt] takes
  /// precedence.
  final String? systemPrompt;

  /// The chat template format used for formatting prompts
  final ChatTemplateFormat templateFormat;

  final int _contextLength;
  final int _maxResponseTokens;
  final List<ChatMessage> _messages = [];
  bool _isSummarizing = false;

  /// Create a new chat session
  ///
  /// Requires an initialized [EdgeVeda] instance. Throws
  /// [ConfigurationException] if the instance is not initialized.
  ///
  /// [systemPrompt] sets a custom system prompt. If null and [preset]
  /// is provided, the preset's prompt text is used instead.
  ///
  /// [templateFormat] defaults to [ChatTemplateFormat.llama3Instruct]
  /// for Llama 3.x models. Change this if using a different model family.
  ///
  /// [maxResponseTokens] reserves space in the context window for the
  /// model's response (defaults to 512 tokens).
  ChatSession({
    required EdgeVeda edgeVeda,
    String? systemPrompt,
    SystemPromptPreset? preset,
    this.templateFormat = ChatTemplateFormat.llama3Instruct,
    int maxResponseTokens = 512,
  })  : _edgeVeda = edgeVeda,
        systemPrompt = systemPrompt ?? preset?.prompt,
        _contextLength = edgeVeda.config?.contextLength ?? 2048,
        _maxResponseTokens = maxResponseTokens {
    if (!edgeVeda.isInitialized) {
      throw const ConfigurationException(
        'EdgeVeda must be initialized before creating a ChatSession. Call init() first.',
      );
    }
  }

  /// Read-only access to conversation history
  ///
  /// Returns an unmodifiable view of the message list. Messages are in
  /// chronological order. Includes user messages, assistant responses,
  /// and any summary messages from context overflow handling.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Number of user turns in the conversation
  int get turnCount => _messages.where((m) => m.role == ChatRole.user).length;

  /// Estimated context window usage as a fraction (0.0 to 1.0+)
  ///
  /// Uses a rough heuristic of ~4 characters per token. This is an
  /// approximation -- exact token counting requires the model's vocabulary
  /// which is not exposed via the current API.
  ///
  /// Values above 0.7 may trigger automatic summarization on the next
  /// [send] or [sendStream] call.
  double get contextUsage {
    if (_contextLength <= 0) return 0.0;
    final formatted = _formatConversation();
    final estimatedTokens = formatted.length ~/ 4;
    return estimatedTokens / _contextLength;
  }

  /// Whether a summarization is currently in progress
  bool get isSummarizing => _isSummarizing;

  /// Send a message and get the complete response
  ///
  /// Adds the user message to history, checks for context overflow
  /// (triggering summarization if needed), formats the conversation,
  /// generates a response, and adds the assistant reply to history.
  ///
  /// Returns the assistant's [ChatMessage] with the complete response.
  ///
  /// On error, the user message is rolled back from history to keep
  /// the conversation in a consistent state.
  ///
  /// Example:
  /// ```dart
  /// final reply = await session.send('What is Dart?');
  /// print(reply.content);
  /// print('Turn ${session.turnCount}');
  /// ```
  Future<ChatMessage> send(
    String prompt, {
    GenerateOptions? options,
    CancelToken? cancelToken,
  }) async {
    // Add user message
    _messages.add(ChatMessage(
      role: ChatRole.user,
      content: prompt,
      timestamp: DateTime.now(),
    ));

    try {
      // Check and summarize if needed
      await _summarizeIfNeeded(cancelToken: cancelToken);

      // Format full conversation
      final formatted = _formatConversation();

      // Generate response
      final response = await _edgeVeda.generate(formatted, options: options);

      // Add assistant message
      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        content: response.text,
        timestamp: DateTime.now(),
      );
      _messages.add(assistantMsg);
      return assistantMsg;
    } catch (e) {
      // Rollback user message on error
      if (_messages.isNotEmpty && _messages.last.role == ChatRole.user) {
        _messages.removeLast();
      }
      rethrow;
    }
  }

  /// Send a message and stream the response token-by-token
  ///
  /// Adds the user message to history, checks for context overflow,
  /// formats the conversation, and streams the model's response. Each
  /// [TokenChunk] contains a token fragment. After the stream completes,
  /// the full assistant response is added to history.
  ///
  /// On error, the user message is rolled back from history.
  ///
  /// Example:
  /// ```dart
  /// final buffer = StringBuffer();
  /// await for (final chunk in session.sendStream('Tell me a joke')) {
  ///   if (!chunk.isFinal) {
  ///     buffer.write(chunk.token);
  ///     stdout.write(chunk.token);
  ///   }
  /// }
  /// print('\nFull response: $buffer');
  /// ```
  Stream<TokenChunk> sendStream(
    String prompt, {
    GenerateOptions? options,
    CancelToken? cancelToken,
  }) async* {
    // Add user message
    _messages.add(ChatMessage(
      role: ChatRole.user,
      content: prompt,
      timestamp: DateTime.now(),
    ));

    try {
      // Check and summarize if needed
      await _summarizeIfNeeded(cancelToken: cancelToken);

      // Format full conversation
      final formatted = _formatConversation();

      // Stream response, collecting tokens
      final buffer = StringBuffer();
      await for (final chunk in _edgeVeda.generateStream(
        formatted,
        options: options,
        cancelToken: cancelToken,
      )) {
        if (!chunk.isFinal) {
          buffer.write(chunk.token);
        }
        yield chunk;
      }

      // Add complete assistant message to history
      final responseText = buffer.toString();
      if (responseText.isNotEmpty) {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          content: responseText,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      // Rollback user message on error
      if (_messages.isNotEmpty && _messages.last.role == ChatRole.user) {
        _messages.removeLast();
      }
      rethrow;
    }
  }

  /// Reset conversation history (keep model loaded)
  ///
  /// Clears all messages but preserves the system prompt and model state.
  /// The next [send] or [sendStream] call starts a fresh conversation
  /// with fast response time (no model reload needed).
  void reset() {
    _messages.clear();
  }

  /// Format the current conversation into a prompt string
  String _formatConversation() {
    return ChatTemplate.format(
      template: templateFormat,
      systemPrompt: systemPrompt,
      messages: _messages,
    );
  }

  /// Check if context window is getting full and summarize if needed
  ///
  /// Triggers summarization when estimated token usage exceeds 70% of
  /// available capacity (context length minus reserved response tokens).
  ///
  /// Keeps the last 2 user turns and their assistant replies intact.
  /// Older messages are summarized by the model and replaced with a
  /// single summary message.
  ///
  /// If summarization fails, falls back to simple truncation (dropping
  /// oldest messages until within budget). Never crashes.
  Future<void> _summarizeIfNeeded({CancelToken? cancelToken}) async {
    final formatted = _formatConversation();
    final estimatedTokens = formatted.length ~/ 4;
    final availableTokens = _contextLength - _maxResponseTokens;

    // Only summarize when above 70% of available capacity
    if (estimatedTokens < availableTokens * 0.7) return;

    _isSummarizing = true;
    try {
      // Find split point: keep last 2 user turns + their assistant replies
      int userCount = 0;
      int splitIndex = _messages.length;
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].role == ChatRole.user) {
          userCount++;
        }
        if (userCount >= 2) {
          splitIndex = i;
          break;
        }
      }

      // Nothing to summarize if split point is at or before start
      if (splitIndex <= 0) return;

      // Extract old and recent messages
      final oldMessages = _messages.sublist(0, splitIndex);
      final recentMessages = _messages.sublist(splitIndex);

      // Build summarization prompt
      final summaryPrompt = StringBuffer();
      summaryPrompt.writeln(
          'Summarize this conversation concisely. Keep key facts and decisions:');
      for (final msg in oldMessages) {
        if (msg.role == ChatRole.summary) {
          summaryPrompt.writeln('summary: ${msg.content}');
        } else {
          summaryPrompt.writeln('${msg.role.name}: ${msg.content}');
        }
      }

      // Generate summary using the model (low temperature for factual output)
      final summaryResponse = await _edgeVeda.generate(
        summaryPrompt.toString(),
        options: const GenerateOptions(maxTokens: 128, temperature: 0.3),
      );

      // Replace old messages with summary + recent messages
      _messages.clear();
      _messages.add(ChatMessage(
        role: ChatRole.summary,
        content: summaryResponse.text,
        timestamp: DateTime.now(),
      ));
      _messages.addAll(recentMessages);
    } catch (e) {
      // Fallback: simple truncation if summarization fails
      // Drop oldest messages until estimated tokens are under 60% of available
      final availableTokens = _contextLength - _maxResponseTokens;
      final targetTokens = (availableTokens * 0.6).toInt();

      while (_messages.length > 2) {
        final currentFormatted = _formatConversation();
        final currentTokens = currentFormatted.length ~/ 4;
        if (currentTokens <= targetTokens) break;
        _messages.removeAt(0);
      }

      // Log warning but never crash
      print(
          'ChatSession: Summarization failed, fell back to truncation. Error: $e');
    } finally {
      _isSummarizing = false;
    }
  }
}
