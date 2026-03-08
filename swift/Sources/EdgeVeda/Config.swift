import Foundation

// MARK: - Backend Configuration

/// Computation backend for inference
public enum Backend: String, Sendable {
    /// CPU-only inference
    case cpu = "CPU"

    /// Metal GPU acceleration (Apple Silicon)
    case metal = "Metal"

    /// Auto-detect best available backend
    case auto = "Auto"
}

// MARK: - EdgeVeda Configuration

/// Configuration options for EdgeVeda initialization
public struct EdgeVedaConfig: Sendable {
    /// Computation backend to use
    public let backend: Backend

    /// Number of threads for CPU inference (0 = auto-detect)
    public let threads: Int

    /// Context window size in tokens
    public let contextSize: Int

    /// Enable GPU offload layers (-1 = all layers, 0 = none)
    public let gpuLayers: Int

    /// Batch size for prompt processing
    public let batchSize: Int

    /// Enable memory mapping for faster model loading
    public let useMemoryMapping: Bool

    /// Enable memory locking to prevent swapping
    public let lockMemory: Bool

    /// Verbose logging
    public let verbose: Bool

    /// Memory limit in bytes (0 = no limit)
    public let memoryLimitBytes: UInt64

    /// Auto-unload model on memory pressure
    public let autoUnloadOnMemoryPressure: Bool

    /// Random seed for sampling (-1 = random)
    public let seed: Int

    /// Flash attention mode (-1 = auto, 0 = disabled, 1 = enabled)
    public let flashAttn: Int

    /// KV cache quantization type for keys (1 = F16, 8 = Q8_0)
    public let kvCacheTypeK: Int

    /// KV cache quantization type for values (1 = F16, 8 = Q8_0)
    public let kvCacheTypeV: Int

    // MARK: - Initialization

    /// Create custom configuration
    /// - Parameters:
    ///   - backend: Computation backend (default: auto)
    ///   - threads: CPU threads (default: 0 for auto)
    ///   - contextSize: Context window size (default: 2048)
    ///   - gpuLayers: GPU offload layers (default: -1 for all)
    ///   - batchSize: Batch size (default: 512)
    ///   - useMemoryMapping: Enable mmap (default: true)
    ///   - lockMemory: Lock memory (default: false)
    ///   - verbose: Verbose logging (default: false)
    ///   - memoryLimitBytes: Memory limit in bytes (default: 0 for no limit)
    ///   - autoUnloadOnMemoryPressure: Auto-unload on memory pressure (default: false)
    ///   - seed: Random seed (default: -1 for random)
    ///   - flashAttn: Flash attention (-1 = auto, 0 = disabled, 1 = enabled, default: -1)
    ///   - kvCacheTypeK: KV cache type for keys (1 = F16, 8 = Q8_0, default: 1)
    ///   - kvCacheTypeV: KV cache type for values (1 = F16, 8 = Q8_0, default: 1)
    public init(
        backend: Backend = .auto,
        threads: Int = 0,
        contextSize: Int = 2048,
        gpuLayers: Int = -1,
        batchSize: Int = 512,
        useMemoryMapping: Bool = true,
        lockMemory: Bool = false,
        verbose: Bool = false,
        memoryLimitBytes: UInt64 = 0,
        autoUnloadOnMemoryPressure: Bool = false,
        seed: Int = -1,
        flashAttn: Int = -1,
        kvCacheTypeK: Int = 1,
        kvCacheTypeV: Int = 1
    ) {
        self.backend = backend
        self.threads = threads
        self.contextSize = contextSize
        self.gpuLayers = gpuLayers
        self.batchSize = batchSize
        self.useMemoryMapping = useMemoryMapping
        self.lockMemory = lockMemory
        self.verbose = verbose
        self.memoryLimitBytes = memoryLimitBytes
        self.autoUnloadOnMemoryPressure = autoUnloadOnMemoryPressure
        self.seed = seed
        self.flashAttn = flashAttn
        self.kvCacheTypeK = kvCacheTypeK
        self.kvCacheTypeV = kvCacheTypeV
    }

