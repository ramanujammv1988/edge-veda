/**
 * VisionWorker - Persistent vision inference manager
 *
 * Maintains a persistent native vision context (~600MB VLM + mmproj) that is
 * loaded once and reused for all frame inferences. Uses a FrameQueue with
 * drop-newest backpressure to stay current with camera feeds.
 *
 * Pattern mirrors Swift's Actor-based VisionWorker and Flutter's Isolate-based
 * VisionWorker, adapted for React Native's TurboModule architecture.
 *
 * Usage:
 * 1. Create VisionWorker instance
 * 2. Call initialize() to load VLM model + mmproj
 * 3. Call enqueueFrame() for each camera frame
 * 4. Call processNextFrame() to process queued frames
 * 5. Call cleanup() when done
 */

import { FrameQueue } from './FrameQueue';
import NativeEdgeVeda from './NativeEdgeVeda';
import type {
  VisionConfig,
  VisionResult,
  VisionGenerationParams,
  VisionTimings,
} from './types';
import { EdgeVedaError, EdgeVedaErrorCode } from './types';

// Base64 encoding lookup table
const BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/**
 * VisionWorker - Manages persistent vision inference context
 *
 * Handles native vision context lifecycle and frame processing with
 * backpressure management via FrameQueue.
 */
export class VisionWorker {
  private frameQueue: FrameQueue;
  private _isInitialized = false;
  private backend = '';

  constructor() {
    this.frameQueue = new FrameQueue();
  }

  /**
   * Whether the vision context is initialized and ready
   */
  get isInitialized(): boolean {
    return this._isInitialized;
  }

  /**
   * Number of frames dropped due to backpressure
   */
  get droppedFrames(): number {
    return this.frameQueue.droppedFrames;
  }

  /**
   * Reset the dropped frames counter
   */
  resetCounters(): void {
    this.frameQueue.resetCounters();
  }

