/// DTEST-03: Integration test — Whisper end-to-end transcription
///
/// Loads a whisper model (whisper-tiny-en) and verifies that
/// transcribeChunk() processes synthetic audio without crashing
/// and returns a response (even if text is empty for a sine wave).
///
/// Run: flutter test integration_test/whisper_test.dart -d <device>
library;

import 'dart:math' show pi, sin;
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

  testWidgets('Whisper transcribes synthetic audio without crash',
      (tester) async {
    // Select best available whisper model (downloads if needed)
    final selection = await ModelSelector.bestWhisper(modelManager);
    if (selection.needsDownload) {
      await modelManager.downloadModel(selection.model);
    }
    final modelPath = await modelManager.getModelPath(selection.model.id);

    // Spawn and initialize whisper worker
    final worker = WhisperWorker();
    await worker.spawn();
    final useGpu = await InferenceConfig.useGpu();
    await worker.initWhisper(
      modelPath: modelPath,
      numThreads: 2,
      useGpu: useGpu,
    );

    expect(worker.isActive, isTrue);

    // Generate 2 seconds of 440Hz sine wave at 16kHz mono
    const sampleRate = 16000;
    const durationMs = 2000;
    const frequency = 440.0;
    final numSamples = (sampleRate * durationMs / 1000).round();
    final pcm = Float32List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      pcm[i] = (sin(2 * pi * frequency * i / sampleRate) * 0.5);
    }

    // Transcribe the synthetic audio
    final result = await worker.transcribeChunk(
      pcm,
      timeout: const Duration(seconds: 60),
    );

    // Sine wave won't produce meaningful text, but the call should succeed
    // without crashing. The response object should be valid.
    expect(result, isNotNull, reason: 'Transcription should return a result');
    // Segments may be empty for non-speech audio — that's fine
    expect(result.segments, isA<List>());

    await worker.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
