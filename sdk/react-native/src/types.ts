/**
 * Configuration for initializing Edge Veda.
 */
export interface EdgeVedaConfig {
  /** Path to the GGUF model file. */
  modelPath: string;
  /** Maximum tokens to generate (default: 512). */
  maxTokens?: number;
  /** Number of CPU threads (default: 4). */
  numThreads?: number;
  /** GPU layers to offload (-1 = all). */
  gpuLayers?: number;
  /** Context size in tokens (default: 2048). */
  contextSize?: number;
  /** Enable GPU acceleration (default: true). */
  useGpu?: boolean;
  /** Memory limit in MB (default: 1536). */
  maxMemoryMb?: number;
}

/**
 * Options for text generation.
 */
export interface GenerateOptions {
  /** System prompt for context/behavior. */
  systemPrompt?: string;
  /** Temperature (0.0 = deterministic, 1.0 = creative). */
  temperature?: number;
  /** Top-p nucleus sampling. */
  topP?: number;
  /** Top-k sampling limit. */
  topK?: number;
  /** Maximum tokens to generate. */
  maxTokens?: number;
  /** Stop sequences. */
  stopSequences?: string[];
  /** Repetition penalty. */
  repeatPenalty?: number;
  /** Confidence threshold for cloud handoff (0 = disabled). */
  confidenceThreshold?: number;
}

/**
 * Response from text generation.
 */
export interface GenerateResponse {
  /** Generated text. */
  text: string;
  /** Number of tokens in the prompt. */
  promptTokens: number;
  /** Number of tokens generated. */
  completionTokens: number;
  /** Total tokens used. */
  totalTokens: number;
  /** Generation latency in milliseconds. */
  latencyMs: number;
  /** Tokens per second throughput. */
  tokensPerSecond: number | null;
}

/**
 * Token event from streaming generation.
 */
export interface TokenEvent {
  /** The token text. */
  token: string;
  /** Token index in the sequence. */
  index: number;
  /** Whether this is the final token. */
  isFinal: boolean;
}

/**
 * Options for Whisper transcription.
 */
export interface TranscribeOptions {
  /** Path to the audio file. */
  audioPath: string;
  /** Language code (default: "en"). */
  language?: string;
  /** Translate to English. */
  translate?: boolean;
}

/**
 * Result from Whisper transcription.
 */
export interface TranscriptionResult {
  /** Full transcribed text. */
  text: string;
  /** Transcription segments with timing. */
  segments: TranscriptionSegment[];
  /** Processing time in milliseconds. */
  processingTimeMs: number;
}

export interface TranscriptionSegment {
  text: string;
  startMs: number;
  endMs: number;
}

/**
 * Text embedding result.
 */
export interface EmbeddingResult {
  /** Embedding vector. */
  embedding: number[];
  /** Number of dimensions. */
  dimensions: number;
}

/**
 * Memory usage statistics.
 */
export interface MemoryStats {
  currentBytes: number;
  peakBytes: number;
  limitBytes: number;
  modelBytes: number;
  contextBytes: number;
}
