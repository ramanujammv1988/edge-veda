/**
 * Edge Veda SDK Types
 * Type definitions for React Native SDK
 */

// Extend ErrorConstructor to include V8's captureStackTrace method
declare global {
  interface ErrorConstructor {
    captureStackTrace?(targetObject: object, constructorOpt?: Function): void;
  }
}

/**
 * Model configuration options
 */
export interface EdgeVedaConfig {
  /**
   * Maximum number of tokens to generate
   * @default 512
   */
  maxTokens?: number;

  /**
   * Temperature for sampling (0.0 - 2.0)
   * Higher values make output more random
   * @default 0.7
   */
  temperature?: number;

  /**
   * Top-p (nucleus) sampling parameter (0.0 - 1.0)
   * @default 0.9
   */
  topP?: number;

  /**
   * Top-k sampling parameter
   * @default 40
   */
  topK?: number;

  /**
   * Repetition penalty (1.0 = no penalty)
   * @default 1.1
   */
  repetitionPenalty?: number;

  /**
   * Number of threads to use for inference
   * @default 4
   */
  numThreads?: number;

  /**
   * Enable GPU acceleration if available
   * @default true
   */
  useGpu?: boolean;

  /**
   * Context window size
   * @default 2048
   */
  contextSize?: number;

  /**
   * Batch size for processing
   * @default 512
   */
  batchSize?: number;

  /**
   * Flash attention mode: -1 = auto (default), 0 = disabled, 1 = enabled.
   * Maps to ev_config.flash_attn in the C API.
   */
  flashAttn?: number;

  /**
   * KV-cache key data type: 1 = F16, 8 = Q8_0 (halves cache size).
   * Maps to ev_config.kv_cache_type_k in the C API.
   */
  kvCacheTypeK?: number;

  /**
   * KV-cache value data type: 1 = F16, 8 = Q8_0.
   * Maps to ev_config.kv_cache_type_v in the C API.
   */
  kvCacheTypeV?: number;
}

/**
 * Options for text generation
 */
export interface GenerateOptions {
  /**
   * System prompt to prepend
   */
  systemPrompt?: string;

  /**
   * Override temperature for this generation
   */
  temperature?: number;

  /**
   * Override maxTokens for this generation
   */
  maxTokens?: number;

  /**
   * Override topP for this generation
   */
  topP?: number;

  /**
   * Override topK for this generation
   */
  topK?: number;

  /**
   * Stop sequences
   */
  stopSequences?: string[];

  /**
   * Random seed for reproducibility
   */
  seed?: number;

  /**
   * Confidence threshold (0.0 = disabled). When set, enables per-token
   * confidence values in TokenChunk. Mirrors Flutter SDK's confidenceThreshold.
   */
  confidenceThreshold?: number;

  /**
   * Force JSON mode output. Mirrors Flutter SDK's jsonMode.
   */
  jsonMode?: boolean;

  /**
   * GBNF grammar string for constrained decoding (used by GbnfBuilder).
   * Mirrors Flutter SDK's grammarStr.
   */
  grammarStr?: string;

  /**
   * Grammar entry point name.
   * @default 'root'
   */
  grammarRoot?: string;
}

/**
 * Complete generation response (non-streaming).
 * Mirrors Flutter SDK's GenerateResponse.
 */
export interface GenerateResponse {
  /** Generated text content */
  text: string;
  /** Number of tokens in the prompt */
  promptTokens: number;
  /** Number of tokens generated */
  completionTokens: number;
  /** Total tokens used (prompt + completion) */
  totalTokens: number;
  /** Time taken for generation in milliseconds */
  latencyMs?: number;
  /** Average confidence across all generated tokens (null if not tracked) */
  avgConfidence?: number;
  /** Whether cloud handoff was recommended during generation */
  needsCloudHandoff: boolean;
  /** Tokens per second throughput */
  tokensPerSecond?: number;
}

/**
 * Token chunk in a streaming response.
 * Mirrors Flutter SDK's TokenChunk.
 */
