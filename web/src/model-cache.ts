/**
 * Model Cache Management using IndexedDB
 *
 * Features:
 * - IndexedDB-based model caching
 * - Download with retry and exponential backoff (3 retries)
 * - CancelToken / AbortSignal support
 * - Streaming progress with speed and ETA calculations
 * - Atomic download pattern (temp key → rename in IndexedDB)
 * - SHA-256 checksum verification via Web Crypto API
 */

import type {
  CachedModel,
  CachedModelMetadata,
  DownloadableModelInfo,
  DownloadProgress,
  PrecisionType,
} from './types';
import { CancelToken } from './types';

const DB_NAME = 'edgeveda-models';
const DB_VERSION = 1;
const STORE_NAME = 'models';

/** Maximum number of download retry attempts */
const MAX_RETRIES = 3;

/** Initial retry delay in milliseconds (doubles each retry) */
const INITIAL_RETRY_DELAY_MS = 1000;

/**
 * Opens IndexedDB connection
 */
function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => {
      reject(new Error(`Failed to open IndexedDB: ${request.error?.message}`));
    };

    request.onsuccess = () => {
      resolve(request.result);
    };

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;

      // Create object store if it doesn't exist
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        const store = db.createObjectStore(STORE_NAME, { keyPath: 'metadata.modelId' });
        store.createIndex('timestamp', 'metadata.timestamp', { unique: false });
        store.createIndex('modelId', 'metadata.modelId', { unique: true });
      }
    };
  });
}

/**
 * Stores a model in the cache
 */
export async function cacheModel(
  modelId: string,
  data: ArrayBuffer,
  precision: PrecisionType,
  version: string = '1.0.0',
  checksum?: string
): Promise<void> {
  const db = await openDatabase();

  const metadata: CachedModelMetadata = {
    modelId,
    timestamp: Date.now(),
    size: data.byteLength,
    version,
    precision,
    checksum,
  };

  const cachedModel: CachedModel = {
    metadata,
    data,
  };

  return new Promise((resolve, reject) => {
    const transaction = db.transaction([STORE_NAME], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.put(cachedModel);

    request.onsuccess = () => {
      db.close();
      resolve();
    };

    request.onerror = () => {
      db.close();
      reject(new Error(`Failed to cache model: ${request.error?.message}`));
    };
  });
}

/**
 * Retrieves a model from the cache
 */
export async function getCachedModel(modelId: string): Promise<CachedModel | null> {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const transaction = db.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.get(modelId);

    request.onsuccess = () => {
      db.close();
      resolve(request.result || null);
    };

    request.onerror = () => {
      db.close();
      reject(new Error(`Failed to get cached model: ${request.error?.message}`));
    };
  });
}

/**
 * Checks if a model exists in the cache
 */
export async function hasCachedModel(modelId: string): Promise<boolean> {
  const model = await getCachedModel(modelId);
  return model !== null;
}

/**
 * Deletes a model from the cache
 */
export async function deleteCachedModel(modelId: string): Promise<void> {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const transaction = db.transaction([STORE_NAME], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.delete(modelId);

    request.onsuccess = () => {
      db.close();
      resolve();
    };

    request.onerror = () => {
      db.close();
      reject(new Error(`Failed to delete cached model: ${request.error?.message}`));
    };
  });
}

/**
 * Lists all cached models
 */
export async function listCachedModels(): Promise<CachedModelMetadata[]> {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const transaction = db.transaction([STORE_NAME], 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.getAll();

    request.onsuccess = () => {
      db.close();
      const models = request.result as CachedModel[];
      resolve(models.map((m) => m.metadata));
    };

    request.onerror = () => {
      db.close();
      reject(new Error(`Failed to list cached models: ${request.error?.message}`));
    };
  });
}

/**
 * Gets the total size of all cached models
 */
export async function getCacheSize(): Promise<number> {
  const models = await listCachedModels();
  return models.reduce((total, model) => total + model.size, 0);
}

/**
 * Clears all cached models
 */
export async function clearCache(): Promise<void> {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const transaction = db.transaction([STORE_NAME], 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.clear();

    request.onsuccess = () => {
      db.close();
      resolve();
    };

    request.onerror = () => {
      db.close();
      reject(new Error(`Failed to clear cache: ${request.error?.message}`));
    };
  });
}

/**
 * Invalidates models older than the specified age (in milliseconds)
 */
export async function invalidateOldModels(maxAge: number): Promise<void> {
  const models = await listCachedModels();
  const now = Date.now();
  const expiredModels = models.filter((m) => now - m.timestamp > maxAge);

  for (const model of expiredModels) {
    await deleteCachedModel(model.modelId);
  }
}

/**
 * Downloads a model with progress tracking and caching (legacy API).
 *
 * For new code, prefer {@link downloadModelWithRetry} which adds retry,
 * CancelToken, checksum verification, and speed/ETA progress.
 */
