/**
 * Edge Veda SDK - JavaScript Wrapper
 * High-level JavaScript API wrapping the native TurboModule
 */

import { AppState, NativeEventEmitter, NativeModules, Platform } from 'react-native';
import type { NativeEventSubscription } from 'react-native';
import NativeEdgeVeda from './NativeEdgeVeda';
import type {
  EdgeVedaConfig,
  GenerateOptions,
  MemoryUsage,
  MemoryStats,
  ModelInfo,
  TokenCallback,
  ProgressCallback,
  EmbeddingResult,
  WhisperConfig,
  WhisperParams,
  WhisperResult,
  ImageGenerationConfig,
  ImageProgress,
  ImageResult,
  CancelToken,
} from './types';
import { EdgeVedaError, EdgeVedaErrorCode } from './types';
import { version } from '../package.json';

/**
 * Type declarations for React Native globals
 */
declare const global: {
  HermesInternal?: any;
  nativeFabricUIManager?: any;
  v8?: any;
  WeakRef?: any;
  performance?: {
    now?: () => number;
  };
} & typeof globalThis;

/**
 * JavaScript engine detection and compatibility
 */
interface EngineInfo {
  name: 'hermes' | 'jsc' | 'v8' | 'unknown';
  version?: string;
  supportsProxy: boolean;
  supportsWeakRef: boolean;
  supportsBigInt: boolean;
  supportsSharedArrayBuffer: boolean;
}

/**
 * Detect JavaScript engine
 */
function detectEngine(): EngineInfo {
  const supportsProxy = typeof Proxy !== 'undefined';
  const supportsWeakRef = typeof (global as any).WeakRef !== 'undefined';
  const supportsBigInt = typeof BigInt !== 'undefined';
  const supportsSharedArrayBuffer = typeof SharedArrayBuffer !== 'undefined';

  // Check for Hermes
  if (typeof (global as any).HermesInternal !== 'undefined') {
    return {
      name: 'hermes',
      version: (global as any).HermesInternal?.getRuntimeProperties?.()?.['OSS Release Version'],
      supportsProxy,
      supportsWeakRef,
      supportsBigInt,
      supportsSharedArrayBuffer,
    };
  }

  // Check for JSC (Fabric UIManager is JSC-specific on iOS)
  if (typeof (global as any).nativeFabricUIManager !== 'undefined' || Platform.OS === 'ios') {
    return {
      name: 'jsc',
      supportsProxy,
      supportsWeakRef,
      supportsBigInt,
      supportsSharedArrayBuffer,
    };
  }

  // Check for V8 (Android default in older RN versions)
  if (typeof (global as any).v8 !== 'undefined') {
    return {
      name: 'v8',
      supportsProxy,
      supportsWeakRef,
      supportsBigInt,
      supportsSharedArrayBuffer,
    };
  }

  return {
    name: 'unknown',
    supportsProxy,
    supportsWeakRef,
    supportsBigInt,
    supportsSharedArrayBuffer,
  };
}

/**
 * Polyfill Performance.now() if not available
 */
function ensurePerformanceNow(): void {
  const perf = (global as any).performance;
  if (typeof perf === 'undefined' || typeof perf?.now !== 'function') {
    const startTime = Date.now();
    (global as any).performance = {
      now: () => Date.now() - startTime,
    };
  }
}

/**
 * Check engine compatibility and emit warnings
 */
