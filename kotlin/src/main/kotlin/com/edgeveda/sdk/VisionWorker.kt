package com.edgeveda.sdk

import com.edgeveda.sdk.internal.NativeBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * VisionWorker - Persistent vision inference manager
 *
 * Maintains a persistent native vision context (~600MB VLM + mmproj) that is
 * loaded once and reused for all frame inferences. Uses a FrameQueue with
 * drop-newest backpressure to stay current with camera feeds.
 *
 * Pattern mirrors Swift's Actor-based VisionWorker and React Native's async
 * VisionWorker, adapted for Kotlin's coroutine architecture.
 *
 * Usage:
 * ```kotlin
 * val worker = VisionWorker()
 * worker.initialize(config)
 * 
 * // Camera callback
 * fun onFrame(rgb: ByteArray, width: Int, height: Int) {
 *     worker.enqueueFrame(rgb, width, height)
 * }
 * 
 * // Processing loop
 * launch {
 *     while (isActive) {
 *         worker.processNextFrame()?.let { result ->
 *             println("Description: ${result.description}")
 *         }
 *         delay(10)
 *     }
 * }
 * 
 * // Cleanup
 * worker.cleanup()
 * ```
 */
class VisionWorker {
    private val frameQueue = FrameQueue()
    private var _isInitialized = false
    private var backend = ""

    /**
     * Whether the vision context is initialized and ready
     */
    val isInitialized: Boolean
        @Synchronized get() = _isInitialized

    /**
     * Number of frames dropped due to backpressure
     */
    val droppedFrames: Int
        get() = frameQueue.droppedFrames

    /**
     * Backend name (e.g., "Vulkan", "CPU")
     */
    val backendName: String
        @Synchronized get() = backend

    /**
     * Initialize the vision context with VLM model
     *
     * Loads the model and mmproj once (~600MB). Subsequent frame inferences
     * reuse this context without reloading.
     *
     * @param config Vision configuration
     * @return Backend name (e.g., "Vulkan", "CPU")
     * @throws EdgeVedaException if initialization fails
     */
    suspend fun initialize(config: VisionConfig): String = withContext(Dispatchers.IO) {
        if (_isInitialized) {
            throw EdgeVedaException.InvalidConfiguration(
                "VisionWorker already initialized"
            )
        }

        try {
            val configJson = JSONObject().apply {
                put("modelPath", config.modelPath)
                put("mmprojPath", config.mmprojPath)
                put("numThreads", config.numThreads)
                put("contextSize", config.contextSize)
                put("gpuLayers", config.gpuLayers)
                put("memoryLimitBytes", config.memoryLimitBytes)
                put("useMmap", config.useMmap)
            }.toString()

            backend = NativeBridge.initVision(configJson)
            _isInitialized = true
            backend
        } catch (e: EdgeVedaException) {
            throw e
        } catch (e: Exception) {
            throw EdgeVedaException.ModelLoadError(
                "Failed to initialize vision context: ${e.message}",
                e
            )
        }
    }

    /**
     * Enqueue a frame for processing
     *
     * If inference is busy and a frame is already pending, the old frame
     * is dropped and the dropped frame counter is incremented.
     *
     * @param rgb RGB888 pixel data (width * height * 3 bytes)
     * @param width Frame width in pixels
     * @param height Frame height in pixels
     * @return true if frame was queued without dropping, false if a frame was dropped
     * @throws EdgeVedaException if worker is not initialized
     */
    fun enqueueFrame(rgb: ByteArray, width: Int, height: Int): Boolean {
        if (!_isInitialized) {
            throw EdgeVedaException.ModelLoadError(
                "VisionWorker not initialized. Call initialize() first."
            )
        }

        return frameQueue.enqueue(rgb, width, height)
    }

    /**
     * Process the next queued frame
     *
     * Dequeues a frame (if available and not already processing) and performs
     * vision inference. Returns null if no frame is pending or inference is
     * already running.
     *
     * @param prompt Text prompt for the model
     * @param params Optional generation parameters
     * @return Vision result with description and timings, or null if no frame to process
     * @throws EdgeVedaException if inference fails
     */
    suspend fun processNextFrame(
        prompt: String = "Describe what you see.",
        params: VisionGenerationParams = VisionGenerationParams()
    ): VisionResult? {
        if (!_isInitialized) {
            throw EdgeVedaException.ModelLoadError(
                "VisionWorker not initialized. Call initialize() first."
            )
        }

        val frame = frameQueue.dequeue() ?: return null

        return try {
            val result = describeFrameInternal(
                frame.rgb,
                frame.width,
                frame.height,
                prompt,
                params
            )
            frameQueue.markDone()
            result
        } catch (e: Exception) {
            frameQueue.markDone()
            throw e
        }
    }

