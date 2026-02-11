/**
 * VisionWorker - Persistent vision inference manager for Web
 *
 * Maintains a persistent vision context in a Web Worker (~600MB VLM + mmproj)
 * that is loaded once and reused for all frame inferences. Uses a FrameQueue
 * with drop-newest backpressure to stay current with camera feeds.
 *
 * Pattern mirrors Swift's Actor-based VisionWorker and React Native's VisionWorker,
 * adapted for Web Worker message-passing architecture.
 *
 * Usage:
 * 1. Create VisionWorker instance
 * 2. Call initialize() to load VLM model + mmproj in worker
 * 3. Call enqueueFrame() for each camera frame
 * 4. Call processNextFrame() to process queued frames
 * 5. Call cleanup() when done
 */

import { FrameQueue } from './FrameQueue';
import type {
  VisionConfig,
  VisionResult,
  VisionGenerationParams,
  VisionTimings,
  FrameData,
} from './types';

/**
 * Message types for VisionWorker communication
 */
enum VisionWorkerMessageType {
  INIT = 'vision_init',
  INIT_SUCCESS = 'vision_init_success',
  INIT_ERROR = 'vision_init_error',
  DESCRIBE = 'vision_describe',
  DESCRIBE_SUCCESS = 'vision_describe_success',
  DESCRIBE_ERROR = 'vision_describe_error',
  FREE = 'vision_free',
  FREE_SUCCESS = 'vision_free_success',
}

interface VisionWorkerMessage {
  type: VisionWorkerMessageType;
  id: string;
  config?: VisionConfig;
  frameData?: {
    rgb: string; // Base64 encoded
    width: number;
    height: number;
  };
  prompt?: string;
  params?: VisionGenerationParams;
  backend?: string;
  result?: VisionResult;
  error?: string;
}

/**
 * VisionWorker - Manages persistent vision inference context in Web Worker
 *
 * Handles worker lifecycle and frame processing with backpressure management
 * via FrameQueue. Communicates with the worker thread via message passing.
 */
export class VisionWorker {
  private frameQueue: FrameQueue;
  private worker: Worker | null = null;
  private _isInitialized = false;
  private _backend = '';
  private messageId = 0;
  private pendingRequests = new Map<string, {
    resolve: (value: any) => void;
    reject: (error: Error) => void;
  }>();

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
   * Backend name (e.g., "WebGPU", "WASM")
   */
  get backend(): string {
    return this._backend;
  }

