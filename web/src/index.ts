/**
 * Edge Veda Web SDK
 * Browser-based LLM inference using WebGPU/WASM
 */

import type {
  EdgeVedaConfig,
  GenerateOptions,
  GenerateResult,
  StreamChunk,
  WorkerMessage,
  WorkerMessageType,
} from './types';
import { version } from '../package.json';
import { detectWebGPU, supportsWasmThreads } from './wasm-loader';

export * from './types';
export { detectWebGPU, supportsWasmThreads, getOptimalThreadCount } from './wasm-loader';
export {
  getCachedModel,
  listCachedModels,
  deleteCachedModel,
  clearCache,
  getCacheSize,
  estimateStorageQuota,
} from './model-cache';

// Export ChatSession and related types
export { ChatSession } from './ChatSession';
export type { ChatMessage } from './ChatTypes';
export { ChatRole, SystemPromptPreset } from './ChatTypes';
export { ChatTemplate } from './ChatTemplate';

// Export VisionWorker and related types
export { VisionWorker } from './VisionWorker';
export { FrameQueue } from './FrameQueue';
export type {
  VisionConfig,
  VisionResult,
  VisionTimings,
  VisionGenerationParams,
  FrameData,
} from './types';

// Export WhisperWorker and related types
export { WhisperWorker, WhisperSession } from './WhisperWorker';
export type {
  WhisperConfig,
  WhisperParams,
  WhisperSegment,
  WhisperResult,
  WhisperTimings,
} from './types';

// Export Embeddings API types
export type { EmbeddingResult } from './types';

// Export Model Manager
export { ModelManager, ModelDownloadError, ModelChecksumError } from './ModelManager';

// Export Tool Calling System (Priority 2)
export {
  ToolRegistry,
  ToolDefinition,
  ToolCall,
  ToolResult,
  ToolPriority,
  ToolCallParseException,
} from './ToolRegistry';

export { GbnfBuilder } from './GbnfBuilder';

export { SchemaValidator, SchemaValidationResult } from './SchemaValidator';

export { ToolTemplate, ToolTemplateFormat } from './ToolTemplate';

// Export Vector Index & RAG Pipeline (Priority 2)
export { VectorIndex, SearchResult } from './VectorIndex';

export { RagPipeline } from './RagPipeline';
export type { RagConfig, IEdgeVeda } from './RagPipeline';

// Phase 4: Runtime Supervision exports
export {
  Budget,
  BudgetProfile,
  BudgetConstraint,
  WorkloadPriority,
  WorkloadId,
} from './Budget';
export type { EdgeVedaBudget, MeasuredBaseline, BudgetViolation } from './Budget';

export { LatencyTracker } from './LatencyTracker';

export { ResourceMonitor } from './ResourceMonitor';

export { ThermalMonitor } from './ThermalMonitor';

export { BatteryDrainTracker } from './BatteryDrainTracker';

export { Scheduler } from './Scheduler';
export { TaskPriority, TaskStatus } from './Scheduler';
export type { TaskHandle, QueueStatus } from './Scheduler';

export type { RuntimePolicy } from './RuntimePolicy';
export {
  RuntimePolicyPresets,
  RuntimePolicyEnforcer,
  detectCapabilities,
  throttleRecommendationToString,
} from './RuntimePolicy';
export type {
  RuntimePolicyOptions,
  RuntimeCapabilities,
  ThrottleRecommendation,
  RuntimePolicyEnforcerOptions,
} from './RuntimePolicy';

export {
  Telemetry,
  BudgetViolationType,
  ViolationSeverity,
  latencyStatsToString,
} from './Telemetry';
export type {
  LatencyMetric,
  BudgetViolationRecord,
  ResourceSnapshot,
  LatencyStats,
} from './Telemetry';

// Phase 5: Model Management exports
export { ModelRegistry } from './ModelRegistry';

