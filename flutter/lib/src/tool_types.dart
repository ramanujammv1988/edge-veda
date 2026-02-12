/// Tool/function calling type definitions for structured output.
///
/// Provides [ToolDefinition], [ToolCall], [ToolResult], and supporting types
/// used by [ToolRegistry] and [ChatSession] to enable model-driven function
/// calling with JSON Schema parameter validation.
library;

import 'dart:convert';

import 'types.dart';

/// Priority level for a tool in the registry.
///
/// Used by [ToolRegistry.forBudgetLevel] to degrade tool availability
/// under resource pressure. Required tools are kept longer than optional ones.
enum ToolPriority {
  /// Tool is essential -- kept available under reduced QoS.
  required,

  /// Tool is nice-to-have -- dropped first under resource pressure.
  optional,
}

/// Name validation pattern for tool function names.
///
/// Allows alphanumeric characters and underscores, starting with a letter
/// or underscore. Maximum 64 characters.
final _toolNamePattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]{0,63}$');

/// Immutable definition of a tool that a model can invoke.
///
/// Each tool has a unique [name], human-readable [description], and a
/// JSON Schema [parameters] object describing the expected arguments.
///
/// Example:
/// ```dart
/// final weatherTool = ToolDefinition(
///   name: 'get_weather',
///   description: 'Get current weather for a location',
///   parameters: {
///     'type': 'object',
///     'properties': {
///       'location': {'type': 'string', 'description': 'City name'},
///       'unit': {'type': 'string', 'enum': ['celsius', 'fahrenheit']},
///     },
///     'required': ['location'],
///   },
/// );
/// ```
class ToolDefinition {
  /// Tool function name (alphanumeric + underscores, 1-64 chars).
  final String name;

  /// Human-readable description of what the tool does, shown to the model.
  final String description;

  /// JSON Schema object describing the tool's parameters.
  ///
  /// Must have `'type': 'object'` at the top level.
  final Map<String, dynamic> parameters;

  /// Priority for budget-aware degradation.
  final ToolPriority priority;

  /// Create a tool definition with validation.
  ///
  /// Throws [ConfigurationException] if:
  /// - [name] does not match `^[a-zA-Z_][a-zA-Z0-9_]{0,63}$`
  /// - [description] is empty
  /// - [parameters] does not have `'type': 'object'`
  ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.priority = ToolPriority.required,
  }) {
    if (!_toolNamePattern.hasMatch(name)) {
      throw ConfigurationException(
        'Invalid tool name: "$name"',
        details:
            'Tool names must match ^[a-zA-Z_][a-zA-Z0-9_]{0,63}\$ '
            '(alphanumeric + underscores, 1-64 chars, starting with letter or underscore)',
      );
    }
    if (description.isEmpty) {
      throw ConfigurationException(
        'Tool description cannot be empty',
        details: 'Tool "$name" must have a non-empty description',
      );
    }
    if (parameters['type'] != 'object') {
      throw ConfigurationException(
        'Tool parameters must be a JSON Schema object',
        details:
            'Tool "$name" parameters must have \'type\': \'object\' at the top level',
      );
    }
  }

  /// Serialize to Hermes/Qwen3 function calling format.
  ///
  /// Returns:
  /// ```json
  /// {
  ///   "type": "function",
  ///   "function": {
  ///     "name": "...",
  ///     "description": "...",
  ///     "parameters": {...}
  ///   }
  /// }
  /// ```
  Map<String, dynamic> toFunctionJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };

  /// Serialize to Gemma3/FunctionGemma tool calling format.
  ///
  /// Returns:
  /// ```json
  /// {
  ///   "name": "...",
  ///   "description": "...",
  ///   "parameters": {...}
  /// }
  /// ```
  Map<String, dynamic> toToolJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };

  /// Serialize to JSON string (Hermes format) for prompt injection.
  String toFunctionJsonString() => jsonEncode(toFunctionJson());

  @override
  String toString() => 'ToolDefinition($name, priority=${priority.name})';
}

/// A parsed tool call extracted from model output.
///
/// Contains the tool [name] and parsed [arguments] that the model
/// wants to invoke. The [id] is auto-generated for tracking.
class ToolCall {
  /// Unique identifier for this tool call.
  ///
  /// Generated from the current timestamp in base-36 for compactness.
  final String id;

  /// Name of the tool function to invoke.
  final String name;

  /// Parsed arguments from the model output.
  final Map<String, dynamic> arguments;

  /// Create a tool call with an auto-generated ID.
  ToolCall({
    required this.name,
    required this.arguments,
  }) : id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// Create a tool call with an explicit ID (for deserialization).
  ToolCall.withId({
    required this.id,
    required this.name,
    required this.arguments,
  });

  @override
  String toString() =>
      'ToolCall($id, $name, ${jsonEncode(arguments)})';
}

/// Result of executing a tool call, provided by the developer.
///
/// Create via [ToolResult.success] or [ToolResult.failure] factories.
class ToolResult {
  /// References the [ToolCall.id] this result responds to.
  final String toolCallId;

  /// Successful result data, or null if the tool failed.
  final Map<String, dynamic>? data;

  /// Error message if the tool execution failed, or null on success.
  final String? error;

  /// Whether this result represents a failure.
  bool get isError => error != null;

  const ToolResult._({
    required this.toolCallId,
    this.data,
    this.error,
  });

  /// Create a successful tool result.
  factory ToolResult.success({
    required String toolCallId,
    required Map<String, dynamic> data,
  }) =>
      ToolResult._(toolCallId: toolCallId, data: data);

  /// Create a failed tool result.
  factory ToolResult.failure({
    required String toolCallId,
    required String error,
  }) =>
      ToolResult._(toolCallId: toolCallId, error: error);

  @override
  String toString() => isError
      ? 'ToolResult.failure($toolCallId, $error)'
      : 'ToolResult.success($toolCallId, ${jsonEncode(data)})';
}

/// Thrown when model output cannot be parsed as a valid tool call.
///
/// Contains the [rawOutput] that failed to parse for debugging.
class ToolCallParseException extends EdgeVedaException {
  /// The raw model output that could not be parsed as a tool call.
  final String rawOutput;

  ToolCallParseException(
    super.message, {
    required this.rawOutput,
    super.details,
  });

  @override
  String toString() {
    final truncated = rawOutput.length > 100
        ? '${rawOutput.substring(0, 100)}...'
        : rawOutput;
    return 'ToolCallParseException: $message (raw: "$truncated")';
  }
}