    /**
     * Describe a frame directly, bypassing the queue
     *
     * Use for one-off inferences. For continuous camera feeds, prefer
     * enqueueFrame() + processNextFrame() for backpressure management.
     *
     * @param rgb RGB888 pixel data (width * height * 3 bytes)
     * @param width Frame width in pixels
     * @param height Frame height in pixels
     * @param prompt Text prompt for the model
     * @param params Optional generation parameters
     * @return Vision result with description and timings
     * @throws EdgeVedaException if inference fails
     */
    suspend fun describeFrame(
        rgb: ByteArray,
        width: Int,
        height: Int,
        prompt: String = "Describe what you see.",
        params: VisionGenerationParams = VisionGenerationParams()
    ): VisionResult {
        if (!_isInitialized) {
            throw EdgeVedaException.ModelLoadError(
                "VisionWorker not initialized. Call initialize() first."
            )
        }

        return describeFrameInternal(rgb, width, height, prompt, params)
    }

    /**
     * Internal method to perform vision inference (zero-copy via DirectByteBuffer)
     */
    private suspend fun describeFrameInternal(
        rgb: ByteArray,
        width: Int,
        height: Int,
        prompt: String,
        params: VisionGenerationParams
    ): VisionResult = withContext(Dispatchers.IO) {
        try {
            // Allocate DirectByteBuffer for zero-copy JNI transfer
            val buffer = java.nio.ByteBuffer.allocateDirect(rgb.size)
            buffer.put(rgb)
            buffer.flip()

            val paramsJson = JSONObject().apply {
                put("maxTokens", params.maxTokens)
                put("temperature", params.temperature)
                put("topP", params.topP)
                put("topK", params.topK)
                put("repeatPenalty", params.repeatPenalty)
            }.toString()

            val resultJson = NativeBridge.describeImage(
                buffer,
                width,
                height,
                prompt,
                paramsJson
            )

            val parsed = JSONObject(resultJson)

            // Calculate derived timing metrics
            val totalMs = parsed.getDouble("modelLoadMs") +
                    parsed.getDouble("imageEncodeMs") +
                    parsed.getDouble("promptEvalMs") +
                    parsed.getDouble("decodeMs")

            val generatedTokens = parsed.getInt("generatedTokens")
            val decodeMs = parsed.getDouble("decodeMs")
            val tokensPerSecond = if (generatedTokens > 0 && decodeMs > 0) {
                (generatedTokens / decodeMs) * 1000
            } else {
                0.0
            }

            val timings = VisionTimings(
                modelLoadMs = parsed.getDouble("modelLoadMs"),
                imageEncodeMs = parsed.getDouble("imageEncodeMs"),
                promptEvalMs = parsed.getDouble("promptEvalMs"),
                decodeMs = decodeMs,
                promptTokens = parsed.getInt("promptTokens"),
                generatedTokens = generatedTokens,
                totalMs = totalMs,
                tokensPerSecond = tokensPerSecond
            )

            VisionResult(
                description = parsed.getString("description"),
                timings = timings
            )
        } catch (e: EdgeVedaException) {
            throw e
        } catch (e: Exception) {
            throw EdgeVedaException.GenerationError(
                "Vision inference failed: ${e.message}",
                e
            )
        }
    }

    /**
     * Reset the dropped frames counter
     */
    fun resetCounters() {
        frameQueue.resetCounters()
    }

    /**
     * Reset the frame queue (clears pending frames)
     */
    fun resetQueue() {
        frameQueue.reset()
    }

    /**
     * Clean up and free native vision resources
     *
     * Frees the native vision context (model + mmproj). The worker cannot
     * be used after cleanup unless initialize() is called again.
     *
     * @throws EdgeVedaException if cleanup fails
     */
    suspend fun cleanup() = withContext(Dispatchers.IO) {
        if (!_isInitialized) {
            return@withContext
        }

        try {
            NativeBridge.freeVision()
            _isInitialized = false
            frameQueue.reset()
            backend = ""
        } catch (e: Exception) {
            throw EdgeVedaException.NativeError(
                "Failed to cleanup vision context: ${e.message}",
                e
            )
        }
    }
}