function checkEngineCompatibility(engine: EngineInfo): void {
  const warnings: string[] = [];

  // Hermes-specific checks
  if (engine.name === 'hermes') {
    console.log(`[EdgeVeda] Running on Hermes ${engine.version || 'unknown version'}`);
    
    if (!engine.supportsProxy) {
      warnings.push(
        'Proxy is not supported in this Hermes version. Some advanced features may be limited.'
      );
    }

    if (!engine.supportsBigInt) {
      warnings.push(
        'BigInt is not supported. Large token IDs may have precision issues.'
      );
    }
  }

  // JSC-specific checks
  if (engine.name === 'jsc') {
    console.log('[EdgeVeda] Running on JavaScriptCore');
    
    if (Platform.OS === 'ios' && parseInt(Platform.Version as string, 10) < 14) {
      warnings.push(
        'iOS 13 or earlier detected. Some JavaScript features may be limited. ' +
        'Consider updating to iOS 14+ for best compatibility.'
      );
    }
  }

  // General checks
  if (!engine.supportsWeakRef) {
    warnings.push(
      'WeakRef is not supported. Memory management may be less efficient.'
    );
  }

  if (!engine.supportsSharedArrayBuffer) {
    warnings.push(
      'SharedArrayBuffer is not supported. Multi-threaded WASM operations are disabled.'
    );
  }

  // Emit warnings
  if (warnings.length > 0) {
    console.warn('[EdgeVeda] Engine compatibility warnings:');
    warnings.forEach((warning, i) => {
      console.warn(`  ${i + 1}. ${warning}`);
    });
  }

  // Check for critical missing features
  if (typeof Promise === 'undefined') {
    throw new Error(
      '[EdgeVeda] Promise is not available. This is a critical requirement. ' +
      'Please ensure your React Native version is up to date.'
    );
  }

  if (typeof Uint8Array === 'undefined') {
    throw new Error(
      '[EdgeVeda] Uint8Array is not available. This is a critical requirement. ' +
      'Please ensure your React Native version is up to date.'
    );
  }
}

/**
 * Initialize compatibility layer
 */
function initCompatibilityLayer(): EngineInfo {
  // Detect engine
  const engine = detectEngine();

  // Ensure Performance.now()
  ensurePerformanceNow();

  // Check compatibility
  checkEngineCompatibility(engine);

  return engine;
}

/**
 * Native event types
 */
const EVENTS = {
  TOKEN_GENERATED: 'EdgeVeda_TokenGenerated',
  GENERATION_COMPLETE: 'EdgeVeda_GenerationComplete',
  GENERATION_ERROR: 'EdgeVeda_GenerationError',
  MODEL_LOAD_PROGRESS: 'EdgeVeda_ModelLoadProgress',
  IMAGE_PROGRESS: 'EdgeVeda_ImageProgress',
} as const;

/**
 * Edge Veda SDK Main Class
 * Provides high-level API for on-device LLM inference
 */
/**
 * Memory pressure handler callback type.
 * Called when the OS signals memory pressure (iOS only).
 */
type MemoryPressureHandler = () => void | Promise<void>;

class EdgeVedaSDK {
  private eventEmitter: NativeEventEmitter;
  private requestIdCounter = 0;
  private activeGenerations = new Map<string, TokenCallback>();
  private progressCallback?: ProgressCallback;

  // Memory warning / lifecycle management
  private memoryWarningSubscription: NativeEventSubscription | null = null;
  private appStateSubscription: NativeEventSubscription | null = null;
  private customMemoryPressureHandler: MemoryPressureHandler | null = null;
  private autoUnloadedDueToMemory = false;
  private lastModelPath: string | null = null;
  private lastConfig: EdgeVedaConfig | undefined = undefined;

  constructor() {
    // Initialize compatibility layer
    initCompatibilityLayer();

    // Create event emitter for native events
    this.eventEmitter = new NativeEventEmitter(
      NativeModules.EdgeVeda || NativeEdgeVeda
    );

    // Set up event listeners
    this.setupEventListeners();

    // Register memory warning listener (iOS emits 'memoryWarning' via AppState)
    this.setupMemoryWarningListener();
  }

  /**
   * Set up native event listeners
   */
  private setupEventListeners(): void {
    // Token generated event
    this.eventEmitter.addListener(
      EVENTS.TOKEN_GENERATED,
      ({ requestId, token }: { requestId: string; token: string }) => {
        const callback = this.activeGenerations.get(requestId);
        if (callback) {
          callback(token, false);
        }
      }
    );

    // Generation complete event
    this.eventEmitter.addListener(
      EVENTS.GENERATION_COMPLETE,
      ({ requestId }: { requestId: string }) => {
        const callback = this.activeGenerations.get(requestId);
        if (callback) {
          callback('', true);
          this.activeGenerations.delete(requestId);
        }
      }
    );

    // Generation error event
    this.eventEmitter.addListener(
      EVENTS.GENERATION_ERROR,
      ({ requestId, error }: { requestId: string; error: string }) => {
        const callback = this.activeGenerations.get(requestId);
        if (callback) {
          this.activeGenerations.delete(requestId);
          throw new EdgeVedaError(
            EdgeVedaErrorCode.GENERATION_FAILED,
            'Generation failed',
            error
          );
        }
      }
    );

    // Model load progress event
    this.eventEmitter.addListener(
      EVENTS.MODEL_LOAD_PROGRESS,
      ({ progress, message }: { progress: number; message: string }) => {
        if (this.progressCallback) {
          this.progressCallback(progress, message);
        }
      }
    );
  }

