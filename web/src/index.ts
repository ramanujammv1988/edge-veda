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
  LoadProgress,
} from './types';

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

    // Create worker
    try {
      // In a real implementation, the worker URL would be bundled/imported
      // For now, we use a blob URL with the worker code
      const workerUrl = this.createWorkerUrl();
      this.worker = new Worker(workerUrl, { type: 'module' });

      // Set up message handler
      this.worker.onmessage = this.handleWorkerMessage.bind(this);
      this.worker.onerror = (error) => {
        console.error('Worker error:', error);
        if (this.config.onError) {
          this.config.onError(new Error(error.message));
        }
      };

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

    return response.stats;
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
   * Gets the SDK version
   */
  static getVersion(): string {
    return '1.0.0';
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
