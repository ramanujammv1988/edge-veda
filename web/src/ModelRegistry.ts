/**
 * Pre-configured Model Registry for Web Edge Veda SDK
 *
 * Contains popular GGUF models with download URLs, sizes, and checksums.
 * Mirrors the Flutter SDK's ModelRegistry for cross-platform parity.
 */

import { DownloadableModelInfo } from './types';

/**
 * Pre-configured model registry with popular models.
 *
 * All URLs point to Hugging Face GGUF repositories.
 * Sizes are approximate and may vary slightly between releases.
 */
export const ModelRegistry = {
  // =========================================================================
  // Text Language Models
  // =========================================================================

  /** Llama 3.2 1B Instruct (Q4_K_M) — Primary model, fast & efficient */
  llama32_1b: {
    id: 'llama-3.2-1b-instruct-q4',
    name: 'Llama 3.2 1B Instruct',
    sizeBytes: 668 * 1024 * 1024, // ~668 MB
    description: 'Fast and efficient instruction-tuned model',
    downloadUrl:
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  } as DownloadableModelInfo,

  /** Phi-3.5 Mini Instruct (Q4_K_M) — High-quality reasoning model */
  phi35_mini: {
    id: 'phi-3.5-mini-instruct-q4',
    name: 'Phi 3.5 Mini Instruct',
    sizeBytes: 2300 * 1024 * 1024, // ~2.3 GB
    description: 'High-quality reasoning model from Microsoft',
    downloadUrl:
      'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  } as DownloadableModelInfo,

  /** Gemma 2 2B Instruct (Q4_K_M) — Google's efficient instruction model */
  gemma2_2b: {
    id: 'gemma-2-2b-instruct-q4',
    name: 'Gemma 2 2B Instruct',
    sizeBytes: 1600 * 1024 * 1024, // ~1.6 GB
    description: "Google's efficient instruction model",
    downloadUrl:
      'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  } as DownloadableModelInfo,

  /** TinyLlama 1.1B Chat (Q4_K_M) — Smallest / fastest option */
  tinyLlama: {
    id: 'tinyllama-1.1b-chat-q4',
    name: 'TinyLlama 1.1B Chat',
    sizeBytes: 669 * 1024 * 1024, // ~669 MB
    description: 'Ultra-fast lightweight chat model',
    downloadUrl:
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  } as DownloadableModelInfo,

  // =========================================================================
  // Vision Language Models
  // =========================================================================

  /** SmolVLM2-500M Video Instruct (Q8_0) — Vision + video understanding */
  smolvlm2_500m: {
    id: 'smolvlm2-500m-video-instruct-q8',
    name: 'SmolVLM2 500M Video Instruct',
    sizeBytes: 436808704, // ~417 MB
    description: 'Vision + video understanding model for image description',
    downloadUrl:
      'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    format: 'GGUF',
    quantization: 'Q8_0',
  } as DownloadableModelInfo,

  /** SmolVLM2-500M Multimodal Projector (F16) — Required companion for SmolVLM2 */
  smolvlm2_500m_mmproj: {
    id: 'smolvlm2-500m-mmproj-f16',
    name: 'SmolVLM2 500M Multimodal Projector',
    sizeBytes: 199470624, // ~190 MB
    description: 'Multimodal projector for SmolVLM2 vision model',
    downloadUrl:
      'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-f16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    modelType: 'mmproj',
  } as DownloadableModelInfo,

  // =========================================================================
  // Text Language Models (continued)
  // =========================================================================

  /** Qwen3 0.6B Instruct (Q4_K_M) — Alibaba's compact chat model */
  qwen3_06b: {
    id: 'qwen3-0.6b-q4',
    name: 'Qwen3 0.6B',
    sizeBytes: 522 * 1024 * 1024, // ~522 MB
    description: "Alibaba's Qwen3 0.6B Instruct (Q4_K_M)",
    downloadUrl:
      'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    modelType: 'text',
  } as DownloadableModelInfo,

  // =========================================================================
  // Speech-to-Text Models (Whisper)
  // =========================================================================

  /** Whisper Tiny English (ggml) — Fastest STT model */
  whisperTinyEn: {
    id: 'whisper-tiny-en',
    name: 'Whisper Tiny EN',
    sizeBytes: 77_700_000, // ~74 MB
    description: 'OpenAI Whisper Tiny English — fastest speech-to-text',
    downloadUrl:
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin',
    format: 'ggml',
    quantization: 'fp16',
    modelType: 'whisper',
  } as DownloadableModelInfo,

  /** Whisper Base English (ggml) — Better accuracy than Tiny */
  whisperBaseEn: {
    id: 'whisper-base-en',
    name: 'Whisper Base EN',
    sizeBytes: 145_000_000, // ~138 MB
    description: 'OpenAI Whisper Base English — balanced speed and accuracy',
    downloadUrl:
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin',
    format: 'ggml',
    quantization: 'fp16',
    modelType: 'whisper',
  } as DownloadableModelInfo,

  // =========================================================================
  // Embedding Models
  // =========================================================================

  /** all-MiniLM-L6-v2 (F16) — Compact 384-dim sentence embedding model */
  allMiniLmL6V2: {
    id: 'all-minilm-l6-v2-f16',
    name: 'all-MiniLM-L6-v2',
    sizeBytes: 44_000_000, // ~42 MB
    description: 'Sentence embedding model — 384-dim, fast and accurate',
    downloadUrl:
      'https://huggingface.co/leliuga/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2.F16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    modelType: 'embedding',
  } as DownloadableModelInfo,

  // =========================================================================
  // Utility Methods
  // =========================================================================

  /** Get all text language models */
  getAllTextModels(): DownloadableModelInfo[] {
    return [
      ModelRegistry.llama32_1b,
      ModelRegistry.phi35_mini,
      ModelRegistry.gemma2_2b,
      ModelRegistry.tinyLlama,
      ModelRegistry.qwen3_06b,
    ];
  },

  /** Get all vision models (excluding mmproj companions) */
  getVisionModels(): DownloadableModelInfo[] {
    return [ModelRegistry.smolvlm2_500m];
  },

  /** Get all Whisper speech-to-text models */
  getWhisperModels(): DownloadableModelInfo[] {
    return [ModelRegistry.whisperTinyEn, ModelRegistry.whisperBaseEn];
  },

  /** Get all sentence embedding models */
  getEmbeddingModels(): DownloadableModelInfo[] {
    return [ModelRegistry.allMiniLmL6V2];
  },

  /** Get all models across all categories (including mmproj) */
  getAllModels(): DownloadableModelInfo[] {
    return [
      ...ModelRegistry.getAllTextModels(),
      ...ModelRegistry.getVisionModels(),
      ModelRegistry.smolvlm2_500m_mmproj,
      ...ModelRegistry.getWhisperModels(),
      ...ModelRegistry.getEmbeddingModels(),
    ];
  },

  /**
   * Get the multimodal projector for a vision model.
   *
   * Vision models require both the main model file and a separate
   * mmproj (multimodal projector) file.
   */
  getMmprojForModel(modelId: string): DownloadableModelInfo | null {
    switch (modelId) {
      case 'smolvlm2-500m-video-instruct-q8':
        return ModelRegistry.smolvlm2_500m_mmproj;
      default:
        return null;
    }
  },

  /** Get a model by its ID (searches all models including mmproj) */
  getModelById(id: string): DownloadableModelInfo | null {
    return ModelRegistry.getAllModels().find((m) => m.id === id) ?? null;
  },
};