package com.edgeveda.sdk

import android.app.Application
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.edgeveda.sdk.internal.NativeBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.coroutineContext

/**
 * Memory pressure handler callback.
 * Called when the system requests memory to be freed.
 */
typealias MemoryPressureHandler = suspend (level: Int) -> Unit

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
    private val nativeBridge: NativeBridge,
    private val applicationContext: Context?
) : Closeable {

    private val initialized = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val currentGenerationJob = AtomicReference<Job?>(null)
    private val currentStreamJob = AtomicReference<Job?>(null)
    
    // Lifecycle management
    private val lifecycleScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var componentCallbacks: ComponentCallbacks2? = null
    private var lifecycleObserver: DefaultLifecycleObserver? = null
    private var customMemoryPressureHandler: MemoryPressureHandler? = null
    private val autoUnloadedDueToMemory = AtomicBoolean(false)
    private var lastModelPath: String? = null
    private var lastConfig: EdgeVedaConfig? = null

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

        // Store for potential reload
        lastModelPath = modelPath
        lastConfig = config

        withContext(Dispatchers.IO) {
            try {
                nativeBridge.initModel(modelPath, config)
                autoUnloadedDueToMemory.set(false)
            } catch (e: Exception) {
                initialized.set(false)
                lastModelPath = null
                lastConfig = null
                throw EdgeVedaException.ModelLoadError("Failed to load model: ${e.message}", e)
            }
        }

        // Register lifecycle callbacks on main thread (after IO completes)
        // Must NOT run inside Dispatchers.IO — addObserver requires main thread
        applicationContext?.let { ctx ->
            withContext(Dispatchers.Main) {
                registerLifecycleCallbacks(ctx)
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
     * Cancels any active generation or stream operation. For streaming, this sets
     * a cancel flag in the native bridge that aborts token delivery at the JNI
     * callback level, then cancels the Kotlin coroutine Jobs.
     *
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun cancelGeneration() {
        checkInitialized()

        withContext(Dispatchers.Default) {
            // Signal the native bridge to abort token delivery in the stream callback
            nativeBridge.cancelCurrentStream()
            // Cancel both generation and stream jobs if they exist
            currentGenerationJob.getAndSet(null)?.cancel()
            currentStreamJob.getAndSet(null)?.cancel()
        }
    }

    /**
     * Get text embedding for semantic similarity and retrieval.
     *
     * Returns a normalized embedding vector for the given text. The model must be
     * an embedding model (e.g., nomic-embed, bge, etc.) -- using a generative model
     * will produce meaningless embeddings.
     *
     * @param text Text to generate embedding for
     * @return FloatArray containing the embedding vector
     * @throws EdgeVedaException.GenerationError if embedding generation fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun getEmbedding(text: String): FloatArray {
        checkInitialized()

        if (text.isEmpty()) {
            throw EdgeVedaException.GenerationError("Text cannot be empty for embedding")
        }

        return withContext(Dispatchers.Default) {
            try {
                nativeBridge.getEmbedding(text)
                    ?: throw EdgeVedaException.GenerationError("Embedding generation returned null")
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Embedding generation failed: ${e.message}", e)
            }
        }
    }

    /**
     * Tokenize text into token IDs.
     *
     * Converts text into the model's token representation. Useful for:
     * - Counting tokens in a prompt to check context limits
     * - Understanding how the model sees the text
     * - Debugging tokenization issues
     *
     * @param text Text to tokenize
     * @return IntArray of token IDs
     * @throws EdgeVedaException.GenerationError if tokenization fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun tokenize(text: String): IntArray {
        checkInitialized()

        return withContext(Dispatchers.Default) {
            try {
                nativeBridge.tokenize(text)
                    ?: throw EdgeVedaException.GenerationError("Tokenization returned null")
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Tokenization failed: ${e.message}", e)
            }
        }
    }

    /**
     * Convert token IDs back to text.
     *
     * Converts a sequence of token IDs back into text. Useful for:
     * - Debugging token sequences
     * - Understanding model output at token level
     * - Implementing custom token processing
     *
     * @param tokens Array of token IDs
     * @return Detokenized text
     * @throws EdgeVedaException.GenerationError if detokenization fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun detokenize(tokens: IntArray): String {
        checkInitialized()

        return withContext(Dispatchers.Default) {
            try {
                nativeBridge.detokenize(tokens)
                    ?: throw EdgeVedaException.GenerationError("Detokenization returned null")
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Detokenization failed: ${e.message}", e)
            }
        }
    }

    /**
     * Get the maximum context window size in tokens.
     *
     * Returns the total number of tokens that can fit in the context window,
     * as configured during initialization.
     *
     * @return Context size in tokens
     * @throws IllegalStateException if not initialized or closed
     */
    fun getContextSize(): Int {
        checkInitialized()
        val size = nativeBridge.getContextSize()
        if (size < 0) {
            throw EdgeVedaException.GenerationError("Failed to retrieve context size")
        }
        return size
    }

    /**
     * Get the number of tokens currently used in the context.
     *
     * Returns how many tokens from the context window are currently occupied
     * by the conversation history and KV cache. Use this to monitor context
     * usage and avoid running out of space.
     *
     * @return Number of tokens currently used
     * @throws IllegalStateException if not initialized or closed
     */
    fun getContextUsed(): Int {
        checkInitialized()
        val used = nativeBridge.getContextUsed()
        if (used < 0) {
            throw EdgeVedaException.GenerationError("Failed to retrieve context usage")
        }
        return used
    }

    /**
     * Save the current conversation session to a file.
     *
     * Persists the KV cache and context state to disk, allowing you to resume
     * the conversation later without reprocessing all the history. Useful for:
     * - Long-running conversations that span app sessions
     * - Saving computational resources on app restart
     * - Creating conversation snapshots
     *
     * @param path Absolute path where the session file will be saved
     * @return true if successful
     * @throws EdgeVedaException.GenerationError if save fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun saveSession(path: String): Boolean {
        checkInitialized()

        if (path.isEmpty()) {
            throw EdgeVedaException.GenerationError("Session path cannot be empty")
        }

        return withContext(Dispatchers.IO) {
            try {
                nativeBridge.saveSession(path)
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Failed to save session: ${e.message}", e)
            }
        }
    }

    /**
     * Load a previously saved conversation session from a file.
     *
     * Restores the KV cache and context state from disk, allowing you to resume
     * a conversation from where it left off. The loaded session must have been
     * created with the same model.
     *
     * @param path Absolute path to the session file
     * @return true if successful
     * @throws EdgeVedaException.GenerationError if load fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun loadSession(path: String): Boolean {
        checkInitialized()

        if (path.isEmpty()) {
            throw EdgeVedaException.GenerationError("Session path cannot be empty")
        }

        return withContext(Dispatchers.IO) {
            try {
                nativeBridge.loadSession(path)
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Failed to load session: ${e.message}", e)
            }
        }
    }

    /**
     * Set a system prompt to guide the model's behavior.
     *
     * System prompts establish rules, tone, and behavior that the model should
     * follow across all interactions. Unlike user messages, system prompts are
     * typically not visible in the conversation and guide the model's responses.
     *
     * Example:
     * ```
     * edgeVeda.setSystemPrompt("You are a helpful coding assistant. Provide concise, accurate code examples.")
     * ```
     *
     * @param systemPrompt The system instruction text
     * @return true if successful
     * @throws EdgeVedaException.GenerationError if setting fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun setSystemPrompt(systemPrompt: String): Boolean {
        checkInitialized()

        return withContext(Dispatchers.Default) {
            try {
                nativeBridge.setSystemPrompt(systemPrompt)
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Failed to set system prompt: ${e.message}", e)
            }
        }
    }

    /**
     * Clear the conversation history while keeping the model loaded.
     *
     * Removes all previous messages from the context, freeing up space for new
     * conversations. This is lighter than resetContext() as it only clears the
     * conversation history while maintaining other context state.
     *
     * @return true if successful
     * @throws EdgeVedaException.GenerationError if clearing fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun clearChatHistory(): Boolean {
        checkInitialized()

        return withContext(Dispatchers.Default) {
            try {
                nativeBridge.clearChatHistory()
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Failed to clear chat history: ${e.message}", e)
            }
        }
    }

    /**
     * Get the last error message from the native layer.
     *
     * Retrieves detailed error information from the underlying C++ implementation.
     * Useful for debugging when operations fail.
     *
     * @return Error message string, or empty string if no error
     * @throws IllegalStateException if not initialized or closed
     */
    fun getLastError(): String {
        checkInitialized()
        return try {
            nativeBridge.getLastError()
        } catch (e: Exception) {
            "Failed to retrieve error: ${e.message}"
        }
    }

    /**
     * Run a performance benchmark to measure inference speed.
     *
     * Executes a standardized benchmark to measure tokens per second and latency.
     * Useful for:
     * - Comparing different model configurations
     * - Verifying GPU acceleration is working
     * - Profiling performance across devices
     *
     * @param numThreads Number of threads to use for the benchmark
     * @param numTokens Number of tokens to process in the benchmark
     * @return BenchmarkResult with performance metrics
     * @throws EdgeVedaException.GenerationError if benchmark fails
     * @throws IllegalStateException if not initialized or closed
     */
    suspend fun runBenchmark(numThreads: Int = 4, numTokens: Int = 512): BenchmarkResult {
        checkInitialized()

        if (numThreads < 1 || numThreads > 32) {
            throw EdgeVedaException.ConfigurationError("numThreads must be between 1 and 32")
        }

        if (numTokens < 1 || numTokens > 4096) {
            throw EdgeVedaException.ConfigurationError("numTokens must be between 1 and 4096")
        }

        return withContext(Dispatchers.Default) {
            try {
                val result = nativeBridge.bench(numThreads, numTokens)
                    ?: throw EdgeVedaException.GenerationError("Benchmark returned null")

                BenchmarkResult(
                    tokensPerSecond = result.getOrNull(0) ?: 0.0,
                    timeMs = result.getOrNull(1) ?: 0.0,
                    tokensProcessed = result.getOrNull(2)?.toInt() ?: 0
                )
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError("Benchmark failed: ${e.message}", e)
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
     * Reload the model after it was unloaded.
     * Useful for recovering from memory pressure situations.
     *
     * @throws EdgeVedaException.ModelLoadError if reload fails
     * @throws IllegalStateException if model path is not available or already loaded
     */
    suspend fun reloadModel() {
        checkNotClosed()
        if (initialized.get()) {
            return // Already loaded
        }
        
        val modelPath = lastModelPath
            ?: throw IllegalStateException("No model path available for reload. Call init() first.")
        val config = lastConfig ?: EdgeVedaConfig()
        
        init(modelPath, config)
    }
    
    /**
     * Check if model was auto-unloaded due to memory pressure.
     *
     * @return true if model was unloaded due to memory warning
     */
    fun wasAutoUnloaded(): Boolean {
        return autoUnloadedDueToMemory.get()
    }

    /**
     * Close the SDK and release all resources.
     *
     * This is idempotent - calling it multiple times is safe.
     */
    override fun close() {
        if (closed.compareAndSet(false, true)) {
            try {
                // Unregister lifecycle callbacks
                unregisterLifecycleCallbacks()
                
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
    
    // MARK: - Lifecycle Management
    
    /**
     * Register Android lifecycle callbacks for memory management.
     */
    private fun registerLifecycleCallbacks(context: Context) {
        // ComponentCallbacks2 for memory pressure
        val callbacks = object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                lifecycleScope.launch {
                    handleMemoryPressure(level)
                }
            }
            
            override fun onConfigurationChanged(newConfig: Configuration) {
                // No action needed
            }
            
            override fun onLowMemory() {
                lifecycleScope.launch {
                    handleMemoryPressure(ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
                }
            }
        }
        
        context.registerComponentCallbacks(callbacks)
        componentCallbacks = callbacks
        
        // Lifecycle observer for app backgrounding
        val observer = object : DefaultLifecycleObserver {
            override fun onStop(owner: LifecycleOwner) {
                // App is going to background - consider unloading if needed
                lifecycleScope.launch {
                    handleAppBackground()
                }
            }
        }
        
        ProcessLifecycleOwner.get().lifecycle.addObserver(observer)
        lifecycleObserver = observer
    }
    
    /**
     * Unregister lifecycle callbacks.
     */
    private fun unregisterLifecycleCallbacks() {
        componentCallbacks?.let { callbacks ->
            applicationContext?.unregisterComponentCallbacks(callbacks)
            componentCallbacks = null
        }
        
        lifecycleObserver?.let { observer ->
            ProcessLifecycleOwner.get().lifecycle.removeObserver(observer)
            lifecycleObserver = null
        }
    }
    
    /**
     * Handle memory pressure events.
     */
    private suspend fun handleMemoryPressure(level: Int) {
        if (!initialized.get() || closed.get()) {
            return
        }
        
        // Call custom handler if set
        customMemoryPressureHandler?.let { handler ->
            handler(level)
            return
        }
        
        // Default behavior based on trim level
        when (level) {
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> {
                // Critical memory pressure - unload model
                handleMemoryPressureDefault()
            }
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_MODERATE -> {
                // Moderate pressure - cancel ongoing operations
                cancelGeneration()
            }
        }
    }
    
    /**
     * Default memory pressure handler: unload the model.
     */
    private suspend fun handleMemoryPressureDefault() {
        if (!initialized.get()) {
            return
        }
        
        // Cancel any ongoing generation
        currentGenerationJob.getAndSet(null)?.cancel()
        currentStreamJob.getAndSet(null)?.cancel()
        
        // Unload model to free memory
        withContext(Dispatchers.IO) {
            try {
                nativeBridge.unloadModel()
                initialized.set(false)
                autoUnloadedDueToMemory.set(true)
            } catch (e: Exception) {
                System.err.println("Error unloading model during memory pressure: ${e.message}")
            }
        }
    }
    
    /**
     * Handle app going to background.
     */
    private suspend fun handleAppBackground() {
        // Optional: Consider unloading on background if memory is tight
        // Currently no action, but can be customized
    }
    
    /**
     * Set a custom memory pressure handler.
     * By default, EdgeVeda will unload the model when critical memory pressure occurs.
     * Use this to customize the behavior (e.g., reduce cache size, free other resources).
     *
     * @param handler Custom handler to call on memory pressure, receives trim level
     *
     * Example:
     * ```
     * edgeVeda.setMemoryPressureHandler { level ->
     *     when (level) {
     *         ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
     *             // Custom cleanup logic
     *             println("Critical memory pressure, performing custom cleanup")
     *         }
     *     }
     * }
     * ```
     */
    fun setMemoryPressureHandler(handler: MemoryPressureHandler?) {
        customMemoryPressureHandler = handler
    }

    companion object {
        /**
         * Create a new EdgeVeda instance with Android lifecycle integration.
         *
         * @param context Application context for lifecycle management
         * @return A new EdgeVeda instance ready to be initialized
         */
        fun create(context: Context): EdgeVeda {
            val nativeBridge = NativeBridge()
            val appContext = context.applicationContext
            return EdgeVeda(nativeBridge, appContext)
        }
        
        /**
         * Create a new EdgeVeda instance without lifecycle integration.
         * Use this if you want to manage lifecycle manually.
         *
         * @return A new EdgeVeda instance ready to be initialized
         */
        fun createWithoutLifecycle(): EdgeVeda {
            val nativeBridge = NativeBridge()
            return EdgeVeda(nativeBridge, null)
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
