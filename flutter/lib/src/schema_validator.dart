/// JSON Schema validation for structured output.
///
/// Wraps the `json_schema` package to validate JSON data against
/// JSON Schema Draft 7 schemas. Used by the tool calling system
/// to validate model-generated arguments against tool parameter schemas.
library;

import 'package:json_schema/json_schema.dart';

/// Validation mode for schema checking.
///
/// [standard] uses JSON Schema Draft 7 validation (type checks, required fields).
/// [strict] additionally rejects any keys not defined in the schema's `properties`.
enum SchemaValidationMode {
  /// Standard JSON Schema validation (type errors, missing required fields).
  standard,

  /// Strict validation: rejects extra keys not in schema `properties`.
  strict,
}

/// Result of validating JSON data against a JSON Schema.
class SchemaValidationResult {
  /// Whether the data conforms to the schema.
  final bool isValid;

  /// Validation error messages (empty if valid).
  final List<String> errors;

  /// The validated data if valid, null otherwise.
  final Map<String, dynamic>? validatedData;

  const SchemaValidationResult._({
    required this.isValid,
    required this.errors,
    this.validatedData,
  });

  /// Create a successful validation result.
  factory SchemaValidationResult.valid(Map<String, dynamic> data) =>
      SchemaValidationResult._(
        isValid: true,
        errors: const [],
        validatedData: data,
      );

  /// Create a failed validation result.
  factory SchemaValidationResult.invalid(List<String> errors) =>
      SchemaValidationResult._(
        isValid: false,
        errors: errors,
      );

  @override
  String toString() => isValid
      ? 'SchemaValidationResult(valid)'
      : 'SchemaValidationResult(invalid, ${errors.length} errors)';
}

/// Validates JSON data against JSON Schema Draft 7 schemas.
///
/// Uses the `json_schema` package for standards-compliant validation.
///
/// Example:
/// ```dart
/// final schema = {
///   'type': 'object',
///   'properties': {
///     'location': {'type': 'string'},
///   },
///   'required': ['location'],
/// };
/// final result = SchemaValidator.validate({'location': 'Tokyo'}, schema);
/// print(result.isValid); // true
/// ```
class SchemaValidator {
  // Prevent instantiation -- all methods are static.
  SchemaValidator._();

  /// Validate [data] against a JSON Schema Draft 7 [schema].
  ///
  /// Returns a [SchemaValidationResult] with validation outcome.
  /// If the [schema] itself is malformed, returns an invalid result
  /// with an error describing the schema issue.
  static SchemaValidationResult validate(
    Map<String, dynamic> data,
    Map<String, dynamic> schema,
  ) {
    try {
      final jsonSchema = JsonSchema.create(schema);
      final validationErrors = jsonSchema.validate(data);

      if (validationErrors.errors.isEmpty) {
        return SchemaValidationResult.valid(data);
      }

      final errorMessages = validationErrors.errors
          .map((e) => e.message)
          .toList(growable: false);
      return SchemaValidationResult.invalid(errorMessages);
    } on FormatException catch (e) {
      return SchemaValidationResult.invalid(
        ['Malformed JSON Schema: ${e.message}'],
      );
    } catch (e) {
      return SchemaValidationResult.invalid(
        ['Schema validation error: $e'],
      );
    }
  }

  /// Validate [data] against [schema] in strict mode.
  ///
  /// Runs standard validation first (type checks, required fields), then
  /// recursively checks that no extra keys exist at any nesting depth.
  /// Any key in the data that is not listed in the schema's `properties`
  /// is reported as an error.
  ///
  /// If a schema node has no `properties` defined, that node is treated
  /// as permissive (extra-key check is skipped for it).
  static SchemaValidationResult validateStrict(
    Map<String, dynamic> data,
    Map<String, dynamic> schema,
  ) {
    // Run standard validation first
    final baseResult = validate(data, schema);
    if (!baseResult.isValid) {
      return baseResult;
    }

    // Recursively check for extra keys
    final extraErrors = <String>[];
    _checkExtraKeys(data, schema, '', extraErrors);

    if (extraErrors.isNotEmpty) {
      return SchemaValidationResult.invalid(extraErrors);
    }

    return SchemaValidationResult.valid(data);
  }

  /// Recursively walk [data] and [schema] together, collecting errors for
  /// any keys in the data that are not defined in the schema's `properties`.
  static void _checkExtraKeys(
    dynamic data,
    Map<String, dynamic> schema,
    String path,
    List<String> errors,
  ) {
    final type = schema['type'];

    if (type == 'object' && data is Map<String, dynamic>) {
      final properties =
          schema['properties'] as Map<String, dynamic>?;

      // If no properties defined, schema is permissive -- skip check
      if (properties == null) return;

      // Check for extra keys
      for (final key in data.keys) {
        if (!properties.containsKey(key)) {
          final errorPath = path.isEmpty ? '/$key' : '$path/$key';
          errors.add("Extra key '$key' not allowed in schema at $errorPath");
        }
      }

      // Recurse into defined properties
      for (final entry in properties.entries) {
        final propName = entry.key;
        final propSchema = entry.value as Map<String, dynamic>;
        if (data.containsKey(propName)) {
          final childPath = path.isEmpty ? '/$propName' : '$path/$propName';
          _checkExtraKeys(data[propName], propSchema, childPath, errors);
        }
      }
    } else if (type == 'array' && data is List) {
      final items = schema['items'] as Map<String, dynamic>?;
      if (items != null) {
        for (var i = 0; i < data.length; i++) {
          final childPath = '$path[$i]';
          _checkExtraKeys(data[i], items, childPath, errors);
        }
      }
    }
  }
}
