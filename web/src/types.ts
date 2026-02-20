/**
 * Edge Veda Web SDK Type Definitions
 */

/**
 * Supported device types for inference
 */
export type DeviceType = 'webgpu' | 'wasm' | 'auto';

/**
 * Model precision options
 */
export type PrecisionType = 'fp32' | 'fp16' | 'int8' | 'int4';

/**
 * Configuration for EdgeVeda initialization
 */
export interface EdgeVedaConfig {
  /**
   * Model identifier or URL to model files
   */
  modelId: string;

  /**
   * Device to run inference on
   * @default 'auto'
   */
  device?: DeviceType;

  /**
   * Model precision/quantization
   * @default 'fp16'
   */
  precision?: PrecisionType;

  /**
   * Path to WASM binary (if using custom build)
   */
  wasmPath?: string;

  /**
   * Maximum context length
   * @default 2048
   */
  maxContextLength?: number;

  /**
   * Number of threads for WASM execution
   * @default navigator.hardwareConcurrency || 4
   */
  numThreads?: number;

  // Archive C API v2.1.0 — KV-cache quantization and flash attention
  /**
   * Flash attention mode: -1 = auto (default), 0 = disabled, 1 = enabled.
   * Maps to ev_config.flash_attn.
   */
  flashAttn?: number;

  /**
   * KV-cache key data type: 1 = F16, 8 = Q8_0 (default, halves cache size).
   * Maps to ev_config.kv_cache_type_k.
   */
  kvCacheTypeK?: number;

  /**
   * KV-cache value data type: 1 = F16, 8 = Q8_0 (default).
   * Maps to ev_config.kv_cache_type_v.
   */
  kvCacheTypeV?: number;

  /**
   * Enable model caching in IndexedDB
   * @default true
   */
  enableCache?: boolean;

  /**
   * Cache name for IndexedDB
   * @default 'edgeveda-models'
   */
  cacheName?: string;

  /**
   * Progress callback for model loading
   */
  onProgress?: (progress: LoadProgress) => void;

  /**
   * Error callback
   */
  onError?: (error: Error) => void;
}

/**
 * Options for text generation
 */
export interface GenerateOptions {
  /**
   * The input prompt
   */
  prompt: string;

  /**
   * Maximum number of tokens to generate
   * @default 512
   */
  maxTokens?: number;

  /**
   * Sampling temperature (0.0 to 2.0)
   * @default 0.7
   */
  temperature?: number;

  /**
   * Top-p (nucleus) sampling
   * @default 0.9
   */
  topP?: number;

  /**
   * Top-k sampling
   * @default 40
   */
  topK?: number;

  /**
   * Repetition penalty
   * @default 1.1
   */
  repetitionPenalty?: number;

  /**
   * Stop sequences
   */
  stopSequences?: string[];

  /**
   * Random seed for reproducibility
   */
  seed?: number;

  // Flutter gold standard — confidence scoring and grammar-constrained decoding
  /**
   * Confidence threshold (0.0 = disabled). When set, enables per-token confidence
   * values in StreamChunk. Mirrors Flutter SDK's GenerateOptions.confidenceThreshold.
   */
  confidenceThreshold?: number;

  /**
   * Force JSON mode output. Mirrors Flutter SDK's GenerateOptions.jsonMode.
   */
  jsonMode?: boolean;

  /**
   * GBNF grammar string for constrained decoding (used by GbnfBuilder).
   * Mirrors Flutter SDK's GenerateOptions.grammarStr.
   */
  grammarStr?: string;

  /**
   * Grammar entry point name (default: 'root').
   * Mirrors Flutter SDK's GenerateOptions.grammarRoot.
   */
  grammarRoot?: string;
}

/**
 * Result from text generation
 */
export interface GenerateResult {
  /**
   * Generated text
   */
  text: string;

  /**
   * Number of tokens generated
   */
  tokensGenerated: number;

  /**
   * Time taken in milliseconds
   */
  timeMs: number;

