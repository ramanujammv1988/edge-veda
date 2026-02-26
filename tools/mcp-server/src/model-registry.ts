/**
 * TypeScript mirror of Dart ModelRegistry from flutter/lib/src/model_manager.dart
 *
 * Contains all model metadata (IDs, sizes, URLs, capabilities) for device-aware
 * recommendations. Keep in sync with the Dart source.
 */

export interface ModelInfo {
  id: string;
  name: string;
  sizeBytes: number;
  description: string;
  downloadUrl: string;
  format: string;
  quantization: string | null;
  parametersB: number | null;
  maxContextLength: number | null;
  capabilities: string[];
  family: string | null;
}

// === Text Models ===

const llama31_8b: ModelInfo = {
  id: "llama-3.1-8b-instruct-q4",
  name: "Llama 3.1 8B Instruct",
  sizeBytes: 4920 * 1024 * 1024,
  description: "Highly capable desktop-class 8B instruction model",
  downloadUrl:
    "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 8.0,
  maxContextLength: 131072,
  capabilities: ["chat", "instruct", "reasoning", "tool-calling"],
  family: "llama3",
};

const mistral_nemo_12b: ModelInfo = {
  id: "mistral-nemo-12b-instruct-q4",
  name: "Mistral Nemo 12B Instruct",
  sizeBytes: 7100 * 1024 * 1024,
  description: "Powerful desktop-class 12B model with large context window",
  downloadUrl:
    "https://huggingface.co/bartowski/Mistral-Nemo-Instruct-2407-GGUF/resolve/main/Mistral-Nemo-Instruct-2407-Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 12.0,
  maxContextLength: 128000,
  capabilities: ["chat", "instruct", "reasoning"],
  family: "mistral",
};

const llama32_1b: ModelInfo = {
  id: "llama-3.2-1b-instruct-q4",
  name: "Llama 3.2 1B Instruct",
  sizeBytes: 668 * 1024 * 1024,
  description: "Fast and efficient instruction-tuned model",
  downloadUrl:
    "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 1.24,
  maxContextLength: 131072,
  capabilities: ["chat", "instruct"],
  family: "llama3",
};

const phi35_mini: ModelInfo = {
  id: "phi-3.5-mini-instruct-q4",
  name: "Phi 3.5 Mini Instruct",
  sizeBytes: 2300 * 1024 * 1024,
  description: "High-quality reasoning model from Microsoft",
  downloadUrl:
    "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 3.82,
  maxContextLength: 131072,
  capabilities: ["chat", "instruct", "reasoning"],
  family: "phi3",
};

const gemma2_2b: ModelInfo = {
  id: "gemma-2-2b-instruct-q4",
  name: "Gemma 2 2B Instruct",
  sizeBytes: 1600 * 1024 * 1024,
  description: "Google's efficient instruction model",
  downloadUrl:
    "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 2.61,
  maxContextLength: 8192,
  capabilities: ["chat", "instruct"],
  family: "gemma2",
};

const tinyLlama: ModelInfo = {
  id: "tinyllama-1.1b-chat-q4",
  name: "TinyLlama 1.1B Chat",
  sizeBytes: 669 * 1024 * 1024,
  description: "Ultra-fast lightweight chat model",
  downloadUrl:
    "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 1.1,
  maxContextLength: 2048,
  capabilities: ["chat"],
  family: "tinyllama",
};

const qwen3_06b: ModelInfo = {
  id: "qwen3-0.6b-q4",
  name: "Qwen3 0.6B",
  sizeBytes: 397 * 1024 * 1024,
  description: "Compact model with native tool calling support",
  downloadUrl:
    "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 0.6,
  maxContextLength: 32768,
  capabilities: ["chat", "tool-calling"],
  family: "qwen3",
};

// === Vision Language Models ===

const smolvlm2_500m: ModelInfo = {
  id: "smolvlm2-500m-video-instruct-q8",
  name: "SmolVLM2 500M Video Instruct",
  sizeBytes: 436808704,
  description: "Vision + video understanding model for image description",
  downloadUrl:
    "https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf",
  format: "GGUF",
  quantization: "Q8_0",
  parametersB: 0.5,
  maxContextLength: 4096,
  capabilities: ["vision"],
  family: "smolvlm",
};

const smolvlm2_500m_mmproj: ModelInfo = {
  id: "smolvlm2-500m-mmproj-f16",
  name: "SmolVLM2 500M Multimodal Projector",
  sizeBytes: 199470624,
  description: "Multimodal projector for SmolVLM2 vision model",
  downloadUrl:
    "https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-f16.gguf",
  format: "GGUF",
  quantization: "F16",
  parametersB: null,
  maxContextLength: null,
  capabilities: ["vision-projector"],
  family: "smolvlm",
};

