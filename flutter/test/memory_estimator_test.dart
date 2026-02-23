import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/model_advisor.dart';
import 'package:edge_veda/src/types.dart' show ModelInfo;

void main() {
  group('Non-LLM models (whisper/minilm)', () {
    test('whisper model uses simpler formula: fileSize + 100MB overhead', () {
      const model = ModelInfo(
        id: 'whisper-base-en',
        name: 'Whisper Base EN',
        sizeBytes: 148 * 1024 * 1024, // 148 MB
        downloadUrl: 'https://example.com/whisper.bin',
        family: 'whisper',
      );
      const device = DeviceProfile(
        identifier: 'iPhone16,1',
        deviceName: 'iPhone 15 Pro',
        totalRamGB: 8,
        chipName: 'A17 Pro',
        tier: DeviceTier.high,
      );

      final estimate = MemoryEstimator.estimate(model: model, device: device);
      // totalMB = (148 + 100) = 248
      expect(estimate.totalMB, 248);
      expect(estimate.kvCacheMB, 0);
      expect(estimate.metalBuffersMB, 0);
      expect(estimate.runtimeOverheadMB, 100);
      // 8GB device: safeMemoryBudgetMB = (8 * 1024 * 0.6).round() = 4915
      expect(estimate.fits, true);
    });
  });

  group('LLM models', () {
    test('llama3 1B Q4_K_M at context 2048 matches calibrated formula', () {
      const model = ModelInfo(
        id: 'llama-3.2-1b-instruct-q4',
        name: 'Llama 3.2 1B Instruct',
        sizeBytes: 700 * 1024 * 1024, // 700 MB
        downloadUrl: 'https://example.com/llama.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'Q4_K_M',
      );
      const device = DeviceProfile(
        identifier: 'iPhone16,1',
        deviceName: 'iPhone 15 Pro',
        totalRamGB: 8,
        chipName: 'A17 Pro',
        tier: DeviceTier.high,
      );

      final estimate = MemoryEstimator.estimate(
        model: model,
        device: device,
        contextLength: 2048,
      );

      // modelWeightsMB = (700 * 1024 * 1024 * 0.15 / (1024 * 1024)).round() = 105
      expect(estimate.modelWeightsMB, 105);
      // kvCacheMB = (1.0 * 4.0 * (2048/2048) * 1.0).round() = 4  (Q4_K_M kvQuantFactor=1.0)
      expect(estimate.kvCacheMB, 4);
      // metalBuffersMB = (1.0 * 80).round() = 80
      expect(estimate.metalBuffersMB, 80);
      // runtimeOverheadMB = 150
      expect(estimate.runtimeOverheadMB, 150);
      // rawTotal = 105 + 4 + 80 + 150 = 339
      // totalMB = (339 * 1.3).round() = 441
      expect(estimate.totalMB, 441);
      // fits: 441 / 4915 = ~0.09 < 1.0
      expect(estimate.fits, true);
    });
  });

  group('Memory ratio and fits', () {
    test('model exceeding safe budget has fits=false and memoryRatio > 1.0',
        () {
      // Create a huge model on a small device
      const model = ModelInfo(
        id: 'huge-model',
        name: 'Huge Model',
        sizeBytes: 10000 * 1024 * 1024, // 10 GB
        downloadUrl: 'https://example.com/huge.gguf',
        family: 'llama3',
        parametersB: 13.0,
        quantization: 'Q4_K_M',
      );
      const device = DeviceProfile(
        identifier: 'iPhone13,1',
        deviceName: 'iPhone 12 mini',
        totalRamGB: 4,
        chipName: 'A14 Bionic',
        tier: DeviceTier.minimum,
      );

      final estimate = MemoryEstimator.estimate(model: model, device: device);
      expect(estimate.fits, false);
      expect(estimate.memoryRatio, greaterThan(1.0));
    });

    test('model within budget has fits=true and memoryRatio <= 1.0', () {
      const model = ModelInfo(
        id: 'small-model',
        name: 'Small Model',
        sizeBytes: 300 * 1024 * 1024,
        downloadUrl: 'https://example.com/small.gguf',
        family: 'llama3',
        parametersB: 0.5,
        quantization: 'Q4_K_M',
      );
      const device = DeviceProfile(
        identifier: 'iPhone18,1',
        deviceName: 'iPhone 17 Pro',
        totalRamGB: 12,
        chipName: 'A19 Pro',
        tier: DeviceTier.ultra,
      );

      final estimate = MemoryEstimator.estimate(model: model, device: device);
      expect(estimate.fits, true);
      expect(estimate.memoryRatio, lessThanOrEqualTo(1.0));
    });
  });

  group('Context length scaling', () {
    test('context 4096 has ~2x kvCacheMB vs context 2048', () {
      const model = ModelInfo(
        id: 'test-model',
        name: 'Test Model',
        sizeBytes: 700 * 1024 * 1024,
        downloadUrl: 'https://example.com/test.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'Q4_K_M',
      );
      const device = DeviceProfile(
        identifier: 'iPhone16,1',
        deviceName: 'iPhone 15 Pro',
        totalRamGB: 8,
        chipName: 'A17 Pro',
        tier: DeviceTier.high,
      );

      final at2048 = MemoryEstimator.estimate(
        model: model,
        device: device,
        contextLength: 2048,
      );
      final at4096 = MemoryEstimator.estimate(
        model: model,
        device: device,
        contextLength: 4096,
      );

      // kvCacheMB scales linearly with context length
      // at2048: (1.0 * 4.0 * 1.0 * 1.0).round() = 4
      // at4096: (1.0 * 4.0 * 2.0 * 1.0).round() = 8
      expect(at4096.kvCacheMB, at2048.kvCacheMB * 2);
    });
  });

  group('F16 KV quantization factor', () {
    test('F16 quantization doubles kvCacheMB (kvQuantFactor=2.0)', () {
      const modelQ4 = ModelInfo(
        id: 'test-q4',
        name: 'Test Q4',
        sizeBytes: 700 * 1024 * 1024,
        downloadUrl: 'https://example.com/test.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'Q4_K_M',
      );
      const modelF16 = ModelInfo(
        id: 'test-f16',
        name: 'Test F16',
        sizeBytes: 700 * 1024 * 1024,
        downloadUrl: 'https://example.com/test.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'F16',
      );
      const device = DeviceProfile(
        identifier: 'iPhone16,1',
        deviceName: 'iPhone 15 Pro',
        totalRamGB: 8,
        chipName: 'A17 Pro',
        tier: DeviceTier.high,
      );

      final estimateQ4 =
          MemoryEstimator.estimate(model: modelQ4, device: device);
      final estimateF16 =
          MemoryEstimator.estimate(model: modelF16, device: device);

      // F16 kvQuantFactor=2.0, Q4_K_M kvQuantFactor=1.0
      expect(estimateF16.kvCacheMB, estimateQ4.kvCacheMB * 2);
    });
  });

  group('Device safe memory budget', () {
    test('8GB device: safeMemoryBudgetMB = 4915', () {
      const device = DeviceProfile(
        identifier: 'iPhone16,1',
        deviceName: 'iPhone 15 Pro',
        totalRamGB: 8,
        chipName: 'A17 Pro',
        tier: DeviceTier.high,
      );
      expect(device.safeMemoryBudgetMB, (8 * 1024 * 0.60).round());
      expect(device.safeMemoryBudgetMB, 4915);
    });

    test('4GB device: safeMemoryBudgetMB = 2458', () {
      const device = DeviceProfile(
        identifier: 'iPhone13,1',
        deviceName: 'iPhone 12 mini',
        totalRamGB: 4,
        chipName: 'A14 Bionic',
        tier: DeviceTier.minimum,
      );
      expect(device.safeMemoryBudgetMB, (4 * 1024 * 0.60).round());
      expect(device.safeMemoryBudgetMB, 2458);
    });
  });
}
