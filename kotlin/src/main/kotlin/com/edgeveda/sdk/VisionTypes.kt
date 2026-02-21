package com.edgeveda.sdk

/**
 * Configuration for vision inference.
 *
 * @property modelPath Absolute path to the VLM model file (e.g., SmolVLM2 GGUF)
 * @property mmprojPath Absolute path to the mmproj file (multimodal projector)
 * @property numThreads Number of CPU threads to use (default: 4)
 * @property contextSize Context size for the model (default: 2048)
 * @property gpuLayers Number of layers to offload to GPU, -1 for auto (default: -1)
 * @property memoryLimitBytes Memory limit in bytes, 0 for unlimited (default: 0)
 * @property useMmap Use memory mapping for model loading (default: true)
 */
data class VisionConfig(
    val modelPath: String,
    val mmprojPath: String,
    val numThreads: Int = 4,
    val contextSize: Int = 2048,
    val gpuLayers: Int = -1,
    val memoryLimitBytes: Long = 0L,
    val useMmap: Boolean = true
)

/**
 * Result from vision inference.
 *
 * @property description The generated description of the image
 * @property timings Performance timings for the inference
 */
data class VisionResult(
    val description: String,
    val timings: VisionTimings
)

/**
 * Performance timings for vision inference.
 *
 * @property modelLoadMs Time to load model (0 if already loaded)
 * @property imageEncodeMs Time to encode image with mmproj
 * @property promptEvalMs Time to evaluate prompt tokens
 * @property decodeMs Time to generate output tokens
 * @property promptTokens Number of prompt tokens processed
 * @property generatedTokens Number of tokens generated
 * @property totalMs Total inference time
 * @property tokensPerSecond Generation speed in tokens/second
 */
data class VisionTimings(
    val modelLoadMs: Double,
    val imageEncodeMs: Double,
    val promptEvalMs: Double,
    val decodeMs: Double,
    val promptTokens: Int,
    val generatedTokens: Int,
    val totalMs: Double,
    val tokensPerSecond: Double
)

/**
 * Parameters for vision generation.
 *
 * @property maxTokens Maximum tokens to generate (default: 100)
 * @property temperature Sampling temperature 0.0-2.0 (default: 0.3)
 * @property topP Nucleus sampling threshold (default: 0.9)
 * @property topK Top-K sampling threshold (default: 40)
 * @property repeatPenalty Penalty for repeating tokens (default: 1.1)
 */
data class VisionGenerationParams(
    val maxTokens: Int = 100,
    val temperature: Float = 0.3f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f
)

/**
 * Frame data for vision inference.
 *
 * @property rgb RGB888 pixel data (width * height * 3 bytes)
 * @property width Frame width in pixels
 * @property height Frame height in pixels
 */
data class FrameData(
    val rgb: ByteArray,
    val width: Int,
    val height: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as FrameData

        if (!rgb.contentEquals(other.rgb)) return false
        if (width != other.width) return false
        if (height != other.height) return false

        return true
    }

    override fun hashCode(): Int {
        var result = rgb.contentHashCode()
        result = 31 * result + width
        result = 31 * result + height
        return result
    }
}