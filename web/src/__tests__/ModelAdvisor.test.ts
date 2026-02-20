import {
  detectBrowserCapabilities,
  estimateModelMemory,
  recommendModels,
  BrowserProfile,
} from '../ModelAdvisor';
import type { DownloadableModelInfo } from '../types';

// Mock wasm-loader so we don't need a real browser WebGPU environment
jest.mock('../wasm-loader', () => ({
  detectWebGPU: jest.fn().mockResolvedValue({ supported: false, limits: null }),
  supportsWasmThreads: jest.fn().mockReturnValue(false),
}));

// Helpers
function makeProfile(overrides: Partial<BrowserProfile> = {}): BrowserProfile {
  return {
    hasWebGPU: false,
    estimatedGpuMemoryMb: 0,
    estimatedSystemMemoryMb: 4096,
    supportsWasmThreads: false,
    hardwareConcurrency: 4,
    platform: 'MacIntel',
    ...overrides,
  };
}

function makeModel(
  overrides: Partial<DownloadableModelInfo> = {}
): DownloadableModelInfo {
  return {
    id: 'test-model',
    name: 'Test Model',
    sizeBytes: 100 * 1024 * 1024, // 100 MB
    description: 'A test model',
    downloadUrl: 'https://example.com/model.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    ...overrides,
  };
}

describe('ModelAdvisor', () => {
  describe('detectBrowserCapabilities', () => {
    it('returns a BrowserProfile with all required fields', async () => {
      const profile = await detectBrowserCapabilities();
      expect(profile).toHaveProperty('hasWebGPU');
      expect(profile).toHaveProperty('estimatedGpuMemoryMb');
      expect(profile).toHaveProperty('estimatedSystemMemoryMb');
      expect(profile).toHaveProperty('supportsWasmThreads');
      expect(profile).toHaveProperty('hardwareConcurrency');
      expect(profile).toHaveProperty('platform');
    });

    it('hasWebGPU is false when detectWebGPU reports not supported', async () => {
      const profile = await detectBrowserCapabilities();
      expect(profile.hasWebGPU).toBe(false);
    });

    it('estimatedSystemMemoryMb falls back to 2048 when deviceMemory unavailable', async () => {
      // In Node/Jest environment navigator.deviceMemory is absent → falls back to 2 GB
      const profile = await detectBrowserCapabilities();
      // 2 GB * 1024 = 2048 MB
      expect(profile.estimatedSystemMemoryMb).toBe(2048);
    });

    it('supportsWasmThreads is false in basic Jest environment', async () => {
      const profile = await detectBrowserCapabilities();
      expect(profile.supportsWasmThreads).toBe(false);
    });

    it('estimatedGpuMemoryMb is 0 when WebGPU is not supported', async () => {
      const profile = await detectBrowserCapabilities();
      expect(profile.estimatedGpuMemoryMb).toBe(0);
    });

    it('platform is a string', async () => {
      const profile = await detectBrowserCapabilities();
      expect(typeof profile.platform).toBe('string');
    });
  });

  describe('estimateModelMemory', () => {
    it('adds 10% overhead to model sizeBytes', () => {
      const model = makeModel({ sizeBytes: 1000 });
      expect(estimateModelMemory(model)).toBe(1100);
    });

    it('estimated memory is greater than sizeBytes for any model', () => {
      const model = makeModel({ sizeBytes: 668 * 1024 * 1024 });
      expect(estimateModelMemory(model)).toBeGreaterThan(model.sizeBytes);
    });

    it('returns a rounded integer result', () => {
      const model = makeModel({ sizeBytes: 999 });
      const result = estimateModelMemory(model);
      expect(Number.isInteger(result)).toBe(true);
    });

    it('scales linearly with sizeBytes', () => {
      const small = makeModel({ sizeBytes: 100 });
      const large = makeModel({ sizeBytes: 200 });
      expect(estimateModelMemory(large)).toBe(estimateModelMemory(small) * 2);
    });
  });

  describe('recommendModels', () => {
    it('returns an array', () => {
      const profile = makeProfile();
      const result = recommendModels(profile, []);
      expect(Array.isArray(result)).toBe(true);
    });

    it('returns empty array when model list is empty', () => {
      expect(recommendModels(makeProfile(), [])).toHaveLength(0);
    });

    it('returns empty array when budget is 0 (zero system memory)', () => {
      const profile = makeProfile({ estimatedSystemMemoryMb: 0 });
      const model = makeModel({ sizeBytes: 1024 });
      expect(recommendModels(profile, [model])).toHaveLength(0);
    });

    it('excludes vision models when hasWebGPU is false', () => {
      const profile = makeProfile({ hasWebGPU: false });
      const visionModel = makeModel({ modelType: 'vision', sizeBytes: 100 });
      const result = recommendModels(profile, [visionModel]);
      expect(result).toHaveLength(0);
    });

    it('excludes mmproj models when hasWebGPU is false', () => {
      const profile = makeProfile({ hasWebGPU: false });
      const mmproj = makeModel({ modelType: 'mmproj', sizeBytes: 100 });
      const result = recommendModels(profile, [mmproj]);
      expect(result).toHaveLength(0);
    });

    it('respects memory budget ceiling — excludes models too large', () => {
      // Budget = 100 MB * 1024^2 * 0.7 ≈ 73.4 MB
      const profile = makeProfile({ estimatedSystemMemoryMb: 100 });
      const hugeModel = makeModel({
        sizeBytes: 500 * 1024 * 1024, // 500 MB — exceeds budget
      });
      const result = recommendModels(profile, [hugeModel]);
      expect(result).toHaveLength(0);
    });

    it('includes text models within budget', () => {
      const profile = makeProfile({ estimatedSystemMemoryMb: 4096 });
      const smallTextModel = makeModel({ sizeBytes: 50 * 1024 * 1024 }); // 50 MB
      const result = recommendModels(profile, [smallTextModel]);
      expect(result).toHaveLength(1);
    });

    it('includes embedding models (no modelType defaults to text behaviour)', () => {
      const profile = makeProfile({ estimatedSystemMemoryMb: 4096 });
      const embeddingModel = makeModel({
        modelType: 'embedding',
        sizeBytes: 44 * 1024 * 1024,
      });
      const result = recommendModels(profile, [embeddingModel]);
      expect(result).toHaveLength(1);
    });

    it('sorts results descending by sizeBytes (largest fitting first)', () => {
      const profile = makeProfile({ estimatedSystemMemoryMb: 8192 });
      const small = makeModel({ id: 'small', sizeBytes: 100 * 1024 * 1024 });
      const large = makeModel({ id: 'large', sizeBytes: 500 * 1024 * 1024 });
      const result = recommendModels(profile, [small, large]);
      expect(result[0].id).toBe('large');
      expect(result[1].id).toBe('small');
    });

    it('includes vision models when hasWebGPU is true and within GPU budget', () => {
      const profile = makeProfile({
        hasWebGPU: true,
        estimatedGpuMemoryMb: 4096,
      });
      const visionModel = makeModel({
        modelType: 'vision',
        sizeBytes: 50 * 1024 * 1024, // 50 MB — well within 4 GB GPU budget
      });
      const result = recommendModels(profile, [visionModel]);
      expect(result).toHaveLength(1);
    });
  });
});