    // MARK: - Presets

    /// Default configuration with auto-detection
    public static let `default` = EdgeVedaConfig()

    /// CPU-only configuration
    public static let cpu = EdgeVedaConfig(
        backend: .cpu,
        gpuLayers: 0
    )

    /// Metal GPU configuration (Apple Silicon optimized)
    public static let metal = EdgeVedaConfig(
        backend: .metal,
        gpuLayers: -1
    )

    /// Low-memory configuration (smaller context)
    public static let lowMemory = EdgeVedaConfig(
        contextSize: 1024,
        batchSize: 256,
        useMemoryMapping: true
    )

    /// High-performance configuration (larger context)
    public static let highPerformance = EdgeVedaConfig(
        backend: .metal,
        contextSize: 4096,
        gpuLayers: -1,
        batchSize: 1024,
        lockMemory: true
    )
}

// MARK: - Generation Options

/// Options for text generation
public struct GenerateOptions: Sendable {
    /// Maximum tokens to generate
    public let maxTokens: Int

    /// Sampling temperature (0.0 = deterministic, higher = more random)
    public let temperature: Float

    /// Nucleus sampling probability threshold
    public let topP: Float

    /// Top-K sampling limit
    public let topK: Int

    /// Repeat penalty (1.0 = no penalty, higher = penalize repetition)
    public let repeatPenalty: Float

    /// Stop sequences to end generation
    public let stopSequences: [String]

    /// Frequency penalty (0.0 = no penalty, higher = penalize frequent tokens)
    public let frequencyPenalty: Float

    /// Presence penalty (0.0 = no penalty, higher = penalize tokens that appeared)
    public let presencePenalty: Float

    /// GBNF grammar string for constrained generation
    public let grammarStr: String?

    /// Grammar root rule name
    public let grammarRoot: String?

    /// Confidence threshold for cloud handoff (0.0 = disabled)
    public let confidenceThreshold: Float

    // MARK: - Initialization

    /// Create custom generation options
    /// - Parameters:
    ///   - maxTokens: Maximum tokens (default: 512)
    ///   - temperature: Sampling temperature (default: 0.7)
    ///   - topP: Nucleus sampling threshold (default: 0.9)
    ///   - topK: Top-K limit (default: 40)
    ///   - repeatPenalty: Repeat penalty (default: 1.1)
    ///   - stopSequences: Stop sequences (default: empty)
    ///   - frequencyPenalty: Frequency penalty (default: 0.0)
    ///   - presencePenalty: Presence penalty (default: 0.0)
    ///   - grammarStr: GBNF grammar string (default: nil)
    ///   - grammarRoot: Grammar root rule (default: nil)
    ///   - confidenceThreshold: Confidence threshold for cloud handoff (default: 0.0)
    public init(
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int = 40,
        repeatPenalty: Float = 1.1,
        stopSequences: [String] = [],
        frequencyPenalty: Float = 0.0,
        presencePenalty: Float = 0.0,
        grammarStr: String? = nil,
        grammarRoot: String? = nil,
        confidenceThreshold: Float = 0.0
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.stopSequences = stopSequences
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.grammarStr = grammarStr
        self.grammarRoot = grammarRoot
        self.confidenceThreshold = confidenceThreshold
    }

    // MARK: - Presets

    /// Default generation options
    public static let `default` = GenerateOptions()

    /// Creative writing (higher temperature)
    public static let creative = GenerateOptions(
        temperature: 0.9,
        topP: 0.95,
        repeatPenalty: 1.2
    )

    /// Precise/factual (lower temperature)
    public static let precise = GenerateOptions(
        temperature: 0.3,
        topP: 0.8,
        topK: 20,
        repeatPenalty: 1.05
    )

    /// Greedy decoding (deterministic)
    public static let greedy = GenerateOptions(
        temperature: 0.0,
        topP: 1.0,
        topK: 1,
        repeatPenalty: 1.0
    )
}
