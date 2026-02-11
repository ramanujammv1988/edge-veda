/**
 * Edge Veda SDK - JavaScript Wrapper
 * High-level JavaScript API wrapping the native TurboModule
 */

import { NativeEventEmitter, NativeModules } from 'react-native';
import NativeEdgeVeda from './NativeEdgeVeda';
import type {
  EdgeVedaConfig,
  GenerateOptions,
  MemoryUsage,
  ModelInfo,
  TokenCallback,
  ProgressCallback,
} from './types';
import { EdgeVedaError, EdgeVedaErrorCode } from './types';
import { version } from '../package.json';

/**
 * Native event types
 */
const EVENTS = {
  TOKEN_GENERATED: 'EdgeVeda_TokenGenerated',
  GENERATION_COMPLETE: 'EdgeVeda_GenerationComplete',
  GENERATION_ERROR: 'EdgeVeda_GenerationError',
  MODEL_LOAD_PROGRESS: 'EdgeVeda_ModelLoadProgress',
} as const;

/**
 * Edge Veda SDK Main Class
 * Provides high-level API for on-device LLM inference
 */
class EdgeVedaSDK {
  private eventEmitter: NativeEventEmitter;
  private requestIdCounter = 0;
  private activeGenerations = new Map<string, TokenCallback>();
  private progressCallback?: ProgressCallback;

  constructor() {
    // Create event emitter for native events
    this.eventEmitter = new NativeEventEmitter(
      NativeModules.EdgeVeda || NativeEdgeVeda
    );

    // Set up event listeners
    this.setupEventListeners();
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

      const configJson = JSON.stringify(config || {});
      await NativeEdgeVeda.initialize(modelPath, configJson);

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
    this.eventEmitter.removeAllListeners(EVENTS.TOKEN_GENERATED);
    this.eventEmitter.removeAllListeners(EVENTS.GENERATION_COMPLETE);
    this.eventEmitter.removeAllListeners(EVENTS.GENERATION_ERROR);
    this.eventEmitter.removeAllListeners(EVENTS.MODEL_LOAD_PROGRESS);
    this.activeGenerations.clear();
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
