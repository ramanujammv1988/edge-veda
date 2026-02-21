package com.edgeveda.sdk

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

// MARK: - CancelToken

/**
 * Token for cancelling ongoing operations (downloads, streaming generation).
 *
 * Thread-safe cancellation token that notifies listeners when cancel() is called.
 */
class CancelToken {
    private val lock = ReentrantLock()
    private var _isCancelled = AtomicBoolean(false)
    private val _listeners = mutableListOf<() -> Unit>()

    /** Whether cancellation has been requested */
    val isCancelled: Boolean get() = _isCancelled.get()

    /**
     * Request cancellation of the operation.
     * Notifies all registered listeners synchronously.
     */
    fun cancel() {
        if (_isCancelled.getAndSet(true)) return
        // Collect listeners under the lock, then invoke them outside to avoid
        // holding the lock while calling arbitrary code (and to stay exception-safe).
        val listeners = lock.withLock { _listeners.toList() }
        listeners.forEach { it() }
    }

    /**
     * Add a listener to be notified when cancel() is called.
     * If already cancelled, the listener is called immediately.
     */
    fun addListener(listener: () -> Unit) {
        // Determine under the lock whether to call immediately or enqueue.
        val callNow = lock.withLock {
            if (_isCancelled.get()) true
            else { _listeners.add(listener); false }
        }
        if (callNow) listener()
    }

    /**
     * Reset the token for reuse.
     * Clears the cancelled state and removes all listeners.
     */
    fun reset() {
        lock.withLock {
            _isCancelled.set(false)
            _listeners.clear()
        }
    }
}

// MARK: - DownloadProgress

/**
 * Model download progress information.
 */
data class DownloadProgress(
    /** Total bytes to download */
    val totalBytes: Long,
    /** Bytes downloaded so far */
    val downloadedBytes: Long,
    /** Download speed in bytes per second */
    val speedBytesPerSecond: Double? = null,
    /** Estimated time remaining in seconds */
    val estimatedSecondsRemaining: Int? = null
) {
    /** Download progress as fraction (0.0 - 1.0) */
    val progress: Double get() = if (totalBytes > 0) downloadedBytes.toDouble() / totalBytes else 0.0

    /** Download progress as percentage (0 - 100) */
    val progressPercent: Int get() = (progress * 100).toInt()
}

// MARK: - ModelType

/** Category of a downloadable model */
enum class ModelType {
    TEXT, VISION, MMPROJ, WHISPER, EMBEDDING
}

// MARK: - DownloadableModelInfo

/**
 * Downloadable model information descriptor.
 *
 * Represents a model that can be downloaded from a remote URL.
 * Distinct from loaded model metadata returned by getModelInfo().
 */
data class DownloadableModelInfo(
    /** Model identifier (e.g., "llama-3.2-1b-instruct-q4") */
    val id: String,
    /** Human-readable model name */
    val name: String,
    /** Model size in bytes */
    val sizeBytes: Long,
    /** Model description */
    val description: String? = null,
    /** Download URL */
    val downloadUrl: String,
    /** SHA256 checksum for verification */
    val checksum: String? = null,
    /** Model format (e.g., "GGUF") */
    val format: String = "GGUF",
    /** Quantization level (e.g., "Q4_K_M") */
    val quantization: String? = null,
    /** Model category (TEXT, VISION, MMPROJ, WHISPER, EMBEDDING) */
    val modelType: ModelType? = null
)

// MARK: - ModelManager

/**
 * Manages model downloads, caching, and verification.
 *
 * Features:
 * - Cache-first: returns existing model immediately if valid
 * - Atomic temp-file + rename: no corrupt files on interrupted download
 * - SHA-256 checksum verification via MessageDigest
 * - Retry with exponential backoff for transient network errors (up to 3 attempts)
 * - CancelToken support for cancelling downloads mid-stream
 * - Coroutine-based: all I/O on Dispatchers.IO
 *
 * Models are stored in the app's internal files directory under edge_veda_models/,
 * persisting across app launches and only removed on uninstall.
 *
 * Example:
 * ```kotlin
 * val manager = ModelManager(context)
 * val path = manager.downloadModel(ModelRegistry.llama32_1b) { progress ->
 *     println("Download: ${progress.progressPercent}%")
 * }
 * val edgeVeda = EdgeVeda.create(context)
 * edgeVeda.init(path)
 * ```
 */
class ModelManager(private val context: Context) {

