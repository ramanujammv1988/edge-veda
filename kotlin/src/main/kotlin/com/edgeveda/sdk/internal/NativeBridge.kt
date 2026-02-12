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
    private val streamCancelFlag = AtomicBoolean(false)
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

        // Reset cancel flag before starting a new stream
        streamCancelFlag.set(false)

        // Create a callback bridge that the native code can invoke
        val callbackBridge = object : StreamCallbackBridge {
            override fun onToken(token: String) {
                // Check cancel flag before delivering token
                if (streamCancelFlag.get()) {
                    throw kotlinx.coroutines.CancellationException("Stream cancelled via cancelCurrentStream()")
                }
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
     * Cancel the current streaming generation.
     *
     * Sets an atomic flag that is checked in the StreamCallbackBridge.onToken()
     * callback. When the flag is set, the callback throws a CancellationException
     * which aborts the native generation loop.
     */
    fun cancelCurrentStream() {
        streamCancelFlag.set(true)
    }

    /**
     * Get current memory usage in bytes.
     */
    fun getMemoryUsage(): Long {
        checkNotDisposed()
        return nativeGetMemoryUsage(nativeHandle)
    }

    /**
     * Set memory pressure callback.
     *
     * @param callback Callback to invoke on memory pressure events (null to unregister)
     * @return true if successful, false otherwise
     */
    fun setMemoryPressureCallback(callback: ((Long, Long) -> Unit)?): Boolean {
        checkNotDisposed()
        val callbackBridge = if (callback != null) {
            object : MemoryPressureCallback {
                override fun onMemoryPressure(currentBytes: Long, limitBytes: Long) {
                    callback(currentBytes, limitBytes)
                }
            }
        } else {
            null
        }
        return nativeSetMemoryPressureCallback(nativeHandle, callbackBridge)
    }

    /**
     * Unload the model from memory.
     */
    fun unloadModel() {
        checkNotDisposed()
        nativeUnloadModel(nativeHandle)
    }

    /**
     * Reset the conversation context while keeping the model loaded.
     *
     * @return true if successful, false otherwise
     */
    fun resetContext(): Boolean {
        checkNotDisposed()
        return nativeReset(nativeHandle)
    }

    /**
     * Get model information including architecture, parameters, and metadata.
     *
     * @return Map of model information
     * @throws EdgeVedaException.GenerationError if retrieval fails
     */
    fun getModelInfo(): Map<String, String> {
        checkNotDisposed()
        val infoArray = nativeGetModelInfo(nativeHandle)
            ?: throw EdgeVedaException.GenerationError("Failed to retrieve model information")

        // Convert array to map (assumes array contains key-value pairs)
        val infoMap = mutableMapOf<String, String>()
        var i = 0
        while (i < infoArray.size - 1) {
            infoMap[infoArray[i]] = infoArray[i + 1]
            i += 2
        }
        return infoMap
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

    // Context Management
    private external fun nativeIsValid(handle: Long): Boolean

    private external fun nativeReset(handle: Long): Boolean

    // Memory Management
    private external fun nativeSetMemoryLimit(handle: Long, limitBytes: Long): Boolean

    private external fun nativeMemoryCleanup(handle: Long): Boolean

    private external fun nativeSetMemoryPressureCallback(handle: Long, callback: MemoryPressureCallback?): Boolean

    private external fun nativeGetMemoryStats(handle: Long): LongArray?

    // Model Information
    private external fun nativeGetModelInfo(handle: Long): Array<String>?

    // Backend Detection (static methods)
    private external fun nativeDetectBackend(): Int

    private external fun nativeIsBackendAvailable(backend: Int): Boolean

    private external fun nativeGetBackendName(backend: Int): String

    // Utility Functions (static methods)
    private external fun nativeGetVersion(): String

    private external fun nativeSetVerbose(enable: Boolean)

    // Stream Control
    private external fun nativeCancelStream(streamHandle: Long)

    companion object {
        private const val LIBRARY_NAME = "edgeveda_jni"
        private val libraryLoaded = AtomicBoolean(false)
        private var libraryLoadError: Throwable? = null
        
        // Vision context singleton
        private var visionHandle: Long = 0L
        private val visionLock = Any()

        // Vision API JNI declarations (must be in companion object for static access)
        @JvmStatic
        private external fun nativeVisionCreate(): Long

        @JvmStatic
        private external fun nativeVisionInit(
            handle: Long,
            modelPath: String,
            mmprojPath: String,
            numThreads: Int,
            contextSize: Int,
            batchSize: Int,
            memoryLimitBytes: Long,
            gpuLayers: Int,
            useMmap: Boolean
        ): Boolean

        @JvmStatic
        private external fun nativeVisionDescribe(
            handle: Long,
            imageBytes: ByteArray,
            width: Int,
            height: Int,
            prompt: String,
            maxTokens: Int,
            temperature: Float,
            topP: Float,
            topK: Int,
            repeatPenalty: Float
        ): String?

        @JvmStatic
        private external fun nativeVisionIsValid(handle: Long): Boolean

        @JvmStatic
        private external fun nativeVisionGetLastTimings(handle: Long): DoubleArray?

        @JvmStatic
        private external fun nativeVisionDispose(handle: Long)

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

        /**
         * Initialize vision context with VLM model.
         *
         * @param configJson JSON string with VisionConfig parameters
         * @return Backend name (e.g., "Vulkan", "CPU")
         * @throws EdgeVedaException if initialization fails
         */
        fun initVision(configJson: String): String {
            synchronized(visionLock) {
                ensureLibraryLoaded()
                
                // Free existing context if any
                if (visionHandle != 0L) {
                    nativeVisionDispose(visionHandle)
                    visionHandle = 0L
                }
                
                // Parse config JSON
                val config = parseVisionConfig(configJson)
                
                // Create new context
                visionHandle = nativeVisionCreate()
                if (visionHandle == 0L) {
                    throw EdgeVedaException.NativeLibraryError("Failed to create vision context")
                }
                
                // Initialize vision model
                val success = nativeVisionInit(
                    visionHandle,
                    config.modelPath,
                    config.mmprojPath,
                    config.numThreads,
                    config.contextSize,
                    config.batchSize,
                    config.memoryLimitBytes,
                    config.gpuLayers,
                    config.useMmap
                )
                
                if (!success) {
                    nativeVisionDispose(visionHandle)
                    visionHandle = 0L
                    throw EdgeVedaException.ModelLoadError("Failed to initialize vision model")
                }
                
                // Verify context is valid
                if (!nativeVisionIsValid(visionHandle)) {
                    nativeVisionDispose(visionHandle)
                    visionHandle = 0L
                    throw EdgeVedaException.ModelLoadError("Vision context validation failed")
                }
                
                // Return backend name (hardcoded for now, could be queried from native)
                return "Vulkan"
            }
        }

        /**
         * Describe an image using the vision model.
         *
         * @param base64Image Base64-encoded RGB888 image data
         * @param width Image width in pixels
         * @param height Image height in pixels
         * @param prompt Text prompt for the model
         * @param paramsJson JSON string with VisionGenerationParams
         * @return JSON string with description and timings
         * @throws EdgeVedaException if inference fails
         */
        fun describeImage(
            base64Image: String,
            width: Int,
            height: Int,
            prompt: String,
            paramsJson: String
        ): String {
            synchronized(visionLock) {
                ensureLibraryLoaded()
                
                if (visionHandle == 0L || !nativeVisionIsValid(visionHandle)) {
                    throw EdgeVedaException.ModelLoadError("Vision context not initialized")
                }
                
                // Parse params JSON
                val params = parseVisionParams(paramsJson)
                
                // Decode Base64 to bytes
                val imageBytes = android.util.Base64.decode(base64Image, android.util.Base64.NO_WRAP)
                
                // Perform vision inference
                val description = nativeVisionDescribe(
                    visionHandle,
                    imageBytes,
                    width,
                    height,
                    prompt,
                    params.maxTokens,
                    params.temperature,
                    params.topP,
                    params.topK,
                    params.repeatPenalty
                ) ?: throw EdgeVedaException.GenerationError("Vision inference returned null")
                
                // Get timings
                val timings = nativeVisionGetLastTimings(visionHandle)
                    ?: doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                
                // Build result JSON
                val result = org.json.JSONObject().apply {
                    put("description", description)
                    put("modelLoadMs", timings.getOrNull(0) ?: 0.0)
                    put("imageEncodeMs", timings.getOrNull(1) ?: 0.0)
                    put("promptEvalMs", timings.getOrNull(2) ?: 0.0)
                    put("decodeMs", timings.getOrNull(3) ?: 0.0)
                    put("promptTokens", timings.getOrNull(4)?.toInt() ?: 0)
                    put("generatedTokens", timings.getOrNull(5)?.toInt() ?: 0)
                }
                
                return result.toString()
            }
        }

        /**
         * Free vision context and release resources.
         *
         * @throws EdgeVedaException if cleanup fails
         */
        fun freeVision() {
            synchronized(visionLock) {
                if (visionHandle != 0L) {
                    try {
                        nativeVisionDispose(visionHandle)
                    } finally {
                        visionHandle = 0L
                    }
                }
            }
        }

        /**
         * Check if vision context is initialized.
         */
        fun isVisionInitialized(): Boolean {
            synchronized(visionLock) {
                return visionHandle != 0L && nativeVisionIsValid(visionHandle)
            }
        }

        /**
         * Parse vision config JSON string.
         */
        private fun parseVisionConfig(json: String): VisionConfigData {
            val obj = org.json.JSONObject(json)
            return VisionConfigData(
                modelPath = obj.getString("modelPath"),
                mmprojPath = obj.getString("mmprojPath"),
                numThreads = obj.optInt("numThreads", 4),
                contextSize = obj.optInt("contextSize", 2048),
                batchSize = obj.optInt("batchSize", 512),
                memoryLimitBytes = obj.optLong("memoryLimitBytes", 0L),
                gpuLayers = obj.optInt("gpuLayers", -1),
                useMmap = obj.optBoolean("useMmap", true)
            )
        }

        /**
         * Parse vision params JSON string.
         */
        private fun parseVisionParams(json: String): VisionParamsData {
            val obj = org.json.JSONObject(json)
            return VisionParamsData(
                maxTokens = obj.optInt("maxTokens", 100),
                temperature = obj.optDouble("temperature", 0.3).toFloat(),
                topP = obj.optDouble("topP", 0.9).toFloat(),
                topK = obj.optInt("topK", 40),
                repeatPenalty = obj.optDouble("repeatPenalty", 1.1).toFloat()
            )
        }
    }
}

/**
 * Internal data class for vision config parsing.
 */
private data class VisionConfigData(
    val modelPath: String,
    val mmprojPath: String,
    val numThreads: Int,
    val contextSize: Int,
    val batchSize: Int,
    val memoryLimitBytes: Long,
    val gpuLayers: Int,
    val useMmap: Boolean
)

/**
 * Internal data class for vision params parsing.
 */
private data class VisionParamsData(
    val maxTokens: Int,
    val temperature: Float,
    val topP: Float,
    val topK: Int,
    val repeatPenalty: Float
)

/**
 * Internal callback interface for streaming generation.
 */
internal interface StreamCallbackBridge {
    fun onToken(token: String)
}

/**
 * Internal callback interface for memory pressure events.
 */
internal interface MemoryPressureCallback {
    fun onMemoryPressure(currentBytes: Long, limitBytes: Long)
}
