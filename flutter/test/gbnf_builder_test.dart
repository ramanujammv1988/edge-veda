import 'package:test/test.dart';
import 'package:edge_veda/src/gbnf_builder.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Regression tests: existing behavior must remain unchanged
  // ---------------------------------------------------------------------------
  group('Regression - existing behavior', () {
    test('object with required and optional properties', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name'],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('"name"'));
      expect(grammar, contains('string ws'));
      expect(grammar, contains('integer ws'));
    });

    test('array with items', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('"[" ws'));
      expect(grammar, contains('string ws'));
    });

    test('enum values', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'enum': ['red', 'green', 'blue'],
      });
      expect(grammar, contains('root ::='));
      expect(grammar, contains('red'));
      expect(grammar, contains('green'));
      expect(grammar, contains('blue'));
    });

    test('primitive types', () {
      expect(
        GbnfBuilder.fromJsonSchema({'type': 'string'}),
        contains('string ws'),
      );
      expect(
        GbnfBuilder.fromJsonSchema({'type': 'number'}),
        contains('number ws'),
      );
      expect(
        GbnfBuilder.fromJsonSchema({'type': 'integer'}),
        contains('integer ws'),
      );
      expect(
        GbnfBuilder.fromJsonSchema({'type': 'boolean'}),
        contains('boolean ws'),
      );
      expect(
        GbnfBuilder.fromJsonSchema({'type': 'null'}),
        contains('"null" ws'),
      );
    });

    test('empty object', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {},
      });
      expect(grammar, contains('"{" ws "}" ws'));
    });
  });

  // ---------------------------------------------------------------------------
  // $ref resolution (CGEN-02)
  // ---------------------------------------------------------------------------
  group('\$ref resolution', () {
    test('simple \$ref resolves to definition', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'address': {r'$ref': '#/definitions/Address'},
        },
        'definitions': {
          'Address': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
              'zip': {'type': 'string'},
            },
            'required': ['city'],
          },
        },
        'required': ['address'],
      });

      // The grammar must contain a ref-derived rule for Address
      expect(grammar, contains('root ::='));
      // The address property should reference a rule that resolves to the
      // Address definition (an object with city and zip)
      expect(grammar, contains('"city"'));
      expect(grammar, contains('"zip"'));
      expect(grammar, contains('"address"'));
    });

    test('nested \$ref resolves through multiple levels', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'address': {r'$ref': '#/definitions/Address'},
        },
        'definitions': {
          'Address': {
            'type': 'object',
            'properties': {
              'city': {r'$ref': '#/definitions/City'},
            },
            'required': ['city'],
          },
          'City': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'zip': {r'$ref': '#/definitions/ZipCode'},
            },
            'required': ['name'],
          },
          'ZipCode': {
            'type': 'string',
          },
        },
        'required': ['address'],
      });

      expect(grammar, contains('root ::='));
      expect(grammar, contains('"city"'));
      expect(grammar, contains('"name"'));
    });

    test('recursive \$ref does not stack overflow', () {
      // A tree/linked-list schema where Node references itself
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'root': {r'$ref': '#/definitions/Node'},
        },
        'definitions': {
          'Node': {
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
              'next': {r'$ref': '#/definitions/Node'},
            },
            'required': ['value'],
          },
        },
        'required': ['root'],
      });

      // Must not throw or hang
      expect(grammar, contains('root ::='));
      expect(grammar, contains('"value"'));
      expect(grammar, contains('"next"'));
    });

    test('missing \$ref falls back to value', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'thing': {r'$ref': '#/definitions/DoesNotExist'},
        },
        'required': ['thing'],
      });

      // Should not throw; should fall back to accepting any value
      expect(grammar, contains('root ::='));
      expect(grammar, contains('value'));
    });

    test('\$ref at property level references resolved rule', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'status': {r'$ref': '#/definitions/Status'},
        },
        'definitions': {
          'Status': {
            'enum': ['active', 'inactive'],
          },
        },
        'required': ['status'],
      });

      expect(grammar, contains('active'));
      expect(grammar, contains('inactive'));
    });

    test('\$ref using \$defs (Draft 2019-09 style) resolves', () {
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'color': {r'$ref': '#/$defs/Color'},
        },
        r'$defs': {
          'Color': {
            'type': 'string',
          },
        },
        'required': ['color'],
      });

      expect(grammar, contains('"color"'));
      expect(grammar, contains('string ws'));
    });
  });

  // ---------------------------------------------------------------------------
  // Rule budget (CGEN-05)
  // ---------------------------------------------------------------------------
  group('Rule budget', () {
    test('schemas under default budget generate normally', () {
      final result = GbnfBuilder.build({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name'],
      });

      expect(result.grammar, contains('root ::='));
      expect(result.budgetExceeded, isFalse);
    });

    test('schema exceeding budget degrades to value', () {
      // Use a very small budget to trigger degradation
      final result = GbnfBuilder.build(
        {
          'type': 'object',
          'properties': {
            'a': {'type': 'string'},
            'b': {'type': 'string'},
            'c': {'type': 'string'},
            'd': {'type': 'string'},
            'e': {'type': 'string'},
          },
          'required': ['a', 'b', 'c', 'd', 'e'],
        },
        maxRules: 3,
      );

      // Should still produce valid grammar
      expect(result.grammar, contains('root ::='));
      // Budget should be exceeded
      expect(result.budgetExceeded, isTrue);
    });

    test('budgetExceeded getter returns true when budget hit', () {
      final result = GbnfBuilder.build(
        {
          'type': 'object',
          'properties': {
            'x': {
              'type': 'object',
              'properties': {
                'y': {
                  'type': 'object',
                  'properties': {
                    'z': {'type': 'string'},
                  },
                },
              },
            },
          },
        },
        maxRules: 2,
      );

      expect(result.budgetExceeded, isTrue);
    });

    test('custom budget via maxRules parameter', () {
      final resultLow = GbnfBuilder.build(
        {
          'type': 'object',
          'properties': {
            'a': {'type': 'string'},
            'b': {'type': 'string'},
          },
          'required': ['a', 'b'],
        },
        maxRules: 2,
      );

      final resultHigh = GbnfBuilder.build(
        {
          'type': 'object',
          'properties': {
            'a': {'type': 'string'},
            'b': {'type': 'string'},
          },
          'required': ['a', 'b'],
        },
        maxRules: 500,
      );

      expect(resultLow.budgetExceeded, isTrue);
      expect(resultHigh.budgetExceeded, isFalse);
    });

    test('budget of 0 degrades entire schema to value', () {
      final result = GbnfBuilder.build(
        {'type': 'string'},
        maxRules: 0,
      );

      expect(result.grammar, contains('root ::= value'));
      expect(result.budgetExceeded, isTrue);
    });

    test('fromJsonSchema still works unchanged (backward compatible)', () {
      // The original static method should still return a String
      final grammar = GbnfBuilder.fromJsonSchema({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'required': ['name'],
      });

      expect(grammar, isA<String>());
      expect(grammar, contains('root ::='));
    });

    test('fromJsonSchema accepts optional maxRules', () {
      final grammar = GbnfBuilder.fromJsonSchema(
        {
          'type': 'object',
          'properties': {
            'a': {'type': 'string'},
            'b': {'type': 'string'},
          },
          'required': ['a', 'b'],
        },
        maxRules: 500,
      );

      expect(grammar, isA<String>());
      expect(grammar, contains('root ::='));
    });
  });
}
