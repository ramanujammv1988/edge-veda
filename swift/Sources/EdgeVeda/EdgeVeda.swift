import Foundation
import CEdgeVeda

/// Main EdgeVeda inference engine with async/await support
@available(iOS 15.0, macOS 12.0, *)
public actor EdgeVeda {
    /// The C context pointer. Marked nonisolated(unsafe) because:
    /// - It's an opaque C pointer managed by the underlying C library
    /// - The C library handles thread safety internally
    /// - We need to access it from nonisolated deinit for cleanup
    private nonisolated(unsafe) var context: ev_context?
    private let config: EdgeVedaConfig
    private let modelPath: String
    
    /// Track the current generation task for cancellation support
    private var currentGenerationTask: Task<String, Error>?
    private var currentStreamTask: Task<Void, Never>?

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

        let task = Task {
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
        }
        
        currentGenerationTask = task
        defer { currentGenerationTask = nil }
        
        return try await task.value
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
            let task = Task {
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
                    ) { @Sendable token in
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            // Store task reference for cancellation (must be done in actor context)
            Task { [weak self] in
                await self?.storeStreamTask(task)
            }
            
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { [weak self] in
                    await self?.clearStreamTask()
                }
            }
        }
    }
    
    /// Helper to store stream task from non-isolated context
    private func storeStreamTask(_ task: Task<Void, Never>) {
        currentStreamTask = task
    }
    
    /// Helper to clear stream task from non-isolated context
    private func clearStreamTask() {
        currentStreamTask = nil
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

    /// Check if a model is currently loaded and ready for inference
    /// - Returns: true if model is loaded, false otherwise
    public func isModelLoaded() -> Bool {
        return context != nil
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

    /// Cancel an ongoing generation
    /// Cancels the current generation task at the Swift concurrency level
    public func cancelGeneration() async throws {
        guard context != nil else {
            throw EdgeVedaError.modelNotLoaded
        }
        
        // Cancel any active Swift tasks
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        
        currentStreamTask?.cancel()
        currentStreamTask = nil
    }

    // MARK: - Vision Inference

    /// Create and initialize a vision worker for image description
    /// - Parameter config: Vision configuration including model and mmproj paths
    /// - Returns: Initialized VisionWorker ready for frame processing
    /// - Throws: EdgeVedaError if initialization fails
    public static func createVisionWorker(config: VisionConfig) async throws -> VisionWorker {
        let worker = VisionWorker()
        try await worker.initialize(config: config)
        return worker
    }

    /// One-shot vision inference - describe a single image
    /// Creates a temporary worker, performs inference, and cleans up automatically
    /// For repeated inferences, use createVisionWorker() to reuse the worker
    ///
    /// - Parameters:
    ///   - config: Vision configuration including model and mmproj paths
    ///   - rgb: RGB888 image data (width * height * 3 bytes)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - prompt: The prompt for describing the image (default: "Describe what you see.")
    ///   - params: Generation parameters (default: VisionGenerationParams with sensible defaults)
    /// - Returns: VisionResult with description and timing information
    /// - Throws: EdgeVedaError if inference fails
    public static func describeImage(
        config: VisionConfig,
        rgb: Data,
        width: Int,
        height: Int,
        prompt: String = "Describe what you see.",
        params: VisionGenerationParams = VisionGenerationParams()
    ) async throws -> VisionResult {
        let worker = VisionWorker()
        try await worker.initialize(config: config)
        defer {
            Task {
                await worker.cleanup()
            }
        }
        
        return try await worker.describeFrame(
            rgb: rgb,
            width: width,
            height: height,
            prompt: prompt,
            params: params
        )
    }

    // MARK: - Static Methods

    /// Get SDK version
    /// - Returns: Version string
    /// - Example:
    /// ```swift
    /// let version = EdgeVeda.getVersion()
    /// print("EdgeVeda SDK version: \(version)") // "1.0.0"
    /// ```
    public static func getVersion() -> String {
        return EdgeVedaVersion.version
    }

    // MARK: - Cleanup

    nonisolated deinit {
        // Capture context locally to avoid actor isolation issues
        let ctx = context
        if let ctx = ctx {
            FFIBridge.freeContext(ctx)
        }
    }
}