const llava16_mistral_7b: ModelInfo = {
  id: "llava-1.6-mistral-7b-q4",
  name: "LLaVA 1.6 Mistral 7B",
  sizeBytes: 4370 * 1024 * 1024,
  description: "State-of-the-art 7B vision-language model for detailed image understanding",
  downloadUrl:
    "https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/resolve/main/llava-1.6-mistral-7b.Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 7.0,
  maxContextLength: 32768,
  capabilities: ["vision", "chat"],
  family: "llava",
};

const llava16_mistral_7b_mmproj: ModelInfo = {
  id: "llava-1.6-mistral-7b-mmproj-f16",
  name: "LLaVA 1.6 Mistral 7B Multimodal Projector",
  sizeBytes: 624 * 1024 * 1024,
  description: "Multimodal projector for LLaVA 1.6 Mistral 7B",
  downloadUrl:
    "https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/resolve/main/mmproj-model-f16.gguf",
  format: "GGUF",
  quantization: "F16",
  parametersB: null,
  maxContextLength: null,
  capabilities: ["vision-projector"],
  family: "llava",
};

const qwen2vl_7b: ModelInfo = {
  id: "qwen2-vl-7b-instruct-q4",
  name: "Qwen2-VL 7B Instruct",
  sizeBytes: 4540 * 1024 * 1024,
  description: "Expert VLM with strong OCR and screen reading capabilities",
  downloadUrl:
    "https://huggingface.co/bartowski/Qwen2-VL-7B-Instruct-GGUF/resolve/main/Qwen2-VL-7B-Instruct-Q4_K_M.gguf",
  format: "GGUF",
  quantization: "Q4_K_M",
  parametersB: 7.0,
  maxContextLength: 32768,
  capabilities: ["vision", "chat", "ocr"],
  family: "qwen2vl",
};

const qwen2vl_7b_mmproj: ModelInfo = {
  id: "qwen2-vl-7b-mmproj-f16",
  name: "Qwen2-VL 7B Multimodal Projector",
  sizeBytes: 892 * 1024 * 1024,
  description: "Multimodal projector for Qwen2-VL 7B",
  downloadUrl:
    "https://huggingface.co/bartowski/Qwen2-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-7B-Instruct-f16.gguf",
  format: "GGUF",
  quantization: "F16",
  parametersB: null,
  maxContextLength: null,
  capabilities: ["vision-projector"],
  family: "qwen2vl",
};

// === Whisper Speech-to-Text Models ===

const whisperTinyEn: ModelInfo = {
  id: "whisper-tiny-en",
  name: "Whisper Tiny (English)",
  sizeBytes: 77 * 1024 * 1024,
  description: "Fast English speech recognition, low memory footprint",
  downloadUrl:
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin",
  format: "GGML",
  quantization: null,
  parametersB: 0.04,
  maxContextLength: null,
  capabilities: ["stt"],
  family: "whisper",
};

const whisperBaseEn: ModelInfo = {
  id: "whisper-base-en",
  name: "Whisper Base (English)",
  sizeBytes: 148 * 1024 * 1024,
  description: "Higher accuracy English speech recognition",
  downloadUrl:
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
  format: "GGML",
  quantization: null,
  parametersB: 0.07,
  maxContextLength: null,
  capabilities: ["stt"],
  family: "whisper",
};

const whisperSmall: ModelInfo = {
  id: "whisper-small-multilingual",
  name: "Whisper Small (Multilingual)",
  sizeBytes: 244 * 1024 * 1024,
  description: "Good accuracy STT in 50+ languages",
  downloadUrl:
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
  format: "GGML",
  quantization: null,
  parametersB: 0.24,
  maxContextLength: null,
  capabilities: ["stt"],
  family: "whisper",
};

const whisperMedium: ModelInfo = {
  id: "whisper-medium-multilingual",
  name: "Whisper Medium (Multilingual)",
  sizeBytes: 769 * 1024 * 1024,
  description: "Production-quality multilingual STT for macOS",
  downloadUrl:
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
  format: "GGML",
  quantization: null,
  parametersB: 0.31,
  maxContextLength: null,
  capabilities: ["stt"],
  family: "whisper",
};

const whisperLargeV3: ModelInfo = {
  id: "whisper-large-v3-multilingual",
  name: "Whisper Large v3 (Multilingual)",
  sizeBytes: 3100 * 1024 * 1024,
  description: "State-of-the-art STT in 100 languages -- requires 8GB+ Mac",
  downloadUrl:
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
  format: "GGML",
  quantization: null,
  parametersB: 1.55,
  maxContextLength: null,
  capabilities: ["stt"],
  family: "whisper",
};

// === Embedding Models ===

const allMiniLmL6V2: ModelInfo = {
  id: "all-minilm-l6-v2-f16",
  name: "All MiniLM L6 v2",
  sizeBytes: 46 * 1024 * 1024,
  description: "Lightweight sentence embedding model (384 dimensions)",
  downloadUrl:
    "https://huggingface.co/leliuga/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2.F16.gguf",
  format: "GGUF",
  quantization: "F16",
  parametersB: 0.02,
  maxContextLength: 512,
  capabilities: ["embedding"],
  family: "minilm",
};