  /**
   * Tokens per second
   */
  tokensPerSecond: number;

  /**
   * Whether generation was stopped early
   */
  stopped: boolean;

  /**
   * Stop reason if applicable
   */
  stopReason?: 'max_tokens' | 'stop_sequence' | 'error';
}

/**
 * Streaming chunk from generateStream
 */
export interface StreamChunk {
  /**
   * Token or text chunk
   */
  token: string;

  /**
   * Cumulative generated text so far
   */
  text: string;

  /**
   * Number of tokens generated so far
   */
  tokensGenerated: number;

  /**
   * Whether this is the final chunk
   */
  done: boolean;

  /**
   * Token confidence score (0.0-1.0)
   * Higher values indicate higher model confidence
   */
  confidence?: number;

  /**
   * Running average confidence across all tokens
   */
  avgConfidence?: number;

  /**
   * Whether low confidence suggests cloud handoff
   * True when avgConfidence falls below threshold
   */
  needsCloudHandoff?: boolean;

  /**
   * Index of this token in the sequence
   */
  tokenIndex?: number;

  /**
   * Statistics (only in final chunk)
   */
  stats?: {
    timeMs: number;
    tokensPerSecond: number;
    stopReason?: 'max_tokens' | 'stop_sequence' | 'error';
  };
}

/**
 * Model loading progress information
 */
export interface LoadProgress {
  /**
   * Stage of loading
   */
  stage: 'downloading' | 'caching' | 'loading' | 'initializing' | 'ready';

  /**
   * Progress percentage (0-100)
   */
  progress: number;

  /**
   * Bytes loaded
   */
  loaded?: number;

  /**
   * Total bytes
   */
  total?: number;

  /**
   * Human-readable message
   */
  message?: string;
}

/**
 * WebGPU capability detection result
 */
export interface WebGPUCapabilities {
  /**
   * Whether WebGPU is supported
   */
  supported: boolean;

  /**
   * GPU adapter info (if available)
   */
  adapter?: {
    vendor: string;
    architecture: string;
    device: string;
    description: string;
  };

  /**
   * Supported features
   */
  features?: string[];

  /**
   * Limits
   */
  limits?: {
    maxBufferSize: number;
    maxStorageBufferBindingSize: number;
    maxComputeWorkgroupSizeX: number;
    maxComputeWorkgroupSizeY: number;
    maxComputeWorkgroupSizeZ: number;
  };

  /**
   * Error if not supported
   */
  error?: string;
}

/**
 * Worker message types
 */
export enum WorkerMessageType {
  INIT = 'init',
  INIT_SUCCESS = 'init_success',
  INIT_ERROR = 'init_error',
  GENERATE = 'generate',
  GENERATE_CHUNK = 'generate_chunk',
  GENERATE_COMPLETE = 'generate_complete',
  GENERATE_ERROR = 'generate_error',
  CANCEL_GENERATION = 'cancel_generation',
  CANCEL_SUCCESS = 'cancel_success',
  GET_MEMORY_USAGE = 'get_memory_usage',
  MEMORY_USAGE_RESPONSE = 'memory_usage_response',
  GET_MODEL_INFO = 'get_model_info',
  MODEL_INFO_RESPONSE = 'model_info_response',
  UNLOAD_MODEL = 'unload_model',
  UNLOAD_SUCCESS = 'unload_success',
  RESET_CONTEXT = 'reset_context',
  RESET_SUCCESS = 'reset_success',
  PROGRESS = 'progress',
  TERMINATE = 'terminate',
  EMBED = 'embed',
  EMBED_SUCCESS = 'embed_success',
  EMBED_ERROR = 'embed_error',
  SET_MEMORY_LIMIT = 'set_memory_limit',
  SET_MEMORY_LIMIT_SUCCESS = 'set_memory_limit_success',
  MEMORY_CLEANUP = 'memory_cleanup',
  MEMORY_CLEANUP_SUCCESS = 'memory_cleanup_success',
  MEMORY_PRESSURE = 'memory_pressure',
}

