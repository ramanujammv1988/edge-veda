import 'package:edge_veda/src/chat_types.dart';
import 'package:edge_veda/src/jinja_chat_template.dart';
import 'package:test/test.dart';

/// Real Llama 3 Instruct Jinja2 template from GGUF metadata.
const _llama3Template =
    '{% set loop_messages = messages %}'
    '{% for message in loop_messages %}'
    "{% set content = '<|start_header_id|>' + message['role'] + "
    "'<|end_header_id|>\n\n' + message['content'] | trim + '<|eot_id|>' %}"
    '{% if loop.first %}{% set content = bos_token + content %}{% endif %}'
    '{{ content }}'
    '{% endfor %}'
    '{% if add_generation_prompt %}'
    "{{ '<|start_header_id|>assistant<|end_header_id|>\n\n' }}"
    '{% endif %}';

/// Standard ChatML template used by many open models.
const _chatMLTemplate =
    '{% for message in messages %}'
    "{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}"
    '{% endfor %}'
    '{% if add_generation_prompt %}'
    "{{'<|im_start|>assistant\n'}}"
    '{% endif %}';

/// Simplified tool-aware template inspired by Qwen3-style patterns.
/// Checks for a `tools` variable and renders tool definitions before the
/// conversation when present.
const _toolAwareTemplate =
    '{% if tools is defined and tools %}'
    '<|im_start|>system\n'
    'You have access to the following tools:\n'
    '{% for tool in tools %}'
    "- {{ tool['function']['name'] }}: {{ tool['function']['description'] }}\n"
    '{% endfor %}'
    '<|im_end|>\n'
    '{% endif %}'
    '{% for message in messages %}'
    "{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}"
    '{% endfor %}'
    '{% if add_generation_prompt %}'
    "{{'<|im_start|>assistant\n'}}"
    '{% endif %}';

