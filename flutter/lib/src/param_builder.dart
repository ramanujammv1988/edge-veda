/// Type-safe JSON Schema builder for tool parameter definitions.
///
/// Replaces raw `Map<String, dynamic>` JSON Schema construction with
/// a declarative [Param] factory that produces validated [ParamSchema]
/// objects compatible with [ToolDefinition] and [GbnfBuilder].
library;

/// Wraps a JSON Schema map with an immutable accessor.
///
/// Created exclusively via [Param] static factories. The underlying
/// schema map is returned as unmodifiable from [toJsonSchema].
class ParamSchema {
  final Map<String, dynamic> _schema;

  const ParamSchema._(this._schema);

  /// Returns an unmodifiable view of the JSON Schema map.
  ///
  /// The returned map is compatible with [ToolDefinition.parameters]
  /// and [GbnfBuilder.fromJsonSchema].
  Map<String, dynamic> toJsonSchema() => Map.unmodifiable(_schema);
}

/// Static factory for building [ParamSchema] instances.
///
/// Provides type-safe constructors for each JSON Schema primitive type,
/// plus `array` and `object` composites. Only includes optional keys
/// when the corresponding parameter is non-null, keeping schemas minimal.
///
/// Example:
/// ```dart
/// final params = Param.object({
///   'location': Param.string(description: 'City name'),
///   'unit': Param.string(
///     description: 'Temperature unit',
///     enumValues: ['celsius', 'fahrenheit'],
///   ),
/// }, required: ['location']);
/// ```
class Param {
  Param._();

  /// Creates a string parameter schema.
  ///
  /// If [enumValues] is provided, adds an `'enum'` constraint.
  static ParamSchema string({String? description, List<String>? enumValues}) {
    final schema = <String, dynamic>{'type': 'string'};
    if (description != null) schema['description'] = description;
    if (enumValues != null) schema['enum'] = enumValues;
    return ParamSchema._(schema);
  }

  /// Creates an integer parameter schema.
  ///
  /// [minimum] and [maximum] are included for documentation and
  /// post-generation validation. GBNF grammar cannot enforce numeric
  /// range constraints.
  static ParamSchema integer({
    String? description,
    int? minimum,
    int? maximum,
  }) {
    final schema = <String, dynamic>{'type': 'integer'};
    if (description != null) schema['description'] = description;
    if (minimum != null) schema['minimum'] = minimum;
    if (maximum != null) schema['maximum'] = maximum;
    return ParamSchema._(schema);
  }

  /// Creates a number (floating-point) parameter schema.
  ///
  /// [minimum] and [maximum] are included for documentation and
  /// post-generation validation. GBNF grammar cannot enforce numeric
  /// range constraints.
  static ParamSchema number({
    String? description,
    num? minimum,
    num? maximum,
  }) {
    final schema = <String, dynamic>{'type': 'number'};
    if (description != null) schema['description'] = description;
    if (minimum != null) schema['minimum'] = minimum;
    if (maximum != null) schema['maximum'] = maximum;
    return ParamSchema._(schema);
  }

  /// Creates a boolean parameter schema.
  static ParamSchema boolean({String? description}) {
    final schema = <String, dynamic>{'type': 'boolean'};
    if (description != null) schema['description'] = description;
    return ParamSchema._(schema);
  }

  /// Creates an array parameter schema.
  ///
  /// [items] defines the schema for each array element.
  /// [minItems] and [maxItems] are included for documentation and
  /// post-generation validation.
  static ParamSchema array({
    required ParamSchema items,
    String? description,
    int? minItems,
    int? maxItems,
  }) {
    final schema = <String, dynamic>{
      'type': 'array',
      'items': items.toJsonSchema(),
    };
    if (description != null) schema['description'] = description;
    if (minItems != null) schema['minItems'] = minItems;
    if (maxItems != null) schema['maxItems'] = maxItems;
    return ParamSchema._(schema);
  }

  /// Creates an object parameter schema.
  ///
  /// [properties] maps property names to their [ParamSchema] definitions.
  /// [required] lists which properties are mandatory.
  static ParamSchema object(
    Map<String, ParamSchema> properties, {
    List<String>? required,
    String? description,
  }) {
    final schemaProperties = <String, dynamic>{};
    for (final entry in properties.entries) {
      schemaProperties[entry.key] = entry.value.toJsonSchema();
    }

    final schema = <String, dynamic>{
      'type': 'object',
      'properties': schemaProperties,
    };
    if (description != null) schema['description'] = description;
    if (required != null && required.isNotEmpty) {
      schema['required'] = required;
    }
    return ParamSchema._(schema);
  }
}
