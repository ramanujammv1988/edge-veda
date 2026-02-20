/**
 * WhisperSession - Persistent speech-to-text inference context
 *
 * Manages a persistent native Whisper context loaded once and reused
 * for subsequent transcriptions. Mirrors the VisionWorker.ts pattern
 * adapted for audio inference.
 *
 * Pattern mirrors Swift's WhisperSession and Flutter's WhisperSession,
 * adapted for React Native's TurboModule architecture.
 *
 * Usage:
 * 1. Create WhisperSession instance with modelPath
 * 2. Call initialize() to load the Whisper model
 * 3. Call transcribe() with Float32Array PCM samples
 * 4. Call cleanup() when done
 */

import NativeEdgeVeda from './NativeEdgeVeda';
import type { WhisperConfig, WhisperParams, WhisperResult } from './types';
import { EdgeVedaError, EdgeVedaErrorCode } from './types';

// Base64 encoding lookup table
const BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/**
 * WhisperSession - Manages persistent Whisper STT inference context
 *
 * Handles native Whisper context lifecycle and audio transcription.
 * Float32Array PCM data is base64-encoded before transfer to the
 * native layer (same pattern as VisionWorker's RGB frame encoding).
 */
export class WhisperSession {
  /** Absolute path to the Whisper GGUF model file */
  readonly modelPath: string;

  private _isInitialized = false;
  private _backend = '';

  constructor(modelPath: string) {
    this.modelPath = modelPath;
  }

  /**
   * Whether the Whisper context is initialized and ready
   */
  get isInitialized(): boolean {
    return this._isInitialized;
  }

  /**
   * Backend used for inference (e.g., "Metal", "CUDA", "CPU")
   */
  get backend(): string {
    return this._backend;
  }

  /**
   * Initialize the Whisper context
   *
   * Loads the Whisper model once. Subsequent transcribe() calls
   * reuse this context without reloading.
   *
   * @param config - Optional Whisper configuration (overrides modelPath if provided)
   * @returns Backend name (e.g., "Metal", "CPU")
   */
  async initialize(config?: WhisperConfig): Promise<string> {
    if (this._isInitialized) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.INVALID_PARAMETER,
        'WhisperSession already initialized'
      );
    }

    try {
      const modelPath = config?.modelPath ?? this.modelPath;
      const configJson = JSON.stringify({
        numThreads: config?.numThreads ?? 4,
        useGpu: config?.useGpu ?? false,
      });

      this._backend = await NativeEdgeVeda.initWhisper(modelPath, configJson);
      this._isInitialized = true;
      return this._backend;
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_LOAD_FAILED,
        'Failed to initialize Whisper context',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Transcribe audio PCM samples to text
   *
   * @param pcmSamples - 16 kHz mono Float32Array PCM audio data
   * @param params - Optional transcription parameters
   * @returns Transcription result with segments and full text
   */
  async transcribe(
    pcmSamples: Float32Array,
    params?: WhisperParams
  ): Promise<WhisperResult> {
    if (!this._isInitialized) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_NOT_LOADED,
        'WhisperSession not initialized. Call initialize() first.'
      );
    }

    try {
      // Encode Float32Array as Base64 for TurboModule transfer
      const pcmBase64 = this._float32ArrayToBase64(pcmSamples);

      const paramsJson = JSON.stringify({
        language: params?.language ?? 'en',
        translate: params?.translate ?? false,
        maxTokens: params?.maxTokens ?? 0,
      });

      const resultJson = await NativeEdgeVeda.transcribeAudio(
        pcmBase64,
        pcmSamples.length,
        paramsJson
      );

      return JSON.parse(resultJson) as WhisperResult;
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        'Whisper transcription failed',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Clean up and free native Whisper resources
   *
   * Frees the native Whisper context. The session cannot be used
   * after cleanup unless initialize() is called again.
   */
  async cleanup(): Promise<void> {
    if (!this._isInitialized) {
      return;
    }

    try {
      await NativeEdgeVeda.freeWhisper();
      this._isInitialized = false;
      this._backend = '';
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to cleanup Whisper context',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Convert Float32Array to Base64 string for TurboModule transfer
   *
   * Reinterprets the Float32 bytes as raw bytes before encoding,
   * preserving the full IEEE 754 float precision on the native side.
   */
  private _float32ArrayToBase64(samples: Float32Array): string {
    // Reinterpret float bytes as raw uint8 bytes
    const bytes = new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
    let result = '';
    const len = bytes.length;

    // Process 3 bytes at a time into 4 Base64 characters
    for (let i = 0; i < len; i += 3) {
      const byte1 = bytes[i];
      const byte2 = i + 1 < len ? bytes[i + 1] : 0;
      const byte3 = i + 2 < len ? bytes[i + 2] : 0;

      const encoded1 = byte1 >> 2;
      const encoded2 = ((byte1 & 0x03) << 4) | (byte2 >> 4);
      const encoded3 = ((byte2 & 0x0f) << 2) | (byte3 >> 6);
      const encoded4 = byte3 & 0x3f;

      result += BASE64_CHARS[encoded1];
      result += BASE64_CHARS[encoded2];
      result += i + 1 < len ? BASE64_CHARS[encoded3] : '=';
      result += i + 2 < len ? BASE64_CHARS[encoded4] : '=';
    }

    return result;
  }
}
