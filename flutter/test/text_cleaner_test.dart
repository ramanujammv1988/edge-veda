import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/text_cleaner.dart';

void main() {
  group('Llama 3 header blocks', () {
    test('strips full assistant header block completely (no orphaned text)', () {
      expect(
        TextCleaner.cleanResponseText(
            '<|start_header_id|>assistant<|end_header_id|>'),
        '',
      );
    });

    test('strips user role header block', () {
      expect(
        TextCleaner.cleanResponseText(
            '<|start_header_id|>user<|end_header_id|>'),
        '',
      );
    });

    test('strips system role header block', () {
      expect(
        TextCleaner.cleanResponseText(
            '<|start_header_id|>system<|end_header_id|>'),
        '',
      );
    });

    test('strips empty role header block', () {
      expect(
        TextCleaner.cleanResponseText(
            '<|start_header_id|><|end_header_id|>'),
        '',
      );
    });

    test('preserves text between header blocks', () {
      final result = TextCleaner.cleanResponseText(
          'Hello<|start_header_id|>assistant<|end_header_id|>World');
      expect(result, 'HelloWorld');
    });
  });

  group('Individual special tokens', () {
    test('strips <|eot_id|> from mid-text', () {
      expect(
        TextCleaner.cleanResponseText('Hello<|eot_id|> world'),
        'Hello world',
      );
    });

    test('strips <|im_end|>', () {
      expect(
        TextCleaner.cleanResponseText('Hello<|im_end|>'),
        'Hello',
      );
    });

    test('strips <|im_start|>', () {
      expect(
        TextCleaner.cleanResponseText('<|im_start|>Hello'),
        'Hello',
      );
    });

    test('strips <|begin_of_text|>', () {
      expect(
        TextCleaner.cleanResponseText('<|begin_of_text|>Hello'),
        'Hello',
      );
    });

    test('strips <|end_of_text|>', () {
      expect(
        TextCleaner.cleanResponseText('Hello<|end_of_text|>'),
        'Hello',
      );
    });

    test('strips <|finetune_right_pad|>', () {
      expect(
        TextCleaner.cleanResponseText('Hello<|finetune_right_pad|>'),
        'Hello',
      );
    });

    test('strips <|reserved_special_token_0|>', () {
      expect(
        TextCleaner.cleanResponseText('Hello<|reserved_special_token_0|>'),
        'Hello',
      );
    });

    test('strips multi-digit reserved token <|reserved_special_token_123|>',
        () {
      expect(
        TextCleaner.cleanResponseText(
            'Hello<|reserved_special_token_123|>'),
        'Hello',
      );
    });
  });

  group('ChatML role headers', () {
    test('strips <|im_start|>assistant with trailing newline', () {
      expect(
        TextCleaner.cleanResponseText('<|im_start|>assistant\nHello'),
        'Hello',
      );
    });

    test('strips <|im_start|>user with trailing newline', () {
      expect(
        TextCleaner.cleanResponseText('<|im_start|>user\nHello'),
        'Hello',
      );
    });

    test('strips <|im_start|>system with trailing newline', () {
      expect(
        TextCleaner.cleanResponseText('<|im_start|>system\nHello'),
        'Hello',
      );
    });

    test('strips <|im_start|> alone', () {
      expect(
        TextCleaner.cleanResponseText('<|im_start|>Hello'),
        'Hello',
      );
    });
  });

  group('Gemma turn markers', () {
    test('strips <start_of_turn>user with newline', () {
      expect(
        TextCleaner.cleanResponseText('<start_of_turn>user\nHello'),
        'Hello',
      );
    });

    test('strips <end_of_turn>', () {
      expect(
        TextCleaner.cleanResponseText('Hello<end_of_turn>'),
        'Hello',
      );
    });

    test('strips <start_of_turn>model with newline', () {
      expect(
        TextCleaner.cleanResponseText('<start_of_turn>model\nHello'),
        'Hello',
      );
    });
  });

  group('Mixed content', () {
    test('strips header block + trailing eot_id, preserves answer', () {
      final result = TextCleaner.cleanResponseText(
        '<|start_header_id|>assistant<|end_header_id|>\n\n'
        'Here is your answer.<|eot_id|>',
      );
      expect(result, 'Here is your answer.');
    });

    test('strips multiple tokens in one string', () {
      final result = TextCleaner.cleanResponseText(
        '<|im_start|>assistant\nHello<|im_end|><|eot_id|>',
      );
      expect(result, 'Hello');
    });

    test('nested/adjacent tags produce empty string', () {
      final result = TextCleaner.cleanResponseText(
        '<|eot_id|><|start_header_id|>assistant<|end_header_id|>',
      );
      expect(result, '');
    });
  });

  group('Edge cases', () {
    test('empty input returns empty', () {
      expect(TextCleaner.cleanResponseText(''), '');
    });

    test('already clean text passes through', () {
      expect(TextCleaner.cleanResponseText('Hello, world!'), 'Hello, world!');
    });

    test('only whitespace returns empty (trimmed)', () {
      expect(TextCleaner.cleanResponseText('   \n  \t  '), '');
    });

    test('only special tokens returns empty', () {
      expect(
        TextCleaner.cleanResponseText(
            '<|eot_id|><|im_end|><|begin_of_text|>'),
        '',
      );
    });

    test('excessive newlines collapsed to double', () {
      expect(
        TextCleaner.cleanResponseText('Hello\n\n\n\nWorld'),
        'Hello\n\nWorld',
      );
    });

    test('case insensitive: <|EOT_ID|> stripped', () {
      expect(
        TextCleaner.cleanResponseText('Hello<|EOT_ID|>'),
        'Hello',
      );
    });
  });
}
