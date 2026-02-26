/**
 * WhisperWorker - Speech-to-Text inference worker for Edge Veda Web SDK
 * 
 * Provides streaming transcription capabilities using Whisper models.
 * Mirrors the Flutter SDK's WhisperSession and WhisperWorker architecture.
 */

import type {
  WhisperConfig,
  WhisperParams,
  WhisperSegment,
  WhisperResult,
  WhisperTimings,
} from './types';

/**
 * Worker message types for Whisper operations
 */
enum WhisperWorkerMessageType {
  INIT = 'whisper_init',
  INIT_SUCCESS = 'whisper_init_success',
  INIT_ERROR = 'whisper_init_error',
  TRANSCRIBE = 'whisper_transcribe',
  TRANSCRIBE_SUCCESS = 'whisper_transcribe_success',
  TRANSCRIBE_ERROR = 'whisper_transcribe_error',
  DISPOSE = 'whisper_dispose',
  DISPOSE_SUCCESS = 'whisper_dispose_success',
}

interface WhisperWorkerMessageBase {
  type: WhisperWorkerMessageType;
  id: string;
}

interface WhisperInitMessage extends WhisperWorkerMessageBase {
  type: WhisperWorkerMessageType.INIT;
  config: WhisperConfig;
}

interface WhisperTranscribeMessage extends WhisperWorkerMessageBase {
  type: WhisperWorkerMessageType.TRANSCRIBE;
  pcmSamples: Float32Array;
  params: WhisperParams;
}

/**
 * WhisperWorker - Long-lived worker for persistent Whisper inference
 * 
 * Maintains a persistent Whisper context across multiple transcription calls.
 * The model is loaded once and reused until dispose() is called.
 * 
 * Usage:
 * ```typescript
 * const worker = new WhisperWorker();
 * await worker.init({
 *   modelPath: '/models/ggml-tiny.en.bin',
 *   numThreads: 4,
 * });
 * 
 * const result = await worker.transcribe(pcmSamples, {
 *   language: 'en',
 * });
 * 
 * console.log(result.segments);
 * await worker.dispose();
 * ```
 */
export class WhisperWorker {
  private worker: Worker | null = null;
  private initialized = false;
  private messageId = 0;
  private pendingRequests = new Map<
    string,
    {
      resolve: (value: any) => void;
      reject: (error: Error) => void;
    }
  >();

  /**
   * Whether the worker is initialized and ready for transcription
   */
  get isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Initialize the Whisper worker with a model
   * 
   * Loads the Whisper model once. Subsequent transcribe() calls
   * reuse this context without reloading.
   * 
   * @param config - Whisper configuration including model path
   */
  async init(config: WhisperConfig): Promise<void> {
    if (this.initialized) {
      throw new Error('WhisperWorker already initialized');
    }

    // Create worker
    this.worker = new Worker(this.createWorkerUrl(), { type: 'module' });
    this.worker.onmessage = this.handleWorkerMessage.bind(this);
    this.worker.onerror = (error) => {
      console.error('[WhisperWorker] Worker error:', error);
      this.cleanup();
    };

    // Send init message
    try {
      await this.sendWorkerMessage({
        type: WhisperWorkerMessageType.INIT,
        config,
      });
      this.initialized = true;
    } catch (error) {
      this.cleanup();
      throw new Error(
        `Failed to initialize WhisperWorker: ${
          error instanceof Error ? error.message : 'Unknown error'
        }`
      );
    }
  }

  /**
   * Transcribe a chunk of PCM audio samples
   * 
   * Sends float32 PCM samples (16kHz mono) to the worker for transcription.
   * Returns segments with text and timing data.
   * 
   * The Whisper context is reused across calls (no model reload).
   * 
   * @param pcmSamples - Float32Array of 16kHz mono PCM samples (values between -1.0 and 1.0)
   * @param params - Transcription parameters
   * @returns WhisperResult containing segments and timing information
   */
  async transcribe(
    pcmSamples: Float32Array,
    params?: WhisperParams
  ): Promise<WhisperResult> {
    if (!this.initialized || !this.worker) {
      throw new Error('WhisperWorker not initialized. Call init() first.');
    }

    const transcribeParams: WhisperParams = {
      language: 'en',
      translate: false,
      ...params,
    };

    const response = await this.sendWorkerMessage({
      type: WhisperWorkerMessageType.TRANSCRIBE,
      pcmSamples,
      params: transcribeParams,
    });

    return response.result;
  }

  /**
   * Dispose the worker and free all native Whisper resources
   * 
   * Frees the native Whisper context (model) and terminates the worker.
   */
  async dispose(): Promise<void> {
    if (!this.worker) return;

    try {
      await this.sendWorkerMessage({
        type: WhisperWorkerMessageType.DISPOSE,
      });
    } catch (error) {
      console.warn('[WhisperWorker] Error during disposal:', error);
    } finally {
      this.cleanup();
    }
  }

