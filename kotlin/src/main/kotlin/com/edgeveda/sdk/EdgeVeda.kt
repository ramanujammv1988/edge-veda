package com.edgeveda.sdk

import com.edgeveda.sdk.internal.NativeBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * EdgeVeda SDK - Main API for on-device LLM inference.
 *
 * This class provides a Kotlin-friendly interface for loading and running
 * large language models on Android devices with hardware acceleration support.
 *
 * Example usage:
 * ```
 * val config = EdgeVedaConfig(
 *     backend = Backend.AUTO,
 *     numThreads = 4,
 *     maxTokens = 512
 * )
 *
 * val edgeVeda = EdgeVeda.create(context)
 * edgeVeda.init("/path/to/model.gguf", config)
 *
 * // Blocking generation
 * val response = edgeVeda.generate("What is the meaning of life?")
 *
 * // Streaming generation
 * edgeVeda.generateStream("Explain quantum physics").collect { token ->
 *     print(token)
 * }
 *
 * edgeVeda.close()
 * ```
 */
class EdgeVeda private constructor(
    private val nativeBridge: NativeBridge
) : Closeable {

    private val initialized = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val currentGenerationJob = AtomicReference<Job?>(null)
    private val currentStreamJob = AtomicReference<Job?>(null)

    /**
     * Initialize the model with the given path and configuration.
     *
     * @param modelPath Absolute path to the model file (e.g., GGUF format)
     * @param config Configuration options for the model
     * @throws EdgeVedaException.ModelLoadError if model loading fails
     * @throws EdgeVedaException.InvalidConfiguration if configuration is invalid
     * @throws IllegalStateException if already initialized or closed
     */
    suspend fun init(modelPath: String, config: EdgeVedaConfig = EdgeVedaConfig()) {
        checkNotClosed()
        if (!initialized.compareAndSet(false, true)) {
            throw IllegalStateException("EdgeVeda is already initialized")
        }

        withContext(Dispatchers.IO) {
            try {
                nativeBridge.initModel(modelPath, config)
            } catch (e: Exception) {
                initialized.set(false)
                throw EdgeVedaException.ModelLoadError("Failed to load model: ${e.message}", e)
            }
        }
    }

    /**
     * Generate a complete response for the given prompt.
     *
     * This is a blocking operation that returns the full generated text.
     *
     * @param prompt The input prompt/question
     * @param options Optional generation parameters
     * @return The complete generated response
     * @throws EdgeVedaException.GenerationError if generation fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun generate(
        prompt: String,
        options: GenerateOptions = GenerateOptions()
    ): String {
        checkInitialized()

        return withContext(Dispatchers.Default) {
            val job = coroutineContext[Job]
            currentGenerationJob.set(job)
            try {
                nativeBridge.generate(prompt, options)
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Generation failed: ${e.message}", e)
            } finally {
                currentGenerationJob.set(null)
            }
        }
    }

    /**
     * Generate a streaming response for the given prompt.
     *
     * Returns a Flow that emits generated tokens as they are produced.
     * This is useful for providing real-time feedback to users.
     *
     * @param prompt The input prompt/question
     * @param options Optional generation parameters
     * @return Flow of generated tokens/text chunks
     * @throws EdgeVedaException.GenerationError if generation fails
     * @throws IllegalStateException if not initialized or closed
     */
    fun generateStream(
        prompt: String,
        options: GenerateOptions = GenerateOptions()
    ): Flow<String> = flow {
        checkInitialized()

        try {
            // Track the stream job for cancellation
            val job = coroutineContext[Job]
            currentStreamJob.set(job)
            
            nativeBridge.generateStream(prompt, options) { token ->
                emit(token)
            }
        } catch (e: Exception) {
            throw EdgeVedaException.GenerationError("Stream generation failed: ${e.message}", e)
        } finally {
            currentStreamJob.set(null)
        }
    }.flowOn(Dispatchers.Default)

    /**
     * Get current memory usage in bytes.
     *
     * @return Memory usage in bytes, or -1 if unavailable
     */
    val memoryUsage: Long
        get() {
            if (!initialized.get() || closed.get()) {
                return -1L
            }
            return try {
                nativeBridge.getMemoryUsage()
            } catch (e: Exception) {
                -1L
            }
        }

    /**
     * Get model information including architecture, parameters, and metadata.
     *
     * @return Map of model information
     * @throws EdgeVedaException.GenerationError if retrieval fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun getModelInfo(): Map<String, String> {
        checkInitialized()

        return withContext(Dispatchers.Default) {
            try {
                nativeBridge.getModelInfo()
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Failed to get model info: ${e.message}", e)
            }
        }
    }

    /**
     * Check if a model is currently loaded and ready for inference.
     *
     * @return true if model is loaded and initialized, false otherwise
     */
    fun isModelLoaded(): Boolean {
        return initialized.get() && !closed.get()
    }

    /**
     * Reset the conversation context while keeping the model loaded.
     *
     * This clears the KV cache and resets the conversation history,
     * allowing you to start a fresh conversation with the same model.
     *
     * @throws EdgeVedaException.GenerationError if reset fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun resetContext() {
        checkInitialized()

        withContext(Dispatchers.Default) {
            try {
                val success = nativeBridge.resetContext()
                if (!success) {
                    throw EdgeVedaException.GenerationError("Failed to reset context", null)
                }
            } catch (e: EdgeVedaException) {
                throw e
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Failed to reset context: ${e.message}", e)
            }
        }
    }

    /**
     * Cancel an ongoing generation.
     *
     * Cancels any active generation or stream operation by cancelling the underlying
     * coroutine Job. This will interrupt the inference operation at the Kotlin level.
     *
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun cancelGeneration() {
        checkInitialized()

        withContext(Dispatchers.Default) {
            // Cancel both generation and stream jobs if they exist
            currentGenerationJob.getAndSet(null)?.cancel()
            currentStreamJob.getAndSet(null)?.cancel()
        }
    }

    /**
     * Unload the model from memory while keeping the SDK instance alive.
     *
     * After calling this, you must call init() again before generating.
     *
     * @throws EdgeVedaException.UnloadError if unloading fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun unloadModel() {
        checkInitialized()

        withContext(Dispatchers.IO) {
            try {
                nativeBridge.unloadModel()
                initialized.set(false)
            } catch (e: Exception) {
                throw EdgeVedaException.UnloadError("Failed to unload model: ${e.message}", e)
            }
        }
    }

    /**
     * Close the SDK and release all resources.
     *
     * This is idempotent - calling it multiple times is safe.
     */
    override fun close() {
        if (closed.compareAndSet(false, true)) {
            try {
                if (initialized.get()) {
                    nativeBridge.unloadModel()
                    initialized.set(false)
                }
                nativeBridge.dispose()
            } catch (e: Exception) {
                // Log but don't throw in close()
                System.err.println("Error during EdgeVeda cleanup: ${e.message}")
            }
        }
    }

    private fun checkInitialized() {
        checkNotClosed()
        if (!initialized.get()) {
            throw IllegalStateException("EdgeVeda is not initialized. Call init() first.")
        }
    }

    private fun checkNotClosed() {
        if (closed.get()) {
            throw IllegalStateException("EdgeVeda is closed and cannot be used.")
        }
    }

    companion object {
        /**
         * Create a new EdgeVeda instance.
         *
         * @return A new EdgeVeda instance ready to be initialized
         */
        fun create(): EdgeVeda {
            val nativeBridge = NativeBridge()
            return EdgeVeda(nativeBridge)
        }

        /**
         * Get the SDK version.
         *
         * @return Version string (e.g., "1.0.0")
         */
        fun getVersion(): String = BuildConfig.VERSION_NAME

        /**
         * Check if the native library is available.
         *
         * @return true if native library loaded successfully
         */
        fun isNativeLibraryAvailable(): Boolean {
            return try {
                NativeBridge.isLibraryLoaded()
            } catch (e: Exception) {
                false
            }
        }

        // MARK: - Vision Inference

        /**
         * Create and initialize a VisionWorker for image description.
         *
         * VisionWorker maintains a persistent vision context (~600MB VLM + mmproj)
         * for efficient frame processing. Use for camera-based vision tasks.
         *
         * @param config Vision configuration including model and mmproj paths
         * @return Initialized VisionWorker ready for frame processing
         * @throws EdgeVedaException if initialization fails
         *
         * Example:
         * ```
         * val worker = EdgeVeda.createVisionWorker(
         *     VisionConfig(
         *         modelPath = "/path/to/smolvlm2.gguf",
         *         mmprojPath = "/path/to/smolvlm2-mmproj.gguf"
         *     )
         * )
         *
         * // Enqueue frames from camera
         * worker.enqueueFrame(rgbData, width, height)
         * val result = worker.processNextFrame("What do you see?")
         *
         * worker.cleanup()
         * ```
         */
        suspend fun createVisionWorker(config: VisionConfig): VisionWorker {
            val worker = VisionWorker()
            worker.initialize(config)
            return worker
        }

        /**
         * Describe an image directly without creating a VisionWorker.
         *
         * Convenience method for one-off vision inference. For continuous
         * camera feeds, prefer createVisionWorker() for better performance.
         *
         * @param config Vision configuration including model and mmproj paths
         * @param rgb RGB888 pixel data (width * height * 3 bytes)
         * @param width Frame width in pixels
         * @param height Frame height in pixels
         * @param prompt Text prompt for the model (default: "Describe what you see.")
         * @param params Optional generation parameters
         * @return VisionResult with description and timing information
         * @throws EdgeVedaException if inference fails
         *
         * Example:
         * ```
         * val result = EdgeVeda.describeImage(
         *     config = VisionConfig(
         *         modelPath = "/path/to/smolvlm2.gguf",
         *         mmprojPath = "/path/to/smolvlm2-mmproj.gguf"
         *     ),
         *     rgb = rgbData,
         *     width = 640,
         *     height = 480,
         *     prompt = "What objects do you see?"
         * )
         * println(result.description)
         * ```
         */
        suspend fun describeImage(
            config: VisionConfig,
            rgb: ByteArray,
            width: Int,
            height: Int,
            prompt: String = "Describe what you see.",
            params: VisionGenerationParams = VisionGenerationParams()
        ): VisionResult {
            val worker = VisionWorker()
            return try {
                worker.initialize(config)
                worker.describeFrame(rgb, width, height, prompt, params)
            } finally {
                worker.cleanup()
            }
        }

        /**
         * Check if vision context is loaded.
         *
         * @return true if vision is loaded and ready for inference
         */
        fun isVisionLoaded(): Boolean {
            return try {
                NativeBridge.isVisionInitialized()
            } catch (e: Exception) {
                false
            }
        }
    }
}
