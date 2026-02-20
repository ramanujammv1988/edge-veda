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

import 'dart:convert';

import 'chat_template.dart';
import 'chat_types.dart';
import 'edge_veda_impl.dart';
import 'gbnf_builder.dart';
import 'json_recovery.dart';
import 'schema_validator.dart';
import 'tool_registry.dart';
import 'tool_template.dart';
import 'tool_types.dart';
import 'types.dart'
    show
        CancelToken,
        ConfigurationException,
        GenerateOptions,
        GenerationException,
        TokenChunk;

/// Event emitted during structured output validation.
///
/// Enterprise consumers can use these events to monitor JSON validation
/// pass/fail rates, track recovery attempts, and log schema mismatches.
class ValidationEvent {
  /// Whether the final output passed validation
  final bool passed;

  /// The validation mode used (standard or strict)
  final SchemaValidationMode mode;

  /// Whether JSON recovery was attempted on the raw output
  final bool recoveryAttempted;

  /// Whether recovery succeeded (raw output was malformed but repair worked)
  final bool recoverySucceeded;

  /// List of repairs applied (empty if no recovery needed)
  final List<String> repairs;

  /// Validation errors (empty if passed)
  final List<String> errors;

  /// The raw model output before any recovery
  final String rawOutput;

  /// Wall-clock time for the validation step in milliseconds
  final int validationTimeMs;