  private cleanup(): void {
    this.initialized = false;
    this.worker?.terminate();
    this.worker = null;
    this.pendingRequests.clear();
  }

  private sendWorkerMessage(message: Partial<WhisperWorkerMessageBase>): Promise<any> {
    return new Promise((resolve, reject) => {
      if (!this.worker) {
        reject(new Error('Worker not available'));
        return;
      }

      const id = this.generateMessageId();
      const fullMessage = { ...message, id };

      this.pendingRequests.set(id, { resolve, reject });
      this.worker.postMessage(fullMessage);

      // Timeout after 60 seconds (Whisper can take time)
      setTimeout(() => {
        if (this.pendingRequests.has(id)) {
          this.pendingRequests.delete(id);
          reject(new Error('Whisper worker request timeout'));
        }
      }, 60000);
    });
  }

  private handleWorkerMessage(event: MessageEvent): void {
    const message = event.data;
    const request = this.pendingRequests.get(message.id);

    if (!request) {
      console.warn('[WhisperWorker] Received message for unknown request:', message.id);
      return;
    }

    switch (message.type) {
      case WhisperWorkerMessageType.INIT_SUCCESS:
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      case WhisperWorkerMessageType.INIT_ERROR:
        request.reject(new Error(message.error));
        this.pendingRequests.delete(message.id);
        break;

      case WhisperWorkerMessageType.TRANSCRIBE_SUCCESS:
        request.resolve(message);
        this.pendingRequests.delete(message.id);
        break;

      case WhisperWorkerMessageType.TRANSCRIBE_ERROR:
        request.reject(new Error(message.error));
        this.pendingRequests.delete(message.id);
        break;

      case WhisperWorkerMessageType.DISPOSE_SUCCESS:
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      default:
        console.warn('[WhisperWorker] Unknown message type:', message.type);
    }
  }

  private generateMessageId(): string {
    return `whisper_msg_${++this.messageId}_${Date.now()}`;
  }

  private createWorkerUrl(): string {
    // In production, this would import the actual worker file
    // For now, we create a placeholder
    const workerCode = `
      // WhisperWorker will be loaded from separate bundle in production
      import('./whisper-worker.js').then(module => {
        console.log('WhisperWorker module loaded');
      });
    `;

    const blob = new Blob([workerCode], { type: 'application/javascript' });
    return URL.createObjectURL(blob);
  }
}

/**
 * WhisperSession - High-level streaming transcription session
 * 
 * Manages a WhisperWorker and provides a simple API for feeding audio chunks
 * and receiving transcription segments. Implements audio buffering and chunking.
 * 
 * Usage:
 * ```typescript
 * const session = new WhisperSession({
 *   modelPath: '/models/ggml-tiny.en.bin',
 * });
 * 
 * await session.start();
 * 
 * // Feed audio chunks as they arrive from microphone
 * session.feedAudio(pcmSamples);
 * 
 * // Listen for transcription results
 * session.onSegment((segment) => {
 *   console.log(`${segment.text} [${segment.startMs}-${segment.endMs}]`);
 * });
 * 
 * await session.stop();
 * ```
 */
export class WhisperSession {
  private worker: WhisperWorker;
  private config: WhisperConfig;
  private isActive = false;
  private audioBuffer: number[] = [];
  private segments: WhisperSegment[] = [];
  private segmentCallbacks: Array<(segment: WhisperSegment) => void> = [];
  private isProcessing = false;

  // Audio processing constants
  private static readonly SAMPLE_RATE = 16000;
  private static readonly CHUNK_SIZE_MS = 3000; // 3 seconds per chunk
  private static readonly CHUNK_SIZE_SAMPLES =
    WhisperSession.SAMPLE_RATE * WhisperSession.CHUNK_SIZE_MS / 1000; // 48000 samples

  constructor(config: WhisperConfig) {
    this.config = config;
    this.worker = new WhisperWorker();
  }

  /**
   * Start the transcription session
   * 
   * Spawns WhisperWorker and loads the model.
   */
  async start(): Promise<void> {
    if (this.isActive) {
      throw new Error('WhisperSession already started');
    }

    await this.worker.init(this.config);
    this.isActive = true;
  }

  /**
   * Feed raw PCM audio samples for transcription
   * 
   * Samples must be 16kHz mono float32 (values between -1.0 and 1.0).
   * Audio is accumulated internally and transcribed in 3-second chunks.
   * 
   * @param samples - Float32Array of PCM samples
   */
  feedAudio(samples: Float32Array): void {
    if (!this.isActive) return;

    // Accumulate samples
    this.audioBuffer.push(...Array.from(samples));

    // Process when we have enough for a chunk
    if (this.audioBuffer.length >= WhisperSession.CHUNK_SIZE_SAMPLES && !this.isProcessing) {
      this.processChunk();
    }
  }

