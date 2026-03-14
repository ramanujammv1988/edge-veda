import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/param_builder.dart';
import 'package:edge_veda/src/tool.dart';
import 'package:edge_veda/src/tool_types.dart';
import 'package:edge_veda/src/types.dart';

void main() {
  late Tool weatherTool;

  setUp(() {
    weatherTool = Tool(
      name: 'get_weather',
      description: 'Get current weather for a location',
      parameters: Param.object({
        'location': Param.string(description: 'City name'),
        'unit': Param.string(
          description: 'Temperature unit',
          enumValues: ['celsius', 'fahrenheit'],
        ),
      }, required: ['location']),
      handler: (args) async {
        final city = args['location'] as String;
        final unit = args['unit'] as String? ?? 'celsius';
        return {'temperature': 22, 'unit': unit, 'city': city};
      },
    );
  });

  group('Tool construction', () {
    test('stores all fields correctly', () {
      expect(weatherTool.name, 'get_weather');
      expect(weatherTool.description, 'Get current weather for a location');
      expect(weatherTool.priority, ToolPriority.required);
    });

    test('default priority is required', () {
      final tool = Tool(
        name: 'test_tool',
        description: 'A test tool',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {'ok': true},
      );
      expect(tool.priority, ToolPriority.required);
    });

    test('accepts optional priority', () {
      final tool = Tool(
        name: 'optional_tool',
        description: 'An optional tool',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {'ok': true},
        priority: ToolPriority.optional,
      );
      expect(tool.priority, ToolPriority.optional);
    });
  });

  group('toDefinition', () {
    test('produces valid ToolDefinition with correct fields', () {
      final def = weatherTool.toDefinition();
      expect(def.name, 'get_weather');
      expect(def.description, 'Get current weather for a location');
      expect(def.parameters['type'], 'object');

      final props = def.parameters['properties'] as Map<String, dynamic>;
      expect(props.containsKey('location'), true);
      expect(props.containsKey('unit'), true);
      expect(def.parameters['required'], ['location']);
    });

    test('preserves priority', () {
      final optTool = Tool(
        name: 'opt_tool',
        description: 'Optional tool',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {},
        priority: ToolPriority.optional,
      );
      final def = optTool.toDefinition();
      expect(def.priority, ToolPriority.optional);
    });

    test('throws on invalid name via ToolDefinition validation', () {
      final badTool = Tool(
        name: '123invalid',
        description: 'Bad name',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {},
      );
      expect(() => badTool.toDefinition(), throwsA(isA<ConfigurationException>()));
    });

    test('throws on empty description via ToolDefinition validation', () {
      final badTool = Tool(
        name: 'good_name',
        description: '',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {},
      );
      expect(() => badTool.toDefinition(), throwsA(isA<ConfigurationException>()));
    });
  });

  group('execute', () {
    test('calls handler with correct arguments and returns success', () async {
      final call = ToolCall(
        name: 'get_weather',
        arguments: {'location': 'London', 'unit': 'celsius'},
      );
      final result = await weatherTool.execute(call);
      expect(result.isError, false);
      expect(result.data!['city'], 'London');
      expect(result.data!['temperature'], 22);
      expect(result.data!['unit'], 'celsius');
      expect(result.toolCallId, call.id);
    });

    test('catches handler exception and returns failure', () async {
      final failingTool = Tool(
        name: 'fail_tool',
        description: 'A tool that fails',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async {
          throw Exception('Something went wrong');
        },
      );
      final call = ToolCall(name: 'fail_tool', arguments: {'x': 'test'});
      final result = await failingTool.execute(call);
      expect(result.isError, true);
      expect(result.error, contains('Something went wrong'));
      expect(result.toolCallId, call.id);
    });

    test('catches non-Exception errors and returns failure', () async {
      final errorTool = Tool(
        name: 'error_tool',
        description: 'Throws a non-Exception',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async {
          throw StateError('bad state');
        },
      );
      final call = ToolCall(name: 'error_tool', arguments: {'x': 'test'});
      final result = await errorTool.execute(call);
      expect(result.isError, true);
      expect(result.error, contains('bad state'));
    });

    test('works with async handler that returns after delay', () async {
      final slowTool = Tool(
        name: 'slow_tool',
        description: 'Slow async tool',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return {'delayed': true};
        },
      );
      final call = ToolCall(name: 'slow_tool', arguments: {'x': 'test'});
      final result = await slowTool.execute(call);
      expect(result.isError, false);
      expect(result.data!['delayed'], true);
    });
  });

  group('round-trip', () {
    test('Param.object parameters round-trip through toDefinition', () {
      final tool = Tool(
        name: 'complex_tool',
        description: 'Tool with complex params',
        parameters: Param.object({
          'query': Param.string(description: 'Search query'),
          'limit': Param.integer(minimum: 1, maximum: 100),
          'filters': Param.object({
            'category': Param.string(enumValues: ['a', 'b', 'c']),
            'active': Param.boolean(),
          }),
        }, required: ['query']),
        handler: (args) async => {'results': []},
      );

      final def = tool.toDefinition();
      final params = def.parameters;

      expect(params['type'], 'object');
      expect(params['required'], ['query']);

      final props = params['properties'] as Map<String, dynamic>;
      expect(props['query']['type'], 'string');
      expect(props['query']['description'], 'Search query');
      expect(props['limit']['type'], 'integer');
      expect(props['limit']['minimum'], 1);
      expect(props['limit']['maximum'], 100);

      final filters = props['filters'] as Map<String, dynamic>;
      expect(filters['type'], 'object');
      final filterProps = filters['properties'] as Map<String, dynamic>;
      expect(filterProps['category']['enum'], ['a', 'b', 'c']);
      expect(filterProps['active']['type'], 'boolean');
    });
  });
}