/**
 * Base worker message
 */
export interface WorkerMessageBase {
  type: WorkerMessageType;
  id: string;
}

/**
 * Init message to worker
 */
export interface WorkerInitMessage extends WorkerMessageBase {
  type: WorkerMessageType.INIT;
  config: EdgeVedaConfig;
}

/**
 * Init success response
 */
export interface WorkerInitSuccessMessage extends WorkerMessageBase {
  type: WorkerMessageType.INIT_SUCCESS;
}

/**
 * Init error response
 */
export interface WorkerInitErrorMessage extends WorkerMessageBase {
  type: WorkerMessageType.INIT_ERROR;
  error: string;
}

/**
 * Generate message to worker
 */
export interface WorkerGenerateMessage extends WorkerMessageBase {
  type: WorkerMessageType.GENERATE;
  options: GenerateOptions;
  stream: boolean;
}

/**
 * Generate chunk response (streaming)
 */
export interface WorkerGenerateChunkMessage extends WorkerMessageBase {
  type: WorkerMessageType.GENERATE_CHUNK;
  chunk: StreamChunk;
}

/**
 * Generate complete response
 */
export interface WorkerGenerateCompleteMessage extends WorkerMessageBase {
  type: WorkerMessageType.GENERATE_COMPLETE;
  result: GenerateResult;
}

/**
 * Generate error response
 */
export interface WorkerGenerateErrorMessage extends WorkerMessageBase {
  type: WorkerMessageType.GENERATE_ERROR;
  error: string;
}

/**
 * Progress update message
 */
export interface WorkerProgressMessage extends WorkerMessageBase {
  type: WorkerMessageType.PROGRESS;
  progress: LoadProgress;
}

/**
 * Cancel generation message
 */
export interface WorkerCancelGenerationMessage extends WorkerMessageBase {
  type: WorkerMessageType.CANCEL_GENERATION;
}

/**
 * Cancel success response
 */
export interface WorkerCancelSuccessMessage extends WorkerMessageBase {
  type: WorkerMessageType.CANCEL_SUCCESS;
}

/**
 * Get memory usage message
 */
export interface WorkerGetMemoryUsageMessage extends WorkerMessageBase {
  type: WorkerMessageType.GET_MEMORY_USAGE;
}

/**
 * Memory usage response
 */
export interface WorkerMemoryUsageResponseMessage extends WorkerMessageBase {
  type: WorkerMessageType.MEMORY_USAGE_RESPONSE;
  memoryStats: MemoryStats;
}

/**
 * Get model info message
 */
export interface WorkerGetModelInfoMessage extends WorkerMessageBase {
  type: WorkerMessageType.GET_MODEL_INFO;
}

/**
 * Model info response
 */
export interface WorkerModelInfoResponseMessage extends WorkerMessageBase {
  type: WorkerMessageType.MODEL_INFO_RESPONSE;
  modelInfo: ModelInfo;
}

/**
 * Unload model message
 */
export interface WorkerUnloadModelMessage extends WorkerMessageBase {
  type: WorkerMessageType.UNLOAD_MODEL;
}

/**
 * Unload success response
 */
export interface WorkerUnloadSuccessMessage extends WorkerMessageBase {
  type: WorkerMessageType.UNLOAD_SUCCESS;
}

/**
 * Reset context message
 */
export interface WorkerResetContextMessage extends WorkerMessageBase {
  type: WorkerMessageType.RESET_CONTEXT;
}

/**
 * Reset success response
 */
export interface WorkerResetSuccessMessage extends WorkerMessageBase {
  type: WorkerMessageType.RESET_SUCCESS;
}

/**
 * Terminate message
 */
export interface WorkerTerminateMessage extends WorkerMessageBase {
  type: WorkerMessageType.TERMINATE;
}

/**
 * Embed message to worker
 */
export interface WorkerEmbedMessage extends WorkerMessageBase {
  type: WorkerMessageType.EMBED;
  text: string;
}

