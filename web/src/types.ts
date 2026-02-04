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
  PROGRESS = 'progress',
  TERMINATE = 'terminate',
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
 * Terminate message
 */
export interface WorkerTerminateMessage extends WorkerMessageBase {
  type: WorkerMessageType.TERMINATE;
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
  | WorkerProgressMessage
  | WorkerTerminateMessage;

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
