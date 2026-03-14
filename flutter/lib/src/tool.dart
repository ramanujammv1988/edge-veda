/// Declarative tool class that bundles definition and handler.
///
/// Combines tool metadata ([name], [description], [parameters]) with an
/// async [handler] function, providing a single object that can both
/// describe itself to the model (via [toDefinition]) and execute calls
/// (via [execute]) with built-in error safety.
library;

import 'param_builder.dart';
import 'tool_types.dart';

/// A declarative tool that combines its JSON Schema definition with
/// an async execution handler.
///
/// Use [toDefinition] to register with [ToolRegistry], and [execute]
/// to safely invoke the handler with error wrapping.
///
/// Example:
/// ```dart
/// final weatherTool = Tool(
///   name: 'get_weather',
///   description: 'Get current weather for a location',
///   parameters: Param.object({
///     'location': Param.string(description: 'City name'),
///     'unit': Param.string(enumValues: ['celsius', 'fahrenheit']),
///   }, required: ['location']),
///   handler: (args) async {
///     final city = args['location'] as String;
///     return {'temperature': 22, 'unit': 'celsius', 'city': city};
///   },
/// );
///
/// // Register with ToolRegistry
/// final registry = ToolRegistry([weatherTool.toDefinition()]);
///
/// // Execute a tool call
/// final result = await weatherTool.execute(toolCall);
/// ```
class Tool {
  /// Tool function name (validated by [ToolDefinition] on [toDefinition]).
  final String name;

  /// Human-readable description shown to the model.
  final String description;

  /// Parameter schema built via [Param] factories.
  final ParamSchema parameters;

  /// Async handler that receives parsed arguments and returns result data.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args)
  handler;

  /// Priority for budget-aware degradation (default: [ToolPriority.required]).
  final ToolPriority priority;

  /// Create a declarative tool with embedded handler.
  ///
  /// Validation of [name], [description], and [parameters] is deferred
  /// to [toDefinition], which delegates to [ToolDefinition]'s constructor.
  Tool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
    this.priority = ToolPriority.required,
  });

  /// Convert to a [ToolDefinition] for registration with [ToolRegistry].
  ///
  /// Validation fires here (name pattern, non-empty description,
  /// parameters must have 'type': 'object').
  ToolDefinition toDefinition() => ToolDefinition(
    name: name,
    description: description,
    parameters: parameters.toJsonSchema(),
    priority: priority,
  );

  /// Execute this tool with the given [call] arguments.
  ///
  /// Wraps [handler] in a try/catch so that handler exceptions never
  /// crash the calling inference loop. Returns [ToolResult.success] on
  /// normal completion, [ToolResult.failure] on any exception.
  Future<ToolResult> execute(ToolCall call) async {
    try {
      final result = await handler(call.arguments);
      return ToolResult.success(toolCallId: call.id, data: result);
    } catch (e) {
      return ToolResult.failure(toolCallId: call.id, error: e.toString());
    }
  }
}