  /**
   * Set up memory warning and app state listeners.
   * On iOS, AppState emits a 'memoryWarning' event when the OS signals pressure.
   */
  private setupMemoryWarningListener(): void {
    // iOS memory warning via AppState
    this.memoryWarningSubscription = AppState.addEventListener(
      'memoryWarning',
      () => {
        this.handleMemoryWarning();
      }
    );

    // Track app state changes for background/foreground awareness
    this.appStateSubscription = AppState.addEventListener(
      'change',
      (nextAppState: string) => {
        if (nextAppState === 'background') {
          this.handleAppBackground();
        }
      }
    );
  }

  /**
   * Handle OS memory warning.
   * If a custom handler is set, delegates to it. Otherwise, auto-unloads the model.
   */
  private handleMemoryWarning(): void {
    console.warn('[EdgeVeda] Memory warning received from OS');

    if (this.customMemoryPressureHandler) {
      try {
        this.customMemoryPressureHandler();
      } catch (e) {
        console.error('[EdgeVeda] Error in custom memory pressure handler:', e);
      }
      return;
    }

    // Default behavior: auto-unload model to free memory
    if (this.isModelLoaded()) {
      console.warn('[EdgeVeda] Auto-unloading model due to memory pressure');
      this.cancelGeneration()
        .then(() => this.unloadModel())
        .then(() => {
          this.autoUnloadedDueToMemory = true;
        })
        .catch((err) => {
          console.error('[EdgeVeda] Error during memory pressure unload:', err);
        });
    }
  }

  /**
   * Handle app going to background.
   * Currently a no-op hook — can be customized by subclasses or future logic.
   */
  private handleAppBackground(): void {
    // Optional: could cancel active generations or reduce resource usage
  }

  /**
   * Set a custom memory pressure handler.
   * By default, EdgeVeda auto-unloads the model on memory warnings.
   * Use this to override with custom logic (e.g., clear caches, downsize context).
   *
   * @param handler - Custom handler, or null to restore default behavior
   *
   * @example
   * ```typescript
   * EdgeVeda.setMemoryPressureHandler(() => {
   *   console.log('Custom memory handling');
   *   // Clear application caches instead of unloading model
   * });
   * ```
   */
  setMemoryPressureHandler(handler: MemoryPressureHandler | null): void {
    this.customMemoryPressureHandler = handler;
  }

  /**
   * Check if the model was auto-unloaded due to memory pressure.
   * Use this to decide whether to reload the model when the app returns to foreground.
   *
   * @returns true if model was auto-unloaded due to memory warning
   *
   * @example
   * ```typescript
   * if (EdgeVeda.wasAutoUnloaded()) {
   *   await EdgeVeda.reloadModel();
   * }
   * ```
   */
  wasAutoUnloaded(): boolean {
    return this.autoUnloadedDueToMemory;
  }

