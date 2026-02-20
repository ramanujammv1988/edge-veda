//
//  VisionTypes.swift
//  EdgeVeda
//
//  Vision inference types and configuration for Vision Language Models (VLMs).
//  Defines Swift types that map to the C vision API (ev_vision_*).
//
//  Created: 2026-11-02
//

import Foundation

// MARK: - Vision Configuration

/// Configuration for initializing a vision inference context.
///
/// Maps to `ev_vision_config` from the C API. Vision contexts are separate
/// from text contexts and require both a VLM model file and an mmproj
/// (multimodal projector) file.
///
/// Example:
/// ```swift
/// let config = VisionConfig(
///     modelPath: "/path/to/model.gguf",
///     mmprojPath: "/path/to/mmproj.gguf",
///     numThreads: 4,
///     useGpu: true
/// )
/// ```
public struct VisionConfig: Sendable {
    /// Path to VLM GGUF model file (e.g., SmolVLM2)
    public let modelPath: String
    
    /// Path to mmproj (multimodal projector) GGUF file
    public let mmprojPath: String
    
    /// Number of CPU threads for inference (0 = auto-detect)
    public let numThreads: Int
    
    /// Token context window size (0 = auto, based on model)
    public let contextSize: Int
    
    /// Batch size for processing (0 = default 512)
    public let batchSize: Int
    
    /// Memory limit in bytes (0 = no limit)
    public let memoryLimitBytes: Int
    
    /// GPU layers to offload (-1 = all, 0 = CPU only, >0 = specific count)
    public let gpuLayers: Int
    
    /// Use memory mapping for model file (recommended: true)
    public let useMmap: Bool
    
    /// Initialize vision configuration
    ///
    /// - Parameters:
    ///   - modelPath: Path to VLM GGUF model file
    ///   - mmprojPath: Path to mmproj GGUF file
    ///   - numThreads: CPU threads (0 = auto)
    ///   - contextSize: Token context size (0 = auto)
    ///   - batchSize: Batch size (0 = default 512)
    ///   - memoryLimitBytes: Memory limit (0 = no limit)
    ///   - useGpu: Enable GPU acceleration (gpuLayers = -1 if true)
    ///   - useMmap: Use memory mapping (recommended: true)
    public init(
        modelPath: String,
        mmprojPath: String,
        numThreads: Int = 0,
        contextSize: Int = 0,
        batchSize: Int = 0,
        memoryLimitBytes: Int = 0,
        useGpu: Bool = true,
        useMmap: Bool = true
    ) {
        self.modelPath = modelPath
        self.mmprojPath = mmprojPath
        self.numThreads = numThreads
        self.contextSize = contextSize
        self.batchSize = batchSize
        self.memoryLimitBytes = memoryLimitBytes
        self.gpuLayers = useGpu ? -1 : 0
        self.useMmap = useMmap
    }
}

// MARK: - Vision Result

/// Result from a vision inference operation.
///
/// Contains the generated text description and detailed timing metrics
/// from the native vision engine.
public struct VisionResult: Sendable {
    /// Generated text description of the image
    public let description: String
    
    /// Detailed timing breakdown from the inference
    public let timings: VisionTimings
    
    /// Initialize vision result
    ///
    /// - Parameters:
    ///   - description: Generated text description
    ///   - timings: Timing metrics from inference
    public init(description: String, timings: VisionTimings) {
        self.description = description
        self.timings = timings
    }
}

// MARK: - Vision Timings

/// Timing data from vision inference.
///
/// Maps to `ev_timings_data` from the C API. Provides detailed breakdown
/// of inference performance, extracted from llama.cpp's perf counters.
///
/// Timing categories:
/// - **Model Load**: Time to load VLM + mmproj (only on first call)
/// - **Image Encode**: Time to encode image through multimodal projector
/// - **Prompt Eval**: Time to process prompt tokens + image tokens
/// - **Decode**: Time to generate output tokens
public struct VisionTimings: Sendable {
    /// Model load time in milliseconds
    ///
    /// Usually 0ms after first inference (model stays loaded).
    /// On first call, includes VLM + mmproj load time.
    public let modelLoadMs: Double
    
    /// Image encoding time in milliseconds
    ///
    /// Time to process image through multimodal projector.
    /// Depends on image resolution and model architecture.
    public let imageEncodeMs: Double
    
