/// JSON Schema validation for structured output.
///
/// Wraps the `json_schema` package to validate JSON data against
/// JSON Schema Draft 7 schemas. Used by the tool calling system
/// to validate model-generated arguments against tool parameter schemas.
library;

import 'package:json_schema/json_schema.dart';

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
}
