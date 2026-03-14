import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/edge_veda.dart';

void main() {
  group('Export verification', () {
    test('Tool, Param, ParamSchema are importable from edge_veda.dart', () {
      // If this compiles and runs, the exports work.
      final schema = Param.object(
        {'city': Param.string(description: 'City name')},
        required: ['city'],
      );

      final tool = Tool(
        name: 'test_tool',
        description: 'A test tool',
        parameters: schema,
        handler: (args) async => {'ok': true},
      );

      expect(tool.name, 'test_tool');
      expect(schema, isA<ParamSchema>());
    });
  });

  group('Param -> ToolDefinition -> GbnfBuilder integration', () {
    test('single-tool schema produces valid GBNF with tool name', () {
      final tool = Tool(
        name: 'get_weather',
        description: 'Get weather info',
        parameters: Param.object(
          {
            'location': Param.string(description: 'City name'),
            'unit': Param.string(enumValues: ['celsius', 'fahrenheit']),
          },
          required: ['location'],
        ),
        handler: (args) async => {},
      );

      // Build schema the same way chat() does for a single tool
      final schema = {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'enum': [tool.name],
          },
          'arguments': tool.parameters.toJsonSchema(),
        },
        'required': ['name', 'arguments'],
      };

      final gbnf = GbnfBuilder.fromJsonSchema(schema);
      expect(gbnf, isNotEmpty);
      expect(gbnf, contains('root'));
      expect(gbnf, contains('get_weather'));
    });

    test('multi-tool schema produces GBNF with all tool names', () {
      final tools = [
        Tool(
          name: 'get_weather',
          description: 'Get weather',
          parameters: Param.object(
            {'location': Param.string()},
            required: ['location'],
          ),
          handler: (args) async => {},
        ),
        Tool(
          name: 'search_web',
          description: 'Search the web',
          parameters: Param.object(
            {'query': Param.string()},
            required: ['query'],
          ),
          handler: (args) async => {},
        ),
      ];

      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'enum': tools.map((t) => t.name).toList()},
          'arguments': {'type': 'object'},
        },
        'required': ['name', 'arguments'],
      };

      final gbnf = GbnfBuilder.fromJsonSchema(schema);
      expect(gbnf, isNotEmpty);
      expect(gbnf, contains('get_weather'));
      expect(gbnf, contains('search_web'));
    });

    test('complex nested Param flows through to valid GBNF', () {
      final tool = Tool(
        name: 'complex_tool',
        description: 'Complex tool',
        parameters: Param.object(
          {
            'query': Param.string(description: 'Search query'),
            'limit': Param.integer(minimum: 1, maximum: 100),
            'filters': Param.object({
              'category': Param.string(enumValues: ['a', 'b', 'c']),
              'active': Param.boolean(),
            }),
            'tags': Param.array(items: Param.string()),
          },
          required: ['query'],
        ),
        handler: (args) async => {},
      );

      final schema = {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'enum': [tool.name],
          },
          'arguments': tool.parameters.toJsonSchema(),
        },
        'required': ['name', 'arguments'],
      };

      final gbnf = GbnfBuilder.fromJsonSchema(schema);
      expect(gbnf, isNotEmpty);
      expect(gbnf, contains('root'));
      // Should have rules for nested object and array
      expect(gbnf, contains('obj'));
      expect(gbnf, contains('arr'));
    });
  });

  group('Gemma3 vs Qwen3 field naming', () {
    test('Gemma3 format uses "parameters" field name', () {
      final tool = Tool(
        name: 'my_tool',
        description: 'A tool',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {},
      );

      // Gemma3 schema uses 'parameters'
      final schema = {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'enum': [tool.name],
          },
          'parameters': tool.parameters.toJsonSchema(),
        },
        'required': ['name', 'parameters'],
      };

      final gbnf = GbnfBuilder.fromJsonSchema(schema);
      expect(gbnf, isNotEmpty);
      expect(gbnf, contains('parameters'));
    });

    test('Qwen3 format uses "arguments" field name', () {
      final tool = Tool(
        name: 'my_tool',
        description: 'A tool',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {},
      );

      // Qwen3 schema uses 'arguments'
      final schema = {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'enum': [tool.name],
          },
          'arguments': tool.parameters.toJsonSchema(),
        },
        'required': ['name', 'arguments'],
      };

      final gbnf = GbnfBuilder.fromJsonSchema(schema);
      expect(gbnf, isNotEmpty);
      expect(gbnf, contains('arguments'));
    });
  });

  group('Tool dispatch error handling', () {
    test('handler exception produces ToolResult.failure', () async {
      final failTool = Tool(
        name: 'fail_tool',
        description: 'Always fails',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async {
          throw Exception('Network timeout');
        },
      );

      final call = ToolCall(name: 'fail_tool', arguments: {'x': 'test'});
      final result = await failTool.execute(call);
      expect(result.isError, true);
      expect(result.error, contains('Network timeout'));
      expect(result.toolCallId, call.id);
    });

    test('successful handler produces ToolResult.success', () async {
      final okTool = Tool(
        name: 'ok_tool',
        description: 'Always succeeds',
        parameters: Param.object({'x': Param.string()}),
        handler: (args) async => {'result': args['x']},
      );

      final call = ToolCall(name: 'ok_tool', arguments: {'x': 'hello'});
      final result = await okTool.execute(call);
      expect(result.isError, false);
      expect(result.data!['result'], 'hello');
    });
  });

  group('ToolTemplate integration', () {
    test('Param-built definitions format into Qwen3 system prompt', () {
      final tool = Tool(
        name: 'get_weather',
        description: 'Get current weather',
        parameters: Param.object(
          {'location': Param.string(description: 'City name')},
          required: ['location'],
        ),
        handler: (args) async => {},
      );

      final def = tool.toDefinition();
      final prompt = ToolTemplate.formatToolSystemPrompt(
        format: ChatTemplateFormat.qwen3,
        tools: [def],
        systemPrompt: 'You are helpful.',
      );

      expect(prompt, contains('<tools>'));
      expect(prompt, contains('get_weather'));
      expect(prompt, contains('Get current weather'));
      expect(prompt, contains('You are helpful.'));
    });

    test('Param-built definitions format into Gemma3 system prompt', () {
      final tool = Tool(
        name: 'search',
        description: 'Search the web',
        parameters: Param.object(
          {'query': Param.string()},
          required: ['query'],
        ),
        handler: (args) async => {},
      );

      final def = tool.toDefinition();
      final prompt = ToolTemplate.formatToolSystemPrompt(
        format: ChatTemplateFormat.gemma3,
        tools: [def],
      );

      expect(prompt, contains('search'));
      expect(prompt, contains('Search the web'));
      expect(prompt, contains('"name"'));
    });

    test('parseToolCalls extracts Qwen3-style tool call', () {
      final output =
          '<tool_call>\n{"name": "get_weather", "arguments": {"location": "Tokyo"}}\n</tool_call>';
      final calls = ToolTemplate.parseToolCalls(
        format: ChatTemplateFormat.qwen3,
        output: output,
      );

      expect(calls, isNotNull);
      expect(calls!.length, 1);
      expect(calls.first.name, 'get_weather');
      expect(calls.first.arguments['location'], 'Tokyo');
    });

    test('parseToolCalls extracts Gemma3-style tool call', () {
      final output = '{"name": "search", "parameters": {"query": "flutter"}}';
      final calls = ToolTemplate.parseToolCalls(
        format: ChatTemplateFormat.gemma3,
        output: output,
      );

      expect(calls, isNotNull);
      expect(calls!.length, 1);
      expect(calls.first.name, 'search');
      expect(calls.first.arguments['query'], 'flutter');
    });
  });
}
