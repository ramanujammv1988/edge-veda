import Foundation
import CEdgeVeda

/// Edge Veda Swift SDK — on-device AI inference for iOS and macOS.
///
/// ```swift
/// let veda = try EdgeVeda(config: Config(modelPath: "model.gguf"))
///
/// // Streaming with AsyncSequence
/// for try await token in veda.generate("What is AI?") {
///     print(token, terminator: "")
/// }
///
/// // Single-shot
/// let response = try await veda.generateComplete("What is AI?")
/// print(response.text)
/// ```
@available(iOS 15.0, macOS 12.0, *)
public final class EdgeVeda: @unchecked Sendable {
    private var context: OpaquePointer?

    /// Initialize Edge Veda with the given configuration.
    public init(config: Config) throws {
        var nativeConfig = ev_config()
        ev_config_default(&nativeConfig)

        nativeConfig.num_threads = Int32(config.numThreads)
        nativeConfig.context_size = Int32(config.contextSize)
        nativeConfig.gpu_layers = Int32(config.gpuLayers)
        nativeConfig.memory_limit_bytes = config.maxMemoryMB * 1024 * 1024
        nativeConfig.flash_attn = Int32(config.flashAttn)
        nativeConfig.kv_cache_type_k = Int32(config.kvCacheTypeK)
        nativeConfig.kv_cache_type_v = Int32(config.kvCacheTypeV)

        var error = EV_SUCCESS
        let ctx = config.modelPath.withCString { pathPtr in
            nativeConfig.model_path = pathPtr
            return ev_init(&nativeConfig, &error)
        }

        guard let ctx = ctx, error == EV_SUCCESS else {
            throw EdgeVedaError.from(code: error)
        }

        self.context = ctx
    }

    deinit {
        if let ctx = context {
            ev_free(ctx)
        }
    }

    private func requireContext() throws -> OpaquePointer {
        guard let ctx = context else {
            throw EdgeVedaError.contextInvalid("Context has been freed")
        }
        return ctx
    }

    // MARK: - Streaming Generation

    /// Generate text with streaming via AsyncSequence.
    public func generate(
        _ prompt: String,
        options: GenerateOptions = .default
    ) throws -> TokenStream {
        let ctx = try requireContext()

        var params = ev_generation_params()
        ev_generation_params_default(&params)
        params.max_tokens = Int32(options.maxTokens)
        params.temperature = options.temperature
        params.top_p = options.topP
        params.top_k = Int32(options.topK)
        params.repeat_penalty = options.repeatPenalty
        params.confidence_threshold = options.confidenceThreshold

        let fullPrompt: String
        if let sys = options.systemPrompt {
            fullPrompt = "\(sys)\n\n\(prompt)"
        } else {
            fullPrompt = prompt
        }

        var error = EV_SUCCESS
        let stream = fullPrompt.withCString { promptPtr in
            ev_generate_stream(ctx, promptPtr, &params, &error)
        }

        guard let stream = stream, error == EV_SUCCESS else {
            throw EdgeVedaError.from(code: error)
        }

        return TokenStream(streamHandle: stream)
    }

    // MARK: - Single-Shot Generation

    /// Generate a complete response.
    public func generateComplete(
        _ prompt: String,
        options: GenerateOptions = .default
    ) async throws -> GenerateResponse {
        let start = DispatchTime.now()
        var text = ""
        var tokenCount = 0

        let stream = try generate(prompt, options: options)
        for try await token in stream {
            text += token
            tokenCount += 1
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let latencyMs = Int(elapsed / 1_000_000)

        return GenerateResponse(
            text: text,
            promptTokens: 0,
            completionTokens: tokenCount,
            latencyMs: latencyMs
        )
    }

    // MARK: - Embeddings

    /// Compute text embeddings.
    public func embed(_ text: String) async throws -> EmbeddingResult {
        let ctx = try requireContext()

        var result = ev_embed_result()
        let error = text.withCString { textPtr in
            ev_embed(ctx, textPtr, &result)
        }

        guard error == EV_SUCCESS else {
            throw EdgeVedaError.from(code: error)
        }

        let count = Int(result.dimensions)
        let embedding = Array(UnsafeBufferPointer(start: result.embeddings, count: count))
        let tokenCount = Int(result.token_count)
        ev_free_embeddings(&result)

        return EmbeddingResult(embedding: embedding, tokenCount: tokenCount)
    }

    // MARK: - Memory

    /// Get current memory usage statistics.
    public var memoryUsage: MemoryStats {
        get throws {
            let ctx = try requireContext()
            var stats = ev_memory_stats()
            let error = ev_get_memory_usage(ctx, &stats)

            guard error == EV_SUCCESS else {
                throw EdgeVedaError.from(code: error)
            }

            return MemoryStats(
                currentBytes: Int(stats.current_bytes),
                peakBytes: Int(stats.peak_bytes),
                limitBytes: Int(stats.limit_bytes),
                modelBytes: Int(stats.model_bytes),
                contextBytes: Int(stats.context_bytes)
            )
        }
    }

    // MARK: - Version

    /// Get the SDK version string.
    public static var version: String {
        String(cString: ev_version())
    }
}
