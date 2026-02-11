import Foundation
import CEdgeVeda

/// Main EdgeVeda inference engine with async/await support
@available(iOS 15.0, macOS 12.0, *)
public actor EdgeVeda {
    private var context: ev_context?
    private let config: EdgeVedaConfig
    private let modelPath: String

    // MARK: - Initialization

    /// Initialize EdgeVeda with a model file and configuration
    /// - Parameters:
    ///   - modelPath: Path to the GGUF model file
    ///   - config: Configuration options (defaults to auto-detected settings)
    /// - Throws: EdgeVedaError if initialization fails
    public init(modelPath: String, config: EdgeVedaConfig = .default) async throws {
        self.modelPath = modelPath
        self.config = config

        // Verify model file exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw EdgeVedaError.modelNotFound(path: modelPath)
        }

        // Load model via FFI
        try await loadModel()
    }

    private func loadModel() async throws {
        try await Task {
            let ctx = try FFIBridge.initContext(
                modelPath: modelPath,
                backend: config.backend,
                threads: config.threads,
                contextSize: config.contextSize,
                gpuLayers: config.gpuLayers,
                batchSize: config.batchSize,
                useMmap: true,
                useMlock: false,
                seed: -1
            )
            self.context = ctx
        }.value
    }

    // MARK: - Text Generation

    /// Generate text completion synchronously
    /// - Parameter prompt: Input prompt text
    /// - Returns: Generated text completion
    /// - Throws: EdgeVedaError if generation fails
    public func generate(_ prompt: String) async throws -> String {
        return try await generate(prompt, options: .default)
    }

    /// Generate text completion with custom options
    /// - Parameters:
    ///   - prompt: Input prompt text
    ///   - options: Generation parameters
    /// - Returns: Generated text completion
    /// - Throws: EdgeVedaError if generation fails
    public func generate(_ prompt: String, options: GenerateOptions) async throws -> String {
        guard let ctx = context else {
            throw EdgeVedaError.modelNotLoaded
        }

        return try await Task {
            try FFIBridge.generate(
                ctx: ctx,
                prompt: prompt,
                maxTokens: options.maxTokens,
                temperature: options.temperature,
                topP: options.topP,
                topK: options.topK,
                repeatPenalty: options.repeatPenalty,
                frequencyPenalty: 0.0,
                presencePenalty: 0.0,
                stopSequences: options.stopSequences
            )
        }.value
    }

    /// Generate text with streaming token-by-token output
    /// - Parameter prompt: Input prompt text
    /// - Returns: AsyncThrowingStream yielding tokens as they're generated
    public func generateStream(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        return generateStream(prompt, options: .default)
    }

    /// Generate text with streaming and custom options
    /// - Parameters:
    ///   - prompt: Input prompt text
    ///   - options: Generation parameters
    /// - Returns: AsyncThrowingStream yielding tokens as they're generated
    public func generateStream(_ prompt: String, options: GenerateOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let ctx = context else {
                    continuation.finish(throwing: EdgeVedaError.modelNotLoaded)
                    return
                }

                do {
                    try await FFIBridge.generateStream(
                        ctx: ctx,
                        prompt: prompt,
                        maxTokens: options.maxTokens,
                        temperature: options.temperature,
                        topP: options.topP,
                        topK: options.topK,
                        repeatPenalty: options.repeatPenalty,
                        frequencyPenalty: 0.0,
                        presencePenalty: 0.0,
                        stopSequences: options.stopSequences
                    ) { token in
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Model Information

    /// Current memory usage in bytes
    public var memoryUsage: UInt64 {
        get async {
            guard let ctx = context else {
                return 0
            }
            do {
                let stats = try FFIBridge.getMemoryUsage(ctx: ctx)
                return stats.current
            } catch {
                return 0
            }
        }
    }

    /// Get model metadata information
    /// - Returns: Dictionary of model metadata
    public func getModelInfo() async throws -> [String: String] {
        guard let ctx = context else {
            throw EdgeVedaError.modelNotLoaded
        }
        return try FFIBridge.getModelInfo(ctx: ctx)
    }

    // MARK: - Model Management

    /// Unload the model and free resources
    public func unloadModel() async {
        guard let ctx = context else {
            return
        }

        await Task {
            FFIBridge.freeContext(ctx)
        }.value

        context = nil
    }

    /// Reset conversation context
    public func resetContext() async throws {
        guard let ctx = context else {
            throw EdgeVedaError.modelNotLoaded
        }

        try await Task {
            try FFIBridge.resetContext(ctx: ctx)
        }.value
    }

    // MARK: - Cleanup

    deinit {
        if let ctx = context {
            FFIBridge.freeContext(ctx)
        }
    }
}
