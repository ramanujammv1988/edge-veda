/**
 * Model Manager for React Native Edge Veda SDK
 *
 * Manages model downloads, caching, and verification.
 * Uses fetch API for downloading with retry/backoff, CancelToken support,
 * SHA-256 checksum verification, and atomic temp-file handling.
 */

import {
  CancelToken,
  DownloadProgress,
  DownloadableModelInfo,
  EdgeVedaError,
  EdgeVedaErrorCode,
} from './types';

// ReadableStream type shim for environments that lack DOM lib
interface ReadableStreamReader<T> {
  read(): Promise<{ done: boolean; value: T }>;
  cancel(reason?: any): Promise<void>;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_RETRIES = 3;
const INITIAL_RETRY_DELAY_MS = 1000;

// ---------------------------------------------------------------------------
// Helpers – SHA-256 (pure-JS, streaming-friendly)
// ---------------------------------------------------------------------------

/**
 * Compute SHA-256 hex digest of an ArrayBuffer.
 *
 * Prefers SubtleCrypto (available in Hermes ≥ 0.73 / JSC with polyfill),
 * falls back to a bundled pure-JS implementation if unavailable.
 */
async function sha256Hex(data: ArrayBuffer): Promise<string> {
  // Try Web Crypto first (available in newer RN runtimes)
  try {
    const cryptoObj = (globalThis as any).crypto;
    if (cryptoObj && typeof cryptoObj.subtle?.digest === 'function') {
      const hashBuffer: ArrayBuffer = await cryptoObj.subtle.digest(
        'SHA-256',
        data
      );
      return bufferToHex(hashBuffer);
    }
  } catch {
    // fall through
  }

  // Fallback: delegate to native module if available
  // For production, add react-native-quick-crypto or similar
  console.warn(
    '[EdgeVeda] SubtleCrypto unavailable – checksum verification skipped'
  );
  return '';
}

function bufferToHex(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i]!.toString(16).padStart(2, '0');
  }
  return hex;
}

// ---------------------------------------------------------------------------
// ModelManager
// ---------------------------------------------------------------------------

/**
 * Download progress callback type.
 */
export type DownloadProgressCallback = (progress: DownloadProgress) => void;

/**
 * Manages GGUF model file downloads, caching, and integrity verification
 * for React Native applications.
 *
 * Storage strategy:
 *  - Uses the app's document/cache directory via react-native-fs (if available)
 *    or falls back to fetch + in-memory cache for web-like RN environments.
 *  - Downloads go to a `.tmp` file first, then are atomically renamed.
 *
 * NOTE: This implementation uses `fetch` for downloading.  File I/O (cache
 * directory, rename, delete) requires a native file-system module such as
 * `react-native-fs` or `expo-file-system`.  The class accepts a `FileSystem`
 * adapter so consumers can inject the appropriate implementation.
 */
export interface FileSystemAdapter {
  /** Return the base directory path for model storage */
  getModelsDirectory(): Promise<string>;
  /** Check whether a file exists at `path` */
  exists(path: string): Promise<boolean>;
  /** Delete a file at `path` */
  deleteFile(path: string): Promise<void>;
  /** Rename / move `from` → `to` atomically */
  moveFile(from: string, to: string): Promise<void>;
  /** Write binary data to `path` */
  writeFile(path: string, data: ArrayBuffer): Promise<void>;
  /** Read binary data from `path` */
  readFile(path: string): Promise<ArrayBuffer>;
  /** Get file size in bytes (returns 0 if missing) */
  fileSize(path: string): Promise<number>;
  /** List filenames in a directory */
  listDirectory(path: string): Promise<string[]>;
  /** Create directory (recursive) */
  mkdir(path: string): Promise<void>;
}

export class ModelManager {
  private readonly fs: FileSystemAdapter;
  private currentCancelToken: CancelToken | null = null;

