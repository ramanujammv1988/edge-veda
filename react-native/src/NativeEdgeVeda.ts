/**
 * Native Edge Veda TurboModule Spec
 * This is the interface specification for the native module
 */

import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

/**
 * TurboModule specification for Edge Veda
 * This defines the contract between JavaScript and native code
 */
export interface Spec extends TurboModule {
  /**
   * Initialize the model with given path and configuration
   * @param modelPath - Absolute path to the model file
   * @param config - JSON string of configuration options
   * @returns Promise that resolves when model is loaded
   */
  initialize(modelPath: string, config: string): Promise<void>;

  /**
   * Generate text completion for given prompt
   * @param prompt - Input text prompt
   * @param options - JSON string of generation options
   * @returns Promise resolving to generated text
   */
  generate(prompt: string, options: string): Promise<string>;

  /**
   * Generate text with streaming tokens
   * This will emit events through the event emitter
   * @param prompt - Input text prompt
   * @param options - JSON string of generation options
   * @param requestId - Unique identifier for this generation request
   * @returns Promise that resolves when generation is complete
   */
  generateStream(prompt: string, options: string, requestId: string): Promise<void>;

  /**
   * Cancel an ongoing streaming generation
   * @param requestId - Request identifier to cancel
   * @returns Promise that resolves when cancelled
   */
  cancelGeneration(requestId: string): Promise<void>;

  /**
   * Get current memory usage statistics
   * @returns JSON string containing memory usage data
   */
  getMemoryUsage(): string;

  /**
   * Get model information
   * @returns JSON string containing model info
   */
  getModelInfo(): string;

  /**
   * Check if model is currently loaded
   * @returns true if model is loaded, false otherwise
   */
  isModelLoaded(): boolean;

  /**
   * Reset the conversation context
   * @returns Promise that resolves when context is reset
   */
  resetContext(): Promise<void>;

  /**
   * Unload the model from memory
   * @returns Promise that resolves when model is unloaded
   */
  unloadModel(): Promise<void>;

  /**
   * Validate model file at given path
   * @param modelPath - Path to model file to validate
   * @returns Promise resolving to true if valid, false otherwise
   */
  validateModel(modelPath: string): Promise<boolean>;

  /**
   * Get supported GPU devices
   * @returns JSON string array of available GPU devices
   */
  getAvailableGpuDevices(): string;

  /**
   * Add a listener for native events
   * Required for TurboModule event support
   */
  addListener(eventName: string): void;

  /**
   * Remove event listeners
   * Required for TurboModule event support
   */
  removeListeners(count: number): void;

  // Vision Inference Methods

  /**
   * Initialize vision inference context
   * @param config - JSON string of vision configuration
   * @returns Promise resolving to backend name
   */
  initVision(config: string): Promise<string>;

  /**
   * Describe an image using vision inference
   * @param rgbBytes - Base64-encoded RGB888 pixel data
   * @param width - Image width in pixels
   * @param height - Image height in pixels
   * @param prompt - Text prompt for the model
   * @param params - JSON string of generation parameters
   * @returns Promise resolving to JSON string containing description and timings
   */
  describeImage(
    rgbBytes: string,
    width: number,
    height: number,
    prompt: string,
    params: string
  ): Promise<string>;

  /**
   * Free vision inference context
   * @returns Promise that resolves when context is freed
   */
  freeVision(): Promise<void>;

  /**
   * Check if vision context is initialized
   * @returns true if vision context is loaded
   */
  isVisionLoaded(): boolean;

  // ---------------------------------------------------------------------------
  // Embedding Methods
  // ---------------------------------------------------------------------------

  /**
   * Generate a text embedding vector
   * @param text - Input text to embed
   * @returns JSON string containing EmbeddingResult (embedding, dimensions, tokenCount, timeMs)
   */
  embed(text: string): Promise<string>;

  // ---------------------------------------------------------------------------
  // Whisper STT Methods
  // ---------------------------------------------------------------------------

  /**
   * Initialize Whisper STT context
   * @param modelPath - Absolute path to the Whisper GGUF model file
   * @param config - JSON string of WhisperConfig options
   * @returns Promise resolving to backend name (e.g., "Metal", "CPU")
   */
  initWhisper(modelPath: string, config: string): Promise<string>;

  /**
   * Transcribe audio samples to text
   * @param pcmBase64 - Base64-encoded 16 kHz mono Float32 PCM audio data
   * @param nSamples - Number of float32 samples (not bytes)
   * @param params - JSON string of WhisperParams options
   * @returns JSON string containing WhisperResult (segments, fullText, processingTimeMs)
   */
  transcribeAudio(pcmBase64: string, nSamples: number, params: string): Promise<string>;

  /**
   * Free Whisper STT context
   * @returns Promise that resolves when context is freed
   */
  freeWhisper(): Promise<void>;

  /**
   * Check if Whisper context is initialized
   * @returns true if Whisper context is loaded
   */
  isWhisperLoaded(): boolean;

  // ---------------------------------------------------------------------------
  // Image Generation Methods
  // ---------------------------------------------------------------------------

  /**
   * Initialize image generation context
   * @param modelPath - Absolute path to the Stable Diffusion GGUF model file
   * @param config - JSON string of ImageGenerationConfig options
   * @returns Promise that resolves when context is initialized
   */
  initImageGeneration(modelPath: string, config: string): Promise<void>;

  /**
   * Generate an image from a text prompt
   *
   * Progress events are emitted as 'EdgeVeda_ImageProgress' native events
   * with { step, totalSteps, elapsedSeconds } payload.
   *
   * @param params - JSON string containing prompt and ImageGenerationConfig
   * @returns JSON string containing base64-encoded RGB pixel data, width, height, generationTimeMs
   */
  generateImage(params: string): Promise<string>;

  /**
   * Free image generation context
   * @returns Promise that resolves when context is freed
   */
  freeImageGeneration(): Promise<void>;

  /**
   * Check if image generation context is initialized
   * @returns true if image generation context is loaded
   */
  isImageGenerationLoaded(): boolean;
}

/**
 * Get the native Edge Veda TurboModule
 */
export default TurboModuleRegistry.getEnforcing<Spec>('EdgeVeda');
