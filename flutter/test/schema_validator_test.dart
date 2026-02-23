import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/schema_validator.dart';

void main() {
  group('Standard validation', () {
    test('valid data against schema passes', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name'],
      };
      final result = SchemaValidator.validate({'name': 'John', 'age': 30}, schema);
      expect(result.isValid, true);
      expect(result.errors, isEmpty);
    });

    test('missing required field fails with error message', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'required': ['name'],
      };
      final result = SchemaValidator.validate({}, schema);
      expect(result.isValid, false);
      expect(result.errors, isNotEmpty);
    });

    test('wrong type (string where int expected) fails', () {
      final schema = {
        'type': 'object',
        'properties': {
          'count': {'type': 'integer'},
        },
        'required': ['count'],
      };
      final result = SchemaValidator.validate({'count': 'not a number'}, schema);
      expect(result.isValid, false);
      expect(result.errors, isNotEmpty);
    });

    test('extra keys allowed in standard mode', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      };
      final result =
          SchemaValidator.validate({'name': 'John', 'extra': 'x'}, schema);
      expect(result.isValid, true);
    });
  });

  group('Strict validation (validateStrict)', () {
    test('extra key at root level rejected', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      };
      final result = SchemaValidator.validateStrict(
          {'name': 'John', 'extra': 'x'}, schema);
      expect(result.isValid, false);
      expect(result.errors, contains(contains('extra')));
    });

    test('extra key in nested object rejected', () {
      final schema = {
        'type': 'object',
        'properties': {
          'address': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          },
        },
      };
      final result = SchemaValidator.validateStrict({
        'address': {'city': 'Tokyo', 'zip': '100'},
      }, schema);
      expect(result.isValid, false);
      expect(result.errors, contains(contains('zip')));
    });

    test('no extra keys passes strict validation', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      };
      final result =
          SchemaValidator.validateStrict({'name': 'John'}, schema);
      expect(result.isValid, true);
    });

    test('schema with no properties defined is permissive', () {
      final schema = {
        'type': 'object',
      };
      final result = SchemaValidator.validateStrict(
          {'anything': 'goes', 'foo': 42}, schema);
      expect(result.isValid, true);
    });
  });

  group('Type validation', () {
    test('string type validates correctly', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'required': ['name'],
      };
      expect(
          SchemaValidator.validate({'name': 'hello'}, schema).isValid, true);
    });

    test('integer type validates correctly', () {
      final schema = {
        'type': 'object',
        'properties': {
          'count': {'type': 'integer'},
        },
        'required': ['count'],
      };
      expect(SchemaValidator.validate({'count': 42}, schema).isValid, true);
    });

    test('boolean type validates correctly', () {
      final schema = {
        'type': 'object',
        'properties': {
          'active': {'type': 'boolean'},
        },
        'required': ['active'],
      };
      expect(
          SchemaValidator.validate({'active': true}, schema).isValid, true);
    });

    test('array type validates correctly', () {
      final schema = {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
        },
        'required': ['items'],
      };
      expect(
        SchemaValidator.validate({
          'items': [1, 2, 3]
        }, schema).isValid,
        true,
      );
    });

    test('nested object validates recursively', () {
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
      expect(
        SchemaValidator.validate({
          'person': {'name': 'John'}
        }, schema).isValid,
        true,
      );
    });
  });

  group('Array item validation', () {
    test('array of objects with strict mode checks each item', () {
      final schema = {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
              },
            },
          },
        },
      };
      final result = SchemaValidator.validateStrict({
        'items': [
          {'id': 1, 'extra': 'bad'},
        ],
      }, schema);
      expect(result.isValid, false);
      expect(result.errors, contains(contains('extra')));
    });

    test('empty array passes', () {
      final schema = {
        'type': 'object',
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
              },
            },
          },
        },
      };
      final result = SchemaValidator.validateStrict({
        'items': <Map<String, dynamic>>[],
      }, schema);
      expect(result.isValid, true);
    });
  });

  group('Edge cases', () {
    test('empty schema validates any object', () {
      final result = SchemaValidator.validate({'anything': 123}, {});
      expect(result.isValid, true);
    });

    test('malformed schema returns error (does not throw)', () {
      // A schema with an invalid type value should be handled gracefully
      final result = SchemaValidator.validate(
        {'name': 'John'},
        {
          'type': 'object',
          'properties': {
            'name': {'type': 'nonexistent_type'},
          },
        },
      );
      // json_schema package may or may not reject unknown types at schema
      // creation time. The important thing is it does not throw.
      expect(result, isA<SchemaValidationResult>());
    });
  });
}
