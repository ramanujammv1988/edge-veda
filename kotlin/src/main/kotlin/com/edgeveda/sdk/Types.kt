package com.edgeveda.sdk

/**
 * Options for text generation.
 *
 * @property maxTokens Maximum number of tokens to generate (null = use config default)
 * @property temperature Sampling temperature (null = use config default)
 * @property topP Top-p sampling parameter (null = use config default)
 * @property topK Top-k sampling parameter (null = use config default)
 * @property repeatPenalty Penalty for repeating tokens (null = use config default)
 * @property stopSequences List of sequences that stop generation when encountered
 * @property seed Random seed for this generation (null = use config default)
 */
data class GenerateOptions(
    val maxTokens: Int? = null,
    val temperature: Float? = null,
    val topP: Float? = null,
    val topK: Int? = null,
    val repeatPenalty: Float? = null,
    val stopSequences: List<String> = emptyList(),
    val seed: Long? = null
) {
    init {
        maxTokens?.let { require(it > 0) { "maxTokens must be > 0" } }
        temperature?.let { require(it > 0) { "temperature must be > 0" } }
        topP?.let { require(it in 0.0f..1.0f) { "topP must be between 0 and 1" } }
        topK?.let { require(it > 0) { "topK must be > 0" } }
        repeatPenalty?.let { require(it >= 0) { "repeatPenalty must be >= 0" } }
    }

    companion object {
        /**
         * Default generation options (uses all config defaults).
         */
        val DEFAULT = GenerateOptions()

        /**
         * Options for creative/diverse text generation.
         */
        fun creative() = GenerateOptions(
            temperature = 1.0f,
            topP = 0.95f,
            topK = 50,
            repeatPenalty = 1.05f
        )

        /**
         * Options for deterministic/factual text generation.
         */
        fun deterministic() = GenerateOptions(
            temperature = 0.3f,
            topP = 0.85f,
            topK = 20,
            repeatPenalty = 1.2f
        )

        /**
         * Options for balanced text generation.
         */
        fun balanced() = GenerateOptions(
            temperature = 0.7f,
            topP = 0.9f,
            topK = 40,
            repeatPenalty = 1.1f
        )
    }
}

/**
 * Statistics about a generation operation.
 *
 * @property tokensGenerated Number of tokens generated
 * @property timeMs Total time taken in milliseconds
 * @property tokensPerSecond Generation speed
 * @property promptTokens Number of tokens in the prompt
 * @property finishReason Why generation stopped
 */
data class GenerationStats(
    val tokensGenerated: Int,
    val timeMs: Long,
    val tokensPerSecond: Double,
    val promptTokens: Int,
    val finishReason: FinishReason
)

/**
 * Reason why text generation stopped.
 */
enum class FinishReason {
    /**
     * Reached maximum token limit.
     */
    MAX_TOKENS,

    /**
     * Model generated an end-of-sequence token.
     */
    EOS_TOKEN,

    /**
     * Encountered a stop sequence.
     */
    STOP_SEQUENCE,

    /**
     * Generation was cancelled/interrupted.
     */
    CANCELLED,

    /**
     * An error occurred during generation.
     */
    ERROR
}

/**
 * Model information.
 *
 * @property name Model name/identifier
 * @property architecture Model architecture (e.g., "llama", "gpt2")
 * @property parameterCount Number of parameters in the model
 * @property contextLength Maximum context length in tokens
 * @property quantization Quantization method (e.g., "q4_0", "q8_0")
 * @property vocabSize Size of the vocabulary
 */
data class ModelInfo(
    val name: String,
    val architecture: String,
    val parameterCount: Long,
    val contextLength: Int,
    val quantization: String,
    val vocabSize: Int
)

/**
 * Base class for all EdgeVeda exceptions.
 */
sealed class EdgeVedaException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause) {

    /**
     * Error during model loading.
     */
    class ModelLoadError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Invalid configuration provided.
     */
    class InvalidConfiguration(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Error during text generation.
     */
    class GenerationError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Error during model unloading.
     */
    class UnloadError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Native library not found or failed to load.
     */
    class NativeLibraryError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Operation cancelled by user.
     */
    class CancelledException(message: String = "Operation was cancelled") :
        EdgeVedaException(message)

    /**
     * Out of memory error.
     */
    class OutOfMemoryError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Unsupported operation or feature.
     */
    class UnsupportedOperationError(message: String) :
        EdgeVedaException(message)

    /**
     * Model file not found at specified path.
     */
    class ModelNotFoundError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Context overflow - prompt exceeds context window.
     */
    class ContextOverflowError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Vision processing error.
     */
    class VisionError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Generic native error from JNI layer.
     */
    class NativeError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Error during model download.
     */
    class DownloadError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)

    /**
     * Checksum verification mismatch.
     */
    class ChecksumError(message: String, cause: Throwable? = null) :
        EdgeVedaException(message, cause)
}

/**
 * Callback interface for streaming generation progress.
 */
fun interface StreamCallback {
    /**
     * Called when a new token/text chunk is generated.
     *
     * @param token The generated token or text chunk
     */
    suspend fun onToken(token: String)
}

/**
 * Device capabilities and information.
 *
 * @property hasVulkanSupport Whether device supports Vulkan
 * @property hasNnapiSupport Whether device supports NNAPI
 * @property totalMemoryMb Total device RAM in MB
 * @property availableMemoryMb Available device RAM in MB
 * @property cpuCores Number of CPU cores
 * @property cpuArchitecture CPU architecture (e.g., "arm64-v8a")
 * @property androidVersion Android OS version
 * @property gpuVendor GPU vendor if available
 * @property gpuModel GPU model if available
 */
data class DeviceInfo(
    val hasVulkanSupport: Boolean,
    val hasNnapiSupport: Boolean,
    val totalMemoryMb: Long,
    val availableMemoryMb: Long,
    val cpuCores: Int,
    val cpuArchitecture: String,
    val androidVersion: Int,
    val gpuVendor: String?,
    val gpuModel: String?
)
