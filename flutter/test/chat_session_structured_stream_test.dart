import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/gbnf_builder.dart';
import 'package:edge_veda/src/schema_validator.dart';
import 'package:edge_veda/src/json_recovery.dart';
import 'package:edge_veda/src/chat_session.dart';

/// Tests for the sendStructuredStream pipeline components.
///
/// Full end-to-end streaming tests require a loaded model (integration test).
/// These unit tests verify the grammar generation, validation, and recovery
/// logic that sendStructuredStream uses, exercised independently.
void main() {
  group('sendStructuredStream pipeline', () {
    group('Grammar generation from schema', () {
      test('schema produces GBNF grammar with root rule', () {
        final schema = {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'age': {'type': 'integer'},
          },
          'required': ['name', 'age'],
        };

        final grammar = GbnfBuilder.fromJsonSchema(schema);

        expect(grammar, contains('root ::='));
        expect(grammar, contains('ws'));
        // Property names are GBNF-escaped: "\\"name\\""
        expect(grammar, contains('name'));
        expect(grammar, contains('age'));
      });

      test('generated grammar includes string and integer base rules', () {
        final schema = {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'count': {'type': 'integer'},
          },
          'required': ['title'],
        };

        final grammar = GbnfBuilder.fromJsonSchema(schema);

        expect(grammar, contains('string ::='));
        expect(grammar, contains('integer ::='));
      });

      test('nested object schema generates valid grammar', () {
        final schema = {
          'type': 'object',
          'properties': {
            'person': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
              'required': ['name'],
            },
          },
          'required': ['person'],
        };

        final grammar = GbnfBuilder.fromJsonSchema(schema);

        expect(grammar, contains('root ::='));
        // Property names are GBNF-escaped with backslash quotes
        expect(grammar, contains('person'));
        expect(grammar, contains('name'));
      });

      test('array schema generates valid grammar', () {
        final schema = {
          'type': 'object',
          'properties': {
            'items': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['items'],
        };

        final grammar = GbnfBuilder.fromJsonSchema(schema);

        expect(grammar, contains('root ::='));
        // Property names are GBNF-escaped with backslash quotes
        expect(grammar, contains('items'));
        expect(grammar, contains('['));
      });
    });

    group('Post-stream validation (standard mode)', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name', 'age'],
      };

      test('valid JSON passes schema validation', () {
        final data = {'name': 'John', 'age': 30};
        final result = SchemaValidator.validate(data, schema);

        expect(result.isValid, true);
        expect(result.errors, isEmpty);
      });

      test('missing required field fails validation', () {
        final data = {'name': 'John'};
        final result = SchemaValidator.validate(data, schema);

        expect(result.isValid, false);
        expect(result.errors, isNotEmpty);
      });

      test('wrong type fails validation', () {
        final data = {'name': 'John', 'age': 'thirty'};
        final result = SchemaValidator.validate(data, schema);

        expect(result.isValid, false);
      });

      test('extra keys allowed in standard mode', () {
        final data = {'name': 'John', 'age': 30, 'extra': true};
        final result = SchemaValidator.validate(data, schema);

        expect(result.isValid, true);
      });
    });

    group('Post-stream validation (strict mode)', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name', 'age'],
      };

      test('valid JSON passes strict validation', () {
        final data = {'name': 'John', 'age': 30};
        final result = SchemaValidator.validateStrict(data, schema);

        expect(result.isValid, true);
      });

      test('extra keys rejected in strict mode', () {
        final data = {'name': 'John', 'age': 30, 'extra': true};
        final result = SchemaValidator.validateStrict(data, schema);

        expect(result.isValid, false);
        expect(result.errors, contains(contains('extra')));
      });
    });

    group('JSON recovery for malformed stream output', () {
      test('recovers JSON with leading text', () {
        const malformed = 'Here is the JSON: {"name": "John", "age": 30}';
        final repaired = JsonRecovery.tryRepair(malformed);

        expect(repaired, isNotNull);
        final parsed = jsonDecode(repaired!) as Map<String, dynamic>;
        expect(parsed['name'], 'John');
        expect(parsed['age'], 30);
      });

      test('recovers truncated JSON with missing closer', () {
        const malformed = '{"name": "John", "age": 30';
        final result = JsonRecovery.tryRepairWithDetails(malformed);

        expect(result.repaired, isNotNull);
        expect(result.repairs, isNotEmpty);
        final parsed = jsonDecode(result.repaired!) as Map<String, dynamic>;
        expect(parsed['name'], 'John');
      });

      test('unrecoverable input returns null', () {
        final result = JsonRecovery.tryRepair('no json here at all');

        expect(result, isNull);
      });
    });

    group('Full pipeline: schema -> grammar -> parse -> validate', () {
      test('schema-generated grammar constrains to parseable JSON', () {
        // Simulate what sendStructuredStream does:
        // 1. Generate grammar from schema
        // 2. (model generates output constrained by grammar -- simulated)
        // 3. Parse output as JSON
        // 4. Validate against schema

        final schema = {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'age': {'type': 'integer'},
          },
          'required': ['name', 'age'],
        };

        // Step 1: grammar generation succeeds
        final grammar = GbnfBuilder.fromJsonSchema(schema);
        expect(grammar, isNotEmpty);

        // Step 2: simulated model output (grammar-constrained)
        const modelOutput = '{"name": "Alice", "age": 25}';

        // Step 3: parse
        final parsed = jsonDecode(modelOutput) as Map<String, dynamic>;

        // Step 4: validate
        final result = SchemaValidator.validate(parsed, schema);
        expect(result.isValid, true);
        expect(parsed['name'], 'Alice');
        expect(parsed['age'], 25);
      });

      test('pipeline with recovery on slightly malformed output', () {
        final schema = {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city'],
        };

        // Grammar generation
        final grammar = GbnfBuilder.fromJsonSchema(schema);
        expect(grammar, isNotEmpty);

        // Simulated malformed output (trailing text)
        const modelOutput = '{"city": "Tokyo"} extra stuff';

        // Parse fails on raw
        Map<String, dynamic>? parsed;
        try {
          parsed = jsonDecode(modelOutput) as Map<String, dynamic>;
        } catch (_) {
          // Recovery
          final repaired = JsonRecovery.tryRepair(modelOutput);
          expect(repaired, isNotNull);
          parsed = jsonDecode(repaired!) as Map<String, dynamic>;
        }

        // Validate
        final result = SchemaValidator.validate(parsed, schema);
        expect(result.isValid, true);
        expect(parsed['city'], 'Tokyo');
      });
    });

    group('ValidationEvent structure', () {
      test('ValidationEvent constructor accepts all fields', () {
        const event = ValidationEvent(
          passed: true,
          mode: SchemaValidationMode.standard,
          recoveryAttempted: false,
          recoverySucceeded: false,
          repairs: [],
          errors: [],
          rawOutput: '{"name": "test"}',
          validationTimeMs: 5,
        );

        expect(event.passed, true);
        expect(event.mode, SchemaValidationMode.standard);
        expect(event.recoveryAttempted, false);
        expect(event.rawOutput, '{"name": "test"}');
        expect(event.validationTimeMs, 5);
      });

      test('ValidationEvent captures failure details', () {
        const event = ValidationEvent(
          passed: false,
          mode: SchemaValidationMode.strict,
          recoveryAttempted: true,
          recoverySucceeded: true,
          repairs: ['Stripped 10 leading characters before JSON'],
          errors: ["Extra key 'unknown' not allowed in schema at /unknown"],
          rawOutput: 'prefix: {"name": "test", "unknown": true}',
          validationTimeMs: 12,
        );

        expect(event.passed, false);
        expect(event.mode, SchemaValidationMode.strict);
        expect(event.recoveryAttempted, true);
        expect(event.recoverySucceeded, true);
        expect(event.repairs, hasLength(1));
        expect(event.errors, hasLength(1));
      });
    });
  });
}