export interface TokenChunk {
  /** The token text content */
  token: string;
  /** Token index in the sequence */
  index: number;
  /** Whether this is the final token */
  isFinal: boolean;
  /** Per-token confidence score (0.0-1.0), undefined if confidence tracking disabled */
  confidence?: number;
  /** Whether cloud handoff is recommended at this point */
  needsCloudHandoff: boolean;
}

/**
 * Confidence information for a generated token or response.
 * Mirrors Flutter SDK's ConfidenceInfo.
 */
export interface ConfidenceInfo {
  /** Per-token confidence score (0.0-1.0), -1.0 if not computed */
  confidence: number;
  /** Running average confidence across all generated tokens */
  avgConfidence: number;
  /** Whether the model recommends cloud handoff */
  needsCloudHandoff: boolean;
  /** Token position in generated sequence */
  tokenIndex: number;
}

/**
 * Memory usage statistics (legacy — kept for backward compatibility).
 * Prefer MemoryStats for new code.
 */
export interface MemoryUsage {
  /**
   * Total memory used by the model in bytes
   */
  totalBytes: number;

  /**
   * Model weights memory in bytes
   */
  modelBytes: number;

  /**
   * KV cache memory in bytes
   */
  kvCacheBytes: number;

  /**
   * Available memory in bytes
   */
  availableBytes: number;
}

/**
 * Memory statistics matching the Flutter gold standard and C API ev_memory_stats.
 *
 * Mirrors Flutter SDK's MemoryStats with computed pressure properties.
 */
export interface MemoryStats {
  /** Current total memory usage in bytes (maps to ev_memory_stats.current_bytes) */
  currentBytes: number;
  /** Peak memory usage in bytes since initialization (ev_memory_stats.peak_bytes) */
  peakBytes: number;
  /** Configured memory ceiling in bytes, 0 = no limit (ev_memory_stats.limit_bytes) */
  limitBytes: number;
  /** Memory used by loaded model weights in bytes (ev_memory_stats.model_bytes) */
  modelBytes: number;
  /** Memory used by KV inference context in bytes (ev_memory_stats.context_bytes) */
  contextBytes: number;
  /** Memory usage as ratio (0.0-1.0). Returns 0 if limitBytes is 0. */
  usagePercent: number;
  /** Whether memory usage exceeds 80% threshold */
  isHighPressure: boolean;
  /** Whether memory usage exceeds 90% threshold (critical) */
  isCritical: boolean;
}

/**
 * Model information
 */
export interface ModelInfo {
  /**
   * Model name
   */
  name: string;

  /**
   * Model architecture (e.g., "llama", "mistral")
   */
  architecture: string;

  /**
   * Number of parameters
   */
  parameters: number;

  /**
   * Context length
   */
  contextLength: number;

  /**
   * Vocabulary size
   */
  vocabSize: number;

  /**
   * Quantization type (e.g., "q4_0", "q8_0", "f16")
   */
  quantization: string;
}

/**
 * Error codes
 */
export enum EdgeVedaErrorCode {
  MODEL_NOT_FOUND = 'MODEL_NOT_FOUND',
  MODEL_NOT_LOADED = 'MODEL_NOT_LOADED',
  MODEL_LOAD_FAILED = 'MODEL_LOAD_FAILED',
  INVALID_MODEL_PATH = 'INVALID_MODEL_PATH',
  GENERATION_FAILED = 'GENERATION_FAILED',
  INVALID_PARAMETER = 'INVALID_PARAMETER',
  INVALID_CONFIG = 'INVALID_CONFIG',
  OUT_OF_MEMORY = 'OUT_OF_MEMORY',
  CONTEXT_OVERFLOW = 'CONTEXT_OVERFLOW',
  CANCELLATION = 'CANCELLATION',
  VISION_ERROR = 'VISION_ERROR',
  UNLOAD_ERROR = 'UNLOAD_ERROR',
  GPU_NOT_AVAILABLE = 'GPU_NOT_AVAILABLE',
  UNSUPPORTED_ARCHITECTURE = 'UNSUPPORTED_ARCHITECTURE',
  UNKNOWN_ERROR = 'UNKNOWN_ERROR',
}

