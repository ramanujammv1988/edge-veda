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

    /// Context overflow - prompt exceeds context window
    case contextOverflow

    /// Operation was cancelled
    case cancellation

    /// Vision processing error
    case visionError(reason: String)

    /// Error during model unloading
    case unloadError(reason: String)

    /// Invalid configuration
    case invalidConfig(reason: String)

    /// FFI/C interop error
    case ffiError(message: String)

    /// Initialization failed with a specific reason
    case initializationFailed(reason: String)

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

        case .contextOverflow:
            return "Context overflow: prompt exceeds the model's context window size."

        case .cancellation:
            return "Operation was cancelled."

        case .visionError(let reason):
            return "Vision processing error: \(reason)"

        case .unloadError(let reason):
            return "Failed to unload model: \(reason)"

        case .invalidConfig(let reason):
            return "Invalid configuration: \(reason)"

        case .initializationFailed(let reason):
            return "Initialization failed: \(reason)"

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

        case .contextOverflow:
            return "Reduce the prompt length or increase contextSize in configuration."

        case .cancellation:
            return nil

        case .visionError:
            return "Ensure the image data is valid and the vision model is loaded."

        case .unloadError:
            return "Try calling unloadModel() again or force-terminate the engine."

        case .invalidConfig:
            return "Review the EdgeVedaConfig values and ensure all parameters are within valid ranges."

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

// MARK: - Embeddings

/// Result of a text embedding operation
public struct EmbeddingResult: Sendable {
    /// The embedding vector (normalized float array)
    public let embeddings: [Float]
    
    /// Dimensionality of the embedding vector
    public let dimensions: Int
    
    public init(embeddings: [Float]) {
        self.embeddings = embeddings
        self.dimensions = embeddings.count
    }
}

// MARK: - Stream Token Info

/// Per-token confidence information during streaming generation
public struct StreamTokenInfo: Sendable {
    /// Confidence score for the current token (0.0 - 1.0)
    public let confidence: Float
    
    /// Average confidence across all tokens so far
    public let avgConfidence: Float
    
    /// Whether confidence has dropped below threshold, suggesting cloud handoff
    public let needsCloudHandoff: Bool
    
    /// Position/index of the current token in the sequence
    public let tokenIndex: Int
    
    public init(
        confidence: Float,
        avgConfidence: Float,
        needsCloudHandoff: Bool,
        tokenIndex: Int
    ) {
        self.confidence = confidence
        self.avgConfidence = avgConfidence
        self.needsCloudHandoff = needsCloudHandoff
        self.tokenIndex = tokenIndex
    }
}

// MARK: - Whisper (Speech-to-Text)

/// Configuration for Whisper speech-to-text initialization
public struct WhisperConfig: Sendable {
    /// Path to the Whisper model file (GGUF format)
    public let modelPath: String
    
    /// Number of threads to use for processing
    public let threads: Int
    
    /// Maximum context size
    public let contextSize: Int
    
    /// GPU layers to offload (0 = CPU only)
    public let gpuLayers: Int
    
    /// Whether to use memory mapping
    public let useMemoryMapping: Bool
    
    public init(
        modelPath: String,
        threads: Int = 4,
        contextSize: Int = 448,
        gpuLayers: Int = 0,
        useMemoryMapping: Bool = true
    ) {
        self.modelPath = modelPath
        self.threads = threads
        self.contextSize = contextSize
        self.gpuLayers = gpuLayers
        self.useMemoryMapping = useMemoryMapping
    }
}

/// Parameters for Whisper transcription
public struct WhisperParams: Sendable {
    /// Language code (e.g., "en", "es", "fr") or nil for auto-detect
    public let language: String?
    
    /// Whether to translate to English
    public let translate: Bool
    
    /// Number of threads to use for transcription
    public let threads: Int
    
    /// Maximum segment length in milliseconds
    public let maxSegmentLength: Int
    