/**
 * Embed success response
 */
export interface WorkerEmbedSuccessMessage extends WorkerMessageBase {
  type: WorkerMessageType.EMBED_SUCCESS;
  result: EmbeddingResult;
}

/**
 * Embed error response
 */
export interface WorkerEmbedErrorMessage extends WorkerMessageBase {
  type: WorkerMessageType.EMBED_ERROR;
  error: string;
}

/**
 * Set memory limit message to worker
 */
export interface WorkerSetMemoryLimitMessage extends WorkerMessageBase {
  type: WorkerMessageType.SET_MEMORY_LIMIT;
  limitBytes: number;
}

/**
 * Set memory limit success response
 */
export interface WorkerSetMemoryLimitSuccessMessage extends WorkerMessageBase {
  type: WorkerMessageType.SET_MEMORY_LIMIT_SUCCESS;
}

/**
 * Memory cleanup message to worker
 */
export interface WorkerMemoryCleanupMessage extends WorkerMessageBase {
  type: WorkerMessageType.MEMORY_CLEANUP;
}

/**
 * Memory cleanup success response
 */
export interface WorkerMemoryCleanupSuccessMessage extends WorkerMessageBase {
  type: WorkerMessageType.MEMORY_CLEANUP_SUCCESS;
}

/**
 * Memory pressure notification from worker
 */
export interface WorkerMemoryPressureMessage extends WorkerMessageBase {
  type: WorkerMessageType.MEMORY_PRESSURE;
  event: MemoryPressureEvent;
}

/**
 * Union of all worker messages
 */
export type WorkerMessage =
  | WorkerInitMessage
  | WorkerInitSuccessMessage
  | WorkerInitErrorMessage
  | WorkerGenerateMessage
  | WorkerGenerateChunkMessage
  | WorkerGenerateCompleteMessage
  | WorkerGenerateErrorMessage
  | WorkerCancelGenerationMessage
  | WorkerCancelSuccessMessage
  | WorkerGetMemoryUsageMessage
  | WorkerMemoryUsageResponseMessage
  | WorkerGetModelInfoMessage
  | WorkerModelInfoResponseMessage
  | WorkerUnloadModelMessage
  | WorkerUnloadSuccessMessage
  | WorkerResetContextMessage
  | WorkerResetSuccessMessage
  | WorkerProgressMessage
  | WorkerTerminateMessage
  | WorkerEmbedMessage
  | WorkerEmbedSuccessMessage
  | WorkerEmbedErrorMessage
  | WorkerSetMemoryLimitMessage
  | WorkerSetMemoryLimitSuccessMessage
  | WorkerMemoryCleanupMessage
  | WorkerMemoryCleanupSuccessMessage
  | WorkerMemoryPressureMessage;

/**
 * Model metadata stored in cache
 */
export interface CachedModelMetadata {
  modelId: string;
  timestamp: number;
  size: number;
  version: string;
  precision: PrecisionType;
  checksum?: string;
}

/**
 * Cached model entry
 */
export interface CachedModel {
  metadata: CachedModelMetadata;
  data: ArrayBuffer;
}

/**
 * Memory usage statistics
 *
 * Core fields (`used`, `total`, `percentage`) are always populated.
 * Fields that map to C `ev_memory_stats` (`peakBytes`, `limitBytes`,
 * `modelBytes`, `contextBytes`) are populated when the WASM module
 * exports `ev_get_memory_usage`.
 */
export interface MemoryStats {
  /**
   * Bytes currently used by the model and context (maps to ev_memory_stats.current_bytes)
   */
  used: number;

  /**
   * Total memory available (estimated from browser APIs)
   */
  total: number;

  /**
   * Usage percentage (0-1)
   */
  percentage: number;

  /**
   * WASM heap size if using WASM backend
   */
  wasmHeapSize?: number;

  /**
   * GPU memory usage if using WebGPU
   */
  gpuMemoryUsage?: number;

