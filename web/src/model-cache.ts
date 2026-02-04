/**
 * Model Cache Management using IndexedDB
 */

import type { CachedModel, CachedModelMetadata, PrecisionType } from './types';

const DB_NAME = 'edgeveda-models';
const DB_VERSION = 1;
const STORE_NAME = 'models';

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
 * Downloads a model with progress tracking and caching
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

/**
 * Validates model checksum (SHA-256)
 */
export async function validateModelChecksum(
  data: ArrayBuffer,
  expectedChecksum: string
): Promise<boolean> {
  try {
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
    return hashHex === expectedChecksum;
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
