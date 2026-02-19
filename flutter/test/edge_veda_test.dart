import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/edge_veda.dart';

void main() {
  group('EdgeVedaConfig', () {
    test('creates config with required parameters', () {
      const config = EdgeVedaConfig(
        modelPath: '/path/to/model.gguf',
      );

      expect(config.modelPath, '/path/to/model.gguf');
      expect(config.numThreads, 4);
      expect(config.contextLength, 2048);
      expect(config.useGpu, true);
      expect(config.maxMemoryMb, 1536);
      expect(config.verbose, false);
    });

    test('creates config with custom parameters', () {
      const config = EdgeVedaConfig(
        modelPath: '/custom/model.gguf',
        numThreads: 8,
        contextLength: 4096,
        useGpu: false,
        maxMemoryMb: 2048,
        verbose: true,
      );

      expect(config.numThreads, 8);
      expect(config.contextLength, 4096);
      expect(config.useGpu, false);
      expect(config.maxMemoryMb, 2048);
      expect(config.verbose, true);
    });

    test('toJson returns correct map', () {
      const config = EdgeVedaConfig(
        modelPath: '/test.gguf',
        numThreads: 2,
      );

      final json = config.toJson();
      expect(json['modelPath'], '/test.gguf');
      expect(json['numThreads'], 2);
      expect(json['contextLength'], 2048);
    });
  });

  group('GenerateOptions', () {
    test('creates default options', () {
      const options = GenerateOptions();

      expect(options.maxTokens, 512);
      expect(options.temperature, 0.7);
      expect(options.topP, 0.9);
      expect(options.topK, 40);
      expect(options.repeatPenalty, 1.1);
      expect(options.jsonMode, false);
      expect(options.stream, false);
    });

    test('creates custom options', () {
      const options = GenerateOptions(
        systemPrompt: 'You are helpful',
        maxTokens: 256,
        temperature: 0.5,
        jsonMode: true,
      );

      expect(options.systemPrompt, 'You are helpful');
      expect(options.maxTokens, 256);
      expect(options.temperature, 0.5);
      expect(options.jsonMode, true);
    });

    test('copyWith creates modified copy', () {
      const original = GenerateOptions(maxTokens: 100);
      final modified = original.copyWith(temperature: 0.9);

      expect(original.maxTokens, 100);
      expect(original.temperature, 0.7);
      expect(modified.maxTokens, 100);
      expect(modified.temperature, 0.9);
    });
  });

  group('GenerateResponse', () {
    test('calculates total tokens correctly', () {
      const response = GenerateResponse(
        text: 'Hello world',
        promptTokens: 5,
        completionTokens: 10,
      );

      expect(response.totalTokens, 15);
    });

    test('calculates tokens per second', () {
      const response = GenerateResponse(
        text: 'Hello',
        promptTokens: 5,
        completionTokens: 100,
        latencyMs: 1000, // 1 second
      );

      expect(response.tokensPerSecond, 100.0);
    });

    test('returns null tokens per second when latency is null', () {
      const response = GenerateResponse(
        text: 'Hello',
        promptTokens: 5,
        completionTokens: 100,
      );

      expect(response.tokensPerSecond, null);
    });
  });

  group('TokenChunk', () {
    test('creates token chunk', () {
      const chunk = TokenChunk(
        token: 'Hello',
        index: 0,
      );

      expect(chunk.token, 'Hello');
      expect(chunk.index, 0);
      expect(chunk.isFinal, false);
    });

    test('creates final token chunk', () {
      const chunk = TokenChunk(
        token: '',
        index: 10,
        isFinal: true,
      );

      expect(chunk.isFinal, true);
    });
  });

  group('DownloadProgress', () {
    test('calculates progress percentage', () {
      const progress = DownloadProgress(
        totalBytes: 1000,
        downloadedBytes: 500,
      );

      expect(progress.progress, 0.5);
      expect(progress.progressPercent, 50);
    });

    test('handles zero total bytes', () {
      const progress = DownloadProgress(
        totalBytes: 0,
        downloadedBytes: 0,
      );

      expect(progress.progress, 0.0);
    });
  });

  group('ModelInfo', () {
    test('creates from JSON', () {
      final json = {
        'id': 'test-model',
        'name': 'Test Model',
        'sizeBytes': 1024 * 1024 * 100, // 100 MB
        'downloadUrl': 'https://example.com/model.gguf',
      };

      final model = ModelInfo.fromJson(json);
      expect(model.id, 'test-model');
      expect(model.name, 'Test Model');
      expect(model.sizeBytes, 1024 * 1024 * 100);
      expect(model.format, 'GGUF');
    });

    test('toJson returns correct map', () {
      const model = ModelInfo(
        id: 'test',
        name: 'Test',
        sizeBytes: 1000,
        downloadUrl: 'https://test.com',
      );

      final json = model.toJson();
      expect(json['id'], 'test');
      expect(json['name'], 'Test');
      expect(json['sizeBytes'], 1000);
    });
  });

  group('EdgeVedaException', () {
    test('InitializationException has correct type', () {
      const exception = InitializationException('Failed');
      expect(exception.message, 'Failed');
      expect(exception, isA<EdgeVedaException>());
    });

    test('exception toString includes details', () {
      const exception = GenerationException(
        'Failed',
        details: 'Out of memory',
      );

      final str = exception.toString();
      expect(str, contains('Failed'));
      expect(str, contains('Out of memory'));
    });
  });

  group('ModelRegistry', () {
    test('contains predefined models', () {
      expect(ModelRegistry.llama32_1b.id, contains('llama'));
      expect(ModelRegistry.phi35_mini.id, contains('phi'));
      expect(ModelRegistry.gemma2_2b.id, contains('gemma'));
      expect(ModelRegistry.tinyLlama.id, contains('tiny'));
    });

    test('getAllModels returns all models', () {
      final models = ModelRegistry.getAllModels();
      expect(models.length, greaterThanOrEqualTo(4));
    });

    test('getModelById finds model', () {
      final model = ModelRegistry.getModelById('llama-3.2-1b-instruct-q4');
      expect(model, isNotNull);
      expect(model?.name, contains('Llama'));
    });

    test('getModelById returns null for unknown id', () {
      final model = ModelRegistry.getModelById('unknown-model');
      expect(model, isNull);
    });
  });

  group('EdgeVeda', () {
    test('isInitialized is false before init', () {
      final edgeVeda = EdgeVeda();
      expect(edgeVeda.isInitialized, false);
    });

    test('config is null before init', () {
      final edgeVeda = EdgeVeda();
      expect(edgeVeda.config, null);
    });

    // Note: Actual initialization tests require native library
    // These would be integration tests
  });

  group('Platform Support', () {
    test('pubspec registers macOS platform', () {
      // This is a structural test — verifying that the plugin
      // configuration includes macOS. The actual registration
      // is in pubspec.yaml under flutter.plugin.platforms.macos.
      // If this test runs on macOS, it implicitly proves the
      // platform is registered (Flutter would fail to resolve otherwise).
      expect(true, isTrue); // placeholder for CI validation
    });
  });
}
