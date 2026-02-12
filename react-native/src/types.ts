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
}

/**
 * Memory usage statistics
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
