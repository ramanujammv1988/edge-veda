package com.edgeveda.sdk

import com.edgeveda.sdk.internal.NativeBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean

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
            try {
                nativeBridge.generate(prompt, options)
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Generation failed: ${e.message}", e)
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
            nativeBridge.generateStream(prompt, options) { token ->
                emit(token)
            }
        } catch (e: Exception) {
            throw EdgeVedaException.GenerationError("Stream generation failed: ${e.message}", e)
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
     * Cancel an ongoing generation.
     *
     * Note: This is a placeholder for future implementation with proper cancellation support.
     *
     * @throws EdgeVedaException.GenerationError if cancellation fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun cancelGeneration() {
        checkInitialized()

        withContext(Dispatchers.Default) {
            try {
                // TODO: Implement native cancellation when native layer supports it
                throw EdgeVedaException.GenerationError(
                    "Cancellation not yet implemented in native layer",
                    null
                )
            } catch (e: EdgeVedaException) {
                throw e
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Failed to cancel generation: ${e.message}", e)
            }
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
    }
}
