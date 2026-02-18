import Foundation

// MARK: - ModelRegistry

/// Pre-configured model registry with popular models for on-device inference.
///
/// Provides static `DownloadableModelInfo` instances for commonly used models, matching
/// the Flutter SDK's `ModelRegistry` for cross-platform consistency.
///
/// Example:
/// ```swift
/// let manager = ModelManager()
/// let path = try await manager.downloadModel(ModelRegistry.llama32_1b) { progress in
///     print("Download: \(progress.progressPercent)%")
/// }
/// ```
@available(iOS 15.0, macOS 12.0, *)
public enum ModelRegistry {

    // MARK: - Text Models

    /// Llama 3.2 1B Instruct (Q4_K_M quantization) — Primary model
    public static let llama32_1b = DownloadableModelInfo(
        id: "llama-3.2-1b-instruct-q4",
        name: "Llama 3.2 1B Instruct",
        sizeBytes: 668 * 1024 * 1024, // ~668 MB
        description: "Fast and efficient instruction-tuned model",
        downloadUrl: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        checksum: nil,
        format: "GGUF",
        quantization: "Q4_K_M"
    )

    /// Phi-3.5 Mini Instruct (Q4_K_M quantization) — Reasoning model
    public static let phi35_mini = DownloadableModelInfo(
        id: "phi-3.5-mini-instruct-q4",
        name: "Phi 3.5 Mini Instruct",
        sizeBytes: 2300 * 1024 * 1024, // ~2.3 GB
        description: "High-quality reasoning model from Microsoft",
        downloadUrl: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf",
        checksum: nil,
        format: "GGUF",
        quantization: "Q4_K_M"
    )

    /// Gemma 2 2B Instruct (Q4_K_M quantization)
    public static let gemma2_2b = DownloadableModelInfo(
        id: "gemma-2-2b-instruct-q4",
        name: "Gemma 2 2B Instruct",
        sizeBytes: 1600 * 1024 * 1024, // ~1.6 GB
        description: "Google's efficient instruction model",
        downloadUrl: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf",
        checksum: nil,
        format: "GGUF",
        quantization: "Q4_K_M"
    )

    /// TinyLlama 1.1B Chat (Q4_K_M quantization) — Smallest option
    public static let tinyLlama = DownloadableModelInfo(
        id: "tinyllama-1.1b-chat-q4",
        name: "TinyLlama 1.1B Chat",
        sizeBytes: 669 * 1024 * 1024, // ~669 MB
        description: "Ultra-fast lightweight chat model",
        downloadUrl: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        checksum: nil,
        format: "GGUF",
        quantization: "Q4_K_M"
    )

    // MARK: - Vision Language Models

    /// SmolVLM2-500M-Video-Instruct (Q8_0) — Vision Language Model
    public static let smolvlm2_500m = DownloadableModelInfo(
        id: "smolvlm2-500m-video-instruct-q8",
        name: "SmolVLM2 500M Video Instruct",
        sizeBytes: 436_808_704, // ~417 MB
        description: "Vision + video understanding model for image description",
        downloadUrl: "https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf",
        checksum: nil,
        format: "GGUF",
        quantization: "Q8_0"
    )

    /// SmolVLM2-500M mmproj (F16) — Multimodal projector for SmolVLM2
    public static let smolvlm2_500m_mmproj = DownloadableModelInfo(
        id: "smolvlm2-500m-mmproj-f16",
        name: "SmolVLM2 500M Multimodal Projector",
        sizeBytes: 199_470_624, // ~190 MB
        description: "Multimodal projector for SmolVLM2 vision model",
        downloadUrl: "https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-f16.gguf",
        checksum: nil,
        format: "GGUF",
        quantization: "F16"
    )

    // MARK: - Query Methods

    /// Get all available text models
    public static func getAllModels() -> [DownloadableModelInfo] {
        return [llama32_1b, phi35_mini, gemma2_2b, tinyLlama]
    }

    /// Get all available vision models (model files only, not mmproj)
    public static func getVisionModels() -> [DownloadableModelInfo] {
        return [smolvlm2_500m]
    }

    /// Get the multimodal projector for a vision model
    ///
    /// Vision models require both the main model file and a separate
    /// mmproj (multimodal projector) file. This method returns the
    /// corresponding mmproj for a given vision model ID.
    ///
    /// - Parameter modelId: The vision model identifier
    /// - Returns: The corresponding mmproj `DownloadableModelInfo`, or nil if not found
    public static func getMmprojForModel(_ modelId: String) -> DownloadableModelInfo? {
        switch modelId {
        case "smolvlm2-500m-video-instruct-q8":
            return smolvlm2_500m_mmproj
        default:
            return nil
        }
    }

    /// Get model by ID (searches both text and vision models)
    ///
    /// - Parameter id: The model identifier to look up
    /// - Returns: The matching `DownloadableModelInfo`, or nil if not found
    public static func getModelById(_ id: String) -> DownloadableModelInfo? {
        let allModels: [DownloadableModelInfo] = getAllModels() + getVisionModels() + [smolvlm2_500m_mmproj]
        return allModels.first { $0.id == id }
    }

    /// Get models that fit within a memory budget (in bytes)
    ///
    /// - Parameter maxBytes: Maximum model size in bytes
    /// - Returns: Array of models that fit within the budget, sorted by size ascending
    public static func getModelsWithinBudget(_ maxBytes: Int64) -> [DownloadableModelInfo] {
        return getAllModels()
            .filter { $0.sizeBytes <= maxBytes }
            .sorted { $0.sizeBytes < $1.sizeBytes }
    }

    /// Get the recommended model for the current device
    ///
    /// Selects based on available memory:
    /// - ≥3GB: phi35_mini (best quality)
    /// - ≥1.5GB: gemma2_2b (good balance)
    /// - <1.5GB: llama32_1b or tinyLlama (lightweight)
    public static func getRecommendedModel() -> DownloadableModelInfo {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let availableForModel = Int64(totalMemory) / 2 // Use at most half of RAM

        if availableForModel >= 3 * 1024 * 1024 * 1024 {
            return phi35_mini
        } else if availableForModel >= 1536 * 1024 * 1024 {
            return gemma2_2b
        } else {
            return llama32_1b
        }
    }
}