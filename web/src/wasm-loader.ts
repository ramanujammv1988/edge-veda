/**
 * WASM Module Loader with WebGPU Detection
 */

import type { WebGPUCapabilities } from './types';

/**
 * Detects WebGPU support and capabilities
 */
export async function detectWebGPU(): Promise<WebGPUCapabilities> {
  if (typeof navigator === 'undefined' || !('gpu' in navigator)) {
    return {
      supported: false,
      error: 'WebGPU not available in this browser',
    };
  }

  try {
    const gpu = navigator.gpu as any;
    if (!gpu) {
      return {
        supported: false,
        error: 'navigator.gpu is undefined',
      };
    }

    const adapter = await gpu.requestAdapter({
      powerPreference: 'high-performance',
    });

    if (!adapter) {
      return {
        supported: false,
        error: 'Failed to request WebGPU adapter',
      };
    }

    const device = await adapter.requestDevice();
    const info = adapter.info;
    const features = Array.from(adapter.features) as string[];
    const limits = adapter.limits;

    // Clean up device after checking
    device.destroy();

    return {
      supported: true,
      adapter: {
        vendor: info.vendor || 'Unknown',
        architecture: info.architecture || 'Unknown',
        device: info.device || 'Unknown',
        description: info.description || 'Unknown',
      },
      features,
      limits: {
        maxBufferSize: limits.maxBufferSize,
        maxStorageBufferBindingSize: limits.maxStorageBufferBindingSize,
        maxComputeWorkgroupSizeX: limits.maxComputeWorkgroupSizeX,
        maxComputeWorkgroupSizeY: limits.maxComputeWorkgroupSizeY,
        maxComputeWorkgroupSizeZ: limits.maxComputeWorkgroupSizeZ,
      },
    };
  } catch (error) {
    return {
      supported: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Checks if WASM with threads is supported
 */
export function supportsWasmThreads(): boolean {
  try {
    // Check for SharedArrayBuffer (required for threads)
    if (typeof SharedArrayBuffer === 'undefined') {
      return false;
    }

    // Check for Atomics
    if (typeof Atomics === 'undefined') {
      return false;
    }

    // Additional check: try to create a small SharedArrayBuffer
    try {
      new SharedArrayBuffer(1);
      return true;
    } catch {
      return false;
    }
  } catch {
    return false;
  }
}

/**
 * Gets the optimal number of threads for WASM
 */
export function getOptimalThreadCount(): number {
  if (!supportsWasmThreads()) {
    return 1;
  }

  const hardwareConcurrency = navigator.hardwareConcurrency || 4;
  // Cap at 8 threads for browser stability
  return Math.min(hardwareConcurrency, 8);
}

/**
 * WASM module instance interface
 */
export interface WasmModule {
  instance: WebAssembly.Instance;
  module: WebAssembly.Module;
  memory: WebAssembly.Memory;
  exports: Record<string, any>;
}

/**
 * Options for loading WASM module
 */
export interface WasmLoadOptions {
  wasmPath: string;
  numThreads?: number;
  importObject?: WebAssembly.Imports;
  onProgress?: (loaded: number, total: number) => void;
}

/**
 * Loads a WASM module from a URL with progress tracking
 */
export async function loadWasmModule(
  options: WasmLoadOptions
): Promise<WasmModule> {
  const { wasmPath, numThreads = 1, importObject = {}, onProgress } = options;

  try {
    // Fetch WASM binary with progress
    const response = await fetch(wasmPath);

    if (!response.ok) {
      throw new Error(`Failed to fetch WASM: ${response.statusText}`);
    }

    const contentLength = response.headers.get('Content-Length');
    const total = contentLength ? parseInt(contentLength, 10) : 0;

    if (!response.body) {
      throw new Error('Response body is null');
    }

    // Track download progress
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let loaded = 0;

    while (true) {
      const { done, value } = await reader.read();

      if (done) break;

      chunks.push(value);
      loaded += value.length;

      if (onProgress && total > 0) {
        onProgress(loaded, total);
      }
    }

    // Combine chunks
    const wasmBytes = new Uint8Array(loaded);
    let offset = 0;
    for (const chunk of chunks) {
      wasmBytes.set(chunk, offset);
      offset += chunk.length;
    }

    // Create memory based on thread support
    const memory = new WebAssembly.Memory({
      initial: 256, // 16MB
      maximum: 32768, // 2GB
      shared: numThreads > 1,
    });

    // Build import object
    const imports: WebAssembly.Imports = {
      env: {
        memory,
        ...importObject.env,
      },
      wasi_snapshot_preview1: {
        proc_exit: () => {},
        fd_write: () => 0,
        fd_close: () => 0,
        fd_seek: () => 0,
        ...importObject.wasi_snapshot_preview1,
      },
      ...importObject,
    };

    // Compile and instantiate
    let instance: WebAssembly.Instance;
    let module: WebAssembly.Module;

    if (WebAssembly.instantiateStreaming) {
      // Use streaming compilation if available
      const newResponse = await fetch(wasmPath);
      const result = await WebAssembly.instantiateStreaming(newResponse, imports);
      instance = result.instance;
      module = result.module;
    } else {
      // Fallback to regular instantiation
      const result = await WebAssembly.instantiate(wasmBytes, imports);
      instance = result.instance;
      module = result.module;
    }

    return {
      instance,
      module,
      memory,
      exports: instance.exports as Record<string, any>,
    };
  } catch (error) {
    throw new Error(
      `Failed to load WASM module: ${
        error instanceof Error ? error.message : 'Unknown error'
      }`
    );
  }
}

/**
 * Validates WASM module exports
 */
export function validateWasmExports(
  exports: Record<string, any>,
  requiredFunctions: string[]
): boolean {
  for (const funcName of requiredFunctions) {
    if (typeof exports[funcName] !== 'function') {
      console.error(`Missing required WASM export: ${funcName}`);
      return false;
    }
  }
  return true;
}

/**
 * Gets WASM memory as a typed array view
 */
export function getWasmMemoryView(memory: WebAssembly.Memory): {
  uint8: Uint8Array;
  uint32: Uint32Array;
  float32: Float32Array;
  int32: Int32Array;
} {
  const buffer = memory.buffer;
  return {
    uint8: new Uint8Array(buffer),
    uint32: new Uint32Array(buffer),
    float32: new Float32Array(buffer),
    int32: new Int32Array(buffer),
  };
}

/**
 * Copies data into WASM memory
 */
export function copyToWasmMemory(
  memory: WebAssembly.Memory,
  data: ArrayBuffer | Uint8Array,
  offset: number
): void {
  const view = new Uint8Array(memory.buffer);
  const sourceView = data instanceof Uint8Array ? data : new Uint8Array(data);
  view.set(sourceView, offset);
}

/**
 * Reads data from WASM memory
 */
export function readFromWasmMemory(
  memory: WebAssembly.Memory,
  offset: number,
  length: number
): Uint8Array {
  const view = new Uint8Array(memory.buffer);
  return view.slice(offset, offset + length);
}

/**
 * Allocates memory in WASM heap (assumes malloc export)
 */
export function wasmMalloc(
  exports: Record<string, any>,
  size: number
): number {
  if (typeof exports.malloc !== 'function') {
    throw new Error('WASM module does not export malloc');
  }
  return exports.malloc(size) as number;
}

/**
 * Frees memory in WASM heap (assumes free export)
 */
export function wasmFree(exports: Record<string, any>, ptr: number): void {
  if (typeof exports.free !== 'function') {
    throw new Error('WASM module does not export free');
  }
  exports.free(ptr);
}
