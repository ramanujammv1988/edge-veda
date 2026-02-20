/**
 * Edge Veda Web SDK – ModelAdvisor
 *
 * Detects browser capabilities and recommends models that fit within the
 * available memory budget. Mirrors the Flutter SDK's ModelAdvisor for
 * cross-platform parity.
 *
 * @example
 * ```typescript
 * const profile = await detectBrowserCapabilities();
 * const recommended = recommendModels(profile, ModelRegistry.getAllModels());
 * console.log('Best model:', recommended[0]?.name);
 * ```
 */

import type { DownloadableModelInfo } from './types';
import { detectWebGPU, supportsWasmThreads } from './wasm-loader';

/**
 * Snapshot of the browser's hardware and API capabilities relevant to
 * on-device inference.
 */
export interface BrowserProfile {
  /** Whether WebGPU is available and a suitable adapter was obtained */
  hasWebGPU: boolean;
  /** Estimated GPU memory in megabytes (from WebGPU adapter limits, or 0) */
  estimatedGpuMemoryMb: number;
  /**
   * Estimated system memory in megabytes.
   *
   * Derived from `navigator.deviceMemory` (Gigabytes → MB). Returns 2048 MB
   * as a conservative default on browsers that don't expose `deviceMemory`.
   */
  estimatedSystemMemoryMb: number;
  /** Whether SharedArrayBuffer + Atomics are available (needed for multi-threaded WASM) */
  supportsWasmThreads: boolean;
  /** Number of logical CPU cores (`navigator.hardwareConcurrency`, default 4) */
  hardwareConcurrency: number;
  /** `navigator.platform` (e.g. "MacIntel", "Win32", "Linux aarch64") */
  platform: string;
}

/**
 * Detect the current browser's hardware and API capabilities.
 *
 * Performs an async WebGPU probe — call this once at startup and cache
 * the result rather than calling it on every recommendation.
 */
export async function detectBrowserCapabilities(): Promise<BrowserProfile> {
  const webgpuCaps = await detectWebGPU();

  let estimatedGpuMemoryMb = 0;
  if (webgpuCaps.supported && webgpuCaps.limits) {
    // maxBufferSize is the best available proxy for addressable GPU memory
    estimatedGpuMemoryMb = Math.round(
      webgpuCaps.limits.maxBufferSize / (1024 * 1024)
    );
  }

  // navigator.deviceMemory is in GB (floating point); multiply by 1024 → MB.
  // The property is only exposed in Chromium-based browsers; fall back to 2 GB.
  const deviceMemoryGb =
    typeof navigator !== 'undefined' &&
    'deviceMemory' in navigator
      ? (navigator as Navigator & { deviceMemory: number }).deviceMemory
      : 2;
  const estimatedSystemMemoryMb = Math.round(deviceMemoryGb * 1024);

  return {
    hasWebGPU: webgpuCaps.supported,
    estimatedGpuMemoryMb,
    estimatedSystemMemoryMb,
    supportsWasmThreads: supportsWasmThreads(),
    hardwareConcurrency:
      typeof navigator !== 'undefined'
        ? navigator.hardwareConcurrency || 4
        : 4,
    platform:
      typeof navigator !== 'undefined' ? navigator.platform : 'unknown',
  };
}

/**
 * Estimate the total memory a model will require at runtime in bytes.
 *
 * Adds a 10 % overhead on top of the download size to account for the KV
 * cache and runtime bookkeeping.
 */
export function estimateModelMemory(model: DownloadableModelInfo): number {
  return Math.round(model.sizeBytes * 1.1);
}

/**
 * Return the subset of `allModels` that fit within the available memory
 * budget, sorted from largest to smallest (best fitting model first).
 *
 * **Filtering rules:**
 * - Text / embedding / whisper models: must fit in `estimatedSystemMemoryMb * 0.7`
 * - Vision / mmproj models: require WebGPU and must fit in `estimatedGpuMemoryMb * 0.7`
 *   (falls back to system memory budget if GPU memory is unknown)
 *
 * The 0.7 headroom factor reserves 30 % for the browser, JS heap, and other
 * page resources.
 */
export function recommendModels(
  profile: BrowserProfile,
  allModels: DownloadableModelInfo[]
): DownloadableModelInfo[] {
  const systemBudgetBytes = profile.estimatedSystemMemoryMb * 1024 * 1024 * 0.7;
  const gpuBudgetBytes =
    profile.estimatedGpuMemoryMb > 0
      ? profile.estimatedGpuMemoryMb * 1024 * 1024 * 0.7
      : systemBudgetBytes;

  const fitting = allModels.filter((model) => {
    const required = estimateModelMemory(model);
    const type = model.modelType ?? 'text';

    if (type === 'vision' || type === 'mmproj') {
      // Vision models need WebGPU; skip entirely if unavailable
      if (!profile.hasWebGPU) return false;
      return required <= gpuBudgetBytes;
    }

    return required <= systemBudgetBytes;
  });

  // Sort descending by size — largest model that fits is most capable
  return fitting.sort((a, b) => b.sizeBytes - a.sizeBytes);
}
