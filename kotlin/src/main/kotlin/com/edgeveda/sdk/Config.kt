package com.edgeveda.sdk

/**
 * Backend acceleration options for EdgeVeda inference.
 */
enum class Backend {
    /**
     * CPU-only inference. Works on all devices but may be slower.
     */
    CPU,

    /**
     * Vulkan GPU acceleration. Requires Vulkan support.
     */
    VULKAN,

    /**
     * Android NNAPI hardware acceleration.
     * Uses device-specific neural network accelerators.
     */
    NNAPI,

    /**
     * Automatically select the best available backend.
     * Tries NNAPI -> Vulkan -> CPU in that order.
     */
    AUTO;

    internal fun toNativeValue(): Int = when (this) {
        AUTO -> 0    // EV_BACKEND_AUTO = 0
        VULKAN -> 2  // EV_BACKEND_VULKAN = 2
        CPU -> 3     // EV_BACKEND_CPU = 3
        NNAPI -> 3   // No C equivalent, fallback to CPU
    }

    companion object {
        internal fun fromNativeValue(value: Int): Backend = when (value) {
            0 -> AUTO
            2 -> VULKAN
            3 -> CPU
            else -> AUTO
        }
    }
}

/**
 * Result from a benchmark run.
 *
 * @property tokensPerSecond Average tokens processed per second
 * @property timeMs Total time taken in milliseconds
 * @property tokensProcessed Total number of tokens processed
 */
data class BenchmarkResult(
    val tokensPerSecond: Double,
    val timeMs: Double,
    val tokensProcessed: Int
) {
    override fun toString(): String {
        return "BenchmarkResult(tokensPerSec=%.2f, timeMs=%.2f, tokens=%d)".format(
            tokensPerSecond,
            timeMs,
            tokensProcessed
        )
    }
}
/**
 * Configuration options for EdgeVeda model initialization.
 *
 * @property backend Hardware acceleration backend to use
 * @property numThreads Number of CPU threads (0 = auto-detect, default: 0)
 * @property maxTokens Maximum number of tokens to generate (default: 512)
 * @property contextSize Context window size in tokens (default: 2048)
 * @property batchSize Batch size for prompt processing (default: 512)
 * @property useGpu Enable GPU acceleration if available (default: true)
 * @property useMmap Use memory mapping for model loading (default: true)
 * @property useMlock Lock model in RAM to prevent swapping (default: false)
 * @property temperature Sampling temperature for generation (default: 0.7; 0.0 = greedy/deterministic)
 * @property topP Top-p (nucleus) sampling parameter (default: 0.9)
 * @property topK Top-k sampling parameter (default: 40)
 * @property repeatPenalty Penalty for repeating tokens (default: 1.1)
 * @property seed Random seed for reproducibility (-1 = random, default: -1)
 */
data class EdgeVedaConfig(
    val backend: Backend = Backend.AUTO,
    val numThreads: Int = 0,
    val maxTokens: Int = 512,
    val contextSize: Int = 2048,
    val batchSize: Int = 512,
    val useGpu: Boolean = true,
    val useMmap: Boolean = true,
    val useMlock: Boolean = false,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,
    val seed: Long = -1L
) {
    init {
        require(numThreads >= 0) { "numThreads must be >= 0" }
        require(maxTokens > 0) { "maxTokens must be > 0" }
        require(contextSize > 0) { "contextSize must be > 0" }
        require(batchSize > 0) { "batchSize must be > 0" }
        require(temperature >= 0) { "temperature must be >= 0 (0.0 = deterministic/greedy)" }
        require(topP in 0.0f..1.0f) { "topP must be between 0 and 1" }
        require(topK > 0) { "topK must be > 0" }
        require(repeatPenalty >= 0) { "repeatPenalty must be >= 0" }
    }

    /**
     * Create a copy with modified parameters.
     */
    fun withBackend(backend: Backend): EdgeVedaConfig = copy(backend = backend)
    fun withNumThreads(numThreads: Int): EdgeVedaConfig = copy(numThreads = numThreads)
    fun withMaxTokens(maxTokens: Int): EdgeVedaConfig = copy(maxTokens = maxTokens)
    fun withContextSize(contextSize: Int): EdgeVedaConfig = copy(contextSize = contextSize)
    fun withTemperature(temperature: Float): EdgeVedaConfig = copy(temperature = temperature)
    fun withTopP(topP: Float): EdgeVedaConfig = copy(topP = topP)
    fun withTopK(topK: Int): EdgeVedaConfig = copy(topK = topK)

    companion object {
        /**
         * Default configuration optimized for mobile devices.
         */
        fun mobile(): EdgeVedaConfig = EdgeVedaConfig(
            backend = Backend.AUTO,
            numThreads = 4,
            maxTokens = 256,
            contextSize = 1024,
            batchSize = 256,
            useGpu = true,
            useMmap = true,
            useMlock = false
        )

        /**
         * Configuration for maximum quality (slower, more memory).
         */
        fun highQuality(): EdgeVedaConfig = EdgeVedaConfig(
            backend = Backend.AUTO,
            numThreads = 0,
            maxTokens = 1024,
            contextSize = 4096,
            batchSize = 512,
            useGpu = true,
            useMmap = true,
            useMlock = true,
            temperature = 0.8f,
            topP = 0.95f,
            topK = 50
        )

        /**
         * Configuration for maximum speed (lower quality).
         */
        fun fast(): EdgeVedaConfig = EdgeVedaConfig(
            backend = Backend.AUTO,
            numThreads = 2,
            maxTokens = 128,
            contextSize = 512,
            batchSize = 128,
            useGpu = true,
            useMmap = true,
            useMlock = false,
            temperature = 0.5f,
            topP = 0.85f,
            topK = 30
        )
    }
}
