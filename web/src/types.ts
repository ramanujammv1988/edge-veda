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

/**
 * Memory usage statistics
 */
export interface MemoryStats {
  /**
   * Bytes currently used by the model and context
   */
  used: number;

  /**
   * Total memory available (estimated)
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
      throw new Error('Operation was cancelled');
    }
  }
}