  /**
   * Force transcription of any remaining buffered audio
   * 
   * Useful when recording stops and you want the last partial chunk.
   */
  async flush(): Promise<void> {
    if (!this.isActive || this.audioBuffer.length === 0) return;
    
    // Wait for in-flight transcription to complete
    while (this.isProcessing) {
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    
    if (this.audioBuffer.length > 0) {
      await this.processChunk();
    }
  }

  /**
   * Register a callback for transcription segments
   * 
   * @param callback - Function to call when a segment is transcribed
   */
  onSegment(callback: (segment: WhisperSegment) => void): void {
    this.segmentCallbacks.push(callback);
  }

  /**
   * Get all transcribed segments so far
   */
  getSegments(): WhisperSegment[] {
    return [...this.segments];
  }

  /**
   * Get the full transcript (all segments concatenated)
   */
  getTranscript(): string {
    return this.segments.map(s => s.text).join(' ').trim();
  }

  /**
   * Reset the session (clear transcript but keep model loaded)
   */
  resetTranscript(): void {
    this.segments = [];
    this.audioBuffer = [];
  }

  /**
   * Stop the transcription session and release resources
   */
  async stop(): Promise<void> {
    if (!this.isActive) return;

    this.isActive = false;
    this.isProcessing = false;
    this.audioBuffer = [];

    await this.worker.dispose();
  }

  private async processChunk(): Promise<void> {
    if (!this.worker || !this.isActive) return;

    this.isProcessing = true;

    // Take up to CHUNK_SIZE_SAMPLES from buffer
    const chunkLen = Math.min(this.audioBuffer.length, WhisperSession.CHUNK_SIZE_SAMPLES);
    const chunk = new Float32Array(this.audioBuffer.slice(0, chunkLen));

    // Remove processed samples from buffer
    this.audioBuffer.splice(0, chunkLen);

    try {
      const result = await this.worker.transcribe(chunk, {
        language: this.config.language || 'en',
      });

      // Add segments and notify callbacks
      for (const segment of result.segments) {
        this.segments.push(segment);
        for (const callback of this.segmentCallbacks) {
          callback(segment);
        }
      }
    } catch (error) {
      console.error('[WhisperSession] Transcription error:', error);
      // Continue processing - don't stop on single chunk failure
    } finally {
      this.isProcessing = false;

      // If audio accumulated while processing, process next chunk
      if (this.isActive && this.audioBuffer.length >= WhisperSession.CHUNK_SIZE_SAMPLES) {
        this.processChunk();
      }
    }
  }

  /**
   * Request microphone permission (browser API)
   * 
   * @returns true if permission granted, false otherwise
   */
  static async requestMicrophonePermission(): Promise<boolean> {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      // Close the stream immediately - we just needed permission
      stream.getTracks().forEach(track => track.stop());
      return true;
    } catch (error) {
      console.error('[WhisperSession] Microphone permission denied:', error);
      return false;
    }
  }

  /**
   * Create a stream of PCM audio from the device microphone
   * 
   * Returns an async generator that yields Float32Array chunks of 16kHz mono audio.
   * Call for await...of to process audio chunks.
   * 
   * @param sampleRate - Audio sample rate (default: 16000)
   * @returns AsyncGenerator yielding Float32Array audio chunks
   */
  static async *microphone(sampleRate: number = 16000): AsyncGenerator<Float32Array> {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });

    const audioContext = new AudioContext({ sampleRate });
    const source = audioContext.createMediaStreamSource(stream);
    const processor = audioContext.createScriptProcessor(4096, 1, 1);

    const chunks: Float32Array[] = [];
    let resolveNext: ((value: Float32Array) => void) | null = null;

    processor.onaudioprocess = (event) => {
      const inputData = event.inputBuffer.getChannelData(0);
      const chunk = new Float32Array(inputData);
      
      if (resolveNext) {
        resolveNext(chunk);
        resolveNext = null;
      } else {
        chunks.push(chunk);
      }
    };

    source.connect(processor);
    processor.connect(audioContext.destination);

    try {
      while (true) {
        if (chunks.length > 0) {
          yield chunks.shift()!;
        } else {
          yield await new Promise<Float32Array>((resolve) => {
            resolveNext = resolve;
          });
        }
      }
    } finally {
      processor.disconnect();
      source.disconnect();
      stream.getTracks().forEach(track => track.stop());
      await audioContext.close();
    }
  }
}