void main() {
  group('Llama 3 Instruct template', () {
    late JinjaChatTemplate tmpl;

    setUp(() {
      tmpl = JinjaChatTemplate(_llama3Template);
    });

    test('system + user message produces correct Llama 3 format', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hello!',
            timestamp: DateTime.now(),
          ),
        ],
        systemPrompt: 'You are helpful.',
      );

      expect(
        result,
        equals(
          '<|start_header_id|>system<|end_header_id|>\n\n'
          'You are helpful.<|eot_id|>'
          '<|start_header_id|>user<|end_header_id|>\n\n'
          'Hello!<|eot_id|>'
          '<|start_header_id|>assistant<|end_header_id|>\n\n',
        ),
      );
    });

    test('multi-turn conversation produces correct format', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hi',
            timestamp: DateTime.now(),
          ),
          ChatMessage(
            role: ChatRole.assistant,
            content: 'Hello! How can I help?',
            timestamp: DateTime.now(),
          ),
          ChatMessage(
            role: ChatRole.user,
            content: 'Tell me a joke.',
            timestamp: DateTime.now(),
          ),
        ],
        systemPrompt: 'You are helpful.',
      );

      expect(result, contains('<|start_header_id|>system<|end_header_id|>'));
      expect(
        result,
        contains(
          'Hi<|eot_id|>'
          '<|start_header_id|>assistant<|end_header_id|>\n\n'
          'Hello! How can I help?<|eot_id|>',
        ),
      );
      expect(
        result,
        endsWith('<|start_header_id|>assistant<|end_header_id|>\n\n'),
      );
    });

    test('no system prompt still works', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hello!',
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(
        result,
        equals(
          '<|start_header_id|>user<|end_header_id|>\n\n'
          'Hello!<|eot_id|>'
          '<|start_header_id|>assistant<|end_header_id|>\n\n',
        ),
      );
    });

    test('bos_token is injected when provided', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hello!',
            timestamp: DateTime.now(),
          ),
        ],
        bosToken: '<s>',
      );

      expect(result, startsWith('<s><|start_header_id|>'));
    });
  });

  group('ChatML template', () {
    late JinjaChatTemplate tmpl;

    setUp(() {
      tmpl = JinjaChatTemplate(_chatMLTemplate);
    });

    test('produces correct im_start/im_end format', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hi',
            timestamp: DateTime.now(),
          ),
        ],
        systemPrompt: 'You are helpful.',
      );

      expect(
        result,
        equals(
          '<|im_start|>system\n'
          'You are helpful.<|im_end|>\n'
          '<|im_start|>user\n'
          'Hi<|im_end|>\n'
          '<|im_start|>assistant\n',
        ),
      );
    });

    test('add_generation_prompt=false omits final assistant marker', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hi',
            timestamp: DateTime.now(),
          ),
        ],
        systemPrompt: 'You are helpful.',
        addGenerationPrompt: false,
      );

      expect(result, isNot(contains('<|im_start|>assistant')));
      expect(result, endsWith('<|im_end|>\n'));
    });
  });

  group('Tool injection', () {
    late JinjaChatTemplate tmpl;

    setUp(() {
      tmpl = JinjaChatTemplate(_toolAwareTemplate);
    });

    test('tools list appears in rendered output', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'What is the weather?',
            timestamp: DateTime.now(),
          ),
        ],
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'get_weather',
              'description': 'Get current weather for a location',
            },
          },
        ],
      );

      expect(result, contains('get_weather'));
      expect(result, contains('Get current weather for a location'));
      expect(result, contains('<|im_start|>user'));
    });

    test('no tools renders without error', () {
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hello',
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(result, isNot(contains('tools')));
      expect(result, contains('<|im_start|>user'));
    });
  });

  group('Edge cases', () {
    test('empty messages list', () {
      final tmpl = JinjaChatTemplate(_chatMLTemplate);
      final result = tmpl.format(messages: []);

      // With no messages and add_generation_prompt=true, just the assistant
      // prompt marker should appear.
      expect(result, equals('<|im_start|>assistant\n'));
    });

    test('message with empty content', () {
      final tmpl = JinjaChatTemplate(_chatMLTemplate);
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: '',
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(result, contains('<|im_start|>user\n<|im_end|>'));
    });

    test('template with set variable assignments', () {
      const templateWithSet =
          "{% set greeting = 'Hello' %}"
          "{{ greeting }} {{ messages[0]['content'] }}";

      final tmpl = JinjaChatTemplate(templateWithSet);
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'World',
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(result, equals('Hello World'));
    });

    test('bos_token and eos_token are injected into template output', () {
      // Template that explicitly uses bos_token and eos_token
      const tokenTemplate =
          '{{ bos_token }}'
          '{% for message in messages %}'
          "{{ message['content'] }}"
          '{% endfor %}'
          '{{ eos_token }}';

      final tmpl = JinjaChatTemplate(tokenTemplate);
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            content: 'Hi',
            timestamp: DateTime.now(),
          ),
        ],
        bosToken: '<s>',
        eosToken: '</s>',
      );

      expect(result, startsWith('<s>'));
      expect(result, endsWith('</s>'));
      expect(result, equals('<s>Hi</s>'));
    });

    test('ChatRole.toolCall maps to assistant role', () {
      final tmpl = JinjaChatTemplate(_chatMLTemplate);
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.toolCall,
            content: '{"name": "get_weather"}',
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(result, contains('<|im_start|>assistant'));
    });

    test('ChatRole.toolResult maps to tool role', () {
      final tmpl = JinjaChatTemplate(_chatMLTemplate);
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.toolResult,
            content: '{"temperature": 72}',
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(result, contains('<|im_start|>tool'));
    });

    test('ChatRole.summary maps to system role', () {
      final tmpl = JinjaChatTemplate(_chatMLTemplate);
      final result = tmpl.format(
        messages: [
          ChatMessage(
            role: ChatRole.summary,
            content: 'Previous conversation about weather.',
            timestamp: DateTime.now(),
          ),
        ],
      );

      expect(result, contains('<|im_start|>system'));
    });
  });

  group('Error handling', () {
    test('invalid template string throws at construction time', () {
      expect(() => JinjaChatTemplate('{% if %}'), throwsA(isA<Exception>()));
    });

    test('template calling raise_exception produces a Dart exception', () {
      final tmpl = JinjaChatTemplate(
        "{{ raise_exception('feature not supported') }}",
      );

      expect(() => tmpl.format(messages: []), throwsA(isA<Exception>()));
    });
  });
}