    /// Whether to split on word boundaries
    public let splitOnWord: Bool
    
    /// Maximum tokens per segment
    public let maxTokens: Int
    
    /// Temperature for sampling
    public let temperature: Float
    
    public init(
        language: String? = nil,
        translate: Bool = false,
        threads: Int = 4,
        maxSegmentLength: Int = 0,
        splitOnWord: Bool = false,
        maxTokens: Int = 0,
        temperature: Float = 0.0
    ) {
        self.language = language
        self.translate = translate
        self.threads = threads
        self.maxSegmentLength = maxSegmentLength
        self.splitOnWord = splitOnWord
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
    
    /// Default parameters for general transcription
    public static let `default` = WhisperParams()
}

/// Individual segment from Whisper transcription with timing
public struct WhisperSegment: Sendable {
    /// Transcribed text for this segment
    public let text: String
    
    /// Start time in milliseconds
    public let startTime: Int64
    
    /// End time in milliseconds
    public let endTime: Int64
    
    public init(text: String, startTime: Int64, endTime: Int64) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Result of a Whisper transcription operation
public struct WhisperResult: Sendable {
    /// Full transcribed text
    public let text: String
    
    /// Individual segments with timing information
    public let segments: [WhisperSegment]
    
    /// Detected language code (if auto-detected)
    public let detectedLanguage: String?
    
    /// Processing time in milliseconds
    public let processingTime: Double
    
    public init(
        text: String,
        segments: [WhisperSegment],
        detectedLanguage: String? = nil,
        processingTime: Double
    ) {
        self.text = text
        self.segments = segments
        self.detectedLanguage = detectedLanguage
        self.processingTime = processingTime
    }
}

// MARK: - Memory Statistics

/// Memory usage statistics from the inference engine.
/// Field names map to C `ev_memory_stats` struct fields (camelCase).
public struct MemoryStats: Sendable {
    /// Bytes currently in use by model weights + KV cache
    public let currentBytes: UInt64
    /// Peak bytes observed since context creation
    public let peakBytes: UInt64
    /// Configured memory ceiling in bytes; 0 = no limit
    public let limitBytes: UInt64
    /// Bytes consumed by model weights
    public let modelBytes: UInt64
    /// Bytes consumed by the KV context cache
    public let contextBytes: UInt64

    /// Fraction of limit currently used (0.0–1.0+). Returns 0 if no limit set.
    public var usagePercent: Double {
        limitBytes > 0 ? Double(currentBytes) / Double(limitBytes) : 0.0
    }

    /// True when memory usage exceeds 80% of the configured limit.
    public var isHighPressure: Bool { usagePercent > 0.8 }

    /// True when memory usage exceeds 90% of the configured limit.
    public var isCritical: Bool { usagePercent > 0.9 }

    public init(
        currentBytes: UInt64,
        peakBytes: UInt64,
        limitBytes: UInt64,
        modelBytes: UInt64,
        contextBytes: UInt64
    ) {
        self.currentBytes = currentBytes
        self.peakBytes = peakBytes
        self.limitBytes = limitBytes
        self.modelBytes = modelBytes
        self.contextBytes = contextBytes
    }
}

/// Event emitted to callbacks registered via `setMemoryPressureCallback(_:)`.
public struct MemoryPressureEvent: Sendable {
    /// Current memory usage in bytes
    public let currentBytes: UInt64
    /// Configured memory limit in bytes
    public let limitBytes: UInt64
    /// Ratio of currentBytes to limitBytes (0.0–1.0+)
    public let pressureRatio: Double
    /// When the event was generated
    public let timestamp: Date

    public init(
        currentBytes: UInt64,
        limitBytes: UInt64,
        pressureRatio: Double,
        timestamp: Date
    ) {
        self.currentBytes = currentBytes
        self.limitBytes = limitBytes
        self.pressureRatio = pressureRatio
        self.timestamp = timestamp
    }
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
