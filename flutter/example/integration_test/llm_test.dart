/// DTEST-01: Integration test — LLM end-to-end text generation
///
/// Loads a tiny LLM model (TinyLlama or Qwen3-0.6B) and verifies that
/// streaming text generation produces non-empty tokens.
///
/// Run: flutter test integration_test/llm_test.dart -d <device>
library;

import 'package:edge_veda/edge_veda.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:edge_veda_example/model_selector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ModelManager modelManager;

  setUpAll(() {
    modelManager = ModelManager();
  });

  testWidgets('LLM generates non-empty streaming output', (tester) async {
    // Select best available LLM (downloads if needed)
    final selection = await ModelSelector.bestLlm(modelManager);
    if (selection.needsDownload) {
      await modelManager.downloadModel(selection.model);
    }
    final modelPath = await modelManager.getModelPath(selection.model.id);

    // Spawn and initialize worker
    final worker = StreamingWorker();
    await worker.spawn();
    final useGpu = await InferenceConfig.useGpu();
    await worker.init(
      modelPath: modelPath,
      numThreads: 2,
      contextSize: 2048,
      useGpu: useGpu,
    );

    expect(worker.isActive, isTrue);

    // Start streaming with a simple prompt
    await worker.startStream(
      prompt: 'Hello, how are you?',
      maxTokens: 20,
      temperature: 0.7,
    );

    // Collect tokens
    final tokens = <String>[];
    while (true) {
      final tok = await worker.nextToken();
      if (tok.isFinal) break;
      if (tok.token != null) tokens.add(tok.token!);
    }

    expect(tokens, isNotEmpty, reason: 'LLM should produce at least 1 token');
    expect(tokens.join(), isNotEmpty,
        reason: 'Concatenated output should be non-empty');

    await worker.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