/**
 * Edge Veda SDK Error
 */
export class EdgeVedaError extends Error {
  code: EdgeVedaErrorCode;
  details?: string;

  constructor(code: EdgeVedaErrorCode, message: string, details?: string) {
    super(message);
    this.name = 'EdgeVedaError';
    this.code = code;
    this.details = details;

    // Maintains proper stack trace for where our error was thrown
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, EdgeVedaError);
    }
  }
}

/**
 * Thrown when token generation fails.
 * Mirrors Flutter SDK's GenerationException.
 */
export class GenerationError extends EdgeVedaError {
  constructor(message: string, details?: string) {
    super(EdgeVedaErrorCode.GENERATION_FAILED, message, details);
    this.name = 'GenerationError';
  }
}

/**
 * Cancellation token for aborting downloads and generation.
 *
 * Thread-safe cancellation token that notifies listeners when cancel() is called.
 * Integrates with AbortController for fetch-based operations.
 */
export class CancelToken {
  private _cancelled = false;
  private _callbacks: Array<() => void> = [];

  /** Whether cancellation has been requested */
  get isCancelled(): boolean {
    return this._cancelled;
  }

  /** Request cancellation of the operation */
  cancel(): void {
    if (this._cancelled) return;
    this._cancelled = true;

    for (const callback of this._callbacks) {
      try {
        callback();
      } catch (_) {
        // Ignore callback errors
      }
    }
    this._callbacks = [];
  }

  /** Register a callback for when cancellation is requested */
  onCancel(callback: () => void): void {
    if (this._cancelled) {
      callback();
    } else {
      this._callbacks.push(callback);
    }
  }

  /** Throw if cancelled */
  throwIfCancelled(): void {
    if (this._cancelled) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.CANCELLATION,
        'Operation was cancelled'
      );
    }
  }

  /** Reset the token for reuse */
  reset(): void {
    this._cancelled = false;
    this._callbacks = [];
  }
}

/**
 * Model download progress information.
 */
export interface DownloadProgress {
  /** Total bytes to download */
  totalBytes: number;
  /** Bytes downloaded so far */
  downloadedBytes: number;
  /** Download speed in bytes per second */
  speedBytesPerSecond?: number;
  /** Estimated time remaining in seconds */
  estimatedSecondsRemaining?: number;
  /** Progress as fraction (0.0 - 1.0) */
  progress: number;
  /** Progress as percentage (0 - 100) */
  progressPercent: number;
}

/**
 * Downloadable model information descriptor.
 *
 * Represents a model that can be downloaded from a remote URL.
 * Distinct from loaded model metadata returned by getModelInfo().
 */
export interface DownloadableModelInfo {
  /** Model identifier (e.g., "llama-3.2-1b-instruct-q4") */
  id: string;
  /** Human-readable model name */
  name: string;
  /** Model size in bytes */
  sizeBytes: number;
  /** Model description */
  description?: string;
  /** Download URL */
  downloadUrl: string;
  /** SHA256 checksum for verification */
  checksum?: string;
  /** Model format (e.g., "GGUF") */
  format: string;
  /** Quantization level (e.g., "Q4_K_M") */
  quantization?: string;
  /** Model category — used to group models in the registry */
  modelType?: 'text' | 'vision' | 'mmproj' | 'whisper' | 'embedding' | 'imageGeneration';
}

/**
 * Quality of Service levels for runtime policy management.
 *
 * Used to adapt behavior under resource constraints (memory pressure,
 * thermal throttling, battery level, etc.)
 */
export enum QoSLevel {
  /** Full quality - all features enabled, no restrictions */
  FULL = 'full',
  /** Reduced quality - optional features disabled, smaller context */
  REDUCED = 'reduced',
  /** Minimal quality - bare minimum functionality */
  MINIMAL = 'minimal',
  /** Paused - inference suspended, cleanup in progress */
  PAUSED = 'paused',
}