// Model Advisor — browser capability detection and model recommendation
export type { BrowserProfile } from './ModelAdvisor';
export {
  detectBrowserCapabilities,
  estimateModelMemory,
  recommendModels,
} from './ModelAdvisor';

// Typed exception hierarchy — re-exported via `export * from './types'` above

// Phase 6: Camera Utilities exports
export { CameraUtils } from './CameraUtils';

// Phase 7: Observability exports
export { PerfTrace } from './PerfTrace';
export { NativeErrorCode } from './NativeErrorCode';

/**
 * Main EdgeVeda class for browser-based inference
 */
export class EdgeVeda {
  private worker: Worker | null = null;
  private config: EdgeVedaConfig;
  private initialized = false;
  private messageId = 0;
  private pendingRequests = new Map<
    string,
    {
      resolve: (value: any) => void;
      reject: (error: Error) => void;
      onChunk?: (chunk: StreamChunk) => void;
    }
  >();

  // Worker recovery state
  private workerRestartCount = 0;
  private readonly maxWorkerRestarts = 3;
  private workerRestartCooldownMs = 2000;
  private lastWorkerCrashTime = 0;
  private workerRecoveryInProgress = false;
  private memoryPressureCallback: ((event: import('./types').MemoryPressureEvent) => void) | null = null;

  constructor(config: EdgeVedaConfig) {
    this.config = {
      device: 'auto',
      precision: 'fp16',
      maxContextLength: 2048,
      enableCache: true,
      cacheName: 'edgeveda-models',
      ...config,
    };
  }

  /**
   * Initializes the inference engine
   */
  async init(): Promise<void> {
    if (this.initialized) {
      throw new Error('EdgeVeda already initialized');
    }

    // Perform browser compatibility checks
    await this.checkBrowserCompatibility();

    // Create worker
    try {
      // In a real implementation, the worker URL would be bundled/imported
      // For now, we use a blob URL with the worker code
      await this.createAndAttachWorker();

      // Reset restart counter on successful init
      this.workerRestartCount = 0;

      // Send init message
      await this.sendWorkerMessage(
        {
          type: 'init' as WorkerMessageType.INIT,
          config: this.config,
        },
        (message) => {
          if (message.type === 'progress' && this.config.onProgress) {
            this.config.onProgress(message.progress);
          }
        }
      );

      this.initialized = true;
    } catch (error) {
      throw new Error(
        `Failed to initialize EdgeVeda: ${
          error instanceof Error ? error.message : 'Unknown error'
        }`
      );
    }
  }

  /**
   * Creates and attaches a Web Worker with error recovery handlers.
   */
  private async createAndAttachWorker(): Promise<void> {
    const workerUrl = this.createWorkerUrl();
    this.worker = new Worker(workerUrl, { type: 'module' });

    // Set up message handler
    this.worker.onmessage = this.handleWorkerMessage.bind(this);

    // Error handler with auto-recovery
    this.worker.onerror = (error) => {
      console.error('[EdgeVeda] Worker error:', error);
      if (this.config.onError) {
        this.config.onError(new Error(error.message));
      }
      this.handleWorkerCrash(error.message);
    };
  }

