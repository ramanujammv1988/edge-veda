/**
 * Edge Veda SDK Types
 * Type definitions for React Native SDK
 */

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
  MODEL_NOT_LOADED = 'MODEL_NOT_LOADED',
  MODEL_LOAD_FAILED = 'MODEL_LOAD_FAILED',
  INVALID_MODEL_PATH = 'INVALID_MODEL_PATH',
  GENERATION_FAILED = 'GENERATION_FAILED',
  INVALID_PARAMETER = 'INVALID_PARAMETER',
  OUT_OF_MEMORY = 'OUT_OF_MEMORY',
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
 * Token callback for streaming generation
 */
export type TokenCallback = (token: string, isComplete: boolean) => void;

/**
 * Progress callback for model loading
 */
export type ProgressCallback = (progress: number, message: string) => void;
