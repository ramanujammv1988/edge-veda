package com.edgeveda.sdk

/**
 * Pre-configured model registry with popular models.
 *
 * Provides [DownloadableModelInfo] descriptors for well-known GGUF models
 * that can be passed directly to [ModelManager.downloadModel].
 *
 * Example:
 * ```kotlin
 * val manager = ModelManager(context)
 * val path = manager.downloadModel(ModelRegistry.llama32_1b) { progress ->
 *     println("${progress.progressPercent}%")
 * }
 * ```
 */
object ModelRegistry {

    const val HUGGING_FACE_BASE_URL = "https://huggingface.co"

    // =========================================================================
    // Text Models
    // =========================================================================

    /** Llama 3.2 1B Instruct (Q4_K_M) — Fast and efficient instruction-tuned model */
    val llama32_1b = DownloadableModelInfo(
        id = "llama-3.2-1b-instruct-q4",
        name = "Llama 3.2 1B Instruct",
        sizeBytes = 668L * 1024 * 1024, // ~668 MB
        description = "Fast and efficient instruction-tuned model",
        downloadUrl = "$HUGGING_FACE_BASE_URL/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        format = "GGUF",
        quantization = "Q4_K_M"
    )

    /** Phi-3.5 Mini Instruct (Q4_K_M) — High-quality reasoning model from Microsoft */
    val phi35_mini = DownloadableModelInfo(
        id = "phi-3.5-mini-instruct-q4",
        name = "Phi 3.5 Mini Instruct",
        sizeBytes = 2300L * 1024 * 1024, // ~2.3 GB
        description = "High-quality reasoning model from Microsoft",
        downloadUrl = "$HUGGING_FACE_BASE_URL/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
        format = "GGUF",
        quantization = "Q4_K_M"
    )

    /** Gemma 2 2B Instruct (Q4_K_M) — Google's efficient instruction model */
    val gemma2_2b = DownloadableModelInfo(
        id = "gemma-2-2b-instruct-q4",
        name = "Gemma 2 2B Instruct",
        sizeBytes = 1600L * 1024 * 1024, // ~1.6 GB
        description = "Google's efficient instruction model",
        downloadUrl = "$HUGGING_FACE_BASE_URL/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
        format = "GGUF",
        quantization = "Q4_K_M"
    )

    /** TinyLlama 1.1B Chat (Q4_K_M) — Ultra-fast lightweight chat model */
    val tinyLlama = DownloadableModelInfo(
        id = "tinyllama-1.1b-chat-q4",
        name = "TinyLlama 1.1B Chat",
        sizeBytes = 669L * 1024 * 1024, // ~669 MB
        description = "Ultra-fast lightweight chat model",
        downloadUrl = "$HUGGING_FACE_BASE_URL/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        format = "GGUF",
        quantization = "Q4_K_M"
    )

    // =========================================================================
    // Vision Language Models
    // =========================================================================

    /** SmolVLM2-500M-Video-Instruct (Q8_0) — Vision + video understanding model */
    val smolvlm2_500m = DownloadableModelInfo(
        id = "smolvlm2-500m-video-instruct-q8",
        name = "SmolVLM2 500M Video Instruct",
        sizeBytes = 436808704L, // ~417 MB
        description = "Vision + video understanding model for image description",
        downloadUrl = "$HUGGING_FACE_BASE_URL/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf",
        format = "GGUF",
        quantization = "Q8_0"
    )

    /** SmolVLM2-500M mmproj (F16) — Multimodal projector for SmolVLM2 */
    val smolvlm2_500m_mmproj = DownloadableModelInfo(
        id = "smolvlm2-500m-mmproj-f16",
        name = "SmolVLM2 500M Multimodal Projector",
        sizeBytes = 199470624L, // ~190 MB
        description = "Multimodal projector for SmolVLM2 vision model",
        downloadUrl = "$HUGGING_FACE_BASE_URL/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-f16.gguf",
        format = "GGUF",
        quantization = "F16"
    )

    // =========================================================================
    // Queries
    // =========================================================================

    /** Get all available text models */
    fun getAllTextModels(): List<DownloadableModelInfo> =
        listOf(llama32_1b, phi35_mini, gemma2_2b, tinyLlama)

    /** Get all available vision models (main model only, not mmproj) */
    fun getVisionModels(): List<DownloadableModelInfo> =
        listOf(smolvlm2_500m)

    /**
     * Get the multimodal projector for a vision model.
     *
     * Vision models require both the main model file and a separate
     * mmproj (multimodal projector) file. Returns the corresponding
     * mmproj for the given vision model ID, or null if none exists.
     */
    fun getMmprojForModel(modelId: String): DownloadableModelInfo? =
        when (modelId) {
            "smolvlm2-500m-video-instruct-q8" -> smolvlm2_500m_mmproj
            else -> null
        }

    /** Get a model by its ID (searches both text and vision models) */
    fun getModelById(id: String): DownloadableModelInfo? {
        val all = getAllTextModels() + getVisionModels() + listOf(smolvlm2_500m_mmproj)
        return all.firstOrNull { it.id == id }
    }
}