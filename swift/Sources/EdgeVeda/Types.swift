import Foundation

// MARK: - Errors

/// Errors that can occur during EdgeVeda operations
public enum EdgeVedaError: LocalizedError, Sendable {
    /// Model file not found at specified path
    case modelNotFound(path: String)

    /// Model not loaded (operation requires loaded model)
    case modelNotLoaded

    /// Failed to load model
    case loadFailed(reason: String)

    /// Generation failed
    case generationFailed(reason: String)

    /// Invalid parameter value
    case invalidParameter(name: String, value: String)

    /// Out of memory
    case outOfMemory

    /// Backend not supported on this device
    case unsupportedBackend(Backend)

    /// FFI/C interop error
    case ffiError(message: String)

    /// Unknown error
    case unknown(message: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model file not found at path: \(path)"

        case .modelNotLoaded:
            return "Model is not loaded. Call init(modelPath:config:) first."

        case .loadFailed(let reason):
            return "Failed to load model: \(reason)"

        case .generationFailed(let reason):
            return "Text generation failed: \(reason)"

        case .invalidParameter(let name, let value):
            return "Invalid parameter '\(name)': \(value)"

        case .outOfMemory:
            return "Out of memory. Try using a smaller model or reducing context size."

        case .unsupportedBackend(let backend):
            return "Backend '\(backend.rawValue)' is not supported on this device."

        case .ffiError(let message):
            return "FFI error: \(message)"

        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .modelNotFound:
            return "Verify the model file path is correct and the file exists."

        case .modelNotLoaded:
            return "Initialize EdgeVeda with a valid model path before performing operations."

        case .loadFailed:
            return "Ensure the model file is a valid GGUF format and not corrupted."

        case .outOfMemory:
            return "Try using EdgeVedaConfig.lowMemory or a smaller model."

        case .unsupportedBackend(let backend) where backend == .metal:
            return "Metal is only available on Apple Silicon devices. Use .cpu backend instead."

        default:
            return nil
        }
    }
}

// MARK: - Stream Token

/// Individual token from streaming generation
public struct StreamToken: Sendable {
    /// The token text
    public let text: String

    /// Token position in sequence
    public let position: Int

    /// Token probability (if available)
    public let probability: Float?

    /// Whether this is the final token
    public let isFinal: Bool

    public init(
        text: String,
        position: Int,
        probability: Float? = nil,
        isFinal: Bool = false
    ) {
        self.text = text
        self.position = position
        self.probability = probability
        self.isFinal = isFinal
    }
}

// MARK: - Model Information

/// Information about a loaded model
public struct ModelInfo: Sendable {
    /// Model architecture (e.g., "llama", "mistral")
    public let architecture: String

    /// Number of parameters
    public let parameterCount: UInt64

    /// Context window size
    public let contextSize: Int

    /// Vocabulary size
    public let vocabularySize: Int

    /// Model metadata
    public let metadata: [String: String]

    public init(
        architecture: String,
        parameterCount: UInt64,
        contextSize: Int,
        vocabularySize: Int,
        metadata: [String: String] = [:]
    ) {
        self.architecture = architecture
        self.parameterCount = parameterCount
        self.contextSize = contextSize
        self.vocabularySize = vocabularySize
        self.metadata = metadata
    }
}

// MARK: - Performance Metrics

/// Performance metrics for generation
public struct PerformanceMetrics: Sendable {
    /// Tokens generated per second
    public let tokensPerSecond: Double

    /// Prompt processing time in milliseconds
    public let promptProcessingTime: Double

    /// Generation time in milliseconds
    public let generationTime: Double

    /// Total time in milliseconds
    public let totalTime: Double

    /// Number of tokens generated
    public let tokenCount: Int

    /// Peak memory usage in bytes
    public let peakMemoryUsage: UInt64

    public init(
        tokensPerSecond: Double,
        promptProcessingTime: Double,
        generationTime: Double,
        totalTime: Double,
        tokenCount: Int,
        peakMemoryUsage: UInt64
    ) {
        self.tokensPerSecond = tokensPerSecond
        self.promptProcessingTime = promptProcessingTime
        self.generationTime = generationTime
        self.totalTime = totalTime
        self.tokenCount = tokenCount
        self.peakMemoryUsage = peakMemoryUsage
    }
}

// MARK: - Generation Result

/// Result of a text generation operation
public struct GenerationResult: Sendable {
    /// Generated text
    public let text: String

    /// Performance metrics
    public let metrics: PerformanceMetrics

    /// Stop reason
    public let stopReason: StopReason

    public init(
        text: String,
        metrics: PerformanceMetrics,
        stopReason: StopReason = .maxTokens
    ) {
        self.text = text
        self.metrics = metrics
        self.stopReason = stopReason
    }
}

/// Reason why generation stopped
public enum StopReason: String, Sendable {
    /// Reached maximum token limit
    case maxTokens = "max_tokens"

    /// Encountered stop sequence
    case stopSequence = "stop_sequence"

    /// Model generated end-of-text token
    case endOfText = "end_of_text"

    /// User cancelled generation
    case cancelled = "cancelled"

    /// Error occurred
    case error = "error"
}

// MARK: - Device Information

/// Information about the compute device
public struct DeviceInfo: Sendable {
    /// Device name
    public let name: String

    /// Available backends
    public let availableBackends: [Backend]

    /// Total memory in bytes
    public let totalMemory: UInt64

    /// Available memory in bytes
    public let availableMemory: UInt64

    /// Recommended backend
    public let recommendedBackend: Backend

    public init(
        name: String,
        availableBackends: [Backend],
        totalMemory: UInt64,
        availableMemory: UInt64,
        recommendedBackend: Backend
    ) {
        self.name = name
        self.availableBackends = availableBackends
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.recommendedBackend = recommendedBackend
    }

    /// Get current device information
    public static func current() -> DeviceInfo {
        #if os(iOS) || os(macOS)
        let hasMetalSupport = {
            #if targetEnvironment(simulator)
            return false
            #else
            // Check for Apple Silicon
            var size = 0
            sysctlbyname("hw.optional.arm64", nil, &size, nil, 0)
            return size > 0
            #endif
        }()

        let availableBackends: [Backend] = hasMetalSupport ? [.cpu, .metal, .auto] : [.cpu, .auto]
        let recommendedBackend: Backend = hasMetalSupport ? .metal : .cpu

        return DeviceInfo(
            name: "Apple Device",
            availableBackends: availableBackends,
            totalMemory: ProcessInfo.processInfo.physicalMemory,
            availableMemory: ProcessInfo.processInfo.physicalMemory,
            recommendedBackend: recommendedBackend
        )
        #else
        return DeviceInfo(
            name: "Unknown Device",
            availableBackends: [.cpu, .auto],
            totalMemory: 0,
            availableMemory: 0,
            recommendedBackend: .cpu
        )
        #endif
    }
}