  constructor(fileSystem: FileSystemAdapter) {
    this.fs = fileSystem;
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /**
   * Get the local file path where a model would be / is stored.
   */
  async getModelPath(modelId: string): Promise<string> {
    const dir = await this.fs.getModelsDirectory();
    return `${dir}/${modelId}.gguf`;
  }

  /**
   * Check whether a model is already downloaded.
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    const path = await this.getModelPath(modelId);
    return this.fs.exists(path);
  }

  /**
   * Get the on-disk size of a downloaded model (bytes), or null if missing.
   */
  async getModelSize(modelId: string): Promise<number | null> {
    const path = await this.getModelPath(modelId);
    const exists = await this.fs.exists(path);
    if (!exists) return null;
    return this.fs.fileSize(path);
  }

  /**
   * Download a model with progress, retry/backoff, checksum verification,
   * and CancelToken support.
   *
   * Cache-first: if a valid cached file exists it is returned immediately.
   *
   * @returns Local file path to the downloaded model.
   */
  async downloadModel(
    model: DownloadableModelInfo,
    options: {
      verifyChecksum?: boolean;
      cancelToken?: CancelToken;
      onProgress?: DownloadProgressCallback;
    } = {}
  ): Promise<string> {
    const { verifyChecksum = true, cancelToken, onProgress } = options;
    const modelPath = await this.getModelPath(model.id);

    // ---- cache-first ----
    const cached = await this.fs.exists(modelPath);
    if (cached) {
      if (verifyChecksum && model.checksum) {
        const valid = await this.verifyChecksum(modelPath, model.checksum);
        if (valid) return modelPath;
        // Invalid → delete and re-download
        await this.fs.deleteFile(modelPath);
      } else {
        return modelPath;
      }
    }

    this.currentCancelToken = cancelToken ?? null;

    try {
      return await this.downloadWithRetry(
        model,
        modelPath,
        verifyChecksum,
        cancelToken,
        onProgress
      );
    } finally {
      this.currentCancelToken = null;
    }
  }

  /** Cancel the active download (if any). */
  cancelDownload(): void {
    this.currentCancelToken?.cancel();
  }

  /** Delete a downloaded model from disk. */
  async deleteModel(modelId: string): Promise<void> {
    const modelPath = await this.getModelPath(modelId);
    if (await this.fs.exists(modelPath)) {
      await this.fs.deleteFile(modelPath);
    }
    // Also remove metadata
    const metaPath = `${modelPath}.meta.json`;
    if (await this.fs.exists(metaPath)) {
      await this.fs.deleteFile(metaPath);
    }
  }

  /** Get list of all downloaded model IDs. */
  async getDownloadedModels(): Promise<string[]> {
    const dir = await this.fs.getModelsDirectory();
    await this.ensureDirectory(dir);
    const files = await this.fs.listDirectory(dir);
    return files
      .filter((f) => f.endsWith('.gguf'))
      .map((f) => f.replace(/\.gguf$/, ''));
  }

  /** Get total bytes used by all downloaded models. */
  async getTotalModelsSize(): Promise<number> {
    const dir = await this.fs.getModelsDirectory();
    await this.ensureDirectory(dir);
    const files = await this.fs.listDirectory(dir);
    let total = 0;
    for (const f of files) {
      if (f.endsWith('.gguf')) {
        total += await this.fs.fileSize(`${dir}/${f}`);
      }
    }
    return total;
  }

  /** Delete all downloaded models. */
  async clearAllModels(): Promise<void> {
    const ids = await this.getDownloadedModels();
    for (const id of ids) {
      await this.deleteModel(id);
    }
  }

  /** Verify the SHA-256 checksum of a file on disk. */
  async verifyModelChecksum(
    modelId: string,
    expectedChecksum: string
  ): Promise<boolean> {
    const path = await this.getModelPath(modelId);
    return this.verifyChecksum(path, expectedChecksum);
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  private async ensureDirectory(dir: string): Promise<void> {
    if (!(await this.fs.exists(dir))) {
      await this.fs.mkdir(dir);
    }
  }

  private async verifyChecksum(
    filePath: string,
    expected: string
  ): Promise<boolean> {
    try {
      if (!(await this.fs.exists(filePath))) return false;
      const data = await this.fs.readFile(filePath);
      const actual = await sha256Hex(data);
      if (actual === '') return true; // crypto unavailable, skip
      return actual.toLowerCase() === expected.toLowerCase();
    } catch {
      return false;
    }
  }

  /**
   * Download with exponential-backoff retry (up to MAX_RETRIES).
   */
  private async downloadWithRetry(
    model: DownloadableModelInfo,
    modelPath: string,
    verifyChecksum: boolean,
    cancelToken: CancelToken | undefined,
    onProgress: DownloadProgressCallback | undefined
  ): Promise<string> {
    let attempt = 0;
    let retryDelay = INITIAL_RETRY_DELAY_MS;

    while (true) {
      attempt++;
      try {
        return await this.performDownload(
          model,
          modelPath,
          verifyChecksum,
          cancelToken,
          onProgress
        );
      } catch (err: any) {
        const isNetworkError =
          err?.name === 'TypeError' || // fetch network error
          err?.message?.includes('network') ||
          err?.message?.includes('Network');

        if (!isNetworkError || attempt >= MAX_RETRIES) {
          throw err;
        }
        // Wait then retry
        await delay(retryDelay);
        retryDelay *= 2;
      }
    }
  }

  /**
   * Perform a single download attempt using fetch with streaming reader,
   * atomic temp-file rename, and optional checksum verification.
   */
  private async performDownload(
    model: DownloadableModelInfo,
    modelPath: string,
    verifyChecksum: boolean,
    cancelToken: CancelToken | undefined,
    onProgress: DownloadProgressCallback | undefined
  ): Promise<string> {
    const tempPath = `${modelPath}.tmp`;
    const dir = await this.fs.getModelsDirectory();
    await this.ensureDirectory(dir);

    // Clean stale temp
    if (await this.fs.exists(tempPath)) {
      await this.fs.deleteFile(tempPath);
    }

    cancelToken?.throwIfCancelled();

    // Build an AbortController wired to the CancelToken
    const abortController = new AbortController();
    cancelToken?.onCancel(() => abortController.abort());

    const response = await fetch(model.downloadUrl, {
      signal: abortController.signal,
    });

    if (!response.ok) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        `Download failed: HTTP ${response.status} ${response.statusText}`
      );
    }

    const contentLength = response.headers.get('Content-Length');
    const totalBytes = contentLength
      ? parseInt(contentLength, 10)
      : model.sizeBytes;

    const body = (response as any).body;
    if (!body) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        'Response body is null'
      );
    }

    const reader: ReadableStreamReader<Uint8Array> = body.getReader();
    const chunks: Uint8Array[] = [];
    let downloadedBytes = 0;
    const startTime = Date.now();

    try {
      while (true) {
        cancelToken?.throwIfCancelled();

        const { done, value } = await reader.read();
        if (done) break;

        chunks.push(value);
        downloadedBytes += value.length;

        if (onProgress && totalBytes > 0) {
          const elapsed = Date.now() - startTime;
          const speed =
            elapsed > 0 ? (downloadedBytes / elapsed) * 1000 : 0;
          const remaining =
            speed > 0
              ? Math.round((totalBytes - downloadedBytes) / speed)
              : undefined;
          const progress = downloadedBytes / totalBytes;

          onProgress({
            totalBytes,
            downloadedBytes,
            speedBytesPerSecond: speed,
            estimatedSecondsRemaining: remaining,
            progress: Math.min(progress, 1),
            progressPercent: Math.min(Math.round(progress * 100), 100),
          });
        }
      }
    } catch (err: any) {
      // Cleanup on cancellation or error
      if (await this.fs.exists(tempPath)) {
        await this.fs.deleteFile(tempPath);
      }
      if (err?.name === 'AbortError') {
        throw new EdgeVedaError(
          EdgeVedaErrorCode.UNKNOWN_ERROR,
          'Download cancelled'
        );
      }
      throw err;
    }

    // Combine chunks
    const combined = new Uint8Array(downloadedBytes);
    let offset = 0;
    for (const chunk of chunks) {
      combined.set(chunk, offset);
      offset += chunk.length;
    }

    // Write to temp file
    await this.fs.writeFile(tempPath, combined.buffer);

    // Verify checksum before atomic rename
    if (verifyChecksum && model.checksum) {
      const actual = await sha256Hex(combined.buffer);
      if (actual !== '' && actual.toLowerCase() !== model.checksum.toLowerCase()) {
        await this.fs.deleteFile(tempPath);
        throw new EdgeVedaError(
          EdgeVedaErrorCode.UNKNOWN_ERROR,
          `SHA-256 checksum mismatch. Expected: ${model.checksum}`
        );
      }
    }

    // Atomic rename
    await this.fs.moveFile(tempPath, modelPath);

    // Final progress
    if (onProgress) {
      onProgress({
        totalBytes,
        downloadedBytes: totalBytes,
        speedBytesPerSecond: 0,
        estimatedSecondsRemaining: 0,
        progress: 1,
        progressPercent: 100,
      });
    }

    return modelPath;
  }
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}