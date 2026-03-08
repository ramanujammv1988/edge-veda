/// DTEST-04: Integration test — Image Generation end-to-end
///
/// Loads an SD model (sd-v2-1-turbo) and verifies that generateImage()
/// produces pixel data with the expected dimensions.
///
/// Run: flutter test integration_test/imagegen_test.dart -d <device>
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

  testWidgets('ImageGen produces pixel data from a text prompt',
      (tester) async {
    // Select best available image gen model (downloads if needed)
    final selection = await ModelSelector.bestImageGen(modelManager);
    if (selection.needsDownload) {
      await modelManager.downloadModel(selection.model);
    }
    final modelPath = await modelManager.getModelPath(selection.model.id);

    // Spawn and initialize image worker
    final worker = ImageWorker();
    await worker.spawn();
    final useGpu = await InferenceConfig.useGpu();
    await worker.initImage(
      modelPath: modelPath,
      numThreads: 2,
      useGpu: useGpu,
    );

    expect(worker.isActive, isTrue);

    // Generate a small 256x256 image with minimal steps
    ImageCompleteResponse? completed;
    final stream = worker.generateImage(
      prompt: 'a red circle on white background',
      width: 256,
      height: 256,
      steps: 2,
      cfgScale: 1.0,
    );

    await for (final event in stream) {
      if (event is ImageCompleteResponse) {
        completed = event;
      }
    }

    expect(completed, isNotNull, reason: 'Should receive completion event');
    expect(completed!.width, equals(256));
    expect(completed.height, equals(256));
    expect(completed.pixelData, isNotEmpty,
        reason: 'Pixel data should be non-empty');
    // RGB: 256 * 256 * 3 = 196608 bytes
    expect(completed.pixelData.length, equals(256 * 256 * 3),
        reason: 'Pixel data should be width*height*3 bytes');

    await worker.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