/**
 * Configuration validation error.
 *
 * Thrown when SDK configuration is invalid (e.g., bad tool definitions,
 * invalid parameters, etc.)
 */
export class ConfigurationException extends Error {
  details?: string;

  constructor(message: string, details?: string) {
    super(message);
    this.name = 'ConfigurationException';
    this.details = details;
  }
}

/**
 * Token callback for streaming generation
 */
export type TokenCallback = (token: string, isComplete: boolean) => void;

/**
 * Progress callback for model loading
 */
export type ProgressCallback = (progress: number, message: string) => void;

// =============================================================================
// Vision Inference Types
// =============================================================================

/**
 * Configuration for vision inference with VLM models
 */
export interface VisionConfig {
  /**
   * Path to the vision-language model (GGUF format)
   */
  modelPath: string;

  /**
   * Path to the multimodal projection weights (mmproj file)
   */
  mmprojPath: string;

  /**
   * Number of threads for inference
   * @default 4
   */
  numThreads?: number;

  /**
   * Context window size
   * @default 2048
   */
  contextSize?: number;

  /**
   * Number of GPU layers to offload (-1 = all)
   * @default -1
   */
  gpuLayers?: number;

  /**
   * Memory limit in bytes (0 = no limit)
   * @default 0
   */
  memoryLimitBytes?: number;

  /**
   * Use memory mapping for faster loading
   * @default true
   */
  useMmap?: boolean;
}

/**
 * Result from vision inference
 */
export interface VisionResult {
  /**
   * Generated description of the image
   */
  description: string;

  /**
   * Performance timing data
   */
  timings: VisionTimings;
}

/**
 * Performance timing data for vision inference
 */
export interface VisionTimings {
  /**
   * Model loading time in milliseconds
   */
  modelLoadMs: number;

  /**
   * Image encoding time in milliseconds
   */
  imageEncodeMs: number;

  /**
   * Prompt evaluation time in milliseconds
   */
  promptEvalMs: number;

  /**
   * Token generation time in milliseconds
   */
  decodeMs: number;

  /**
   * Number of prompt tokens processed
   */
  promptTokens: number;

  /**
   * Number of tokens generated
   */
  generatedTokens: number;

  /**
   * Total inference time in milliseconds
   */
  totalMs: number;

  /**
   * Generation speed in tokens per second
   */
  tokensPerSecond: number;
}

/**
 * Generation parameters for vision inference
 */
export interface VisionGenerationParams {
  /**
   * Maximum tokens to generate
   * @default 100
   */
  maxTokens?: number;

  /**
   * Sampling temperature (0.0 - 2.0)
   * @default 0.3
   */
  temperature?: number;

  /**
   * Top-p sampling parameter
   * @default 0.9
   */
  topP?: number;

  /**
   * Top-k sampling parameter
   * @default 40
   */
  topK?: number;

  /**
   * Repetition penalty
   * @default 1.1
   */
  repeatPenalty?: number;
}

/**
 * Frame data for vision processing
 */
export interface FrameData {
  /**
   * RGB888 pixel data (width * height * 3 bytes)
   */
  rgb: Uint8Array;

  /**
   * Frame width in pixels
   */
  width: number;

  /**
   * Frame height in pixels
   */
  height: number;
}

// =============================================================================
// Whisper (Speech-to-Text) Types
// =============================================================================

/**
 * Configuration for Whisper model initialization.
 * Mirrors Flutter SDK's WhisperConfig.
 */
export interface WhisperConfig {
  /**
   * Path to the Whisper model file (GGUF format)
   */
  modelPath: string;

  /**
   * Number of threads for inference
   * @default 4
   */
  numThreads?: number;

  /**
   * Enable GPU acceleration
   * @default false
   */
  useGpu?: boolean;

  /**
   * Default language code for transcription (e.g., 'en', 'es', 'auto')
   * @default 'en'
   */
  language?: string;

  /**
   * Context size for the model
   * @default 1500
   */
  contextSize?: number;
}

/**
 * Parameters for a Whisper transcription request.
 * Mirrors Flutter SDK's WhisperParams.
 */