  /**
   * Handles a worker crash by attempting auto-restart.
   * Implements exponential backoff and a maximum restart limit.
   */
  private async handleWorkerCrash(errorMessage: string): Promise<void> {
    if (this.workerRecoveryInProgress) {
      return;
    }

    const now = Date.now();

    // Reset restart counter if enough time has passed since last crash
    if (now - this.lastWorkerCrashTime > 30_000) {
      this.workerRestartCount = 0;
    }
    this.lastWorkerCrashTime = now;

    // Reject all pending requests
    for (const [id, request] of this.pendingRequests) {
      request.reject(new Error(`Worker crashed: ${errorMessage}`));
      this.pendingRequests.delete(id);
    }

    // Check if we've exceeded restart limit
    if (this.workerRestartCount >= this.maxWorkerRestarts) {
      console.error(
        `[EdgeVeda] Worker crashed ${this.workerRestartCount} times. ` +
        'Giving up on auto-restart. Call init() to manually reinitialize.'
      );
      this.initialized = false;
      this.worker = null;
      return;
    }

    // Attempt restart with exponential backoff
    this.workerRecoveryInProgress = true;
    this.workerRestartCount++;
    const backoffMs = this.workerRestartCooldownMs * Math.pow(2, this.workerRestartCount - 1);

    console.warn(
      `[EdgeVeda] Worker crashed. Attempting restart ${this.workerRestartCount}/${this.maxWorkerRestarts} ` +
      `in ${backoffMs}ms...`
    );

    try {
      // Terminate old worker
      this.worker?.terminate();
      this.worker = null;

      await new Promise((resolve) => setTimeout(resolve, backoffMs));

      // Create new worker
      await this.createAndAttachWorker();

      // Re-initialize
      await this.sendWorkerMessage(
        {
          type: 'init' as WorkerMessageType.INIT,
          config: this.config,
        },
        (message) => {
          if (message.type === 'progress' && this.config.onProgress) {
            this.config.onProgress(message.progress);
          }
        }
      );

      console.log('[EdgeVeda] Worker successfully restarted.');
      this.initialized = true;
    } catch (restartError) {
      console.error('[EdgeVeda] Worker restart failed:', restartError);
      this.initialized = false;
      this.worker = null;
    } finally {
      this.workerRecoveryInProgress = false;
    }
  }

  /**
   * Gets the number of times the worker has been restarted.
   * Useful for monitoring/telemetry.
   */
  getWorkerRestartCount(): number {
    return this.workerRestartCount;
  }

  /**
   * Generates text (non-streaming)
   */
  async generate(options: GenerateOptions): Promise<GenerateResult> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    const response = await this.sendWorkerMessage({
      type: 'generate' as WorkerMessageType.GENERATE,
      options,
      stream: false,
    });

