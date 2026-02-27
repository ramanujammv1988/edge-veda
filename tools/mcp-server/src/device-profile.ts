/**
 * Device profiling and memory estimation for model recommendations.
 *
 * Simplified TypeScript port of Dart DeviceProfile and MemoryEstimator.
 * Runs on the developer's Mac (not the iOS device) to estimate whether
 * models will fit on the target device.
 */

import { exec } from "./utils.js";
import type { ModelInfo } from "./model-registry.js";

export enum DeviceTier {
  minimum = "minimum",
  low = "low",
  medium = "medium",
  high = "high",
  ultra = "ultra",
}

export interface ConnectedDevice {
  name: string;
  udid: string;
  osVersion: string;
}

/**
 * Tier-based safe memory budgets in MB.
 * iOS 60% rule: apps get killed (jetsam) above ~60% of physical RAM.
 */
const TIER_BUDGET_MB: Record<DeviceTier, number> = {
  [DeviceTier.minimum]: 2400,
  [DeviceTier.low]: 3600,
  [DeviceTier.medium]: 3600,
  [DeviceTier.high]: 4800,
  [DeviceTier.ultra]: 9600,
};

/**
 * Detect the developer Mac's hardware tier based on RAM.
 * Uses system_profiler on macOS.
 */
export async function detectDeviceTier(): Promise<{
  tier: DeviceTier;
  ramGB: number;
  chip: string;
}> {
  try {
    const result = await exec("system_profiler SPHardwareDataType");
    const output = result.stdout;

    // Parse RAM
    const ramMatch = output.match(/Memory:\s*(\d+)\s*GB/i);
    const ramGB = ramMatch ? parseInt(ramMatch[1], 10) : 8;

    // Parse chip
    const chipMatch = output.match(/Chip:\s*(.+)/i);
    const chip = chipMatch ? chipMatch[1].trim() : "Unknown";

    const tier =
      ramGB < 6
        ? DeviceTier.minimum
        : ramGB < 8
          ? DeviceTier.low
          : ramGB < 10
            ? DeviceTier.medium
            : ramGB < 16
              ? DeviceTier.high
              : DeviceTier.ultra;

    return { tier, ramGB, chip };
  } catch {
    return { tier: DeviceTier.high, ramGB: 8, chip: "Unknown" };
  }
}

/**
 * Detect connected physical iOS devices via xcrun xctrace.
 */
export async function getConnectedIOSDevice(): Promise<ConnectedDevice | null> {
  try {
    const result = await exec("xcrun xctrace list devices 2>&1");
    const lines = result.stdout.split("\n");

    for (const line of lines) {
      // Format: "Device Name (OS Version) (UDID)"
      const match = line.match(
        /^(.+?)\s+\((\d+\.\d+(?:\.\d+)?)\)\s+\(([0-9A-Fa-f-]+)\)\s*$/,
      );
      if (match) {
        return {
          name: match[1].trim(),
          udid: match[3],
          osVersion: match[2],
        };
      }
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Estimate memory usage for a model in MB.
 *
 * Port of Dart MemoryEstimator:
 * - Non-LLM (whisper, minilm): fileSize/MB + 100
 * - LLM: (weights*0.15 + kvCache + metalBuffers + 150) * 1.3
 */
export function estimateMemoryMB(
  model: ModelInfo,
  contextLength = 2048,
): number {
  const family = model.family ?? "";

  // Non-LLM models: simpler formula
  if (family === "whisper" || family === "minilm") {
    return Math.round(model.sizeBytes / (1024 * 1024) + 100);
  }

  // Image generation models: rough estimate from file size
  if (
    family === "stable-diffusion" ||
    family === "stable-diffusion-xl" ||
    family === "flux"
  ) {
    return Math.round(model.sizeBytes / (1024 * 1024) + 500);
  }

  // LLM/VLM models: calibrated formula
  const modelWeightsMB = (model.sizeBytes * 0.15) / (1024 * 1024);
  const parametersB = model.parametersB ?? 1.0;
  const kvQuantFactor = model.quantization === "F16" ? 2.0 : 1.0;
  const kvCacheMB = parametersB * 4.0 * (contextLength / 2048) * kvQuantFactor;
  const metalBuffersMB = parametersB * 80;
  const runtimeOverheadMB = 150;

  const rawTotal = modelWeightsMB + kvCacheMB + metalBuffersMB + runtimeOverheadMB;
  return Math.round(rawTotal * 1.3);
}

/**
 * Check if a model fits within the safe memory budget for a device tier.
 */
export function modelFitsDevice(
  model: ModelInfo,
  tier: DeviceTier,
): boolean {
  const estimatedMB = estimateMemoryMB(model);
  return estimatedMB <= TIER_BUDGET_MB[tier];
}

/**
 * Format bytes as human-readable string (e.g., "668 MB", "4.9 GB").
 */
export function formatSize(bytes: number): string {
  const mb = bytes / (1024 * 1024);
  if (mb < 1024) return `${Math.round(mb)} MB`;
  return `${(mb / 1024).toFixed(1)} GB`;
}
