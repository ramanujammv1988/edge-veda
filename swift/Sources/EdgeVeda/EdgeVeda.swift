import Foundation

/// Main EdgeVeda inference engine with async/await support
@available(iOS 15.0, macOS 12.0, *)
public actor EdgeVeda {
    private var modelHandle: OpaquePointer?
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
            let handle = try FFIBridge.loadModel(
                path: modelPath,
                backend: config.backend,
                threads: config.threads,
                contextSize: config.contextSize
            )
            self.modelHandle = handle
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
        guard let handle = modelHandle else {
            throw EdgeVedaError.modelNotLoaded
        }

        return try await Task {
            try FFIBridge.generate(
                handle: handle,
                prompt: prompt,
                maxTokens: options.maxTokens,
                temperature: options.temperature,
                topP: options.topP,
                topK: options.topK,
                repeatPenalty: options.repeatPenalty,
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
                guard let handle = modelHandle else {
                    continuation.finish(throwing: EdgeVedaError.modelNotLoaded)
                    return
                }

                do {
                    try await FFIBridge.generateStream(
                        handle: handle,
                        prompt: prompt,
                        maxTokens: options.maxTokens,
                        temperature: options.temperature,
                        topP: options.topP,
                        topK: options.topK,
                        repeatPenalty: options.repeatPenalty,
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
            guard let handle = modelHandle else {
                return 0
            }
            return FFIBridge.getMemoryUsage(handle: handle)
        }
    }

    /// Get model metadata information
    /// - Returns: Dictionary of model metadata
    public func getModelInfo() async throws -> [String: String] {
        guard let handle = modelHandle else {
            throw EdgeVedaError.modelNotLoaded
        }
        return FFIBridge.getModelMetadata(handle: handle)
    }

    // MARK: - Model Management

    /// Unload the model and free resources
    public func unloadModel() async {
        guard let handle = modelHandle else {
            return
        }

        await Task {
            FFIBridge.unloadModel(handle: handle)
        }.value

        modelHandle = nil
    }

    /// Reset conversation context
    public func resetContext() async throws {
        guard let handle = modelHandle else {
            throw EdgeVedaError.modelNotLoaded
        }

        await Task {
            FFIBridge.resetContext(handle: handle)
        }.value
    }

    // MARK: - Cleanup

    deinit {
        if let handle = modelHandle {
            FFIBridge.unloadModel(handle: handle)
        }
    }
}
