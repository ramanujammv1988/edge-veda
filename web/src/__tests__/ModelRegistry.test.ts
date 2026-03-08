import { ModelRegistry } from '../ModelRegistry';

describe('ModelRegistry', () => {
  describe('model counts', () => {
    it('getAllTextModels returns 5 text models', () => {
      expect(ModelRegistry.getAllTextModels()).toHaveLength(5);
    });

    it('getVisionModels returns 1 vision model (not mmproj)', () => {
      expect(ModelRegistry.getVisionModels()).toHaveLength(1);
    });

    it('getWhisperModels returns 2 whisper models', () => {
      expect(ModelRegistry.getWhisperModels()).toHaveLength(2);
    });

    it('getEmbeddingModels returns 1 embedding model', () => {
      expect(ModelRegistry.getEmbeddingModels()).toHaveLength(1);
    });

    it('getImageModels returns 1 image generation model', () => {
      expect(ModelRegistry.getImageModels()).toHaveLength(1);
    });

    it('total across all categories is 11 (includes mmproj and image gen)', () => {
      // 5 text + 1 vision + 1 mmproj + 2 whisper + 1 embedding + 1 image = 11
      expect(ModelRegistry.getAllModels()).toHaveLength(11);
    });
  });

  describe('getModelById', () => {
    it('finds llama-3.2-1b-instruct-q4 by ID', () => {
      const model = ModelRegistry.getModelById('llama-3.2-1b-instruct-q4');
      expect(model).not.toBeNull();
      expect(model!.id).toBe('llama-3.2-1b-instruct-q4');
    });

    it('llama model name contains "Llama"', () => {
      const model = ModelRegistry.getModelById('llama-3.2-1b-instruct-q4');
      expect(model!.name).toContain('Llama');
    });

    it('returns null for unknown ID', () => {
      expect(ModelRegistry.getModelById('does-not-exist')).toBeNull();
    });

    it('finds smolvlm2 mmproj by ID', () => {
      const model = ModelRegistry.getModelById('smolvlm2-500m-mmproj-f16');
      expect(model).not.toBeNull();
      expect(model!.modelType).toBe('mmproj');
    });
  });

  describe('getMmprojForModel', () => {
    it('returns mmproj for smolvlm2-500m-video-instruct-q8', () => {
      const mmproj = ModelRegistry.getMmprojForModel('smolvlm2-500m-video-instruct-q8');
      expect(mmproj).not.toBeNull();
      expect(mmproj!.modelType).toBe('mmproj');
    });

    it('returns null for a text model', () => {
      expect(ModelRegistry.getMmprojForModel('llama-3.2-1b-instruct-q4')).toBeNull();
    });

    it('returns null for an unknown model', () => {
      expect(ModelRegistry.getMmprojForModel('unknown-model')).toBeNull();
    });
  });

  describe('data integrity', () => {
    it('all model IDs are unique across all categories', () => {
      const allModels = ModelRegistry.getAllModels();
      const ids = allModels.map((m) => m.id);
      const uniqueIds = new Set(ids);
      expect(uniqueIds.size).toBe(ids.length);
    });

    it('all models have positive sizeBytes', () => {
      ModelRegistry.getAllModels().forEach((model) => {
        expect(model.sizeBytes).toBeGreaterThan(0);
      });
    });

    it('all downloadUrls start with https://', () => {
      ModelRegistry.getAllModels().forEach((model) => {
        expect(model.downloadUrl).toMatch(/^https:\/\//);
      });
    });

    it('all models have non-empty id and name', () => {
      ModelRegistry.getAllModels().forEach((model) => {
        expect(model.id.trim()).not.toBe('');
        expect(model.name.trim()).not.toBe('');
      });
    });

    it('all models have a non-empty format', () => {
      ModelRegistry.getAllModels().forEach((model) => {
        expect(model.format.trim()).not.toBe('');
      });
    });
  });

  describe('model types and properties', () => {
    it('whisperTinyEn.modelType === "whisper"', () => {
      expect(ModelRegistry.whisperTinyEn.modelType).toBe('whisper');
    });

    it('whisperBaseEn.modelType === "whisper"', () => {
      expect(ModelRegistry.whisperBaseEn.modelType).toBe('whisper');
    });

    it('allMiniLmL6V2.modelType === "embedding"', () => {
      expect(ModelRegistry.allMiniLmL6V2.modelType).toBe('embedding');
    });

    it('smolvlm2_500m_mmproj.format === "GGUF"', () => {
      expect(ModelRegistry.smolvlm2_500m_mmproj.format).toBe('GGUF');
    });

    it('smolvlm2_500m_mmproj.modelType === "mmproj"', () => {
      expect(ModelRegistry.smolvlm2_500m_mmproj.modelType).toBe('mmproj');
    });

    it('llama32_1b.downloadUrl starts with https://', () => {
      expect(ModelRegistry.llama32_1b.downloadUrl).toMatch(/^https:\/\//);
    });

    it('qwen3_06b.modelType === "text"', () => {
      expect(ModelRegistry.qwen3_06b.modelType).toBe('text');
    });

    it('vision model (smolvlm2_500m) is not in getAllTextModels', () => {
      const textIds = ModelRegistry.getAllTextModels().map((m) => m.id);
      expect(textIds).not.toContain('smolvlm2-500m-video-instruct-q8');
    });

    it('mmproj is not in getVisionModels', () => {
      const visionIds = ModelRegistry.getVisionModels().map((m) => m.id);
      expect(visionIds).not.toContain('smolvlm2-500m-mmproj-f16');
    });

    it('sdV21Turbo.modelType === "imageGeneration"', () => {
      expect(ModelRegistry.sdV21Turbo.modelType).toBe('imageGeneration');
    });

    it('sdV21Turbo is findable by ID', () => {
      const model = ModelRegistry.getModelById('sd-v2-1-turbo-q8');
      expect(model).not.toBeNull();
      expect(model!.name).toContain('SD');
    });
  });
});
