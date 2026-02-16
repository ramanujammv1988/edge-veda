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

        // Use a blocking queue to bridge between the JNI callback thread and the
        // suspend coroutine context.  The JNI onToken() callback simply enqueues
        // tokens (pure Java, no coroutines).  A StreamItem.End sentinel signals
        // end-of-stream (LinkedBlockingQueue does NOT allow null elements).
        val tokenQueue = java.util.concurrent.LinkedBlockingQueue<StreamItem>()
        var nativeError: Throwable? = null

        // Run the blocking native generation on a dedicated thread so the
        // current coroutine is free to consume tokens from the queue.
        val nativeThread = Thread({
            val bridge = object : StreamCallbackBridge {
                override fun onToken(token: String) {
                    if (streamCancelFlag.get()) {
                        throw kotlinx.coroutines.CancellationException("Stream cancelled via cancelCurrentStream()")
                    }
                    tokenQueue.put(StreamItem.Token(token))
                }
            }
            try {
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
                    bridge
                )
                if (!success) {
                    nativeError = EdgeVedaException.GenerationError("Native stream generation failed")
                }
            } catch (e: Throwable) {
                nativeError = e
            } finally {
                // Sentinel: signals the consumer loop below to stop
                tokenQueue.put(StreamItem.End)
            }
        }, "ev-stream-native")
        nativeThread.start()

        // Consume tokens from the queue in the caller's coroutine context.
        // This is suspend-safe – callback() (e.g. Flow emit()) runs in the
        // correct coroutine scope.
        try {
            while (true) {
                when (val item = tokenQueue.take()) {
                    is StreamItem.Token -> callback(item.value)
                    is StreamItem.End -> break
                }
            }
        } finally {
            // If the consumer is cancelled (e.g. job cancellation), signal native
            // side to stop producing and wait for the thread to finish.
            streamCancelFlag.set(true)
            nativeThread.join(5_000)
        }

        // Propagate any error from the native thread
        nativeError?.let { throw it }
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
     * Cancel ongoing generation immediately at the native level.
     *
     * @return true if cancellation was successful, false otherwise
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