    companion object {
        private const val MODELS_CACHE_DIR = "edge_veda_models"
        private const val METADATA_FILE_NAME = "metadata.json"
        private const val MAX_RETRIES = 3
        private const val INITIAL_RETRY_DELAY_MS = 1000L
        private const val BUFFER_SIZE = 8192
        private const val PROGRESS_REPORT_INTERVAL = 65536L // ~64KB
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 60_000
    }

    private var currentDownloadToken: CancelToken? = null

    // MARK: - Directory Management

    /**
     * Get the models directory.
     *
     * Uses app internal files directory which persists across app launches
     * and is only removed on uninstall.
     */
    fun getModelsDirectory(): File {
        val modelsDir = File(context.filesDir, MODELS_CACHE_DIR)
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }
        return modelsDir
    }

    /** Get path for a specific model file */
    fun getModelPath(modelId: String): String {
        return File(getModelsDirectory(), "$modelId.gguf").absolutePath
    }

    /** Check if a model is already downloaded */
    fun isModelDownloaded(modelId: String): Boolean {
        return File(getModelPath(modelId)).exists()
    }

    /** Get downloaded model file size in bytes */
    fun getModelSize(modelId: String): Long? {
        val file = File(getModelPath(modelId))
        return if (file.exists()) file.length() else null
    }

    // MARK: - Download

    /** Cancel the current download (if any) */
    fun cancelDownload() {
        currentDownloadToken?.cancel()
    }

    /**
     * Download a model with progress tracking.
     *
     * Downloads to a temporary file first, verifies checksum, then atomically
     * renames to final location. If a valid cached model exists, returns immediately.
     *
     * @param model Model information including download URL
     * @param verifyChecksum Whether to verify SHA-256 checksum (default: true)
     * @param cancelToken Optional token for cancelling the download
     * @param onProgress Optional progress callback
     * @return File path to the downloaded model
     * @throws EdgeVedaException.DownloadError on failure
     */
    suspend fun downloadModel(
        model: DownloadableModelInfo,
        verifyChecksum: Boolean = true,
        cancelToken: CancelToken? = null,
        onProgress: ((DownloadProgress) -> Unit)? = null
    ): String = withContext(Dispatchers.IO) {
        val modelPath = getModelPath(model.id)
        val modelFile = File(modelPath)

        // CACHE-FIRST: skip download if valid model exists
        if (modelFile.exists()) {
            if (verifyChecksum && model.checksum != null) {
                val isValid = verifyChecksum(modelPath, model.checksum)
                if (isValid) {
                    return@withContext modelPath
                }
                // Invalid checksum — delete and re-download
                modelFile.delete()
            } else {
                // No checksum to verify — assume cached file is valid
                return@withContext modelPath
            }
        }

        currentDownloadToken = cancelToken

        try {
            downloadWithRetry(model, modelPath, verifyChecksum, cancelToken, onProgress)
        } finally {
            currentDownloadToken = null
        }
    }

    /**
     * Internal download implementation with retry logic.
     */
    private suspend fun downloadWithRetry(
        model: DownloadableModelInfo,
        modelPath: String,
        verifyChecksum: Boolean,
        cancelToken: CancelToken?,
        onProgress: ((DownloadProgress) -> Unit)?
    ): String {
        var attempt = 0
        var retryDelay = INITIAL_RETRY_DELAY_MS

        while (true) {
            attempt++
            try {
                return performDownload(model, modelPath, verifyChecksum, cancelToken, onProgress)
            } catch (e: Exception) {
                // Only retry on transient network errors
                val isTransient = e is SocketException ||
                    e is SocketTimeoutException ||
                    e is UnknownHostException ||
                    (e is java.io.IOException && e !is java.io.FileNotFoundException)

                if (!isTransient || attempt >= MAX_RETRIES) {
                    throw EdgeVedaException.DownloadError(
                        "Failed to download model after $MAX_RETRIES attempts: ${e.message}",
                        e
                    )
                }

                // Exponential backoff
                kotlinx.coroutines.delay(retryDelay)
                retryDelay *= 2
            }
        }
    }

    /**
     * Perform the actual download to temp file with atomic rename.
     */
    private suspend fun performDownload(
        model: DownloadableModelInfo,
        modelPath: String,
        verifyChecksum: Boolean,
        cancelToken: CancelToken?,
        onProgress: ((DownloadProgress) -> Unit)?
    ): String = withContext(Dispatchers.IO) {
        val tempPath = "$modelPath.tmp"
        val tempFile = File(tempPath)

        // Clean up any stale temp file from previous interrupted download
        if (tempFile.exists()) {
            tempFile.delete()
        }

        // Check cancellation before starting
        if (cancelToken?.isCancelled == true) {
            throw EdgeVedaException.DownloadError("Download cancelled", null)
        }

        var connection: HttpURLConnection? = null

        try {
            // Follow redirects manually (HttpURLConnection doesn't follow cross-protocol redirects)
            var currentUrl = model.downloadUrl
            var redirectCount = 0
            val maxRedirects = 5

            // Follow redirects until we get a 2xx response or hit max redirects
            while (redirectCount < maxRedirects) {
                val url = URL(currentUrl)
                connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = CONNECT_TIMEOUT_MS
                connection.readTimeout = READ_TIMEOUT_MS
                connection.requestMethod = "GET"
                connection.instanceFollowRedirects = false // Disable auto-redirect to handle manually
                connection.connect()

                val responseCode = connection.responseCode

                when (responseCode) {
                    in 200..299 -> {
                        // Success - proceed with download
                        break
                    }
                    in 300..399 -> {
                        // Redirect - follow the Location header
                        val location = connection.getHeaderField("Location")
                        if (location.isNullOrEmpty()) {
                            throw EdgeVedaException.DownloadError(
                                "HTTP $responseCode redirect without Location header",
                                null
                            )
                        }
                        
                        connection.disconnect()
                        currentUrl = location
                        redirectCount++
                        
                        if (redirectCount >= maxRedirects) {
                            throw EdgeVedaException.DownloadError(
                                "Too many redirects (>$maxRedirects)",
                                null
                            )
                        }
                    }
                    else -> {
                        throw EdgeVedaException.DownloadError("HTTP $responseCode", null)
                    }
                }
            }

            // At this point, connection is connected and has a 2xx response
            val finalConnection = connection ?: throw EdgeVedaException.DownloadError(
                "Connection lost after redirects",
                null
            )

            val responseCode = finalConnection.responseCode
            if (responseCode !in 200..299) {
                throw EdgeVedaException.DownloadError("HTTP $responseCode", null)
            }

            val totalBytes = if (finalConnection.contentLengthLong > 0) {
                finalConnection.contentLengthLong
            } else {
                model.sizeBytes
            }

            var downloadedBytes = 0L
            var lastReportedBytes = 0L
            val startTime = System.currentTimeMillis()
            val buffer = ByteArray(BUFFER_SIZE)

            finalConnection.inputStream.use { input ->
                FileOutputStream(tempFile).use { output ->
                    while (isActive) {
                        // Check cancellation
                        if (cancelToken?.isCancelled == true) {
                            output.close()
                            tempFile.delete()
                            throw EdgeVedaException.DownloadError("Download cancelled", null)
                        }

                        val bytesRead = input.read(buffer)
                        if (bytesRead == -1) break

                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead

                        // Report progress at reasonable intervals
                        if (downloadedBytes - lastReportedBytes >= PROGRESS_REPORT_INTERVAL) {
                            lastReportedBytes = downloadedBytes

                            val elapsed = System.currentTimeMillis() - startTime
                            val speed = if (elapsed > 0) {
                                (downloadedBytes.toDouble() / elapsed) * 1000
                            } else 0.0
                            val remaining = if (speed > 0) {
                                ((totalBytes - downloadedBytes) / speed).toInt()
                            } else null

                            onProgress?.invoke(
                                DownloadProgress(
                                    totalBytes = totalBytes,
                                    downloadedBytes = downloadedBytes,
                                    speedBytesPerSecond = speed,
                                    estimatedSecondsRemaining = remaining
                                )
                            )
                        }
                    }
                }
            }

            // Verify checksum BEFORE atomic rename
            if (verifyChecksum && model.checksum != null) {
                val isValid = verifyChecksum(tempPath, model.checksum)
                if (!isValid) {
                    tempFile.delete()
                    throw EdgeVedaException.ChecksumError(
                        "SHA256 checksum mismatch. Expected: ${model.checksum}",
                        null
                    )
                }
            }

            // Atomic rename — ensures no corrupt files if interrupted
            val destFile = File(modelPath)
            if (!tempFile.renameTo(destFile)) {
                // Fallback: copy + delete if rename fails (cross-filesystem)
                tempFile.copyTo(destFile, overwrite = true)
                tempFile.delete()
            }

            // Emit final 100% progress
            onProgress?.invoke(
                DownloadProgress(
                    totalBytes = totalBytes,
                    downloadedBytes = totalBytes,
                    speedBytesPerSecond = 0.0,
                    estimatedSecondsRemaining = 0
                )
            )

            // Save metadata
            saveModelMetadata(model)

            modelPath
        } catch (e: EdgeVedaException) {
            // Clean up temp file on error
            tempFile.delete()
            throw e
        } catch (e: Exception) {
            tempFile.delete()
            throw EdgeVedaException.DownloadError(
                "Download failed: ${e.message}",
                e
            )
        } finally {
            connection?.disconnect()
        }
    }

    // MARK: - Checksum Verification

    /**
     * Verify file SHA-256 checksum.
     *
     * @param filePath Path to the file to verify
     * @param expectedChecksum Expected SHA-256 hex string
     * @return true if checksum matches
     */
    suspend fun verifyChecksum(filePath: String, expectedChecksum: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                val hash = computeSHA256(filePath)
                hash.equals(expectedChecksum, ignoreCase = true)
            } catch (e: Exception) {
                false
            }
        }

    /**
     * Compute SHA-256 hash of a file using MessageDigest.
     * Reads file in chunks to support large model files without loading entirely into memory.
     */
    private fun computeSHA256(filePath: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(1024 * 1024) // 1MB chunks

        FileInputStream(filePath).use { input ->
            var bytesRead: Int
            while (input.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }

        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    // MARK: - Model Deletion & Listing

    /** Delete a downloaded model */
    fun deleteModel(modelId: String) {
        val modelFile = File(getModelPath(modelId))
        if (modelFile.exists()) {
            modelFile.delete()
        }
        deleteModelMetadata(modelId)
    }

    /** Get list of all downloaded model IDs */
    fun getDownloadedModels(): List<String> {
        val modelsDir = getModelsDirectory()
        return modelsDir.listFiles()
            ?.filter { it.extension == "gguf" }
            ?.map { it.nameWithoutExtension }
            ?: emptyList()
    }

    /** Get total size of all downloaded models in bytes */
    fun getTotalModelsSize(): Long {
        val modelsDir = getModelsDirectory()
        return modelsDir.listFiles()
            ?.filter { it.extension == "gguf" }
            ?.sumOf { it.length() }
            ?: 0L
    }

    /** Clear all downloaded models */
    fun clearAllModels() {
        val modelsDir = getModelsDirectory()
        if (modelsDir.exists()) {
            modelsDir.deleteRecursively()
            modelsDir.mkdirs()
        }
    }

    // MARK: - Metadata

    /** Save model metadata to disk */
    private fun saveModelMetadata(model: DownloadableModelInfo) {
        // Use JSONObject for safe serialization — avoids malformed JSON when
        // field values contain quotes, backslashes, or control characters.
        val json = org.json.JSONObject().apply {
            put("id", model.id)
            put("name", model.name)
            put("sizeBytes", model.sizeBytes)
            putOpt("description", model.description)
            put("downloadUrl", model.downloadUrl)
            putOpt("checksum", model.checksum)
            put("format", model.format)
            putOpt("quantization", model.quantization)
            put("downloadedAt", java.time.Instant.now().toString())
            putOpt("modelType", model.modelType?.name)
        }.toString(2)
        File(getModelsDirectory(), "${model.id}_$METADATA_FILE_NAME").writeText(json)
    }

    /** Delete model metadata */
    private fun deleteModelMetadata(modelId: String) {
        val metadataFile = File(getModelsDirectory(), "${modelId}_$METADATA_FILE_NAME")
        if (metadataFile.exists()) {
            metadataFile.delete()
        }
    }

    /** Get model metadata if available */
    fun getModelMetadata(modelId: String): DownloadableModelInfo? {
        val metadataFile = File(getModelsDirectory(), "${modelId}_$METADATA_FILE_NAME")
        if (!metadataFile.exists()) return null

        return try {
            val json = org.json.JSONObject(metadataFile.readText())
            DownloadableModelInfo(
                id = json.getString("id"),
                name = json.getString("name"),
                sizeBytes = json.getLong("sizeBytes"),
                description = json.optString("description", null),
                downloadUrl = json.getString("downloadUrl"),
                checksum = json.optString("checksum", null),
                format = json.optString("format", "GGUF"),
                quantization = json.optString("quantization", null),
                modelType = json.optString("modelType", null)?.let {
                    runCatching { ModelType.valueOf(it) }.getOrNull()
                }
            )
        } catch (e: Exception) {
            null
        }
    }
}

