/// Tool registry for managing function calling tool collections.
///
/// [ToolRegistry] holds a validated set of [ToolDefinition]s and provides
/// budget-aware filtering via [forBudgetLevel] to degrade tool availability
/// under resource pressure.
library;

import 'tool_types.dart';
import 'types.dart';
import 'runtime_policy.dart';

/// Manages a collection of [ToolDefinition]s with budget-aware filtering.
///
/// Enforces a maximum tool count (default 5) to prevent context window
/// exhaustion on small models. Tools are categorized by [ToolPriority]
/// for graceful degradation under resource pressure.
///
/// Example:
/// ```dart
/// final registry = ToolRegistry([weatherTool, searchTool, calcTool]);
/// print(registry.tools.length); // 3
///
/// // Under reduced QoS, only required tools remain
/// final reduced = registry.forBudgetLevel(QoSLevel.reduced);
/// print(reduced.length); // only required-priority tools
/// ```
class ToolRegistry {
  final List<ToolDefinition> _tools;
  final int _maxTools;

  /// Create a registry with the given tools.
  ///
  /// Throws [ConfigurationException] if:
  /// - [tools] contains more than [maxTools] entries (default 5)
  /// - [tools] contains duplicate tool names
  ToolRegistry(
    List<ToolDefinition> tools, {
    int maxTools = 5,
  })  : _maxTools = maxTools,
        _tools = List.unmodifiable(tools) {
    if (tools.length > maxTools) {
      throw ConfigurationException(
        'Too many tools: ${tools.length} exceeds maximum of $maxTools',
        details: 'Small models perform best with $maxTools or fewer tools. '
            'Remove optional tools or increase maxTools if needed.',
      );
    }

    final names = <String>{};
    for (final tool in tools) {
      if (!names.add(tool.name)) {
        throw ConfigurationException(
          'Duplicate tool name: "${tool.name}"',
          details: 'Each tool in the registry must have a unique name',
        );
      }
    }
  }

  /// Unmodifiable list of all registered tools.
  List<ToolDefinition> get tools => _tools;

  /// Tools with [ToolPriority.required] priority.
  List<ToolDefinition> get requiredTools => List.unmodifiable(
        _tools.where((t) => t.priority == ToolPriority.required),
      );

  /// Tools with [ToolPriority.optional] priority.
  List<ToolDefinition> get optionalTools => List.unmodifiable(
        _tools.where((t) => t.priority == ToolPriority.optional),
      );

  /// Maximum number of tools allowed in this registry.
  int get maxTools => _maxTools;

  /// Look up a tool by its function name.
  ///
  /// Returns null if no tool with the given [name] is registered.
  ToolDefinition? findByName(String name) {
    for (final tool in _tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  /// Return tools appropriate for the given [QoSLevel].
  ///
  /// - [QoSLevel.full] -- all tools
  /// - [QoSLevel.reduced] -- required tools only (optional dropped)
  /// - [QoSLevel.minimal] -- empty list (no tools under minimal QoS)
  /// - [QoSLevel.paused] -- empty list
  List<ToolDefinition> forBudgetLevel(QoSLevel level) {
    switch (level) {
      case QoSLevel.full:
        return _tools;
      case QoSLevel.reduced:
        return requiredTools;
      case QoSLevel.minimal:
      case QoSLevel.paused:
        return const [];
    }
  }

  @override
  String toString() =>
      'ToolRegistry(${_tools.length} tools, max=$_maxTools)';
}
