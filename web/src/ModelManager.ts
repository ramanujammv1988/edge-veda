/**
 * ModelManager — Web equivalent of Flutter SDK's ModelManager.
 *
 * High-level model lifecycle management: download, cache, verify, and delete.
 * Wraps the low-level model-cache.ts (IndexedDB) and downloadModelWithRetry()
 * infrastructure to provide a Flutter-parity API.
 *
 * Mirrors Flutter SDK's ModelManager API:
 * - downloadModel()         — fetch + cache, skip if already cached
 * - isModelCached()         — check IndexedDB for a cached model
 * - getDownloadedModels()   — list all cached model IDs
 * - getModelSize()          — size in bytes of a cached model
 * - deleteModel()           — remove a model from IndexedDB
 * - clearAllModels()        — remove all cached models
 * - getTotalModelsSize()    — sum of cached model sizes in bytes
 * - verifyModelChecksum()   — SHA-256 verification via Web Crypto
 */

import {
  getCachedModel,
  listCachedModels,
  deleteCachedModel,
  clearCache,
  getCacheSize,
  downloadModelWithRetry,
  validateModelChecksum,
} from './model-cache';
import type { DownloadableModelInfo, DownloadProgress, CancelToken } from './types';

/**
 * Manages model downloads, caching, and verification for the Web SDK.
 *
 * Models are stored in IndexedDB (via model-cache.ts) rather than the
 * filesystem. SHA-256 checksum verification uses Web Crypto (crypto.subtle).
 *
 * @example
 * ```typescript
 * const manager = new ModelManager();
 *
 * // Download with progress tracking
 * const buffer = await manager.downloadModel(ModelRegistry.llama32_1b, {
 *   onProgress: (p) => console.log(`${p.percentage.toFixed(1)}%`),
 * });
 *
 * // Check cache
 * if (await manager.isModelCached('llama-3.2-1b-instruct-q4')) {
 *   console.log('Model ready');
 * }
 * ```
 */
export class ModelManager {
  /** Active CancelToken for the current download (if any) */
  private _currentCancelToken: CancelToken | null = null;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /**
   * Download a model and cache it in IndexedDB.
   *
   * If a valid cached copy exists (checksum passes if model.checksum is set),
   * the download is skipped entirely and the cached data is returned immediately.
   *
   * Uses retry with exponential backoff (up to 3 attempts) for transient
   * network errors, and Web Crypto SHA-256 verification before caching.
   *
   * @param model - Model descriptor from ModelRegistry
   * @param options.onProgress - Callback for download progress updates
   * @param options.verifyChecksum - Verify SHA-256 if model.checksum set (default true)
   * @param options.cancelToken - CancelToken to abort the download
   * @returns The model file as an ArrayBuffer
   */
  async downloadModel(
    model: DownloadableModelInfo,
    options: {
      onProgress?: (progress: DownloadProgress) => void;
      verifyChecksum?: boolean;
      cancelToken?: CancelToken;
    } = {}
  ): Promise<ArrayBuffer> {
    this._currentCancelToken = options.cancelToken ?? null;

    try {
      return await downloadModelWithRetry(model, {
        cancelToken: options.cancelToken,
        onProgress: options.onProgress,
        verifyChecksum: options.verifyChecksum,
      });
    } finally {
      this._currentCancelToken = null;
    }
  }

  /**
   * Cancel the current download (if any).
   */
  cancelDownload(): void {
    this._currentCancelToken?.cancel();
  }

  /**
   * Check whether a model is already cached in IndexedDB.
   *
   * @param modelId - Model identifier (e.g. 'llama-3.2-1b-instruct-q4')
   */
  async isModelCached(modelId: string): Promise<boolean> {
    const cached = await getCachedModel(modelId);
    return cached !== null;
  }

  /**
   * Get the cached file size in bytes for a model, or null if not cached.
   *
   * @param modelId - Model identifier
   */
  async getModelSize(modelId: string): Promise<number | null> {
    const cached = await getCachedModel(modelId);
    return cached ? cached.data.byteLength : null;
  }

  /**
   * List IDs of all models currently cached in IndexedDB.
   */
  async getDownloadedModels(): Promise<string[]> {
    const metadataList = await listCachedModels();
    return metadataList.map((m) => m.modelId);
  }

  /**
   * Total size in bytes of all cached models.
   */
  async getTotalModelsSize(): Promise<number> {
    return getCacheSize();
  }

  /**
   * Delete a model from IndexedDB.
   *
   * @param modelId - Model identifier
   */
  async deleteModel(modelId: string): Promise<void> {
    await deleteCachedModel(modelId);
  }

  /**
   * Remove all cached models from IndexedDB.
   */
  async clearAllModels(): Promise<void> {
    await clearCache();
  }

  /**
   * Verify a cached model's SHA-256 checksum against an expected value.
   *
   * Returns false if the model is not cached or verification fails.
   *
   * @param modelId - Model identifier (must be cached)
   * @param expectedChecksum - Hex-encoded SHA-256 hash
   */
  async verifyModelChecksum(modelId: string, expectedChecksum: string): Promise<boolean> {
    const cached = await getCachedModel(modelId);
    if (!cached) return false;
    return validateModelChecksum(cached.data, expectedChecksum);
  }
}

// ---------------------------------------------------------------------------
// ModelManager-specific error types (mirrors Flutter SDK exceptions)
// ---------------------------------------------------------------------------

/** Thrown when a model download fails after all retry attempts */
export class ModelDownloadError extends Error {
  readonly details?: string;

  constructor(message: string, details?: string) {
    super(message);
    this.name = 'ModelDownloadError';
    this.details = details;
  }
}

/** Thrown when a downloaded model's SHA-256 checksum does not match */
export class ModelChecksumError extends Error {
  readonly details?: string;

  constructor(message: string, details?: string) {
    super(message);
    this.name = 'ModelChecksumError';
    this.details = details;
  }
}