  /**
   * Peak memory usage observed since initialization (ev_memory_stats.peak_bytes)
   */
  peakBytes?: number;

  /**
   * Configured memory ceiling in bytes, 0 = no limit (ev_memory_stats.limit_bytes)
   */
  limitBytes?: number;

  /**
   * Bytes consumed by model weights (ev_memory_stats.model_bytes)
   */
  modelBytes?: number;

  /**
   * Bytes consumed by the KV context cache (ev_memory_stats.context_bytes)
   */
  contextBytes?: number;

  // Flutter / archive-aligned computed fields (cross-platform parity)
  /**
   * Alias for `used` — current active bytes. Mirrors Flutter MemoryStats.currentBytes.
   */
  currentBytes?: number;

  /**
   * Ratio of currentBytes to limitBytes (0.0 if limitBytes is 0 or absent).
   * Mirrors Flutter MemoryStats.usagePercent.
   */
  usagePercent?: number;

  /**
   * True when usagePercent exceeds 0.8. Mirrors Flutter MemoryStats.isHighPressure.
   */
  isHighPressure?: boolean;

  /**
   * True when usagePercent exceeds 0.9. Mirrors Flutter MemoryStats.isCritical.
   */
  isCritical?: boolean;
}

/**
 * Event emitted when memory usage crosses a pressure threshold.
 *
 * Delivered to callbacks registered via `EdgeVeda.setMemoryPressureCallback()`.
 */
export interface MemoryPressureEvent {
  /** Current memory usage in bytes */
  currentBytes: number;
  /** Configured memory limit in bytes */
  limitBytes: number;
  /** Ratio of currentBytes to limitBytes (0–1+) */
  pressureRatio: number;
  /** Timestamp when the event was generated */
  timestamp: Date;
}

/**
 * Model information and metadata
 */
export interface ModelInfo {
  /**
   * Model name/identifier
   */
  name: string;

  /**
   * Model file size in bytes
   */
  size: number;

  /**
   * Quantization/precision type
   */
  quantization: PrecisionType;

  /**
   * Maximum context length
   */
  contextLength: number;

  /**
   * Vocabulary size
   */
  vocabSize?: number;

  /**
   * Model architecture (e.g., 'llama', 'mistral')
   */
  architecture?: string;

  /**
   * Number of parameters
   */
  parameters?: string;

  /**
   * Model version
   */
  version?: string;
}

/**
 * Downloadable model descriptor (for ModelManager/ModelRegistry)
 */
export interface DownloadableModelInfo {
  /** Unique model identifier */
  id: string;
  /** Human-readable model name */
  name: string;
  /** Model file size in bytes */
  sizeBytes: number;
  /** Description of the model */
  description: string;
  /** Direct download URL for the GGUF file */
  downloadUrl: string;
  /** Expected SHA-256 checksum (hex) */
  checksum?: string;
  /** Model file format (e.g., 'GGUF') */
  format: string;
  /** Quantization type (e.g., 'Q4_K_M', 'Q8_0', 'F16') */
  quantization: string;
  /** Model category — used to group models in the registry */
  modelType?: 'text' | 'vision' | 'mmproj' | 'whisper' | 'embedding';
}

/**
 * Download progress information
 */
export interface DownloadProgress {
  /** Total bytes to download */
  totalBytes: number;
  /** Bytes downloaded so far */
  downloadedBytes: number;
  /** Download speed in bytes per second */
  speedBytesPerSecond: number;
  /** Estimated seconds remaining (null if unknown) */
  estimatedSecondsRemaining: number | null;
  /** Progress percentage 0-100 */
  percentage: number;
}

/**
 * Error codes for EdgeVeda operations
 */