    return response.result;
  }

  /**
   * Generates text (streaming)
   */
  async *generateStream(
    options: GenerateOptions
  ): AsyncGenerator<StreamChunk, void, unknown> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    const chunks: StreamChunk[] = [];
    let resolveStream: ((value: void) => void) | null = null;
    let rejectStream: ((error: Error) => void) | null = null;

    const streamPromise = new Promise<void>((resolve, reject) => {
      resolveStream = resolve;
      rejectStream = reject;
    });

    // Send generate message with streaming enabled
    this.sendWorkerMessage(
      {
        type: 'generate' as WorkerMessageType.GENERATE,
        options,
        stream: true,
      },
      (message) => {
        if (message.type === 'generate_chunk') {
          chunks.push(message.chunk);
        }
      }
    )
      .then(() => {
        resolveStream?.();
      })
      .catch((error) => {
        rejectStream?.(error);
      });

    // Yield chunks as they arrive
    let lastYieldedIndex = 0;

    while (true) {
      // Wait a bit for new chunks
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Yield new chunks
      while (lastYieldedIndex < chunks.length) {
        const chunk = chunks[lastYieldedIndex];
        lastYieldedIndex++;
        yield chunk;

        if (chunk.done) {
          return;
        }
      }

      // Check if stream is complete
      if (lastYieldedIndex > 0 && chunks[lastYieldedIndex - 1]?.done) {
        break;
      }
    }

    await streamPromise;
  }

  /**
   * Terminates the worker and cleans up resources
   */
  async terminate(): Promise<void> {
    if (this.worker) {
      this.worker.postMessage({
        type: 'terminate' as WorkerMessageType.TERMINATE,
        id: this.generateMessageId(),
      });
      this.worker.terminate();
      this.worker = null;
    }

    this.initialized = false;
    this.pendingRequests.clear();
  }

  /**
   * Checks if the engine is initialized
   */
  isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Gets the current configuration
   */
  getConfig(): Readonly<EdgeVedaConfig> {
    return { ...this.config };
  }

  /**
   * Gets current memory usage statistics
   */
  async getMemoryUsage(): Promise<import('./types').MemoryStats> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    const response = await this.sendWorkerMessage({
      type: 'get_memory_usage' as WorkerMessageType.GET_MEMORY_USAGE,
    });

    return response.memoryStats;
  }

  /**
   * Gets information about the loaded model
   */
  async getModelInfo(): Promise<import('./types').ModelInfo> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    const response = await this.sendWorkerMessage({
      type: 'get_model_info' as WorkerMessageType.GET_MODEL_INFO,
    });

    return response.info;
  }

  /**
   * Cancels the currently running generation
   */
  async cancelGeneration(): Promise<void> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    await this.sendWorkerMessage({
      type: 'cancel_generation' as WorkerMessageType.CANCEL_GENERATION,
    });
  }

  /**
   * Unloads the current model and frees memory
   */
  async unloadModel(): Promise<void> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    await this.sendWorkerMessage({
      type: 'unload_model' as WorkerMessageType.UNLOAD_MODEL,
    });
  }

  /**
   * Resets the conversation context
   */
  async resetContext(): Promise<void> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    await this.sendWorkerMessage({
      type: 'reset_context' as WorkerMessageType.RESET_CONTEXT,
    });
  }

  /**
   * Computes text embeddings for semantic search and RAG
   * 
   * Generates a dense vector representation of the input text.
   * The embedding vector can be used for similarity comparisons,
   * semantic search, and retrieval-augmented generation (RAG).
   * 
   * @param text - Input text to embed
   * @returns EmbeddingResult containing the embedding vector and metadata
   */
  async embed(text: string): Promise<import('./types').EmbeddingResult> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    const response = await this.sendWorkerMessage({
      type: 'embed' as WorkerMessageType.EMBED,
      text,
    });

    return response.result;
  }

  /**
   * Embed multiple texts in a single batch.
   *
   * More efficient than calling embed() in a loop because the model stays
   * loaded in the worker between calls. Returns results in the same order
   * as the input texts.
   *
   * Mirrors Flutter SDK's EdgeVeda.embedBatch().
   *
   * @param texts - Array of input texts to embed
   * @param onProgress - Optional callback fired after each text is embedded
   * @returns Array of EmbeddingResult in input order
   */
  async embedBatch(
    texts: string[],
    onProgress?: (completed: number, total: number) => void
  ): Promise<import('./types').EmbeddingResult[]> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    const results: import('./types').EmbeddingResult[] = [];
    for (let i = 0; i < texts.length; i++) {
      results.push(await this.embed(texts[i]));
      onProgress?.(i + 1, texts.length);
    }
    return results;
  }

  /**
   * Check whether memory usage exceeds a pressure threshold.
   *
   * Returns true when the proportion of used memory is above `threshold`
   * (default 0.8 = 80%). Uses `usagePercent` when available (requires
   * limitBytes to be set), falling back to the `percentage` field.
   *
   * Mirrors Flutter SDK's EdgeVeda.isMemoryPressure().
   *
   * @param threshold - Fractional pressure level 0.0–1.0 (default 0.8)
   */
  async isMemoryPressure(threshold: number = 0.8): Promise<boolean> {
    const stats = await this.getMemoryUsage();
    if (stats.usagePercent !== undefined) {
      return stats.usagePercent > threshold;
    }
    return stats.percentage > threshold;
  }

  /**
   * Set a hard memory ceiling in bytes.
   *
   * Passes the limit to the WASM module via `ev_set_memory_limit`. The module
   * will emit a memory-pressure notification (via `setMemoryPressureCallback`)
   * when usage exceeds ~80 % of the limit.
   *
   * @param limitBytes Maximum memory the inference engine may use, in bytes.
   *   Pass 0 to remove the limit.
   */
  async setMemoryLimit(limitBytes: number): Promise<void> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    await this.sendWorkerMessage({
      type: 'set_memory_limit' as WorkerMessageType.SET_MEMORY_LIMIT,
      limitBytes,
    });
  }

  /**
   * Register a callback for memory pressure events.
   *
   * The callback is invoked from the main thread whenever the worker posts a
   * `memory_pressure` notification (triggered when usage exceeds 80 % of the
   * configured limit). Replaces any previously registered callback.
   *
   * Pass `null` to remove the current callback.
   *
   * @param callback Called with a `MemoryPressureEvent` when pressure is detected.
   */
  setMemoryPressureCallback(
    callback: ((event: import('./types').MemoryPressureEvent) => void) | null
  ): void {
    this.memoryPressureCallback = callback;
  }

  /**
   * Ask the WASM engine to release any cached allocations it can safely free.
   *
   * Maps to `ev_memory_cleanup`. This is a best-effort operation — the engine
   * decides which internal buffers to release.
   */
  async memoryCleanup(): Promise<void> {
    if (!this.initialized || !this.worker) {
      throw new Error('EdgeVeda not initialized. Call init() first.');
    }

    await this.sendWorkerMessage({
      type: 'memory_cleanup' as WorkerMessageType.MEMORY_CLEANUP,
    });
  }

  /**
   * Gets the SDK version
   */
  static getVersion(): string {
    return version;
  }

  /**
   * Checks browser compatibility and warns about potential issues
   */
  private async checkBrowserCompatibility(): Promise<void> {
    const warnings: string[] = [];
    const errors: string[] = [];

    // Detect browser and version
    const browserInfo = this.detectBrowser();

    // Check WebGPU support
    if (this.config.device === 'webgpu' || this.config.device === 'auto') {
      const webgpuResult = await detectWebGPU();
      
      if (!webgpuResult.supported) {
        if (this.config.device === 'webgpu') {
          errors.push(
            `WebGPU is not supported in this browser: ${webgpuResult.error}. ` +
            'Consider using device: "wasm" or "auto" for fallback.'
          );
        } else {
          warnings.push(
            `WebGPU is not available (${webgpuResult.error}). ` +
            'Falling back to WASM-only mode. Performance may be reduced.'
          );
        }
      } else {
        console.log('WebGPU detected:', webgpuResult.adapter);
      }
    }

    // Check WASM threads support
    const hasWasmThreads = supportsWasmThreads();
    if (!hasWasmThreads) {
      warnings.push(
        'SharedArrayBuffer not available. WASM threading disabled. ' +
        'For better performance, ensure cross-origin isolation is enabled ' +
        '(COOP and COEP headers).'
      );
    }

    // Safari-specific warnings
    if (browserInfo.isSafari) {
      warnings.push(
        'Safari detected. Note: WebGPU support in Safari is experimental. ' +
        'If you encounter issues, try switching to device: "wasm".'
      );

      if (browserInfo.version && browserInfo.version < 17) {
        warnings.push(
          `Safari ${browserInfo.version} may have limited WebGPU support. ` +
          'Please update to Safari 17+ for best compatibility.'
        );
      }

      // Safari has strict SharedArrayBuffer requirements
      if (!hasWasmThreads) {
        warnings.push(
          'Safari requires specific cross-origin headers for SharedArrayBuffer. ' +
          'Ensure your server sends: Cross-Origin-Opener-Policy: same-origin ' +
          'and Cross-Origin-Embedder-Policy: require-corp'
        );
      }
    }

    // Firefox-specific warnings
    if (browserInfo.isFirefox) {
      if (browserInfo.version && browserInfo.version < 113) {
        warnings.push(
          `Firefox ${browserInfo.version} detected. WebGPU requires Firefox 113+. ` +
          'Please update your browser or use device: "wasm".'
        );
      }
    }

    // Check Web Workers support
    if (typeof Worker === 'undefined') {
      errors.push(
        'Web Workers are not supported in this environment. ' +
        'EdgeVeda requires Web Workers for background inference.'
      );
    }

    // Check for mobile browsers
    if (browserInfo.isMobile) {
      warnings.push(
        'Mobile browser detected. Large models may cause memory issues. ' +
        'Consider using smaller quantized models (Q4, Q5) for better performance.'
      );
    }

    // Check available memory (if Performance API is available)
    if ('memory' in performance && (performance as any).memory) {
      const memoryInfo = (performance as any).memory;
      const availableMB = memoryInfo.jsHeapSizeLimit / (1024 * 1024);
      
      if (availableMB < 512) {
        warnings.push(
          `Limited memory detected (${Math.round(availableMB)}MB available). ` +
          'Large models may fail to load. Consider using smaller models.'
        );
      }
    }

    // Log all warnings
    if (warnings.length > 0) {
      console.warn('EdgeVeda compatibility warnings:');
      warnings.forEach((warning, i) => {
        console.warn(`  ${i + 1}. ${warning}`);
      });
    }

    // Throw errors if critical features are missing
    if (errors.length > 0) {
      const errorMessage = 'EdgeVeda initialization failed due to compatibility issues:\n' +
        errors.map((err, i) => `  ${i + 1}. ${err}`).join('\n');
      throw new Error(errorMessage);
    }

    // Log successful compatibility check
    if (warnings.length === 0 && errors.length === 0) {
      console.log('EdgeVeda compatibility check passed. Browser fully supported.');
    }
  }

  /**
   * Detects the current browser and version
   */
  private detectBrowser(): {
    name: string;
    version: number | null;
    isSafari: boolean;
    isChrome: boolean;
    isFirefox: boolean;
    isEdge: boolean;
    isMobile: boolean;
  } {
    const ua = navigator.userAgent;
    const isMobile = /Mobile|Android|iPhone|iPad|iPod/i.test(ua);

    // Safari detection
    const isSafari = /^((?!chrome|android).)*safari/i.test(ua);
    const safariMatch = ua.match(/Version\/(\d+)/);
    
    // Chrome detection
    const isChrome = /Chrome/.test(ua) && /Google Inc/.test(navigator.vendor);
    const chromeMatch = ua.match(/Chrome\/(\d+)/);
    
    // Firefox detection
    const isFirefox = /Firefox/.test(ua);
    const firefoxMatch = ua.match(/Firefox\/(\d+)/);
    
    // Edge detection
    const isEdge = /Edg/.test(ua);
    const edgeMatch = ua.match(/Edg\/(\d+)/);

    let name = 'Unknown';
    let version: number | null = null;

    if (isEdge && edgeMatch) {
      name = 'Edge';
      version = parseInt(edgeMatch[1], 10);
    } else if (isChrome && chromeMatch) {
      name = 'Chrome';
      version = parseInt(chromeMatch[1], 10);
    } else if (isFirefox && firefoxMatch) {
      name = 'Firefox';
      version = parseInt(firefoxMatch[1], 10);
    } else if (isSafari && safariMatch) {
      name = 'Safari';
      version = parseInt(safariMatch[1], 10);
    }

    return {
      name,
      version,
      isSafari,
      isChrome,
      isFirefox,
      isEdge,
      isMobile,
    };
  }

  /**
   * Sends a message to the worker and waits for response
   */
  private sendWorkerMessage(
    message: Partial<WorkerMessage>,
    onProgress?: (message: WorkerMessage) => void
  ): Promise<any> {
    return new Promise((resolve, reject) => {
      const id = this.generateMessageId();
      const fullMessage = { ...message, id };

      this.pendingRequests.set(id, {
        resolve,
        reject,
        onChunk: onProgress as any,
      });

      this.worker?.postMessage(fullMessage);

      // Timeout after 5 minutes
      setTimeout(() => {
        if (this.pendingRequests.has(id)) {
          this.pendingRequests.delete(id);
          reject(new Error('Worker request timeout'));
        }
      }, 300000);
    });
  }

  /**
   * Handles messages from the worker
   */
  private handleWorkerMessage(event: MessageEvent<WorkerMessage>) {
    const message = event.data;
    const request = this.pendingRequests.get(message.id);

    if (!request) {
      console.warn('Received message for unknown request:', message.id);
      return;
    }

    switch (message.type) {
      case 'init_success':
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      case 'init_error':
        request.reject(new Error(message.error));
        this.pendingRequests.delete(message.id);
        break;

      case 'generate_complete':
        request.resolve(message);
        this.pendingRequests.delete(message.id);
        break;

      case 'generate_chunk':
        if (request.onChunk) {
          request.onChunk(message.chunk);
        }
        if (message.chunk.done) {
          request.resolve({});
          this.pendingRequests.delete(message.id);
        }
        break;

      case 'generate_error':
        request.reject(new Error(message.error));
        this.pendingRequests.delete(message.id);
        break;

      case 'progress':
        if (request.onChunk) {
          request.onChunk(message as any);
        }
        break;

      case 'memory_usage_response':
        request.resolve(message);
        this.pendingRequests.delete(message.id);
        break;

      case 'model_info_response':
        request.resolve(message);
        this.pendingRequests.delete(message.id);
        break;

      case 'cancel_success':
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      case 'unload_success':
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      case 'reset_success':
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      case 'embed_success':
        request.resolve(message);
        this.pendingRequests.delete(message.id);
        break;

      case 'embed_error':
        request.reject(new Error(message.error));
        this.pendingRequests.delete(message.id);
        break;

      case 'set_memory_limit_success':
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      case 'memory_cleanup_success':
        request.resolve({});
        this.pendingRequests.delete(message.id);
        break;

      case 'memory_pressure':
        // Pressure notifications are unsolicited — no pending request to resolve
        if (this.memoryPressureCallback) {
          try {
            this.memoryPressureCallback((message as any).event);
          } catch (error) {
            console.warn('[EdgeVeda] Error in memory pressure callback:', error);
          }
        }
        break;

      default:
        console.warn('Unknown message type:', message.type);
    }
  }

  /**
   * Generates a unique message ID
   */
  private generateMessageId(): string {
    return `msg_${++this.messageId}_${Date.now()}`;
  }

  /**
   * Creates a worker URL from the worker code
   * In production, this would be a separate bundled file
   */
  private createWorkerUrl(): string {
    // In a real implementation, this would import the actual worker file
    // For now, we create a simple placeholder
    const workerCode = `
      // Worker will be loaded from separate bundle in production
      import('./worker.js').then(module => {
        console.log('Worker module loaded');
      });
    `;

    const blob = new Blob([workerCode], { type: 'application/javascript' });
    return URL.createObjectURL(blob);
  }
}

/**
 * Convenience function to create and initialize EdgeVeda instance
 */
export async function init(config: EdgeVedaConfig): Promise<EdgeVeda> {
  const instance = new EdgeVeda(config);
  await instance.init();
  return instance;
}

/**
 * Convenience function for one-off text generation
 */
export async function generate(
  config: EdgeVedaConfig,
  options: GenerateOptions
): Promise<GenerateResult> {
  const instance = await init(config);
  try {
    return await instance.generate(options);
  } finally {
    await instance.terminate();
  }
}

/**
 * Convenience function for one-off streaming generation
 */
export async function* generateStream(
  config: EdgeVedaConfig,
  options: GenerateOptions
): AsyncGenerator<StreamChunk, void, unknown> {
  const instance = await init(config);
  try {
    yield* instance.generateStream(options);
  } finally {
    await instance.terminate();
  }
}

// Default export
export default EdgeVeda;
