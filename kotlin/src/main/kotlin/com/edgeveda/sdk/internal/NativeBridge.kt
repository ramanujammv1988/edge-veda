package com.edgeveda.sdk.internal

import com.edgeveda.sdk.EdgeVedaConfig
import com.edgeveda.sdk.EdgeVedaException
import com.edgeveda.sdk.GenerateOptions
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Internal JNI bridge to native EdgeVeda implementation.
 *
 * This class handles all interactions with the native C++ layer.
 * It should not be used directly by SDK users.
 *
 * @suppress
 */
internal class NativeBridge {

    private val disposed = AtomicBoolean(false)
    private var nativeHandle: Long = 0L

    init {
        ensureLibraryLoaded()
        nativeHandle = nativeCreate()
        if (nativeHandle == 0L) {
            throw EdgeVedaException.NativeLibraryError("Failed to create native instance")
        }
    }

    /**
     * Initialize the model with given path and configuration.
     *
     * @param modelPath Path to the model file
     * @param config Configuration options
     * @throws EdgeVedaException.ModelLoadError if initialization fails
     */
    fun initModel(modelPath: String, config: EdgeVedaConfig) {
        checkNotDisposed()
        val result = nativeInitModel(
            nativeHandle,
            modelPath,
            config.backend.toNativeValue(),
            config.numThreads,
            config.maxTokens,
            config.contextSize,
            config.batchSize,
            config.useGpu,
            config.useMmap,
            config.useMlock,
            config.temperature,
            config.topP,
            config.topK,
            config.repeatPenalty,
            config.seed
        )
        if (!result) {
            throw EdgeVedaException.ModelLoadError("Native model initialization failed")
        }
    }

    /**
     * Generate text synchronously.
     *
     * @param prompt Input prompt
     * @param options Generation options
     * @return Generated text
     * @throws EdgeVedaException.GenerationError if generation fails
     */
    fun generate(prompt: String, options: GenerateOptions): String {
        checkNotDisposed()
        return nativeGenerate(
            nativeHandle,
            prompt,
            options.maxTokens ?: -1,
            options.temperature ?: -1f,
            options.topP ?: -1f,
            options.topK ?: -1,
            options.repeatPenalty ?: -1f,
            options.stopSequences.toTypedArray(),
            options.seed ?: -1L
        ) ?: throw EdgeVedaException.GenerationError("Native generation returned null")
    }

    /**
     * Generate text with streaming callback.
     *
     * @param prompt Input prompt
     * @param options Generation options
     * @param callback Callback invoked for each generated token
     * @throws EdgeVedaException.GenerationError if generation fails
     */
    suspend fun generateStream(
        prompt: String,
        options: GenerateOptions,
        callback: suspend (String) -> Unit
    ) {
        checkNotDisposed()

        // Create a callback bridge that the native code can invoke
        val callbackBridge = object : StreamCallbackBridge {
            override fun onToken(token: String) {
                // Note: We can't use suspend here directly with JNI
                // In production, this would need a more sophisticated approach
                // using coroutine contexts or channels
                kotlinx.coroutines.runBlocking {
                    callback(token)
                }
            }
        }

        val success = nativeGenerateStream(
            nativeHandle,
            prompt,
            options.maxTokens ?: -1,
            options.temperature ?: -1f,
            options.topP ?: -1f,
            options.topK ?: -1,
            options.repeatPenalty ?: -1f,
            options.stopSequences.toTypedArray(),
            options.seed ?: -1L,
            callbackBridge
        )

        if (!success) {
            throw EdgeVedaException.GenerationError("Native stream generation failed")
        }
    }

    /**
     * Get current memory usage in bytes.
     */
    fun getMemoryUsage(): Long {
        checkNotDisposed()
        return nativeGetMemoryUsage(nativeHandle)
    }

    /**
     * Unload the model from memory.
     */
    fun unloadModel() {
        checkNotDisposed()
        nativeUnloadModel(nativeHandle)
    }

    /**
     * Dispose of native resources.
     */
    fun dispose() {
        if (disposed.compareAndSet(false, true)) {
            if (nativeHandle != 0L) {
                nativeDispose(nativeHandle)
                nativeHandle = 0L
            }
        }
    }

    private fun checkNotDisposed() {
        if (disposed.get()) {
            throw IllegalStateException("NativeBridge has been disposed")
        }
    }

    // JNI native method declarations
    private external fun nativeCreate(): Long

    private external fun nativeInitModel(
        handle: Long,
        modelPath: String,
        backend: Int,
        numThreads: Int,
        maxTokens: Int,
        contextSize: Int,
        batchSize: Int,
        useGpu: Boolean,
        useMmap: Boolean,
        useMlock: Boolean,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        seed: Long
    ): Boolean

    private external fun nativeGenerate(
        handle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        stopSequences: Array<String>,
        seed: Long
    ): String?

    private external fun nativeGenerateStream(
        handle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        stopSequences: Array<String>,
        seed: Long,
        callback: StreamCallbackBridge
    ): Boolean

    private external fun nativeGetMemoryUsage(handle: Long): Long

    private external fun nativeUnloadModel(handle: Long)

    private external fun nativeDispose(handle: Long)

    companion object {
        private const val LIBRARY_NAME = "edgeveda_jni"
        private val libraryLoaded = AtomicBoolean(false)
        private var libraryLoadError: Throwable? = null

        /**
         * Load the native library.
         */
        private fun ensureLibraryLoaded() {
            if (!libraryLoaded.get()) {
                synchronized(this) {
                    if (!libraryLoaded.get()) {
                        try {
                            System.loadLibrary(LIBRARY_NAME)
                            libraryLoaded.set(true)
                        } catch (e: UnsatisfiedLinkError) {
                            libraryLoadError = e
                            throw EdgeVedaException.NativeLibraryError(
                                "Failed to load native library: $LIBRARY_NAME",
                                e
                            )
                        } catch (e: SecurityException) {
                            libraryLoadError = e
                            throw EdgeVedaException.NativeLibraryError(
                                "Security exception loading native library",
                                e
                            )
                        }
                    }
                }
            }

            libraryLoadError?.let {
                throw EdgeVedaException.NativeLibraryError(
                    "Native library previously failed to load",
                    it
                )
            }
        }

        /**
         * Check if the native library is loaded.
         */
        fun isLibraryLoaded(): Boolean {
            return libraryLoaded.get()
        }

        /**
         * Get the library load error if any.
         */
        fun getLibraryLoadError(): Throwable? {
            return libraryLoadError
        }
    }
}

/**
 * Internal callback interface for streaming generation.
 */
internal interface StreamCallbackBridge {
    fun onToken(token: String)
}