export enum EdgeVedaErrorCode {
  MODEL_NOT_FOUND = 'MODEL_NOT_FOUND',
  MODEL_LOAD_FAILED = 'MODEL_LOAD_FAILED',
  GENERATION_FAILED = 'GENERATION_FAILED',
  OUT_OF_MEMORY = 'OUT_OF_MEMORY',
  CONTEXT_OVERFLOW = 'CONTEXT_OVERFLOW',
  INVALID_CONFIG = 'INVALID_CONFIG',
  CANCELLATION = 'CANCELLATION',
  VISION_ERROR = 'VISION_ERROR',
  UNLOAD_ERROR = 'UNLOAD_ERROR',
  UNKNOWN_ERROR = 'UNKNOWN_ERROR',
}

/**
 * Typed error for EdgeVeda operations.
 *
 * Provides a structured error with a machine-readable `code` and optional `details`
 * string for additional context.
 */
export class EdgeVedaError extends Error {
  code: EdgeVedaErrorCode;
  details?: string;

  constructor(code: EdgeVedaErrorCode, message: string, details?: string) {
    super(message);
    this.name = 'EdgeVedaError';
    this.code = code;
    this.details = details;
  }
}

/**
 * Thrown when the EdgeVeda engine fails to initialize (WASM load, backend init, etc.)
 */
export class InitializationError extends EdgeVedaError {
  constructor(message: string, details?: string) {
    super(EdgeVedaErrorCode.UNKNOWN_ERROR, message, details);
    this.name = 'InitializationError';
  }
}

/**
 * Thrown when a model file cannot be loaded (corrupt, unsupported format, download failure, etc.)
 */
export class ModelLoadError extends EdgeVedaError {
  constructor(message: string, details?: string) {
    super(EdgeVedaErrorCode.MODEL_LOAD_FAILED, message, details);
    this.name = 'ModelLoadError';
  }
}

/**
 * Thrown when token generation fails (WASM inference error, context overflow, etc.)
 */
export class GenerationError extends EdgeVedaError {
  constructor(message: string, details?: string) {
    super(EdgeVedaErrorCode.GENERATION_FAILED, message, details);
    this.name = 'GenerationError';
  }
}

/**
 * Thrown when a memory limit is exceeded or memory cannot be allocated.
 */
export class MemoryError extends EdgeVedaError {
  constructor(message: string, details?: string) {
    super(EdgeVedaErrorCode.OUT_OF_MEMORY, message, details);
    this.name = 'MemoryError';
  }
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
 * Cancellation token for aborting generation
 */
export class CancelToken {
  private _cancelled = false;
  private _callbacks: Array<() => void> = [];
  private _abortController: AbortController;

  constructor() {
    this._abortController = new AbortController();
  }

  /**
   * Whether cancellation has been requested
   */
  get cancelled(): boolean {
    return this._cancelled;
  }

  /**
   * AbortSignal for fetch/async operations
   */
  get signal(): AbortSignal {
    return this._abortController.signal;
  }

  /**
   * Request cancellation
   */
  cancel(): void {
    if (this._cancelled) return;
    
    this._cancelled = true;
    this._abortController.abort();
    
    // Notify all callbacks
    for (const callback of this._callbacks) {
      try {
        callback();
      } catch (error) {
        console.error('Error in cancel callback:', error);
      }
    }
    
    this._callbacks = [];
  }

  /**
   * Register a callback for when cancellation is requested
   */
  onCancel(callback: () => void): void {
    if (this._cancelled) {
      callback();
    } else {
      this._callbacks.push(callback);
    }
  }

  /**
   * Throw if cancelled
   */
  throwIfCancelled(): void {
    if (this._cancelled) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.CANCELLATION,
        'Operation was cancelled'
      );
    }
  }
}

// ============================================================================
// Whisper (STT) Types
// ============================================================================

/**
 * Configuration for Whisper model initialization
 */
export interface WhisperConfig {
  /**
   * Path or URL to the Whisper model file (GGUF format)
   */
  modelPath: string;

  /**
   * Number of threads for inference
   * @default navigator.hardwareConcurrency || 4
   */
  numThreads?: number;

  /**
   * Use GPU acceleration (WebGPU only)
   * @default false
   */
  useGpu?: boolean;