export interface WhisperParams {
  /**
   * Language code (e.g., 'en', 'es', 'fr', 'auto')
   * @default 'en'
   */
  language?: string;

  /**
   * Translate transcription to English
   * @default false
   */
  translate?: boolean;

  /**
   * Maximum tokens to generate
   */
  maxTokens?: number;
}

/**
 * A single transcription segment with timing.
 * Mirrors Flutter SDK's WhisperSegment.
 */
export interface WhisperSegment {
  /** Transcribed text for this segment */
  text: string;
  /** Segment start time in milliseconds */
  startMs: number;
  /** Segment end time in milliseconds */
  endMs: number;
}

/**
 * Result from a Whisper transcription.
 * Mirrors Flutter SDK's WhisperResult.
 */
export interface WhisperResult {
  /** Array of transcription segments with timing */
  segments: WhisperSegment[];
  /** Full transcript (all segments concatenated) */
  fullText: string;
  /** Processing time in milliseconds */
  processingTimeMs: number;
}

// =============================================================================
// Image Generation Types (Stable Diffusion)
// =============================================================================

/**
 * Sampler types for diffusion denoising.
 * Maps to ev_image_sampler_t in edge_veda.h.
 * Mirrors Flutter SDK's ImageSampler.
 */
export enum ImageSampler {
  EULER_A = 0,
  EULER = 1,
  DPM_PP_2M = 2,
  DPM_PP_2S_A = 3,
  LCM = 4,
}

/**
 * Schedule types for noise scheduling.
 * Maps to ev_image_schedule_t in edge_veda.h.
 * Mirrors Flutter SDK's ImageSchedule.
 */
export enum ImageSchedule {
  DEFAULT = 0,
  DISCRETE = 1,
  KARRAS = 2,
  AYS = 3,
}

/**
 * Configuration for image generation.
 * Mirrors Flutter SDK's ImageGenerationConfig.
 */
export interface ImageGenerationConfig {
  /** Negative prompt to avoid certain features */
  negativePrompt?: string;
  /** Image width in pixels @default 512 */
  width?: number;
  /** Image height in pixels @default 512 */
  height?: number;
  /** Number of denoising steps (4 for turbo, 20-50 for standard) @default 4 */
  steps?: number;
  /** Classifier-free guidance scale (1.0 for turbo) @default 1.0 */
  cfgScale?: number;
  /** Random seed (-1 = random) @default -1 */
  seed?: number;
  /** Sampler type @default EULER_A */
  sampler?: ImageSampler;
  /** Schedule type @default DEFAULT */
  schedule?: ImageSchedule;
}

/**
 * Progress update during image generation.
 * Fires once per denoising step.
 * Mirrors Flutter SDK's ImageProgress.
 */
export interface ImageProgress {
  /** Current step number (1-based) */
  step: number;
  /** Total number of denoising steps */
  totalSteps: number;
  /** Elapsed time in seconds since generation started */
  elapsedSeconds: number;
  /** Progress as a fraction (0.0 to 1.0) */
  progress: number;
}

/**
 * Result of image generation.
 * Mirrors Flutter SDK's ImageResult.
 */
export interface ImageResult {
  /** Raw pixel data (RGB bytes: width * height * channels) */
  pixelData: Uint8Array;
  /** Image width in pixels */
  width: number;
  /** Image height in pixels */
  height: number;
  /** Number of color channels (3 for RGB) */
  channels: number;
  /** Total generation time in milliseconds */
  generationTimeMs: number;
}

// =============================================================================
// Embeddings Types
// =============================================================================

/**
 * Result from text embedding.
 * Mirrors Flutter SDK's EmbeddingResult.
 */
export interface EmbeddingResult {
  /** The embedding vector (L2-normalized floats) */
  embedding: number[];
  /** Number of dimensions in the embedding vector */
  dimensions: number;
  /** Number of tokens processed */
  tokenCount: number;
  /** Time taken to compute embedding in milliseconds */
  timeMs?: number;
}
