/**
 * Edge Veda React Native SDK – ModelAdvisor
 *
 * Detects device capabilities and recommends models that fit within the
 * available memory budget. Mirrors the Flutter SDK's ModelAdvisor and
 * the web SDK's BrowserProfile for cross-platform parity.
 *
 * Adapted from web/src/ModelAdvisor.ts for React Native:
 * - Uses React Native `Platform` API instead of `navigator.*`
 * - GPU availability inferred from platform (iOS = Metal, Android = Vulkan)
 * - Conservative memory estimates (no direct API for exact RAM in RN)
 *
 * @example
 * ```typescript
 * const profile = detectDeviceCapabilities();
 * const recommended = recommendModels(profile, ModelRegistry.getAllModels());
 * console.log('Best model:', recommended[0]?.name);
 * ```
 */

import { Platform } from 'react-native';
import type { DownloadableModelInfo } from './types';

/**
 * Snapshot of the device's hardware capabilities relevant to on-device inference.
 */
export interface DeviceProfile {
  /** Whether a GPU backend is available (Metal on iOS, Vulkan on Android) */
  hasGpu: boolean;

  /** Estimated GPU-accessible memory in megabytes (0 if unknown) */
  estimatedGpuMemoryMb: number;

  /**
   * Estimated system RAM in megabytes.
   *
   * Conservative platform-based estimate:
   * - iOS: 4096 MB (covers iPhone 12+ with 4-8 GB RAM)
   * - Android: 2048 MB (conservative floor for fragmented Android market)
   */
  estimatedSystemMemoryMb: number;

  /** Number of logical CPU cores (conservative default: 4) */
  hardwareConcurrency: number;

  /** Platform identifier string (e.g., "ios 17.0", "android 34") */
  platform: string;

  /** Normalized OS identifier */
  os: 'ios' | 'android' | 'other';
}

/**
 * Detect the current device's hardware capabilities.
 *
 * Returns conservative estimates suitable for memory budget calculations.
 * Call once at startup and cache the result.
 */
export function detectDeviceCapabilities(): DeviceProfile {
  const os = Platform.OS as string;

  // GPU is available on all modern iOS (Metal) and Android (Vulkan/OpenCL) devices
  const hasGpu = os === 'ios' || os === 'android';

  // Conservative platform-based RAM estimates
  let estimatedSystemMemoryMb: number;
  if (os === 'ios') {
    // iPhone 12+ has 4 GB; iPhone 14 Pro+ has 6 GB. Use 4 GB as safe floor.
    estimatedSystemMemoryMb = 4096;
  } else if (os === 'android') {
    // Android market is fragmented; use 2 GB as conservative floor.
    estimatedSystemMemoryMb = 2048;
  } else {
    estimatedSystemMemoryMb = 2048;
  }

  // Mobile GPUs share system memory; estimate 50% accessible for GPU tasks
  const estimatedGpuMemoryMb = hasGpu
    ? Math.round(estimatedSystemMemoryMb * 0.5)
    : 0;

  return {
    hasGpu,
    estimatedGpuMemoryMb,
    estimatedSystemMemoryMb,
    hardwareConcurrency: 4, // navigator.hardwareConcurrency not available in RN
    platform: `${Platform.OS} ${Platform.Version}`,
    os: os === 'ios' ? 'ios' : os === 'android' ? 'android' : 'other',
  };
}

/**
 * Estimate the total memory a model will require at runtime in bytes.
 *
 * Adds a 10% overhead on top of the download size to account for the KV
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
 * - Text / embedding / whisper / imageGeneration models: must fit in
 *   `estimatedSystemMemoryMb * 0.7`
 * - Vision / mmproj models: require GPU and must fit in
 *   `estimatedGpuMemoryMb * 0.7` (falls back to system budget if GPU
 *   memory is unknown)
 *
 * The 0.7 headroom factor reserves 30% for the OS, JS heap, and other
 * app resources.
 */
export function recommendModels(
  profile: DeviceProfile,
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
      // Vision models need GPU; skip entirely if unavailable
      if (!profile.hasGpu) return false;
      return required <= gpuBudgetBytes;
    }

    return required <= systemBudgetBytes;
  });

  // Sort descending by size — largest model that fits is most capable
  return fitting.sort((a, b) => b.sizeBytes - a.sizeBytes);
}