  /**
   * Language code for transcription
   * @default 'en'
   */
  language?: string;

  /**
   * Context size for the model
   * @default 1500
   */
  contextSize?: number;

  /**
   * Device to run inference on
   * @default 'auto'
   */
  device?: DeviceType;
}

/**
 * Parameters for Whisper transcription
 */
export interface WhisperParams {
  /**
   * Language code (e.g., 'en', 'es', 'fr', 'auto')
   * @default 'en'
   */
  language?: string;

  /**
   * Translate to English
   * @default false
   */
  translate?: boolean;

  /**
   * Number of threads to use for this transcription
   * @default undefined (uses config value)
   */
  nThreads?: number;
}

/**
 * A single transcription segment with timing information
 */
export interface WhisperSegment {
  /**
   * Transcribed text for this segment
   */
  text: string;

  /**
   * Start time in milliseconds
   */
  startMs: number;

  /**
   * End time in milliseconds
   */
  endMs: number;
}

/**
 * Result from Whisper transcription
 */
export interface WhisperResult {
  /**
   * Array of transcription segments
   */
  segments: WhisperSegment[];

  /**
   * Processing time in milliseconds
   */
  processTimeMs: number;

  /**
   * Full transcript (all segments concatenated)
   */
  fullText?: string;
}

/**
 * Timing information for Whisper inference
 */
export interface WhisperTimings {
  /**
   * Model loading time in milliseconds
   */
  modelLoadMs: number;

  /**
   * Audio encoding time in milliseconds
   */
  audioEncodeMs: number;

  /**
   * Transcription time in milliseconds
   */
  transcribeMs: number;

  /**
   * Total time in milliseconds
   */
  totalMs: number;
}

// ============================================================================
// Vision Inference Types
// ============================================================================

/**
 * Configuration for vision model initialization
 */
export interface VisionConfig {
  /**
   * Path or URL to the vision model file (GGUF format, e.g., SmolVLM2)
   */
  modelPath: string;

  /**
   * Path or URL to the multimodal projection file
   */
  mmprojPath: string;

  /**
   * Number of threads for inference
   * @default navigator.hardwareConcurrency || 4
   */
  numThreads?: number;

  /**
   * Context size for the model
   * @default 2048
   */
  contextSize?: number;

  /**
   * Number of GPU layers to offload (WebGPU only)
   * @default 0
   */
  gpuLayers?: number;

  /**
   * Memory limit in bytes
   * @default undefined (no limit)
   */
  memoryLimitBytes?: number;

  /**
   * Use memory mapping for model loading
   * @default true
   */
  useMmap?: boolean;

  /**
   * Device to run inference on
   * @default 'auto'
   */
  device?: DeviceType;
}

/**
 * Parameters for vision text generation
 */
export interface VisionGenerationParams {
  /**
   * Maximum number of tokens to generate
   * @default 128
   */
  maxTokens?: number;

  /**
   * Sampling temperature
   * @default 0.1
   */
  temperature?: number;

  /**
   * Top-p sampling
   * @default 0.95
   */
  topP?: number;

  /**
   * Top-k sampling
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
 * Timing information for vision inference
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
   * Decoding/generation time in milliseconds
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
   * Total time in milliseconds
   */
  totalMs: number;

  /**
   * Tokens per second throughput
   */
  tokensPerSecond: number;
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
   * Timing information
   */
  timings: VisionTimings;
}

/**
 * Frame data structure for vision inference
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

// ============================================================================
// Embeddings API Types
// ============================================================================

/**
 * Result from text embedding
 */
export interface EmbeddingResult {
  /**
   * Embedding vector (array of floats)
   */
  embeddings: number[];

  /**
   * Number of dimensions in the embedding vector
   */
  dimensions: number;

  /**
   * Number of tokens processed
   */
  tokenCount: number;

  /**
   * Time taken to compute embedding in milliseconds
   */
  timeMs?: number;
}
