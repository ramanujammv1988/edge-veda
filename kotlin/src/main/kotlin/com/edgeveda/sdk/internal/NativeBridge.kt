package com.edgeveda.sdk.internal

import com.edgeveda.sdk.EdgeVedaConfig
import com.edgeveda.sdk.EdgeVedaException
import com.edgeveda.sdk.GenerateOptions
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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
     * Create a streaming generation handle.
     *
     * Returns a native stream handle that can be iterated token-by-token.
     * This allows for better control over streaming (pause, resume, cancel).
     *
     * @param prompt Input prompt
     * @param options Generation options
     * @return Native stream handle (must be freed with freeStream())
     * @throws EdgeVedaException.GenerationError if stream creation fails
     */
    fun createStream(prompt: String, options: GenerateOptions): Long {
        checkNotDisposed()
        
        val streamHandle = nativeStreamCreate(
            nativeHandle,
            prompt,
            options.maxTokens ?: -1,
            options.temperature ?: -1f,
            options.topP ?: -1f,
            options.topK ?: -1,
            options.repeatPenalty ?: -1f,
            options.stopSequences.toTypedArray(),
            options.seed ?: -1L
        )
        
        if (streamHandle == 0L) {
            throw EdgeVedaException.GenerationError("Failed to create stream: ${getLastError()}")
        }
        
        return streamHandle
    }

    /**
     * Get the next token from a streaming generation.
     *
     * @param streamHandle Native stream handle from createStream()
     * @return Next token, or null if stream is complete
     * @throws EdgeVedaException.GenerationError if token retrieval fails
     */
    fun nextToken(streamHandle: Long): String? {
        checkNotDisposed()
        
        if (streamHandle == 0L) {
            throw EdgeVedaException.GenerationError("Invalid stream handle")
        }
        
        return try {
            nativeStreamNext(streamHandle)
        } catch (e: Exception) {
            throw EdgeVedaException.GenerationError("Failed to get next token: ${e.message}", e)
        }
    }

    /**
     * Free a streaming generation handle and release resources.
     *
     * @param streamHandle Native stream handle from createStream()
     */
    fun freeStream(streamHandle: Long) {
        if (streamHandle != 0L) {
            try {
                nativeStreamFree(nativeHandle, streamHandle)
            } catch (e: Exception) {
                // Log but don't throw in cleanup
                System.err.println("Error freeing stream: ${e.message}")
            }
        }
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

        // Create stream handle
        val streamHandle = createStream(prompt, options)
        
        try {
            // Iterate tokens one by one - allows cancellation between tokens
            while (true) {
                // Check for cancellation
                currentCoroutineContext().ensureActive()
                
                // Get next token (blocking call, but runs on Dispatchers.Default)
                val token = nextToken(streamHandle) ?: break
                
                // Emit token to callback
                callback(token)
            }
        } finally {
            // Always free the stream handle
            freeStream(streamHandle)
        }
    }

    /**
     * Cancel ongoing generation immediately at the native level via ev_stream_cancel().
     *
     * @return true if a stream was found and cancel was requested, false if idle
     */
    fun cancel(): Boolean {
        checkNotDisposed()
        return nativeCancel(nativeHandle)
    }

    /**
     * Get the last error message from the native context.
     *
     * @return Error message string, or empty string if no error
     */
    fun getLastError(): String {
        checkNotDisposed()
        return nativeGetLastError(nativeHandle)
    }

    /**
     * Set system prompt for the context.
     *
     * @param systemPrompt The system prompt to set
     * @return true if successful, false otherwise
     */
    fun setSystemPrompt(systemPrompt: String): Boolean {
        checkNotDisposed()
        return nativeSetSystemPrompt(nativeHandle, systemPrompt)
    }

    /**
     * Clear chat history while keeping the model loaded.
     *
     * @return true if successful, false otherwise
     */
    fun clearChatHistory(): Boolean {
        checkNotDisposed()
        return nativeClearChatHistory(nativeHandle)
    }

    /**
     * Get the context window size (maximum number of tokens).
     *
     * @return Context size in tokens, or -1 on error
     */
    fun getContextSize(): Int {
        checkNotDisposed()
        return nativeGetContextSize(nativeHandle)
    }

    /**
     * Get the number of tokens currently used in the context.
     *
     * @return Number of tokens used, or -1 on error
     */
    fun getContextUsed(): Int {
        checkNotDisposed()
        return nativeGetContextUsed(nativeHandle)
    }

    /**
     * Tokenize text into token IDs.
     *
     * @param text Text to tokenize
     * @return Array of token IDs, or null on error
     */
    fun tokenize(text: String): IntArray? {
        checkNotDisposed()
        return nativeTokenize(nativeHandle, text)
    }

    /**
     * Detokenize token IDs into text.
     *
     * @param tokens Array of token IDs
     * @return Detokenized text, or null on error
     */
    fun detokenize(tokens: IntArray): String? {
        checkNotDisposed()
        return nativeDetokenize(nativeHandle, tokens)
    }

    /**
     * Generate embeddings for the given text.
     *
     * @param text Text to generate embeddings for
     * @return Array of embedding values, or null on error
     */
    fun getEmbedding(text: String): FloatArray? {
        checkNotDisposed()
        return nativeGetEmbedding(nativeHandle, text)
    }

    /**
     * Save the current session state to a file.
     *
     * @param path Path to save the session file
     * @return true if successful, false otherwise
     */
    fun saveSession(path: String): Boolean {
        checkNotDisposed()
        return nativeSaveSession(nativeHandle, path)
    }

    /**
     * Load session state from a file.
     *
     * @param path Path to the session file
     * @return true if successful, false otherwise
     */
    fun loadSession(path: String): Boolean {
        checkNotDisposed()
        return nativeLoadSession(nativeHandle, path)
    }

    /**
     * Run a performance benchmark.
     *
     * @param numThreads Number of threads to use
     * @param numTokens Number of tokens to process
     * @return Array with [tokens_per_second, time_ms, tokens_processed], or null on error
     */
    fun bench(numThreads: Int, numTokens: Int): DoubleArray? {
        checkNotDisposed()
        return nativeBench(nativeHandle, numThreads, numTokens)
    }

    /**
     * Get default generation parameters.
     *
     * @return Map of default parameter values
     */
    fun getGenerationParamsDefault(): Map<String, Any> {
        val params = nativeGenerationParamsDefault()
            ?: throw EdgeVedaException.GenerationError("Failed to retrieve default generation parameters")

        return mapOf(
            "maxTokens" to (params.getOrNull(0)?.toIntOrNull() ?: 256),
            "temperature" to (params.getOrNull(1)?.toFloatOrNull() ?: 0.7f),
            "topP" to (params.getOrNull(2)?.toFloatOrNull() ?: 0.9f),
            "topK" to (params.getOrNull(3)?.toIntOrNull() ?: 40),
            "repeatPenalty" to (params.getOrNull(4)?.toFloatOrNull() ?: 1.1f),
            "frequencyPenalty" to (params.getOrNull(5)?.toFloatOrNull() ?: 0.0f),
            "presencePenalty" to (params.getOrNull(6)?.toFloatOrNull() ?: 0.0f)
        )
    }

    /**
     * Get extended token information from a streaming generation.
     *
     * @param streamHandle Native stream handle
     * @return Map containing confidence, avg_confidence, needs_cloud_handoff, token_index
     */
    fun getStreamTokenInfo(streamHandle: Long): Map<String, Any>? {
        val info = nativeStreamGetTokenInfo(streamHandle) ?: return null

        return mapOf(
            "confidence" to (info.getOrNull(0) ?: -1.0),
            "avgConfidence" to (info.getOrNull(1) ?: -1.0),
            "needsCloudHandoff" to ((info.getOrNull(2) ?: 0.0) > 0.5),
            "tokenIndex" to (info.getOrNull(3)?.toInt() ?: 0)
        )
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
     * Get full memory usage breakdown from the native inference engine.
     *
     * @return LongArray with 5 elements: [currentBytes, peakBytes, limitBytes, modelBytes, contextBytes],
     *         or null on error
     */
    fun getMemoryStats(): LongArray? {
        checkNotDisposed()
        return nativeGetMemoryStats(nativeHandle)
    }

    /**
     * Set a hard memory ceiling in bytes.
     *
     * @param limitBytes Maximum memory in bytes; 0 = no limit
     * @return true if successful, false otherwise
     */
    fun setMemoryLimit(limitBytes: Long): Boolean {
        checkNotDisposed()
        return nativeSetMemoryLimit(nativeHandle, limitBytes)
    }

    /**
     * Ask the native engine to release cached allocations it can safely free.
     *
     * @return true if successful, false otherwise
     */
    fun memoryCleanup(): Boolean {
        checkNotDisposed()
        return nativeMemoryCleanup(nativeHandle)
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

        // JNI returns a flat 6-element array: [name, architecture, num_params,
        // context_length, embedding_dim, num_layers]. Map to named keys.
        val keys = listOf("name", "architecture", "num_parameters",
                          "context_length", "embedding_dim", "num_layers")
        return keys.zip(infoArray.toList()).toMap()
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

    // Token-by-token streaming methods
    private external fun nativeStreamCreate(
        handle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        stopSequences: Array<String>,
        seed: Long
    ): Long

    private external fun nativeStreamNext(streamHandle: Long): String?

    private external fun nativeStreamFree(handle: Long, streamHandle: Long)

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

    // Backend Detection (static methods — @JvmStatic declarations live in companion object)

    private external fun nativeIsBackendAvailable(backend: Int): Boolean

    // Utility Functions (static methods)
    private external fun nativeGetVersion(): String

    private external fun nativeSetVerbose(enable: Boolean)

    // Stream Control & Cancellation
    private external fun nativeCancel(handle: Long): Boolean

    // Error Handling
    private external fun nativeGetLastError(handle: Long): String

    // System Prompt & Chat History
    private external fun nativeSetSystemPrompt(handle: Long, systemPrompt: String): Boolean
    
    private external fun nativeClearChatHistory(handle: Long): Boolean

    // Context Introspection
    private external fun nativeGetContextSize(handle: Long): Int
    
    private external fun nativeGetContextUsed(handle: Long): Int

    // Tokenization
    private external fun nativeTokenize(handle: Long, text: String): IntArray?
    
    private external fun nativeDetokenize(handle: Long, tokens: IntArray): String?

    // Embeddings
    private external fun nativeGetEmbedding(handle: Long, text: String): FloatArray?

    // Session Management
    private external fun nativeSaveSession(handle: Long, path: String): Boolean
    
    private external fun nativeLoadSession(handle: Long, path: String): Boolean

    // Benchmarking
    private external fun nativeBench(handle: Long, numThreads: Int, numTokens: Int): DoubleArray?

    // Stream Token Info (Confidence Scoring)
    private external fun nativeStreamGetTokenInfo(streamHandle: Long): DoubleArray?

    // Generation Parameters
    private external fun nativeGenerationParamsDefault(): Array<String>?

    companion object {
        private const val LIBRARY_NAME = "edgeveda_jni"
        private val libraryLoaded = AtomicBoolean(false)
        private var libraryLoadError: Throwable? = null
        
        // Vision context singleton
        private var visionHandle: Long = 0L
        private val visionLock = Any()
        
        // Whisper context singleton
        private var whisperHandle: Long = 0L
        private val whisperLock = Any()

        // Backend Detection (must be in companion object for static access)
        @JvmStatic
        private external fun nativeDetectBackend(): Int

        @JvmStatic
        private external fun nativeGetBackendName(backend: Int): String

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
            imageBuffer: java.nio.ByteBuffer,
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

        // Whisper API JNI declarations (must be in companion object for static access)
        @JvmStatic
        private external fun nativeWhisperCreate(): Long

        @JvmStatic
        private external fun nativeWhisperInit(
            handle: Long,
            modelPath: String,
            numThreads: Int,
            useGpu: Boolean
        ): Boolean

        @JvmStatic
        private external fun nativeWhisperTranscribe(
            handle: Long,
            pcmSamples: FloatArray,
            language: String,
            translate: Boolean,
            nThreads: Int
        ): Array<String>?

        @JvmStatic
        private external fun nativeWhisperIsValid(handle: Long): Boolean

        @JvmStatic
        private external fun nativeWhisperDispose(handle: Long)

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
                
                // Query the actual backend in use from the native layer
                val detectedBackend = nativeDetectBackend()
                return nativeGetBackendName(detectedBackend)
            }
        }

        /**
         * Describe an image using the vision model (zero-copy via DirectByteBuffer).
         *
         * @param imageBuffer DirectByteBuffer containing RGB888 image data
         * @param width Image width in pixels
         * @param height Image height in pixels
         * @param prompt Text prompt for the model
         * @param paramsJson JSON string with VisionGenerationParams
         * @return JSON string with description and timings
         * @throws EdgeVedaException if inference fails
         */
        fun describeImage(
            imageBuffer: java.nio.ByteBuffer,
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
                
                // Ensure buffer is direct for zero-copy access
                if (!imageBuffer.isDirect) {
                    throw EdgeVedaException.InvalidConfiguration(
                        "Image buffer must be a DirectByteBuffer for zero-copy transfer"
                    )
                }
                
                // Parse params JSON
                val params = parseVisionParams(paramsJson)
                
                // Perform vision inference (zero-copy - direct pointer access)
                val description = nativeVisionDescribe(
                    visionHandle,
                    imageBuffer,
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

        /**
         * Initialize whisper context with Whisper STT model.
         *
         * @param configJson JSON string with WhisperConfig parameters
         * @return Backend name (e.g., "Metal", "CPU")
         * @throws EdgeVedaException if initialization fails
         */
        fun initWhisper(configJson: String): String {
            synchronized(whisperLock) {
                ensureLibraryLoaded()
                
                // Free existing context if any
                if (whisperHandle != 0L) {
                    nativeWhisperDispose(whisperHandle)
                    whisperHandle = 0L
                }
                
                // Parse config JSON
                val config = parseWhisperConfig(configJson)
                
                // Create new context
                whisperHandle = nativeWhisperCreate()
                if (whisperHandle == 0L) {
                    throw EdgeVedaException.NativeLibraryError("Failed to create whisper context")
                }
                
                // Initialize whisper model
                val success = nativeWhisperInit(
                    whisperHandle,
                    config.modelPath,
                    config.numThreads,
                    config.useGpu
                )
                
                if (!success) {
                    nativeWhisperDispose(whisperHandle)
                    whisperHandle = 0L
                    throw EdgeVedaException.ModelLoadError("Failed to initialize whisper model")
                }
                
                // Verify context is valid
                if (!nativeWhisperIsValid(whisperHandle)) {
                    nativeWhisperDispose(whisperHandle)
                    whisperHandle = 0L
                    throw EdgeVedaException.ModelLoadError("Whisper context validation failed")
                }
                
                // Return backend name based on GPU usage
                return if (config.useGpu) "Metal" else "CPU"
            }
        }

        /**
         * Transcribe PCM audio samples to text with timing segments.
         *
         * @param pcmSamples PCM audio data (16kHz, mono, float32, range [-1.0, 1.0])
         * @param paramsJson JSON string with WhisperTranscribeParams
         * @return JSON string with transcription segments and timing info
         * @throws EdgeVedaException if transcription fails
         */
        fun transcribeAudio(
            pcmSamples: FloatArray,
            paramsJson: String
        ): String {
            synchronized(whisperLock) {
                ensureLibraryLoaded()
                
                if (whisperHandle == 0L || !nativeWhisperIsValid(whisperHandle)) {
                    throw EdgeVedaException.ModelLoadError("Whisper context not initialized")
                }
                
                // Parse params JSON
                val params = parseWhisperParams(paramsJson)
                
                // Perform transcription
                val segmentArray = nativeWhisperTranscribe(
                    whisperHandle,
                    pcmSamples,
                    params.language,
                    params.translate,
                    params.nThreads
                ) ?: throw EdgeVedaException.GenerationError("Whisper transcription returned null")
                
                // Convert flat array [text1, start_ms1, end_ms1, text2, start_ms2, end_ms2, ...]
                // to JSON array of segment objects
                val segments = org.json.JSONArray()
                var i = 0
                while (i < segmentArray.size) {
                    if (i + 2 < segmentArray.size) {
                        val segment = org.json.JSONObject().apply {
                            put("text", segmentArray[i])
                            put("start_ms", segmentArray[i + 1].toLongOrNull() ?: 0L)
                            put("end_ms", segmentArray[i + 2].toLongOrNull() ?: 0L)
                        }
                        segments.put(segment)
                    }
                    i += 3
                }
                
                // Build result JSON
                val result = org.json.JSONObject().apply {
                    put("segments", segments)
                    put("n_segments", segments.length())
                }
                
                return result.toString()
            }
        }

        /**
         * Free whisper context and release resources.
         *
         * @throws EdgeVedaException if cleanup fails
         */
        fun freeWhisper() {
            synchronized(whisperLock) {
                if (whisperHandle != 0L) {
                    try {
                        nativeWhisperDispose(whisperHandle)
                    } finally {
                        whisperHandle = 0L
                    }
                }
            }
        }

        /**
         * Check if whisper context is initialized.
         */
        fun isWhisperInitialized(): Boolean {
            synchronized(whisperLock) {
                return whisperHandle != 0L && nativeWhisperIsValid(whisperHandle)
            }
        }

        /**
         * Parse whisper config JSON string.
         */
        private fun parseWhisperConfig(json: String): WhisperConfigData {
            val obj = org.json.JSONObject(json)
            return WhisperConfigData(
                modelPath = obj.getString("modelPath"),
                numThreads = obj.optInt("numThreads", 4),
                useGpu = obj.optBoolean("useGpu", true)
            )
        }

        /**
         * Parse whisper transcribe params JSON string.
         */
        private fun parseWhisperParams(json: String): WhisperParamsData {
            val obj = org.json.JSONObject(json)
            return WhisperParamsData(
                language = obj.optString("language", "en"),
                translate = obj.optBoolean("translate", false),
                nThreads = obj.optInt("nThreads", 4)
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
 * Internal data class for whisper config parsing.
 */
private data class WhisperConfigData(
    val modelPath: String,
    val numThreads: Int,
    val useGpu: Boolean
)

/**
 * Internal data class for whisper params parsing.
 */
private data class WhisperParamsData(
    val language: String,
    val translate: Boolean,
    val nThreads: Int
)

/**
 * Sealed class used as a type-safe sentinel for the streaming token queue.
 * LinkedBlockingQueue does NOT allow null elements, so we use StreamItem.End
 * instead of null to signal end-of-stream.
 */
private sealed class StreamItem {
    data class Token(val value: String) : StreamItem()
    object End : StreamItem()
}

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