    /// Prompt evaluation time in milliseconds
    ///
    /// Time to process prompt tokens + image embedding tokens.
    public let promptEvalMs: Double
    
    /// Token generation time in milliseconds
    ///
    /// Time to decode/generate output tokens.
    public let decodeMs: Double
    
    /// Number of prompt tokens processed
    ///
    /// Includes user prompt + image embedding tokens.
    public let promptTokens: Int
    
    /// Number of tokens generated in response
    public let generatedTokens: Int
    
    /// Total inference time (sum of all stages)
    public var totalMs: Double {
        modelLoadMs + imageEncodeMs + promptEvalMs + decodeMs
    }
    
    /// Tokens per second for generation
    public var tokensPerSecond: Double {
        guard decodeMs > 0, generatedTokens > 0 else { return 0 }
        return Double(generatedTokens) / (decodeMs / 1000.0)
    }
    
    /// Initialize timing data
    ///
    /// - Parameters:
    ///   - modelLoadMs: Model load time in ms
    ///   - imageEncodeMs: Image encoding time in ms
    ///   - promptEvalMs: Prompt evaluation time in ms
    ///   - decodeMs: Token generation time in ms
    ///   - promptTokens: Number of prompt tokens
    ///   - generatedTokens: Number of generated tokens
    public init(
        modelLoadMs: Double,
        imageEncodeMs: Double,
        promptEvalMs: Double,
        decodeMs: Double,
        promptTokens: Int,
        generatedTokens: Int
    ) {
        self.modelLoadMs = modelLoadMs
        self.imageEncodeMs = imageEncodeMs
        self.promptEvalMs = promptEvalMs
        self.decodeMs = decodeMs
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
    }
}

// MARK: - Vision Generation Parameters

/// Parameters for vision text generation.
///
/// Subset of `GenerationParams` relevant for vision inference.
/// Most VLM tasks use shorter responses than text-only LLMs.
public struct VisionGenerationParams: Sendable {
    /// Maximum number of tokens to generate (default: 100)
    public let maxTokens: Int
    
    /// Temperature for sampling (default: 0.3, lower = more deterministic)
    public let temperature: Float
    
    /// Top-p (nucleus) sampling threshold (default: 0.9)
    public let topP: Float
    
    /// Top-k sampling limit (default: 40)
    public let topK: Int
    
    /// Repetition penalty (default: 1.1)
    public let repeatPenalty: Float
    
    /// Default parameters for vision inference
    public static let `default` = VisionGenerationParams(
        maxTokens: 100,
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
        repeatPenalty: 1.1
    )
    
    /// Initialize generation parameters
    ///
    /// - Parameters:
    ///   - maxTokens: Maximum tokens to generate
    ///   - temperature: Sampling temperature (0.0 = deterministic)
    ///   - topP: Nucleus sampling threshold
    ///   - topK: Top-k sampling limit
    ///   - repeatPenalty: Repetition penalty (1.0 = no penalty)
    public init(
        maxTokens: Int = 100,
        temperature: Float = 0.3,
        topP: Float = 0.9,
        topK: Int = 40,
        repeatPenalty: Float = 1.1
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
    }
}

// MARK: - Vision Error

/// Errors specific to vision inference operations.
public enum VisionError: Error, LocalizedError, Sendable {
    /// Vision context not initialized
    case notInitialized
    
    /// Failed to initialize vision context
    case initializationFailed(String)
    
    /// Vision inference failed
    case inferenceFailed(String)
    
    /// Invalid image format or dimensions
    case invalidImage(String)
    
    /// Vision worker not active
    case workerNotActive
    
    /// Vision worker disposed
    case workerDisposed
    
    /// Native error from C API
    case nativeError(Int32, String)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Vision context not initialized. Call initVision() first."
        case .initializationFailed(let message):
            return "Failed to initialize vision context: \(message)"
        case .inferenceFailed(let message):
            return "Vision inference failed: \(message)"
        case .invalidImage(let message):
            return "Invalid image: \(message)"
        case .workerNotActive:
            return "Vision worker not active. Call spawn() first."
        case .workerDisposed:
            return "Vision worker has been disposed."
        case .nativeError(let code, let message):
            return "Native error [\(code)]: \(message)"
        }
    }
}