  /**
   * Reload a previously loaded model after it was unloaded (e.g., due to memory pressure).
   * Uses the same model path and config from the last init() call.
   *
   * @throws EdgeVedaError if no previous model path is available
   *
   * @example
   * ```typescript
   * // After memory pressure auto-unload
   * if (EdgeVeda.wasAutoUnloaded()) {
   *   await EdgeVeda.reloadModel();
   *   console.log('Model reloaded successfully');
   * }
   * ```
   */
  async reloadModel(): Promise<void> {
    if (this.isModelLoaded()) {
      return; // Already loaded
    }

    if (!this.lastModelPath) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_NOT_LOADED,
        'No model path available for reload. Call init() first.'
      );
    }

    await this.init(this.lastModelPath, this.lastConfig);
    this.autoUnloadedDueToMemory = false;
  }

  /**
   * Initialize the model
   * @param modelPath - Absolute path to the GGUF model file
   * @param config - Optional configuration options
   * @param onProgress - Optional progress callback
   */
  async init(
    modelPath: string,
    config?: EdgeVedaConfig,
    onProgress?: ProgressCallback
  ): Promise<void> {
    try {
      if (!modelPath) {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.INVALID_MODEL_PATH,
          'Model path is required'
        );
      }

      this.progressCallback = onProgress;

      // Store for potential reload
      this.lastModelPath = modelPath;
      this.lastConfig = config;

      const configJson = JSON.stringify(config || {});
      await NativeEdgeVeda.initialize(modelPath, configJson);

      this.autoUnloadedDueToMemory = false;
      this.progressCallback = undefined;
    } catch (error) {
      this.progressCallback = undefined;

      if (error instanceof EdgeVedaError) {
        throw error;
      }

      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_LOAD_FAILED,
        'Failed to initialize model',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Generate text completion
   * @param prompt - Input text prompt
   * @param options - Optional generation options
   * @returns Generated text
   */
  async generate(prompt: string, options?: GenerateOptions): Promise<string> {
    try {
      if (!this.isModelLoaded()) {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.MODEL_NOT_LOADED,
          'Model is not loaded. Call init() first.'
        );
      }

      if (!prompt) {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.INVALID_PARAMETER,
          'Prompt is required'
        );
      }

      const optionsJson = JSON.stringify(options || {});
      return await NativeEdgeVeda.generate(prompt, optionsJson);
    } catch (error) {
      if (error instanceof EdgeVedaError) {
        throw error;
      }

      throw new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        'Failed to generate text',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Generate text with streaming tokens
   * @param prompt - Input text prompt
   * @param onToken - Callback for each generated token
   * @param options - Optional generation options
   */
  async generateStream(
    prompt: string,
    onToken: TokenCallback,
    options?: GenerateOptions
  ): Promise<void> {
    try {
      if (!this.isModelLoaded()) {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.MODEL_NOT_LOADED,
          'Model is not loaded. Call init() first.'
        );
      }

      if (!prompt) {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.INVALID_PARAMETER,
          'Prompt is required'
        );
      }

      // Generate unique request ID
      const requestId = `req_${++this.requestIdCounter}_${Date.now()}`;

      // Register callback
      this.activeGenerations.set(requestId, onToken);

      const optionsJson = JSON.stringify(options || {});

      try {
        await NativeEdgeVeda.generateStream(prompt, optionsJson, requestId);
      } catch (error) {
        this.activeGenerations.delete(requestId);
        throw error;
      }
    } catch (error) {
      if (error instanceof EdgeVedaError) {
        throw error;
      }

      throw new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        'Failed to generate streaming text',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Cancel an ongoing generation
   * @param requestId - Optional request ID to cancel. If not provided, cancels all active generations
   */
  async cancelGeneration(requestId?: string): Promise<void> {
    try {
      if (requestId) {
        await NativeEdgeVeda.cancelGeneration(requestId);
        this.activeGenerations.delete(requestId);
      } else {
        // Cancel all active generations
        const promises = Array.from(this.activeGenerations.keys()).map((id) =>
          NativeEdgeVeda.cancelGeneration(id)
        );
        await Promise.all(promises);
        this.activeGenerations.clear();
      }
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to cancel generation',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Reset the conversation context while keeping the model loaded
   * This clears the KV cache and conversation history for a fresh start
   */
  async resetContext(): Promise<void> {
    try {
      if (!this.isModelLoaded()) {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.MODEL_NOT_LOADED,
          'Model is not loaded. Call init() first.'
        );
      }

      await NativeEdgeVeda.resetContext();
    } catch (error) {
      if (error instanceof EdgeVedaError) {
        throw error;
      }

      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to reset context',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Get memory usage statistics
   * @returns Memory usage information
   */
  getMemoryUsage(): MemoryUsage {
    try {
      const json = NativeEdgeVeda.getMemoryUsage();
      return JSON.parse(json);
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to get memory usage',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Get model information
   * @returns Model information
   */
  getModelInfo(): ModelInfo {
    try {
      if (!this.isModelLoaded()) {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.MODEL_NOT_LOADED,
          'Model is not loaded'
        );
      }

      const json = NativeEdgeVeda.getModelInfo();
      return JSON.parse(json);
    } catch (error) {
      if (error instanceof EdgeVedaError) {
        throw error;
      }

      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to get model info',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Check if model is loaded
   * @returns true if model is loaded
   */
  isModelLoaded(): boolean {
    try {
      return NativeEdgeVeda.isModelLoaded();
    } catch (error) {
      return false;
    }
  }

  /**
   * Unload the model from memory
   */
  async unloadModel(): Promise<void> {
    try {
      // Cancel all active generations first
      await this.cancelGeneration();

      await NativeEdgeVeda.unloadModel();
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to unload model',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Validate a model file
   * @param modelPath - Path to model file
   * @returns true if model is valid
   */
  async validateModel(modelPath: string): Promise<boolean> {
    try {
      return await NativeEdgeVeda.validateModel(modelPath);
    } catch (error) {
      return false;
    }
  }

  /**
   * Get available GPU devices
   * @returns Array of GPU device names
   */
  getAvailableGpuDevices(): string[] {
    try {
      const json = NativeEdgeVeda.getAvailableGpuDevices();
      return JSON.parse(json);
    } catch (error) {
      return [];
    }
  }

  /**
   * Clean up resources
   */
  destroy(): void {
    // Remove native event listeners
    this.eventEmitter.removeAllListeners(EVENTS.TOKEN_GENERATED);
    this.eventEmitter.removeAllListeners(EVENTS.GENERATION_COMPLETE);
    this.eventEmitter.removeAllListeners(EVENTS.GENERATION_ERROR);
    this.eventEmitter.removeAllListeners(EVENTS.MODEL_LOAD_PROGRESS);
    this.activeGenerations.clear();

    // Remove memory / lifecycle subscriptions
    this.memoryWarningSubscription?.remove();
    this.memoryWarningSubscription = null;
    this.appStateSubscription?.remove();
    this.appStateSubscription = null;
  }

  /**
   * Create a VisionWorker instance for vision inference
   * 
   * VisionWorker maintains a persistent vision context (~600MB VLM + mmproj)
   * for efficient frame processing. Use for camera-based vision tasks.
   * 
   * @returns New VisionWorker instance
   * @example
   * ```typescript
   * const worker = EdgeVeda.createVisionWorker();
   * await worker.initialize({
   *   modelPath: '/path/to/smolvlm2.gguf',
   *   mmprojPath: '/path/to/smolvlm2-mmproj.gguf'
   * });
   * 
   * // Enqueue frames from camera
   * worker.enqueueFrame(rgbData, width, height);
   * const result = await worker.processNextFrame();
   * 
   * await worker.cleanup();
   * ```
   */
  createVisionWorker() {
    // Dynamically import VisionWorker to avoid circular dependencies
    const { VisionWorker } = require('./VisionWorker');
    return new VisionWorker();
  }

  /**
   * Describe an image directly without creating a VisionWorker
   * 
   * Convenience method for one-off vision inference. For continuous
   * camera feeds, prefer createVisionWorker() for better performance.
   * 
   * @param config - Vision configuration
   * @param rgb - RGB888 pixel data (width * height * 3 bytes)
   * @param width - Frame width in pixels
   * @param height - Frame height in pixels
   * @param prompt - Text prompt for the model
   * @param params - Optional generation parameters
   * @returns Vision result with description and timings
   * @example
   * ```typescript
   * const result = await EdgeVeda.describeImage(
   *   {
   *     modelPath: '/path/to/smolvlm2.gguf',
   *     mmprojPath: '/path/to/smolvlm2-mmproj.gguf'
   *   },
   *   rgbData,
   *   640,
   *   480,
   *   'What objects do you see?'
   * );
   * console.log(result.description);
   * ```
   */
  async describeImage(
    config: any,
    rgb: Uint8Array,
    width: number,
    height: number,
    prompt: string = 'Describe what you see.',
    params?: any
  ): Promise<any> {
    const { VisionWorker } = require('./VisionWorker');
    const worker = new VisionWorker();
    
    try {
      await worker.initialize(config);
      return await worker.describeFrame(rgb, width, height, prompt, params);
    } finally {
      await worker.cleanup();
    }
  }

  /**
   * Check if vision context is loaded
   * @returns true if vision is loaded
   */
  isVisionLoaded(): boolean {
    try {
      return NativeEdgeVeda.isVisionLoaded();
    } catch (error) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Embedding methods
  // ---------------------------------------------------------------------------

  /**
   * Generate a text embedding vector
   *
   * @param text - Input text to embed
   * @returns Embedding result with vector, dimensions, and token count
   * @throws EdgeVedaError if an embedding model is not loaded
   */
  async embed(text: string): Promise<EmbeddingResult> {
    try {
      const json = await NativeEdgeVeda.embed(text);
      return JSON.parse(json) as EmbeddingResult;
    } catch (error) {
      if (error instanceof EdgeVedaError) throw error;
      throw new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        'Failed to generate embedding',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Generate embeddings for multiple texts sequentially
   *
   * @param texts - Array of input texts to embed
   * @param onProgress - Optional callback invoked after each embedding (done, total)
   * @returns Array of embedding results in the same order as input texts
   */
  async embedBatch(
    texts: string[],
    onProgress?: (done: number, total: number) => void
  ): Promise<EmbeddingResult[]> {
    const results: EmbeddingResult[] = [];
    for (let i = 0; i < texts.length; i++) {
      results.push(await this.embed(texts[i]));
      onProgress?.(i + 1, texts.length);
    }
    return results;
  }

  /**
   * Check whether memory usage exceeds a pressure threshold
   *
   * @param threshold - Fraction (0.0-1.0) above which memory is considered pressured (default 0.8)
   * @returns true if current memory usage exceeds the threshold
   */
  isMemoryPressure(threshold: number = 0.8): boolean {
    try {
      const raw = JSON.parse(NativeEdgeVeda.getMemoryUsage()) as MemoryStats;
      if (!raw.limitBytes || raw.limitBytes === 0) return false;
      const usage = raw.currentBytes / raw.limitBytes;
      return usage > threshold;
    } catch {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Whisper STT methods
  // ---------------------------------------------------------------------------

  /**
   * Initialize a persistent Whisper STT context
   *
   * @param modelPath - Absolute path to the Whisper GGUF model file
   * @param config - Optional Whisper configuration
   * @returns Backend name (e.g., "Metal", "CPU")
   */
  async initWhisper(modelPath: string, config?: WhisperConfig): Promise<string> {
    try {
      const configJson = JSON.stringify({
        numThreads: config?.numThreads ?? 4,
        useGpu: config?.useGpu ?? false,
      });
      return await NativeEdgeVeda.initWhisper(modelPath, configJson);
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_LOAD_FAILED,
        'Failed to initialize Whisper',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Transcribe 16 kHz mono PCM audio samples to text
   *
   * @param pcmSamples - Float32Array of 16 kHz mono PCM audio
   * @param params - Optional transcription parameters
   * @returns Transcription result with segments and full text
   */
  async transcribeAudio(pcmSamples: Float32Array, params?: WhisperParams): Promise<WhisperResult> {
    try {
      // Base64-encode Float32 bytes for TurboModule transfer
      const bytes = new Uint8Array(pcmSamples.buffer, pcmSamples.byteOffset, pcmSamples.byteLength);
      const pcmBase64 = this._uint8ArrayToBase64(bytes);
      const paramsJson = JSON.stringify({
        language: params?.language ?? 'en',
        translate: params?.translate ?? false,
        maxTokens: params?.maxTokens ?? 0,
      });
      const resultJson = await NativeEdgeVeda.transcribeAudio(pcmBase64, pcmSamples.length, paramsJson);
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
   * Create a managed WhisperSession for persistent STT inference
   *
   * @param modelPath - Absolute path to the Whisper GGUF model file
   * @returns Uninitialized WhisperSession (call initialize() before use)
   */
  createWhisperSession(modelPath: string): any {
    const { WhisperSession } = require('./WhisperSession');
    return new WhisperSession(modelPath);
  }

  /**
   * Free the Whisper STT context
   */
  async freeWhisper(): Promise<void> {
    try {
      await NativeEdgeVeda.freeWhisper();
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to free Whisper context',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Check if the Whisper context is initialized
   */
  isWhisperLoaded(): boolean {
    try {
      return NativeEdgeVeda.isWhisperLoaded();
    } catch {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Image generation methods
  // ---------------------------------------------------------------------------

  /**
   * Initialize a Stable Diffusion image generation context
   *
   * @param modelPath - Absolute path to the SD GGUF model file
   * @param config - Optional image generation configuration
   */
  async initImageGeneration(
    modelPath: string,
    config?: ImageGenerationConfig
  ): Promise<void> {
    try {
      const configJson = JSON.stringify({
        negativePrompt: config?.negativePrompt ?? '',
        width: config?.width ?? 512,
        height: config?.height ?? 512,
        steps: config?.steps ?? 20,
        cfgScale: config?.cfgScale ?? 7.0,
        seed: config?.seed ?? -1,
        sampler: config?.sampler ?? 0,
        schedule: config?.schedule ?? 0,
      });
      await NativeEdgeVeda.initImageGeneration(modelPath, configJson);
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_LOAD_FAILED,
        'Failed to initialize image generation',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Generate an image from a text prompt
   *
   * @param prompt - Text description of the image to generate
   * @param config - Optional generation parameters
   * @param onProgress - Optional callback for generation progress
   * @param cancelToken - Optional cancellation token
   * @returns Image result with pixel data and metadata
   */
  async generateImage(
    prompt: string,
    config?: ImageGenerationConfig,
    onProgress?: (progress: ImageProgress) => void,
    cancelToken?: CancelToken
  ): Promise<ImageResult> {
    cancelToken?.throwIfCancelled();

    // Subscribe to progress events
    let progressSub: any = null;
    if (onProgress) {
      progressSub = this.eventEmitter.addListener(
        EVENTS.IMAGE_PROGRESS,
        (payload: { step: number; totalSteps: number; elapsedSeconds: number }) => {
          if (cancelToken?.isCancelled) return;
          const progress: ImageProgress = {
            step: payload.step,
            totalSteps: payload.totalSteps,
            elapsedSeconds: payload.elapsedSeconds,
            progress: payload.totalSteps > 0 ? payload.step / payload.totalSteps : 0,
          };
          onProgress(progress);
        }
      );
    }

    try {
      cancelToken?.throwIfCancelled();

      const paramsJson = JSON.stringify({
        prompt,
        negativePrompt: config?.negativePrompt ?? '',
        width: config?.width ?? 512,
        height: config?.height ?? 512,
        steps: config?.steps ?? 20,
        cfgScale: config?.cfgScale ?? 7.0,
        seed: config?.seed ?? -1,
        sampler: config?.sampler ?? 0,
        schedule: config?.schedule ?? 0,
      });

      const resultJson = await NativeEdgeVeda.generateImage(paramsJson);
      return JSON.parse(resultJson) as ImageResult;
    } catch (error) {
      if (error instanceof EdgeVedaError) throw error;
      throw new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        'Image generation failed',
        error instanceof Error ? error.message : String(error)
      );
    } finally {
      progressSub?.remove();
    }
  }

  /**
   * Free the image generation context
   */
  async freeImageGeneration(): Promise<void> {
    try {
      await NativeEdgeVeda.freeImageGeneration();
    } catch (error) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Failed to free image generation context',
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  /**
   * Check if the image generation context is initialized
   */
  isImageGenerationLoaded(): boolean {
    try {
      return NativeEdgeVeda.isImageGenerationLoaded();
    } catch {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private _uint8ArrayToBase64(bytes: Uint8Array): string {
    const BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    const len = bytes.length;
    for (let i = 0; i < len; i += 3) {
      const byte1 = bytes[i];
      const byte2 = i + 1 < len ? bytes[i + 1] : 0;
      const byte3 = i + 2 < len ? bytes[i + 2] : 0;
      result += BASE64_CHARS[byte1 >> 2];
      result += BASE64_CHARS[((byte1 & 0x03) << 4) | (byte2 >> 4)];
      result += i + 1 < len ? BASE64_CHARS[((byte2 & 0x0f) << 2) | (byte3 >> 6)] : '=';
      result += i + 2 < len ? BASE64_CHARS[byte3 & 0x3f] : '=';
    }
    return result;
  }

  /**
   * Get SDK version
   * @returns Version string
   * @example
   * ```typescript
   * const version = EdgeVeda.getVersion();
   * console.log('EdgeVeda SDK version:', version); // "0.1.0"
   * ```
   */
  static getVersion(): string {
    return version;
  }
}

// Export singleton instance
export default new EdgeVedaSDK();