  const ValidationEvent({
    required this.passed,
    required this.mode,
    required this.recoveryAttempted,
    required this.recoverySucceeded,
    required this.repairs,
    required this.errors,
    required this.rawOutput,
    required this.validationTimeMs,
  });
}

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

  /// Optional tool registry for function calling support.
  final ToolRegistry? _tools;

  /// Optional callback for structured output validation events.
  ///
  /// When set, [sendStructured] emits a [ValidationEvent] on every call
  /// with pass/fail status, recovery details, and timing. Enterprise
  /// consumers can use this to monitor validation rates in production.
  final void Function(ValidationEvent)? onValidationEvent;

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
  ///
  /// [tools] is an optional [ToolRegistry] for function calling. When
  /// provided, [sendWithTools] can invoke tools based on model output.
  ///
  /// [onValidationEvent] is an optional callback that fires on every
  /// [sendStructured] call with validation pass/fail, recovery details,
  /// and timing information.
  ChatSession({
    required EdgeVeda edgeVeda,
    String? systemPrompt,
    SystemPromptPreset? preset,
    this.templateFormat = ChatTemplateFormat.llama3Instruct,
    int maxResponseTokens = 512,
    ToolRegistry? tools,
    this.onValidationEvent,
  })  : _edgeVeda = edgeVeda,
        systemPrompt = systemPrompt ?? preset?.prompt,
        _contextLength = edgeVeda.config?.contextLength ?? 2048,
        _maxResponseTokens = maxResponseTokens,
        _tools = tools {
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

  /// The tool registry for this session, or null if no tools registered.
  ToolRegistry? get toolRegistry => _tools;

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

  /// Send a message with tool calling support.
  ///
  /// If the model responds with a tool call, [onToolCall] is invoked.
  /// The developer executes the tool and returns a [ToolResult]. The
  /// result is added to the conversation and sent back to the model
  /// for a final natural language response.
  ///
  /// If the model responds with plain text (no tool call detected),
  /// it is returned as a normal assistant message.
  ///
  /// Tool call and result messages are added to [messages] for
  /// inspection/debugging.
  ///
  /// [maxToolRounds] limits tool call loops (default 3) to prevent
  /// infinite chains.
  ///
  /// Example:
  /// ```dart
  /// final reply = await session.sendWithTools(
  ///   'What is the weather in Tokyo?',
  ///   onToolCall: (toolCall) async {
  ///     final weather = await fetchWeather(toolCall.arguments['location']);
  ///     return ToolResult.success(
  ///       toolCallId: toolCall.id,
  ///       data: {'temperature': weather.temp, 'condition': weather.condition},
  ///     );
  ///   },
  /// );
  /// ```
  Future<ChatMessage> sendWithTools(
    String prompt, {
    required Future<ToolResult> Function(ToolCall toolCall) onToolCall,
    GenerateOptions? options,
    CancelToken? cancelToken,
    int maxToolRounds = 3,
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

      for (int round = 0; round < maxToolRounds; round++) {
        // Format conversation with tool definitions injected
        final formatted = _formatConversationWithTools();

        // Generate response
        final response = await _edgeVeda.generate(formatted, options: options);

        // Check if the response contains a tool call
        final toolCalls = ToolTemplate.parseToolCalls(
          format: templateFormat,
          output: response.text,
        );

        if (toolCalls == null || toolCalls.isEmpty) {
          // No tool call -- return as normal assistant message
          final assistantMsg = ChatMessage(
            role: ChatRole.assistant,
            content: response.text,
            timestamp: DateTime.now(),
          );
          _messages.add(assistantMsg);
          return assistantMsg;
        }

        // Process the first tool call (single-call per round)
        final toolCall = toolCalls.first;

        // Add tool call message to history
        _messages.add(ChatMessage(
          role: ChatRole.toolCall,
          content: jsonEncode({
            'name': toolCall.name,
            'arguments': toolCall.arguments,
          }),
          timestamp: DateTime.now(),
        ));

        // Invoke the developer's tool handler
        final toolResult = await onToolCall(toolCall);

        // Add tool result message to history
        _messages.add(ChatMessage(
          role: ChatRole.toolResult,
          content: toolResult.isError
              ? jsonEncode({'error': toolResult.error})
              : jsonEncode(toolResult.data),
          timestamp: DateTime.now(),
        ));

        // Loop continues -- model will see the tool result and may call
        // another tool or produce a final response.
      }

      // Max rounds exhausted -- do one final generation without tool parsing
      final formatted = _formatConversationWithTools();
      final finalResponse =
          await _edgeVeda.generate(formatted, options: options);
      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        content: finalResponse.text,
        timestamp: DateTime.now(),
      );
      _messages.add(assistantMsg);
      return assistantMsg;
    } catch (e) {
      // Rollback user message on error (only if last user message is ours)
      if (_messages.isNotEmpty && _messages.last.role == ChatRole.user) {
        _messages.removeLast();
      }
      rethrow;
    }
  }

  /// Send a message and get a structured JSON response validated
  /// against the provided schema.
  ///
  /// Uses GBNF grammar-constrained decoding to guarantee the output
  /// is valid JSON conforming to [schema]. The response is validated
  /// before delivery.
  ///
  /// If the raw output is malformed JSON, [JsonRecovery] attempts to
  /// repair it before failing. The [onValidationEvent] callback (if set)
  /// fires with full details on every call.
  ///
  /// [mode] controls validation strictness: [SchemaValidationMode.standard]
  /// (default) checks types and required fields; [SchemaValidationMode.strict]
  /// additionally rejects extra keys not in the schema.
  ///
  /// Returns the validated JSON as a Map.
  ///
  /// Throws [GenerationException] if the model output fails schema
  /// validation even with grammar constraints and recovery (should be rare).
  ///
  /// Example:
  /// ```dart
  /// final result = await session.sendStructured(
  ///   'Extract the name and age from: John is 30 years old.',
  ///   schema: {
  ///     'type': 'object',
  ///     'properties': {
  ///       'name': {'type': 'string'},
  ///       'age': {'type': 'integer'},
  ///     },
  ///     'required': ['name', 'age'],
  ///   },
  ///   mode: SchemaValidationMode.strict,
  /// );
  /// print(result); // {name: John, age: 30}
  /// ```
  Future<Map<String, dynamic>> sendStructured(
    String prompt, {
    required Map<String, dynamic> schema,
    SchemaValidationMode mode = SchemaValidationMode.standard,
    GenerateOptions? options,
    CancelToken? cancelToken,
  }) async {
    final validationStart = DateTime.now();

    // Generate GBNF grammar from schema
    final grammar = GbnfBuilder.fromJsonSchema(schema);

    // Merge grammar into options
    final grammarOptions = (options ?? const GenerateOptions()).copyWith(
      grammarStr: grammar,
      grammarRoot: 'root',
    );

    // Use the existing send() method with grammar-constrained options
    final reply = await send(
      prompt,
      options: grammarOptions,
      cancelToken: cancelToken,
    );

    final rawOutput = reply.content;
    var recoveryAttempted = false;
    var recoverySucceeded = false;
    var repairs = const <String>[];

    // Parse the response as JSON, with recovery fallback
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(rawOutput) as Map<String, dynamic>;
    } catch (_) {
      // JSON parse failed -- attempt recovery
      recoveryAttempted = true;
      final recovery = JsonRecovery.tryRepairWithDetails(rawOutput);

      if (recovery.repaired != null) {
        try {
          parsed = jsonDecode(recovery.repaired!) as Map<String, dynamic>;
          recoverySucceeded = true;
          repairs = recovery.repairs;
        } catch (_) {
          // Recovery parse also failed
          final validationTimeMs = DateTime.now()
              .difference(validationStart)
              .inMilliseconds;
          onValidationEvent?.call(ValidationEvent(
            passed: false,
            mode: mode,
            recoveryAttempted: true,
            recoverySucceeded: false,
            repairs: recovery.repairs,
            errors: ['JSON parse failed even after recovery'],
            rawOutput: rawOutput,
            validationTimeMs: validationTimeMs,
          ));
          throw GenerationException(
            'Model output is not valid JSON (recovery failed)',
            details:
                'Output: "${rawOutput.length > 200 ? '${rawOutput.substring(0, 200)}...' : rawOutput}"',
          );
        }
      } else {
        // Unrecoverable
        final validationTimeMs = DateTime.now()
            .difference(validationStart)
            .inMilliseconds;
        onValidationEvent?.call(ValidationEvent(
          passed: false,
          mode: mode,
          recoveryAttempted: true,
          recoverySucceeded: false,
          repairs: recovery.repairs,
          errors: ['JSON unrecoverable: no structure found'],
          rawOutput: rawOutput,
          validationTimeMs: validationTimeMs,
        ));
        throw GenerationException(
          'Model output is not valid JSON',
          details:
              'Output: "${rawOutput.length > 200 ? '${rawOutput.substring(0, 200)}...' : rawOutput}"',
        );
      }
    }

    // Validate against schema using the selected mode
    final SchemaValidationResult validation;
    if (mode == SchemaValidationMode.strict) {
      validation = SchemaValidator.validateStrict(parsed, schema);
    } else {
      validation = SchemaValidator.validate(parsed, schema);
    }

    final validationTimeMs =
        DateTime.now().difference(validationStart).inMilliseconds;

    // Emit validation event regardless of pass/fail
    onValidationEvent?.call(ValidationEvent(
      passed: validation.isValid,
      mode: mode,
      recoveryAttempted: recoveryAttempted,
      recoverySucceeded: recoverySucceeded,
      repairs: repairs,
      errors: validation.isValid ? const [] : validation.errors,
      rawOutput: rawOutput,
      validationTimeMs: validationTimeMs,
    ));

    if (!validation.isValid) {
      throw GenerationException(
        'Model output failed schema validation',
        details: 'Errors: ${validation.errors.join(', ')}',
      );
    }

    return parsed;
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

  /// Format conversation with tool definitions injected into the system prompt.
  ///
  /// If tools are registered, combines the system prompt with tool definitions
  /// via [ToolTemplate.formatToolSystemPrompt]. Falls back to normal formatting
  /// if no tools are registered.
  String _formatConversationWithTools() {
    final tools = _tools;
    if (tools == null || tools.tools.isEmpty) {
      return _formatConversation();
    }

    final toolSystemPrompt = ToolTemplate.formatToolSystemPrompt(
      format: templateFormat,
      tools: tools.tools,
      systemPrompt: systemPrompt,
    );

    return ChatTemplate.format(
      template: templateFormat,
      systemPrompt: toolSystemPrompt,
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