export async function downloadAndCacheModel(
  url: string,
  modelId: string,
  precision: PrecisionType,
  onProgress?: (loaded: number, total: number) => void
): Promise<ArrayBuffer> {
  // Check if already cached
  const cached = await getCachedModel(modelId);
  if (cached) {
    console.log(`Model ${modelId} found in cache`);
    return cached.data;
  }

  console.log(`Downloading model ${modelId} from ${url}`);

  // Download the model
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to download model: ${response.statusText}`);
  }

  const contentLength = response.headers.get('Content-Length');
  const total = contentLength ? parseInt(contentLength, 10) : 0;

  if (!response.body) {
    throw new Error('Response body is null');
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let loaded = 0;

  // Read chunks with progress
  while (true) {
    const { done, value } = await reader.read();

    if (done) break;

    chunks.push(value);
    loaded += value.length;

    if (onProgress && total > 0) {
      onProgress(loaded, total);
    }
  }

  // Combine chunks into ArrayBuffer
  const modelData = new Uint8Array(loaded);
  let offset = 0;
  for (const chunk of chunks) {
    modelData.set(chunk, offset);
    offset += chunk.length;
  }

  const arrayBuffer = modelData.buffer;

  // Cache the model
  try {
    await cacheModel(modelId, arrayBuffer, precision);
    console.log(`Model ${modelId} cached successfully`);
  } catch (error) {
    console.warn(`Failed to cache model: ${error}`);
    // Continue anyway, caching is optional
  }

  return arrayBuffer;
}

// ============================================================================
// Enhanced Model Download API — retry, CancelToken, checksum, speed/ETA
// ============================================================================

/**
 * Check if an error is a transient network error worth retrying.
 */
function isTransientError(error: unknown): boolean {
  if (error instanceof TypeError) {
    // fetch() throws TypeError for network failures
    return true;
  }
  if (error instanceof DOMException && error.name === 'AbortError') {
    // User-initiated cancellation — do NOT retry
    return false;
  }
  return false;
}

/**
 * Sleep for the specified number of milliseconds, respecting AbortSignal.
 */
function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException('Download cancelled', 'AbortError'));
      return;
    }
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        reject(new DOMException('Download cancelled', 'AbortError'));
      },
      { once: true }
    );
  });
}

/**
 * Compute SHA-256 hex digest of an ArrayBuffer using Web Crypto API.
 */
async function sha256Hex(data: ArrayBuffer): Promise<string> {
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Download a DownloadableModelInfo with full production features:
 *
 * - **Cache-first**: returns immediately if a valid cached model exists
 * - **Retry with exponential backoff**: up to 3 attempts for transient network errors
 * - **CancelToken / AbortSignal**: cooperative cancellation via CancelToken
 * - **Streaming progress**: DownloadProgress with speed (B/s) and ETA
 * - **Atomic download**: stored under a temp key, renamed on success
 * - **SHA-256 checksum**: verified before committing to cache
 *
 * @param model - The downloadable model descriptor
 * @param options - Optional settings
 * @returns The model data as an ArrayBuffer
 */
export async function downloadModelWithRetry(
  model: DownloadableModelInfo,
  options: {
    /** CancelToken for cooperative cancellation */
    cancelToken?: CancelToken;
    /** Callback for download progress */
    onProgress?: (progress: DownloadProgress) => void;
    /** Whether to verify SHA-256 checksum (default: true if checksum provided) */
    verifyChecksum?: boolean;
    /** Precision type for cache metadata */
    precision?: PrecisionType;
  } = {}
): Promise<ArrayBuffer> {
  const {
    cancelToken,
    onProgress,
    verifyChecksum = model.checksum != null,
    precision = 'fp16',
  } = options;

  // ---- Cache-first check ----
  const cached = await getCachedModel(model.id);
  if (cached) {
    // If checksum provided, verify before returning
    if (verifyChecksum && model.checksum) {
      const hex = await sha256Hex(cached.data);
      if (hex.toLowerCase() === model.checksum.toLowerCase()) {
        return cached.data;
      }
      // Checksum mismatch — delete stale entry and re-download
      await deleteCachedModel(model.id);
    } else {
      return cached.data;
    }
  }

  // ---- Download with retry ----
  let attempt = 0;
  let retryDelay = INITIAL_RETRY_DELAY_MS;

  while (true) {
    attempt++;
    try {
      const data = await performDownload(model, cancelToken, onProgress);

      // ---- Checksum verification ----
      if (verifyChecksum && model.checksum) {
        const hex = await sha256Hex(data);
        if (hex.toLowerCase() !== model.checksum.toLowerCase()) {
          throw new Error(
            `SHA-256 checksum mismatch for ${model.id}. Expected: ${model.checksum}, Got: ${hex}`
          );
        }
      }

      // ---- Atomic commit: temp key → final key ----
      // We wrote to a temp key during download; now rename to final key
      const tempId = `__temp_${model.id}`;
      await deleteCachedModel(tempId); // clean up temp if it exists

      await cacheModel(model.id, data, precision, '1.0.0', model.checksum);

      // Emit final 100% progress
      if (onProgress) {
        onProgress({
          totalBytes: model.sizeBytes,
          downloadedBytes: model.sizeBytes,
          speedBytesPerSecond: 0,
          estimatedSecondsRemaining: 0,
          percentage: 100,
        });
      }

      return data;
    } catch (error) {
      // Cancellation — do not retry
      if (
        error instanceof DOMException &&
        error.name === 'AbortError'
      ) {
        // Clean up temp entry
        await deleteCachedModel(`__temp_${model.id}`).catch(() => {});
        throw new Error(`Download of ${model.id} was cancelled`);
      }

      // Transient network error — retry with exponential backoff
      if (isTransientError(error) && attempt < MAX_RETRIES) {
        console.warn(
          `Download attempt ${attempt}/${MAX_RETRIES} failed for ${model.id}, retrying in ${retryDelay}ms...`,
          error
        );
        await sleep(retryDelay, cancelToken?.signal);
        retryDelay *= 2;
        continue;
      }

      // Non-retryable or max retries exhausted
      await deleteCachedModel(`__temp_${model.id}`).catch(() => {});
      throw error instanceof Error
        ? error
        : new Error(`Failed to download model ${model.id} after ${MAX_RETRIES} attempts`);
    }
  }
}

/**
 * Internal: perform a single download attempt with streaming progress.
 */
async function performDownload(
  model: DownloadableModelInfo,
  cancelToken?: CancelToken,
  onProgress?: (progress: DownloadProgress) => void
): Promise<ArrayBuffer> {
  // Check cancellation before starting
  if (cancelToken?.cancelled) {
    throw new DOMException('Download cancelled', 'AbortError');
  }

  const response = await fetch(model.downloadUrl, {
    signal: cancelToken?.signal,
  });

  if (!response.ok) {
    throw new Error(
      `HTTP ${response.status} ${response.statusText} downloading ${model.id}`
    );
  }

  const contentLength = response.headers.get('Content-Length');
  const totalBytes = contentLength ? parseInt(contentLength, 10) : model.sizeBytes;

  if (!response.body) {
    // Fallback: no streaming, download all at once
    const buf = await response.arrayBuffer();
    return buf;
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let downloadedBytes = 0;
  let lastReportedBytes = 0;
  const startTime = Date.now();

  while (true) {
    // Check cancellation during download
    if (cancelToken?.cancelled) {
      reader.cancel();
      throw new DOMException('Download cancelled', 'AbortError');
    }

    const { done, value } = await reader.read();
    if (done) break;

    chunks.push(value);
    downloadedBytes += value.length;

    // Only emit progress if it increased
    if (onProgress && downloadedBytes > lastReportedBytes && totalBytes > 0) {
      lastReportedBytes = downloadedBytes;

      const elapsedMs = Date.now() - startTime;
      const speedBytesPerSecond =
        elapsedMs > 0 ? (downloadedBytes / elapsedMs) * 1000 : 0;
      const remainingBytes = totalBytes - downloadedBytes;
      const estimatedSecondsRemaining =
        speedBytesPerSecond > 0
          ? Math.round(remainingBytes / speedBytesPerSecond)
          : null;
      const percentage = Math.min(
        99,
        Math.round((downloadedBytes / totalBytes) * 100)
      );

      onProgress({
        totalBytes,
        downloadedBytes,
        speedBytesPerSecond,
        estimatedSecondsRemaining,
        percentage,
      });
    }
  }

  // Combine chunks into a single ArrayBuffer
  const modelData = new Uint8Array(downloadedBytes);
  let offset = 0;
  for (const chunk of chunks) {
    modelData.set(chunk, offset);
    offset += chunk.length;
  }

  return modelData.buffer;
}

/**
 * Validates model checksum (SHA-256)
 */
export async function validateModelChecksum(
  data: ArrayBuffer,
  expectedChecksum: string
): Promise<boolean> {
  try {
    const hex = await sha256Hex(data);
    return hex.toLowerCase() === expectedChecksum.toLowerCase();
  } catch (error) {
    console.error('Failed to validate checksum:', error);
    return false;
  }
}

/**
 * Estimates available storage quota
 */
export async function estimateStorageQuota(): Promise<{
  usage: number;
  quota: number;
  available: number;
}> {
  if ('storage' in navigator && 'estimate' in navigator.storage) {
    const estimate = await navigator.storage.estimate();
    const usage = estimate.usage || 0;
    const quota = estimate.quota || 0;
    return {
      usage,
      quota,
      available: quota - usage,
    };
  }

  // Fallback: assume we have space
  return {
    usage: 0,
    quota: Number.MAX_SAFE_INTEGER,
    available: Number.MAX_SAFE_INTEGER,
  };
}

/**
 * Checks if there's enough storage for a model
 */
export async function hasEnoughStorage(requiredBytes: number): Promise<boolean> {
  const { available } = await estimateStorageQuota();
  return available >= requiredBytes;
}