  /**
   * Number of frames dropped due to backpressure
   */
  get droppedFrames(): number {
    return this.frameQueue.getDroppedFrames();
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
   * Creates a Web Worker and loads the model and mmproj once (~600MB).
   * Subsequent frame inferences reuse this context without reloading.
   *
   * @param config - Vision configuration
   * @param workerUrl - Optional custom worker script URL
   * @returns Backend name (e.g., "WebGPU", "WASM")
   */
  async initialize(config: VisionConfig, workerUrl?: string): Promise<string> {
    if (this._isInitialized) {
      throw new Error('VisionWorker already initialized');
    }

    // Create Web Worker
    const scriptUrl = workerUrl || new URL('./vision-worker.js', import.meta.url).href;
    this.worker = new Worker(scriptUrl, { type: 'module' });

    // Set up message handler
    this.worker.onmessage = (event: MessageEvent<VisionWorkerMessage>) => {
      this.handleWorkerMessage(event.data);
    };

    this.worker.onerror = (error) => {
      console.error('VisionWorker error:', error);
      this.rejectAll(new Error('Worker error: ' + error.message));
    };

    // Send init message
    try {
      this._backend = await this.sendMessage({
        type: VisionWorkerMessageType.INIT,
        id: this.generateMessageId(),
        config,
      });
      this._isInitialized = true;
      return this._backend;
    } catch (error) {
      this.cleanup();
      throw new Error(
        'Failed to initialize vision context: ' +
        (error instanceof Error ? error.message : String(error))
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
   */
  enqueueFrame(rgb: Uint8Array, width: number, height: number): void {
    if (!this._isInitialized) {
      throw new Error('VisionWorker not initialized. Call initialize() first.');
    }

    this.frameQueue.enqueue(rgb, width, height);
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
      throw new Error('VisionWorker not initialized. Call initialize() first.');
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
      throw new Error('VisionWorker not initialized. Call initialize() first.');
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
    if (!this.worker) {
      throw new Error('Worker not initialized');
    }

    // Convert RGB bytes to Base64 for worker transfer
    const base64 = this.uint8ArrayToBase64(rgb);

    try {
      const result = await this.sendMessage({
        type: VisionWorkerMessageType.DESCRIBE,
        id: this.generateMessageId(),
        frameData: {
          rgb: base64,
          width,
          height,
        },
        prompt,
        params: params || {},
      });

      return result;
    } catch (error) {
      throw new Error(
        'Vision inference failed: ' +
        (error instanceof Error ? error.message : String(error))
      );
    }
  }

  /**
   * Clean up and free vision resources
   *
   * Terminates the Web Worker and frees the native vision context.
   * The worker cannot be used after cleanup unless initialize() is called again.
   */
  async cleanup(): Promise<void> {
    if (!this._isInitialized) {
      return;
    }

    try {
      if (this.worker) {
        // Send free message
        await this.sendMessage({
          type: VisionWorkerMessageType.FREE,
          id: this.generateMessageId(),
        });

        // Terminate worker
        this.worker.terminate();
        this.worker = null;
      }

      this._isInitialized = false;
      this._backend = '';
      this.frameQueue.reset();
      this.pendingRequests.clear();
    } catch (error) {
      console.error('Error during cleanup:', error);
      // Force cleanup even if message fails
      if (this.worker) {
        this.worker.terminate();
        this.worker = null;
      }
      this._isInitialized = false;
      this._backend = '';
      this.frameQueue.reset();
      this.pendingRequests.clear();
    }
  }

  /**
   * Handle messages from the Web Worker
   */
  private handleWorkerMessage(message: VisionWorkerMessage): void {
    const pending = this.pendingRequests.get(message.id);
    if (!pending) {
      console.warn('Received message for unknown request:', message.id);
      return;
    }

    this.pendingRequests.delete(message.id);

    switch (message.type) {
      case VisionWorkerMessageType.INIT_SUCCESS:
        pending.resolve(message.backend || 'WASM');
        break;

      case VisionWorkerMessageType.INIT_ERROR:
        pending.reject(new Error(message.error || 'Initialization failed'));
        break;

      case VisionWorkerMessageType.DESCRIBE_SUCCESS:
        pending.resolve(message.result);
        break;

      case VisionWorkerMessageType.DESCRIBE_ERROR:
        pending.reject(new Error(message.error || 'Inference failed'));
        break;

      case VisionWorkerMessageType.FREE_SUCCESS:
        pending.resolve(undefined);
        break;

      default:
        pending.reject(new Error('Unknown message type: ' + message.type));
    }
  }

  /**
   * Send a message to the worker and wait for response
   */
  private sendMessage(message: VisionWorkerMessage): Promise<any> {
    return new Promise((resolve, reject) => {
      if (!this.worker) {
        reject(new Error('Worker not initialized'));
        return;
      }

      this.pendingRequests.set(message.id, { resolve, reject });
      this.worker.postMessage(message);

      // Timeout after 60 seconds
      setTimeout(() => {
        const pending = this.pendingRequests.get(message.id);
        if (pending) {
          this.pendingRequests.delete(message.id);
          pending.reject(new Error('Worker request timeout'));
        }
      }, 60000);
    });
  }

  /**
   * Generate unique message ID
   */
  private generateMessageId(): string {
    return `vision-${Date.now()}-${this.messageId++}`;
  }

  /**
   * Reject all pending requests
   */
  private rejectAll(error: Error): void {
    for (const [id, pending] of this.pendingRequests.entries()) {
      pending.reject(error);
    }
    this.pendingRequests.clear();
  }

  /**
   * Convert Uint8Array to Base64 string
   *
   * Uses native btoa for efficient conversion in browser environment.
   */
  private uint8ArrayToBase64(bytes: Uint8Array): string {
    // Convert bytes to binary string
    let binary = '';
    const len = bytes.length;
    for (let i = 0; i < len; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    
    // Use native btoa for Base64 encoding
    return btoa(binary);
  }
}