const nomicEmbedText: ModelInfo = {
  id: "nomic-embed-text-v1.5-f16",
  name: "Nomic Embed Text v1.5",
  sizeBytes: 87 * 1024 * 1024,
  description: "High quality 768-dimension embeddings for RAG on macOS",
  downloadUrl:
    "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.f16.gguf",
  format: "GGUF",
  quantization: "F16",
  parametersB: 0.14,
  maxContextLength: 8192,
  capabilities: ["embedding"],
  family: "nomic-embed",
};

const mxbaiEmbedLarge: ModelInfo = {
  id: "mxbai-embed-large-v1-f16",
  name: "mxbai-embed-large v1",
  sizeBytes: 335 * 1024 * 1024,
  description: "State-of-the-art 1024-dimension embeddings for complex RAG",
  downloadUrl:
    "https://huggingface.co/ChristianAzinn/mxbai-embed-large-v1-gguf/resolve/main/mxbai-embed-large-v1-f16.gguf",
  format: "GGUF",
  quantization: "F16",
  parametersB: 0.34,
  maxContextLength: 512,
  capabilities: ["embedding"],
  family: "mxbai-embed",
};

// === Image Generation Models ===

const sdV21Turbo: ModelInfo = {
  id: "sd-v2-1-turbo-q8",
  name: "SD v2.1 Turbo Q8_0",
  sizeBytes: 2023745376,
  description: "Fast 1-4 step 512x512 image generation via Stable Diffusion",
  downloadUrl:
    "https://huggingface.co/Green-Sky/SD-Turbo-GGUF/resolve/main/sd_turbo-f16-q8_0.gguf",
  format: "GGUF",
  quantization: "Q8_0",
  parametersB: null,
  maxContextLength: null,
  capabilities: ["imageGeneration"],
  family: "stable-diffusion",
};

const sdxlTurbo: ModelInfo = {
  id: "sdxl-turbo-fp16",
  name: "SDXL Turbo FP16",
  sizeBytes: 6800 * 1024 * 1024,
  description: "1024x1024 high-quality 4-step image generation for macOS",
  downloadUrl:
    "https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors",
  format: "safetensors",
  quantization: "FP16",
  parametersB: null,
  maxContextLength: null,
  capabilities: ["imageGeneration"],
  family: "stable-diffusion-xl",
};

const flux1Schnell: ModelInfo = {
  id: "flux-1-schnell-q4",
  name: "FLUX.1 Schnell Q4_0",
  sizeBytes: 12400 * 1024 * 1024,
  description: "State-of-the-art 4-step text-to-image -- requires 16GB+ Mac",
  downloadUrl:
    "https://huggingface.co/city96/FLUX.1-schnell-gguf/resolve/main/flux1-schnell-Q4_0.gguf",
  format: "GGUF",
  quantization: "Q4_0",
  parametersB: null,
  maxContextLength: null,
  capabilities: ["imageGeneration"],
  family: "flux",
};

/**
 * Complete model registry -- all models from Dart ModelRegistry.
 */
export const MODEL_REGISTRY: readonly ModelInfo[] = [
  // Text
  llama31_8b,
  mistral_nemo_12b,
  llama32_1b,
  phi35_mini,
  gemma2_2b,
  tinyLlama,
  qwen3_06b,
  // Vision
  smolvlm2_500m,
  smolvlm2_500m_mmproj,
  llava16_mistral_7b,
  llava16_mistral_7b_mmproj,
  qwen2vl_7b,
  qwen2vl_7b_mmproj,
  // Whisper STT
  whisperTinyEn,
  whisperBaseEn,
  whisperSmall,
  whisperMedium,
  whisperLargeV3,
  // Embedding
  allMiniLmL6V2,
  nomicEmbedText,
  mxbaiEmbedLarge,
  // Image Generation
  sdV21Turbo,
  sdxlTurbo,
  flux1Schnell,
];

/**
 * Look up a model by its ID string.
 */
export function getModelById(id: string): ModelInfo | undefined {
  return MODEL_REGISTRY.find((m) => m.id === id);
}

/**
 * Get all models that include a given capability.
 */
export function getModelsByCapability(cap: string): ModelInfo[] {
  return MODEL_REGISTRY.filter((m) => m.capabilities.includes(cap));
}

/**
 * Map a use-case string to the best default model for mobile.
 */
export function getRecommendedModel(
  useCase: string,
  _deviceTier?: string,
): ModelInfo {
  switch (useCase) {
    case "chat":
      return llama32_1b;
    case "vision":
      return smolvlm2_500m;
    case "stt":
      return whisperBaseEn;
    case "embedding":
      return allMiniLmL6V2;
    case "image":
      return sdV21Turbo;
    case "tool-calling":
      return qwen3_06b;
    default:
      return llama32_1b;
  }
}
