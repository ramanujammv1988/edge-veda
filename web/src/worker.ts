/**
 * Web Worker for Edge Veda Inference
 * Handles WASM module loading and inference execution
 */

import type {
  WorkerMessage,
  WorkerMessageType,
  WorkerInitMessage,
  WorkerGenerateMessage,
  EdgeVedaConfig,
  GenerateResult,
  StreamChunk,
  LoadProgress,
} from './types';
import { loadWasmModule, detectWebGPU, getOptimalThreadCount } from './wasm-loader';
import { downloadAndCacheModel } from './model-cache';

// Worker state
interface WorkerState {
  initialized: boolean;
  config: EdgeVedaConfig | null;
  wasmModule: any;
  modelData: ArrayBuffer | null;
  deviceType: 'webgpu' | 'wasm';
}

const state: WorkerState = {
  initialized: false,
  config: null,
  wasmModule: null,
  modelData: null,
  deviceType: 'wasm',
};

/**
 * Sends a message to the main thread
 */
function sendMessage(message: Partial<WorkerMessage>) {
  self.postMessage(message);
}

/**
 * Sends progress update
 */
function sendProgress(id: string, progress: LoadProgress) {
  sendMessage({
    type: 'progress' as WorkerMessageType.PROGRESS,
    id,
    progress,
  });
}

/**
 * Initializes the inference engine
 */
