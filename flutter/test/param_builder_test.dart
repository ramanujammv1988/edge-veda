import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/param_builder.dart';

void main() {
  group('Param.string', () {
    test('produces minimal string schema', () {
      final schema = Param.string().toJsonSchema();
      expect(schema, {'type': 'string'});
    });

    test('includes description when provided', () {
      final schema = Param.string(description: 'A city name').toJsonSchema();
      expect(schema['type'], 'string');
      expect(schema['description'], 'A city name');
    });

    test('includes enum when enumValues provided', () {
      final schema =
          Param.string(enumValues: ['celsius', 'fahrenheit']).toJsonSchema();
      expect(schema['type'], 'string');
      expect(schema['enum'], ['celsius', 'fahrenheit']);
    });

    test('includes both description and enum', () {
      final schema =
          Param.string(
            description: 'Temperature unit',
            enumValues: ['celsius', 'fahrenheit'],
          ).toJsonSchema();
      expect(schema['type'], 'string');
      expect(schema['description'], 'Temperature unit');
      expect(schema['enum'], ['celsius', 'fahrenheit']);
    });
  });

  group('Param.integer', () {
    test('produces minimal integer schema', () {
      final schema = Param.integer().toJsonSchema();
      expect(schema, {'type': 'integer'});
    });

    test('includes minimum and maximum when provided', () {
      final schema =
          Param.integer(
            description: 'Age',
            minimum: 0,
            maximum: 150,
          ).toJsonSchema();
      expect(schema['type'], 'integer');
      expect(schema['description'], 'Age');
      expect(schema['minimum'], 0);
      expect(schema['maximum'], 150);
    });

    test('includes only minimum when maximum is null', () {
      final schema = Param.integer(minimum: 1).toJsonSchema();
      expect(schema['minimum'], 1);
      expect(schema.containsKey('maximum'), false);
    });
  });

  group('Param.number', () {
    test('produces minimal number schema', () {
      final schema = Param.number().toJsonSchema();
      expect(schema, {'type': 'number'});
    });

    test('includes minimum and maximum when provided', () {
      final schema =
          Param.number(
            description: 'Temperature',
            minimum: -273.15,
            maximum: 1000,
          ).toJsonSchema();
      expect(schema['type'], 'number');
      expect(schema['description'], 'Temperature');
      expect(schema['minimum'], -273.15);
      expect(schema['maximum'], 1000);
    });
  });

  group('Param.boolean', () {
    test('produces minimal boolean schema', () {
      final schema = Param.boolean().toJsonSchema();
      expect(schema, {'type': 'boolean'});
    });

    test('includes description when provided', () {
      final schema =
          Param.boolean(
            description: 'Whether to include details',
          ).toJsonSchema();
      expect(schema['type'], 'boolean');
      expect(schema['description'], 'Whether to include details');
    });
  });

  group('Param.array', () {
    test('produces array schema with items', () {
      final schema = Param.array(items: Param.string()).toJsonSchema();
      expect(schema['type'], 'array');
      expect(schema['items'], {'type': 'string'});
    });

    test('includes minItems and maxItems when provided', () {
      final schema =
          Param.array(
            items: Param.integer(),
            description: 'List of scores',
            minItems: 1,
            maxItems: 10,
          ).toJsonSchema();
      expect(schema['type'], 'array');
      expect(schema['items'], {'type': 'integer'});
      expect(schema['description'], 'List of scores');
      expect(schema['minItems'], 1);
      expect(schema['maxItems'], 10);
    });

    test('omits minItems and maxItems when null', () {
      final schema = Param.array(items: Param.string()).toJsonSchema();
      expect(schema.containsKey('minItems'), false);
      expect(schema.containsKey('maxItems'), false);
    });
  });

  group('Param.object', () {
    test('produces object schema with properties', () {
      final schema =
          Param.object({
            'name': Param.string(description: 'User name'),
            'age': Param.integer(),
          }).toJsonSchema();

      expect(schema['type'], 'object');
      final props = schema['properties'] as Map<String, dynamic>;
      expect(props['name'], {'type': 'string', 'description': 'User name'});
      expect(props['age'], {'type': 'integer'});
    });

    test('includes required list when provided', () {
      final schema =
          Param.object(
            {'name': Param.string(), 'age': Param.integer()},
            required: ['name'],
          ).toJsonSchema();

      expect(schema['required'], ['name']);
    });

    test('omits required when null', () {
      final schema = Param.object({'name': Param.string()}).toJsonSchema();
      expect(schema.containsKey('required'), false);
    });

    test('omits required when empty list', () {
      final schema =
          Param.object({'name': Param.string()}, required: []).toJsonSchema();
      expect(schema.containsKey('required'), false);
    });

    test('includes description when provided', () {
      final schema =
          Param.object({
            'x': Param.number(),
          }, description: 'Coordinate object').toJsonSchema();
      expect(schema['description'], 'Coordinate object');
    });
  });

  group('Nested schemas', () {
    test('nested object inside object produces correct deep schema', () {
      final schema =
          Param.object(
            {
              'address': Param.object(
                {
                  'street': Param.string(description: 'Street address'),
                  'city': Param.string(description: 'City name'),
                  'zip': Param.string(),
                },
                required: ['street', 'city'],
              ),
              'name': Param.string(),
            },
            required: ['name', 'address'],
          ).toJsonSchema();

      expect(schema['type'], 'object');
      expect(schema['required'], ['name', 'address']);

      final props = schema['properties'] as Map<String, dynamic>;
      final address = props['address'] as Map<String, dynamic>;
      expect(address['type'], 'object');
      expect(address['required'], ['street', 'city']);

      final addressProps = address['properties'] as Map<String, dynamic>;
      expect(addressProps['street'], {
        'type': 'string',
        'description': 'Street address',
      });
      expect(addressProps['city'], {
        'type': 'string',
        'description': 'City name',
      });
      expect(addressProps['zip'], {'type': 'string'});
    });

    test('array of objects produces correct nested schema', () {
      final schema =
          Param.array(
            items: Param.object(
              {'id': Param.integer(), 'label': Param.string()},
              required: ['id'],
            ),
          ).toJsonSchema();

      expect(schema['type'], 'array');
      final items = schema['items'] as Map<String, dynamic>;
      expect(items['type'], 'object');
      expect(items['required'], ['id']);
      final itemProps = items['properties'] as Map<String, dynamic>;
      expect(itemProps['id'], {'type': 'integer'});
      expect(itemProps['label'], {'type': 'string'});
    });
  });

  group('Schema minimality', () {
    test('optional fields are omitted when null', () {
      final stringSchema = Param.string().toJsonSchema();
      expect(stringSchema.length, 1); // only 'type'
      expect(stringSchema.containsKey('description'), false);
      expect(stringSchema.containsKey('enum'), false);

      final intSchema = Param.integer().toJsonSchema();
      expect(intSchema.length, 1);
      expect(intSchema.containsKey('minimum'), false);
      expect(intSchema.containsKey('maximum'), false);

      final numSchema = Param.number().toJsonSchema();
      expect(numSchema.length, 1);

      final boolSchema = Param.boolean().toJsonSchema();
      expect(boolSchema.length, 1);
    });

    test('toJsonSchema returns unmodifiable map', () {
      final schema = Param.string().toJsonSchema();
      expect(() => schema['extra'] = 'value', throwsA(isA<UnsupportedError>()));
    });
  });
}