  /**
   * Initialize the vision context with VLM model
   *
   * Loads the model and mmproj once (~600MB). Subsequent frame inferences
   * reuse this context without reloading.
   *
   * @param config - Vision configuration
   * @returns Backend name (e.g., "Metal", "CUDA")
   */
  async initialize(config: VisionConfig): Promise<string> {
    if (this._isInitialized) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.INVALID_PARAMETER,
        'VisionWorker already initialized'
      );
    }

    try {
      const configJson = JSON.stringify({
        modelPath: config.modelPath,
        mmprojPath: config.mmprojPath,
        numThreads: config.numThreads ?? 4,
        contextSize: config.contextSize ?? 2048,
        gpuLayers: config.gpuLayers ?? -1,
        memoryLimitBytes: config.memoryLimitBytes ?? 0,
        useMmap: config.useMmap ?? true,
      });

      this.backend = await NativeEdgeVeda.initVision(configJson);
      this._isInitialized = true;
      return this.backend;
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_LOAD_FAILED,
        'Failed to initialize vision context',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Enqueue a frame for processing
   *
   * If inference is busy and a frame is already pending, the old frame
   * is dropped and the dropped frame counter is incremented.
   *
   * @param rgb - RGB888 pixel data (width * height * 3 bytes)
   * @param width - Frame width in pixels
   * @param height - Frame height in pixels
   * @returns true if frame was queued without dropping, false if a frame was dropped
   */
  enqueueFrame(rgb: Uint8Array, width: number, height: number): boolean {
    if (!this._isInitialized) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_NOT_LOADED,
        'VisionWorker not initialized. Call initialize() first.'
      );
    }

    return this.frameQueue.enqueue(rgb, width, height);
  }

  /**
   * Process the next queued frame
   *
   * Dequeues a frame (if available and not already processing) and performs
   * vision inference. Returns null if no frame is pending or inference is
   * already running.
   *
   * @param prompt - Text prompt for the model
   * @param params - Optional generation parameters
   * @returns Vision result with description and timings, or null if no frame to process
   */
  async processNextFrame(
    prompt: string = 'Describe what you see.',
    params?: VisionGenerationParams
  ): Promise<VisionResult | null> {
    if (!this._isInitialized) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_NOT_LOADED,
        'VisionWorker not initialized. Call initialize() first.'
      );
    }

    const frame = this.frameQueue.dequeue();
    if (!frame) {
      return null;
    }

    try {
      const result = await this.describeFrameInternal(
        frame.rgb,
        frame.width,
        frame.height,
        prompt,
        params
      );
      this.frameQueue.markDone();
      return result;
    } catch (error) {
      this.frameQueue.markDone();
      throw error;
    }
  }

  /**
   * Describe a frame directly, bypassing the queue
   *
   * Use for one-off inferences. For continuous camera feeds, prefer
   * enqueueFrame() + processNextFrame() for backpressure management.
   *
   * @param rgb - RGB888 pixel data (width * height * 3 bytes)
   * @param width - Frame width in pixels
   * @param height - Frame height in pixels
   * @param prompt - Text prompt for the model
   * @param params - Optional generation parameters
   * @returns Vision result with description and timings
   */
  async describeFrame(
    rgb: Uint8Array,
    width: number,
    height: number,
    prompt: string = 'Describe what you see.',
    params?: VisionGenerationParams
  ): Promise<VisionResult> {
    if (!this._isInitialized) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_NOT_LOADED,
        'VisionWorker not initialized. Call initialize() first.'
      );
    }

    return this.describeFrameInternal(rgb, width, height, prompt, params);
  }

  /**
   * Internal method to perform vision inference
   */
  private async describeFrameInternal(
    rgb: Uint8Array,
    width: number,
    height: number,
    prompt: string,
    params?: VisionGenerationParams
  ): Promise<VisionResult> {
    try {
      // Convert RGB bytes to Base64 for TurboModule transfer
      const base64 = this.uint8ArrayToBase64(rgb);

      const paramsJson = JSON.stringify({
        maxTokens: params?.maxTokens ?? 100,
        temperature: params?.temperature ?? 0.3,
        topP: params?.topP ?? 0.9,
        topK: params?.topK ?? 40,
        repeatPenalty: params?.repeatPenalty ?? 1.1,
      });

      const resultJson = await NativeEdgeVeda.describeImage(
        base64,
        width,
        height,
        prompt,
        paramsJson
      );

      const parsed = JSON.parse(resultJson);
      
      // Calculate derived timing metrics
      const totalMs =
        parsed.modelLoadMs +
        parsed.imageEncodeMs +
        parsed.promptEvalMs +
        parsed.decodeMs;
      
      const tokensPerSecond =
        parsed.generatedTokens > 0 && parsed.decodeMs > 0
          ? (parsed.generatedTokens / parsed.decodeMs) * 1000
          : 0;

      const timings: VisionTimings = {
        modelLoadMs: parsed.modelLoadMs,
        imageEncodeMs: parsed.imageEncodeMs,
        promptEvalMs: parsed.promptEvalMs,
        decodeMs: parsed.decodeMs,
        promptTokens: parsed.promptTokens,
        generatedTokens: parsed.generatedTokens,
        totalMs,
        tokensPerSecond,
      };

      return {
        description: parsed.description,
        timings,
      };
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        'Vision inference failed',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Clean up and free native vision resources
   *
   * Frees the native vision context (model + mmproj). The worker cannot
   * be used after cleanup unless initialize() is called again.
   */
  async cleanup(): Promise<void> {
    if (!this._isInitialized) {
      return;
    }

    try {
      await NativeEdgeVeda.freeVision();
      this._isInitialized = false;
      this.frameQueue.reset();
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to cleanup vision context',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Convert Uint8Array to Base64 string for TurboModule transfer
   * 
   * Custom implementation since btoa is not available in React Native
   */
  private uint8ArrayToBase64(bytes: Uint8Array): string {
    let result = '';
    const len = bytes.length;
    
    // Process 3 bytes at a time into 4 Base64 characters
    for (let i = 0; i < len; i += 3) {
      const byte1 = bytes[i];
      const byte2 = i + 1 < len ? bytes[i + 1] : 0;
      const byte3 = i + 2 < len ? bytes[i + 2] : 0;
      
      // Convert 3 bytes (24 bits) into 4 6-bit Base64 indices
      const encoded1 = byte1 >> 2;
      const encoded2 = ((byte1 & 0x03) << 4) | (byte2 >> 4);
      const encoded3 = ((byte2 & 0x0f) << 2) | (byte3 >> 6);
      const encoded4 = byte3 & 0x3f;
      
      // Map to Base64 characters
      result += BASE64_CHARS[encoded1];
      result += BASE64_CHARS[encoded2];
      result += i + 1 < len ? BASE64_CHARS[encoded3] : '=';
      result += i + 2 < len ? BASE64_CHARS[encoded4] : '=';
    }
    
    return result;
  }
}