async function initialize(message: WorkerInitMessage): Promise<void> {
  const { id, config } = message;

  try {
    sendProgress(id, {
      stage: 'downloading',
      progress: 0,
      message: 'Detecting device capabilities...',
    });

    // Detect device type
    let deviceType: 'webgpu' | 'wasm' = 'wasm';

    if (config.device === 'auto' || config.device === 'webgpu') {
      const webgpuCaps = await detectWebGPU();
      if (webgpuCaps.supported) {
        deviceType = 'webgpu';
        console.log('WebGPU detected, using GPU acceleration');
      } else {
        console.log('WebGPU not available, falling back to WASM:', webgpuCaps.error);
        deviceType = 'wasm';
      }
    }

    state.deviceType = deviceType;

    // Download and cache model
    sendProgress(id, {
      stage: 'downloading',
      progress: 0,
      message: 'Downloading model...',
    });

    const modelUrl = config.modelId.startsWith('http')
      ? config.modelId
      : `/models/${config.modelId}/${config.precision || 'fp16'}/model.bin`;

    state.modelData = await downloadAndCacheModel(
      modelUrl,
      config.modelId,
      config.precision || 'fp16',
      (loaded, total) => {
        const progress = (loaded / total) * 100;
        sendProgress(id, {
          stage: 'downloading',
          progress,
          loaded,
          total,
          message: `Downloading model: ${(loaded / 1024 / 1024).toFixed(1)}MB / ${(total / 1024 / 1024).toFixed(1)}MB`,
        });
      }
    );

    sendProgress(id, {
      stage: 'loading',
      progress: 0,
      message: 'Loading WASM module...',
    });

    // Load WASM module
    const wasmPath = config.wasmPath || '/wasm/edgeveda.wasm';
    const numThreads = config.numThreads || getOptimalThreadCount();

    state.wasmModule = await loadWasmModule({
      wasmPath,
      numThreads,
      onProgress: (loaded, total) => {
        const progress = (loaded / total) * 100;
        sendProgress(id, {
          stage: 'loading',
          progress,
          loaded,
          total,
          message: 'Loading WASM module...',
        });
      },
    });

    sendProgress(id, {
      stage: 'initializing',
      progress: 50,
      message: 'Initializing inference engine...',
    });

    // Initialize the inference engine with model data
    // This is a placeholder - actual implementation depends on WASM API
    const exports = state.wasmModule.exports;

    if (typeof exports.init === 'function') {
      // Copy model data to WASM memory
      const modelSize = state.modelData.byteLength;
      const modelPtr = exports.malloc(modelSize);

      const wasmMemory = new Uint8Array(state.wasmModule.memory.buffer);
      const modelBytes = new Uint8Array(state.modelData);
      wasmMemory.set(modelBytes, modelPtr);

      // Call init function
      const result = exports.init(
        modelPtr,
        modelSize,
        config.maxContextLength || 2048,
        deviceType === 'webgpu' ? 1 : 0
      );

      if (result !== 0) {
        throw new Error(`Failed to initialize inference engine: error code ${result}`);
      }
    }

    sendProgress(id, {
      stage: 'ready',
      progress: 100,
      message: 'Ready for inference',
    });

    state.initialized = true;
    state.config = config;

    sendMessage({
      type: 'init_success' as WorkerMessageType.INIT_SUCCESS,
      id,
    });
  } catch (error) {
    sendMessage({
      type: 'init_error' as WorkerMessageType.INIT_ERROR,
      id,
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
}

/**
 * Generates text (non-streaming)
 */
async function generate(message: WorkerGenerateMessage): Promise<void> {
  const { id, options } = message;

  if (!state.initialized || !state.wasmModule) {
    sendMessage({
      type: 'generate_error' as WorkerMessageType.GENERATE_ERROR,
      id,
      error: 'Worker not initialized',
    });
    return;
  }

  try {
    const startTime = performance.now();
    const exports = state.wasmModule.exports;

    // Encode prompt to tokens (placeholder implementation)
    const prompt = options.prompt;
    const maxTokens = options.maxTokens || 512;
    const temperature = options.temperature || 0.7;
    const topP = options.topP || 0.9;
    const topK = options.topK || 40;

    let generatedText = '';
    let tokensGenerated = 0;

    // This is a placeholder - actual implementation depends on WASM API
    if (typeof exports.generate === 'function') {
      // Allocate memory for prompt
      const encoder = new TextEncoder();
      const promptBytes = encoder.encode(prompt);
      const promptPtr = exports.malloc(promptBytes.length) as number;

      const wasmMemory = new Uint8Array(state.wasmModule.memory.buffer);
      wasmMemory.set(promptBytes, promptPtr);

      // Allocate output buffer (4 bytes per token, UTF-8 worst case)
      const outputBufferSize = maxTokens * 4;
      const outputPtr = exports.malloc(outputBufferSize) as number;

      // generate() returns an error code (0 = success), NOT a token count
      const errorCode = exports.generate(
        promptPtr,
        promptBytes.length,
        outputPtr,
        outputBufferSize,
        maxTokens,
        temperature,
        topP,
        topK
      ) as number;

      if (errorCode !== 0) {
        exports.free(promptPtr);
        exports.free(outputPtr);
        throw new Error(`WASM generate failed: error code ${errorCode}`);
      }

      // Read null-terminated UTF-8 string from outputPtr
      const memView = new Uint8Array(state.wasmModule.memory.buffer);
      let end = outputPtr;
      while (end < memView.length && memView[end] !== 0) end++;
      generatedText = new TextDecoder().decode(memView.subarray(outputPtr, end));
      tokensGenerated = generatedText.split(/\s+/).filter(Boolean).length;

      // Free memory
      exports.free(promptPtr);
      exports.free(outputPtr);
    } else {
      // Fallback mock implementation for testing
      generatedText = `[Mock response to: "${prompt.slice(0, 50)}..."]`;
      tokensGenerated = generatedText.split(' ').length;

      // Simulate processing time
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    const endTime = performance.now();
    const timeMs = endTime - startTime;
    const tokensPerSecond = (tokensGenerated / timeMs) * 1000;

    const result: GenerateResult = {
      text: generatedText,
      tokensGenerated,
      timeMs,
      tokensPerSecond,
      stopped: tokensGenerated < maxTokens,
      stopReason: tokensGenerated < maxTokens ? 'stop_sequence' : 'max_tokens',
    };

    sendMessage({
      type: 'generate_complete' as WorkerMessageType.GENERATE_COMPLETE,
      id,
      result,
    });
  } catch (error) {
    sendMessage({
      type: 'generate_error' as WorkerMessageType.GENERATE_ERROR,
      id,
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
}

/**
 * Generates text (streaming)
 */
async function generateStream(message: WorkerGenerateMessage): Promise<void> {
  const { id, options } = message;

  if (!state.initialized || !state.wasmModule) {
    sendMessage({
      type: 'generate_error' as WorkerMessageType.GENERATE_ERROR,
      id,
      error: 'Worker not initialized',
    });
    return;
  }

  try {
    const startTime = performance.now();
    const exports = state.wasmModule.exports;
    const maxTokens = options.maxTokens || 512;

    let generatedText = '';
    let tokensGenerated = 0;

    // This is a placeholder - actual implementation would use streaming API
    if (typeof exports.generateStream === 'function') {
      // Streaming implementation with WASM callback
      // (requires WASM module to support callbacks)
    } else {
      // Fallback mock streaming implementation
      const words = `This is a mock streaming response to the prompt: "${options.prompt}".
        In a real implementation, this would use the WASM module's streaming API
        to generate tokens one at a time.`.split(' ');

      for (let i = 0; i < Math.min(words.length, maxTokens); i++) {
        const token = words[i] + ' ';
        generatedText += token;
        tokensGenerated++;

        const chunk: StreamChunk = {
          token,
          text: generatedText,
          tokensGenerated,
          done: false,
        };

        sendMessage({
          type: 'generate_chunk' as WorkerMessageType.GENERATE_CHUNK,
          id,
          chunk,
        });

        // Simulate token generation delay
        await new Promise(resolve => setTimeout(resolve, 50));
      }
    }

    const endTime = performance.now();
    const timeMs = endTime - startTime;
    const tokensPerSecond = (tokensGenerated / timeMs) * 1000;

    // Send final chunk
    const finalChunk: StreamChunk = {
      token: '',
      text: generatedText,
      tokensGenerated,
      done: true,
      stats: {
        timeMs,
        tokensPerSecond,
        stopReason: tokensGenerated < maxTokens ? 'stop_sequence' : 'max_tokens',
      },
    };

    sendMessage({
      type: 'generate_chunk' as WorkerMessageType.GENERATE_CHUNK,
      id,
      chunk: finalChunk,
    });
  } catch (error) {
    sendMessage({
      type: 'generate_error' as WorkerMessageType.GENERATE_ERROR,
      id,
      error: error instanceof Error ? error.message : 'Unknown error',
    });
  }
}

/**
 * Message handler
 */
self.onmessage = async (event: MessageEvent<WorkerMessage>) => {
  const message = event.data;

  switch (message.type) {
    case 'init':
      await initialize(message as WorkerInitMessage);
      break;

    case 'generate':
      const genMessage = message as WorkerGenerateMessage;
      if (genMessage.stream) {
        await generateStream(genMessage);
      } else {
        await generate(genMessage);
      }
      break;

    case 'reset_context':
      if (!state.initialized || !state.wasmModule) {
        sendMessage({
          type: 'generate_error' as WorkerMessageType.GENERATE_ERROR,
          id: message.id,
          error: 'Worker not initialized',
        });
        return;
      }

      try {
        const exports = state.wasmModule.exports;

        // Call reset function if available in WASM module
        if (typeof exports.reset_context === 'function') {
          const result = exports.reset_context();
          if (result !== 0) {
            throw new Error(`Failed to reset context: error code ${result}`);
          }
        }

        sendMessage({
          type: 'reset_success' as WorkerMessageType.RESET_SUCCESS,
          id: message.id,
        });
      } catch (error) {
        sendMessage({
          type: 'generate_error' as WorkerMessageType.GENERATE_ERROR,
          id: message.id,
          error: error instanceof Error ? error.message : 'Unknown error',
        });
      }
      break;

    case 'terminate':
      // Clean up resources
      if (state.wasmModule?.exports?.cleanup) {
        state.wasmModule.exports.cleanup();
      }
      self.close();
      break;

    default:
      console.warn('Unknown message type:', message.type);
  }
};

// Export type for TypeScript
export type {};
