/// DTEST-02: Integration test — Vision end-to-end image description
///
/// Loads a vision model (SmolVLM2 + mmproj) and verifies that
/// describeFrame() produces a non-empty text description from a
/// synthetic test image.
///
/// Run: flutter test integration_test/vision_test.dart -d <device>
library;

import 'dart:typed_data';

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

  testWidgets('Vision describes a synthetic image', (tester) async {
    // Select best available vision model (downloads if needed)
    final selection = await ModelSelector.bestVision(modelManager);
    if (selection.needsDownload) {
      await modelManager.downloadModel(selection.model);
      if (selection.mmproj != null) {
        await modelManager.downloadModel(selection.mmproj!);
      }
    }
    final modelPath = await modelManager.getModelPath(selection.model.id);
    final mmprojPath = selection.mmproj != null
        ? await modelManager.getModelPath(selection.mmproj!.id)
        : modelPath;

    // Spawn and initialize vision worker
    final worker = VisionWorker();
    await worker.spawn();
    final useGpu = await InferenceConfig.useGpu();
    await worker.initVision(
      modelPath: modelPath,
      mmprojPath: mmprojPath,
      numThreads: 2,
      contextSize: 512,
      useGpu: useGpu,
    );

    // Create a simple 64x64 red-gradient test image (RGB)
    const width = 64;
    const height = 64;
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 3;
        rgb[i] = (x * 4).clamp(0, 255); // R gradient
        rgb[i + 1] = (y * 4).clamp(0, 255); // G gradient
        rgb[i + 2] = 128; // B constant
      }
    }

    // Describe the frame
    final result = await worker.describeFrame(
      rgb,
      width,
      height,
      prompt: 'Describe what you see.',
      maxTokens: 30,
    );

    expect(result.description, isNotEmpty,
        reason: 'Vision should produce a description');
    expect(result.generatedTokens, greaterThan(0),
        reason: 'Should generate at least 1 token');

    await worker.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
