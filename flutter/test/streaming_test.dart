import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/edge_veda.dart';

void main() {
  group('TokenChunk - Streaming Behavior', () {
    test('simulates token stream sequence', () {
      // Simulate a sequence of tokens like a real streaming response
      final chunks = [
        const TokenChunk(token: 'Hello', index: 0),
        const TokenChunk(token: ' world', index: 1),
        const TokenChunk(token: '!', index: 2),
        const TokenChunk(token: ' How', index: 3),
        const TokenChunk(token: ' are', index: 4),
        const TokenChunk(token: ' you', index: 5),
        const TokenChunk(token: '?', index: 6),
        const TokenChunk(token: '', index: 7, isFinal: true),
      ];

      // Verify sequence properties
      expect(chunks.length, 8);
      expect(chunks.first.index, 0);
      expect(chunks.last.isFinal, true);
      expect(chunks.last.token, '');

      // Verify intermediate chunks are not final
      for (int i = 0; i < chunks.length - 1; i++) {
        expect(chunks[i].isFinal, false);
      }
    });

    test('concatenates tokens to form complete response', () {
      final chunks = [
        const TokenChunk(token: 'The', index: 0),
        const TokenChunk(token: ' quick', index: 1),
        const TokenChunk(token: ' brown', index: 2),
        const TokenChunk(token: ' fox', index: 3),
        const TokenChunk(token: '', index: 4, isFinal: true),
      ];

      // Concatenate non-final tokens
      final completeText = chunks
          .where((chunk) => !chunk.isFinal)
          .map((chunk) => chunk.token)
          .join('');

      expect(completeText, 'The quick brown fox');
    });

    test('handles empty token chunks', () {
      const emptyChunk = TokenChunk(token: '', index: 0);

      expect(emptyChunk.token, '');
      expect(emptyChunk.index, 0);
      expect(emptyChunk.isFinal, false);
    });

    test('handles single token stream', () {
      const chunks = [
        TokenChunk(token: 'Hello', index: 0),
        TokenChunk(token: '', index: 1, isFinal: true),
      ];

      expect(chunks[0].token, 'Hello');
      expect(chunks[1].isFinal, true);
    });

    test('detects final chunk correctly', () {
      const notFinal = TokenChunk(token: 'text', index: 0);
      const isFinal = TokenChunk(token: '', index: 1, isFinal: true);

      expect(notFinal.isFinal, false);
      expect(isFinal.isFinal, true);
    });
  });

  group('GenerateOptions - Stream Mode', () {
    test('stream property defaults to false', () {
      const options = GenerateOptions();
      expect(options.stream, false);
    });

    test('stream property can be set to true', () {
      const options = GenerateOptions(stream: true);
      expect(options.stream, true);
    });

    test('copyWith preserves stream setting', () {
      const original = GenerateOptions(stream: true, maxTokens: 100);
      final modified = original.copyWith(temperature: 0.8);

      expect(original.stream, true);
      expect(modified.stream, true);
      expect(modified.temperature, 0.8);
      expect(modified.maxTokens, 100);
    });

    test('copyWith can change stream setting', () {
      const original = GenerateOptions(stream: false);
      final modified = original.copyWith(stream: true);

      expect(original.stream, false);
      expect(modified.stream, true);
    });

    test('toJson includes stream flag', () {
      const streamingOptions = GenerateOptions(stream: true);
      const nonStreamingOptions = GenerateOptions(stream: false);

      final streamingJson = streamingOptions.toJson();
      final nonStreamingJson = nonStreamingOptions.toJson();

      expect(streamingJson['stream'], true);
      expect(nonStreamingJson['stream'], false);
    });

    test('stream mode with other options', () {
      const options = GenerateOptions(
        stream: true,
        maxTokens: 256,
        temperature: 0.9,
        topP: 0.95,
        systemPrompt: 'You are helpful',
      );

      expect(options.stream, true);
      expect(options.maxTokens, 256);
      expect(options.temperature, 0.9);
      expect(options.topP, 0.95);
      expect(options.systemPrompt, 'You are helpful');
    });
  });

  group('GenerateResponse - Edge Cases', () {
    test('handles zero latency gracefully', () {
      const response = GenerateResponse(
        text: 'Hello',
        promptTokens: 5,
        completionTokens: 100,
        latencyMs: 0,
      );

      // Division by zero should be handled
      // Expect null or infinity depending on implementation
      final tps = response.tokensPerSecond;
      expect(tps == null || tps.isInfinite || tps.isNaN, true);
    });

    test('handles very large token counts', () {
      const response = GenerateResponse(
        text: 'Long response',
        promptTokens: 1000000,
        completionTokens: 5000000,
        latencyMs: 10000,
      );

      expect(response.totalTokens, 6000000);
      expect(response.tokensPerSecond, 500000.0);
    });

    test('handles empty text response', () {
      const response = GenerateResponse(
        text: '',
        promptTokens: 10,
        completionTokens: 0,
      );

      expect(response.text, '');
      expect(response.totalTokens, 10);
      expect(response.completionTokens, 0);
    });

    test('calculates tokens per second with millisecond precision', () {
      const response = GenerateResponse(
        text: 'Test',
        promptTokens: 5,
        completionTokens: 500,
        latencyMs: 2500, // 2.5 seconds
      );

      expect(response.tokensPerSecond, 200.0);
    });

    test('handles null latency', () {
      const response = GenerateResponse(
        text: 'Hello',
        promptTokens: 5,
        completionTokens: 100,
      );

      expect(response.latencyMs, null);
      expect(response.tokensPerSecond, null);
    });

    test('very fast response calculation', () {
      const response = GenerateResponse(
        text: 'Quick',
        promptTokens: 5,
        completionTokens: 10,
        latencyMs: 10, // 10ms
      );

      expect(response.tokensPerSecond, 1000.0);
    });
  });
}
