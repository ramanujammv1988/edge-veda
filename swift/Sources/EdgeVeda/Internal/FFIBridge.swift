import Foundation
import CEdgeVeda

/// Bridge between Swift and C FFI
/// Handles all unsafe pointer operations and C interop
internal enum FFIBridge {

    // MARK: - Memory Pressure Callback Management

    /// Storage for memory pressure callbacks
    /// Note: Marked as nonisolated(unsafe) because we handle synchronization with callbackLock
    private static nonisolated(unsafe) let memoryCallbacks: NSMapTable<NSValue, AnyObject> = NSMapTable.strongToStrongObjects()
    private static let callbackLock = NSLock()

    /// C callback trampoline for memory pressure events
    private static let cMemoryCallback: ev_memory_pressure_callback = { userDataPtr, currentBytes, limitBytes in
        guard let userDataPtr = userDataPtr else { return }
        
        // Scope the lock with a do-block so defer fires before the callback is invoked.
        // This is exception-safe (unlock always runs) and deadlock-safe (callback runs outside lock).
        let callbackObj: ((UInt64, UInt64) -> Void)?
        do {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            let key = NSValue(pointer: userDataPtr)
            callbackObj = memoryCallbacks.object(forKey: key) as? (UInt64, UInt64) -> Void
        }
        callbackObj?(UInt64(currentBytes), UInt64(limitBytes))
    }

    // MARK: - Context Management

    /// Initialize Edge Veda context with configuration
    static func initContext(
        modelPath: String,
        backend: Backend,
        threads: Int,
        contextSize: Int,
        gpuLayers: Int,
        batchSize: Int,
        useMmap: Bool,
        useMlock: Bool,
        seed: Int,
        memoryLimitBytes: UInt64,
        autoUnloadOnMemoryPressure: Bool,
        flashAttn: Int,
        kvCacheTypeK: Int,
        kvCacheTypeV: Int
    ) throws -> ev_context {
        var config = ev_config()

        // Set configuration (model_path is set inside the withCString scope below;
        // do not assign it here where the pointer would immediately become dangling)
        config.backend = backend.cValue
        config.num_threads = Int32(threads)
        config.context_size = Int32(contextSize)
        config.batch_size = Int32(batchSize)
        config.memory_limit_bytes = Int(memoryLimitBytes)
        config.auto_unload_on_memory_pressure = autoUnloadOnMemoryPressure
        config.gpu_layers = Int32(gpuLayers)
        config.use_mmap = useMmap
        config.use_mlock = useMlock
        config.seed = Int32(seed)
        config.flash_attn = Int32(flashAttn)
        config.kv_cache_type_k = Int32(kvCacheTypeK)
        config.kv_cache_type_v = Int32(kvCacheTypeV)
        config.reserved = nil

        var error: ev_error_t = EV_SUCCESS
        
        // Initialize context
        let ctx = modelPath.withCString { pathPtr in
            var mutableConfig = config
            mutableConfig.model_path = pathPtr
            return ev_init(&mutableConfig, &error)
        }
        
        // Check for errors
        if ctx == nil || error != EV_SUCCESS {
            throw mapError(error, ctx: ctx)
        }
        
        return ctx!
    }

    /// Free Edge Veda context
    static func freeContext(_ ctx: ev_context) {
        ev_free(ctx)
    }

    /// Check if context is valid
    static func isValid(_ ctx: ev_context) -> Bool {
        return ev_is_valid(ctx)
    }

    // MARK: - Text Generation

    /// Generate text synchronously
    static func generate(
        ctx: ev_context,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        frequencyPenalty: Float,
        presencePenalty: Float,
        stopSequences: [String],
        grammarStr: String?,
        grammarRoot: String?,
        confidenceThreshold: Float
    ) throws -> String {
        var params = ev_generation_params()
        params.max_tokens = Int32(maxTokens)
        params.temperature = temperature
        params.top_p = topP
        params.top_k = Int32(topK)
        params.repeat_penalty = repeatPenalty
        params.frequency_penalty = frequencyPenalty
        params.presence_penalty = presencePenalty
        params.confidence_threshold = confidenceThreshold
        params.reserved = nil

        // Convert stop sequences to C array
        var cStopSequences: [UnsafePointer<CChar>?] = []
        var managedStrings: [ContiguousArray<CChar>] = []
        
        for seq in stopSequences {
            let cString = seq.utf8CString
            managedStrings.append(ContiguousArray(cString))
            cStopSequences.append(managedStrings.last!.withUnsafeBufferPointer { $0.baseAddress })
        }
        cStopSequences.append(nil) // NULL terminator
        
        params.num_stop_sequences = Int32(stopSequences.count)

        var output: UnsafeMutablePointer<CChar>?
        let error: ev_error_t
        
        // Call C function with grammar support
        if let grammarStr = grammarStr {
            // Nest grammarRoot.withCString inside grammarStr's scope so the pointer
            // remains valid for the entire duration of the ev_generate call.
            error = grammarStr.withCString { grammarPtr in
                let invoke: (UnsafePointer<CChar>?) -> ev_error_t = { grammarRootPtr in
                    prompt.withCString { promptPtr in
                        cStopSequences.withUnsafeBufferPointer { stopPtr in
                            var mutableParams = params
                            mutableParams.stop_sequences = UnsafeMutablePointer(mutating: stopPtr.baseAddress)
                            mutableParams.grammar_str = grammarPtr
                            mutableParams.grammar_root = grammarRootPtr
                            return ev_generate(ctx, promptPtr, &mutableParams, &output)
                        }
                    }
                }
                if let root = grammarRoot { return root.withCString { invoke($0) } }
                else { return invoke(nil) }
            }
        } else {
            error = prompt.withCString { promptPtr in
                cStopSequences.withUnsafeBufferPointer { stopPtr in
                    var mutableParams = params
                    mutableParams.stop_sequences = UnsafeMutablePointer(mutating: stopPtr.baseAddress)
                    mutableParams.grammar_str = nil
                    mutableParams.grammar_root = nil
                    return ev_generate(ctx, promptPtr, &mutableParams, &output)
                }
            }
        }
        
        // Check for errors
        guard error == EV_SUCCESS, let resultPtr = output else {
            throw mapError(error, ctx: ctx)
        }
        
        defer { ev_free_string(resultPtr) }
        return String(cString: resultPtr)
    }

    /// Generate text with streaming
    /// - Parameter onStreamCreated: Called with the ev_stream handle immediately after creation,
    ///   allowing the caller to store it for external cancellation via ev_stream_cancel().
    static func generateStream(
        ctx: ev_context,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        frequencyPenalty: Float,
        presencePenalty: Float,
        stopSequences: [String],
        grammarStr: String?,
        grammarRoot: String?,
        confidenceThreshold: Float,
        onStreamCreated: ((ev_stream) -> Void)? = nil,
        onToken: @escaping (String) -> Void
    ) async throws {
        var params = ev_generation_params()
        params.max_tokens = Int32(maxTokens)
        params.temperature = temperature
        params.top_p = topP
        params.top_k = Int32(topK)
        params.repeat_penalty = repeatPenalty
        params.frequency_penalty = frequencyPenalty
        params.presence_penalty = presencePenalty
        params.confidence_threshold = confidenceThreshold
        params.reserved = nil

        // Convert stop sequences to C array
        var cStopSequences: [UnsafePointer<CChar>?] = []
        var managedStrings: [ContiguousArray<CChar>] = []
        
        for seq in stopSequences {
            let cString = seq.utf8CString
            managedStrings.append(ContiguousArray(cString))
            cStopSequences.append(managedStrings.last!.withUnsafeBufferPointer { $0.baseAddress })
        }
        cStopSequences.append(nil) // NULL terminator
        
        params.num_stop_sequences = Int32(stopSequences.count)

        var error: ev_error_t = EV_SUCCESS
        
        // Start streaming with grammar support
        let stream: ev_stream?
        if let grammarStr = grammarStr {
            // Nest grammarRoot.withCString inside grammarStr's scope so the pointer
            // remains valid for the entire duration of the ev_generate_stream call.
            stream = grammarStr.withCString { grammarPtr in
                let invoke: (UnsafePointer<CChar>?) -> ev_stream? = { grammarRootPtr in
                    prompt.withCString { promptPtr in
                        cStopSequences.withUnsafeBufferPointer { stopPtr in
                            var mutableParams = params
                            mutableParams.stop_sequences = UnsafeMutablePointer(mutating: stopPtr.baseAddress)
                            mutableParams.grammar_str = grammarPtr
                            mutableParams.grammar_root = grammarRootPtr
                            return ev_generate_stream(ctx, promptPtr, &mutableParams, &error)
                        }
                    }
                }
                if let root = grammarRoot { return root.withCString { invoke($0) } }
                else { return invoke(nil) }
            }
        } else {
            stream = prompt.withCString { promptPtr in
                cStopSequences.withUnsafeBufferPointer { stopPtr in
                    var mutableParams = params
                    mutableParams.stop_sequences = UnsafeMutablePointer(mutating: stopPtr.baseAddress)
                    mutableParams.grammar_str = nil
                    mutableParams.grammar_root = nil
                    return ev_generate_stream(ctx, promptPtr, &mutableParams, &error)
                }
            }
        }
        
        guard error == EV_SUCCESS, let stream = stream else {
            throw mapError(error, ctx: ctx)
        }
        
        defer { ev_stream_free(stream) }
        
        // Notify caller of stream handle for external cancellation
        onStreamCreated?(stream)
        
        // Read tokens from stream
        while ev_stream_has_next(stream) {
            var tokenError: ev_error_t = EV_SUCCESS
            guard let tokenPtr = ev_stream_next(stream, &tokenError) else {
                if tokenError != EV_ERROR_STREAM_ENDED {
                    throw mapError(tokenError, ctx: ctx)
                }
                break
            }
            
            defer { ev_free_string(tokenPtr) }
            let token = String(cString: tokenPtr)
            onToken(token)
        }
    }

    /// Cancel streaming generation
    static func cancelStream(_ stream: ev_stream) {
        ev_stream_cancel(stream)
    }

    /// Get extended token information from stream
    static func getStreamTokenInfo(stream: ev_stream) throws -> (confidence: Float, avgConfidence: Float, needsCloudHandoff: Bool, tokenIndex: Int) {
        var info = ev_stream_token_info()
        let error = ev_stream_get_token_info(stream, &info)
        
        guard error == EV_SUCCESS else {
            throw mapError(error, ctx: nil)
        }
        
        return (
            confidence: info.confidence,
            avgConfidence: info.avg_confidence,
            needsCloudHandoff: info.needs_cloud_handoff,
            tokenIndex: Int(info.token_index)
        )
    }

    // MARK: - Embeddings

    /// Compute text embeddings
    static func embed(ctx: ev_context, text: String) throws -> [Float] {
        var result = ev_embed_result()
        
        let error = text.withCString { textPtr in
            ev_embed(ctx, textPtr, &result)
        }
        
        guard error == EV_SUCCESS else {
            throw mapError(error, ctx: ctx)
        }
        
        guard result.embeddings != nil else {
            throw EdgeVedaError.generationFailed(reason: "No embeddings returned")
        }
        
        // Copy embeddings to Swift array
        let dimensions = Int(result.dimensions)
        let embeddings = Array(UnsafeBufferPointer(start: result.embeddings, count: dimensions))
        
        // Free C memory
        ev_free_embeddings(&result)
        
        return embeddings
    }

    // MARK: - Whisper (Speech-to-Text)

    /// Initialize whisper context
    static func initWhisperContext(
        modelPath: String,
        threads: Int,
        useGpu: Bool
    ) throws -> ev_whisper_context {
        var config = ev_whisper_config()
        config.num_threads = Int32(threads)
        config.use_gpu = useGpu
        config.reserved = nil

        var error: ev_error_t = EV_SUCCESS
        
        let ctx = modelPath.withCString { pathPtr in
            var mutableConfig = config
            mutableConfig.model_path = pathPtr
            return ev_whisper_init(&mutableConfig, &error)
        }
        
        guard ctx != nil && error == EV_SUCCESS else {
            throw mapWhisperError(error)
        }
        
        return ctx!
    }

    /// Free whisper context
    static func freeWhisperContext(_ ctx: ev_whisper_context) {
        ev_whisper_free(ctx)
    }

    /// Check if whisper context is valid
    static func isWhisperValid(_ ctx: ev_whisper_context) -> Bool {
        return ev_whisper_is_valid(ctx)
    }

    /// Transcribe audio
    static func transcribe(
        ctx: ev_whisper_context,
        audioData: [Float],
        language: String?,
        translate: Bool
    ) throws -> [(text: String, startMs: Int64, endMs: Int64)] {
        var params = ev_whisper_params()
        params.n_threads = 0 // Use default from config
        params.translate = translate
        params.reserved = nil

        // Use a non-optional struct — matches the C output-parameter convention
        // (same pattern as ev_embed_result in embed()). &result gives
        // UnsafeMutablePointer<ev_whisper_result> as the C function expects.
        var result = ev_whisper_result()

        let error: ev_error_t
        if let language = language {
            error = language.withCString { langPtr in
                audioData.withUnsafeBufferPointer { audioPtr in
                    var mutableParams = params
                    mutableParams.language = langPtr
                    return ev_whisper_transcribe(
                        ctx,
                        audioPtr.baseAddress!,
                        Int32(audioData.count),
                        &mutableParams,
                        &result
                    )
                }
            }
        } else {
            error = audioData.withUnsafeBufferPointer { audioPtr in
                var mutableParams = params
                mutableParams.language = nil
                return ev_whisper_transcribe(
                    ctx,
                    audioPtr.baseAddress!,
                    Int32(audioData.count),
                    &mutableParams,
                    &result
                )
            }
        }

        guard error == EV_SUCCESS else {
            throw mapWhisperError(error)
        }

        defer { ev_whisper_free_result(&result) }
        
        // Convert segments to Swift array
        var segments: [(text: String, startMs: Int64, endMs: Int64)] = []
        for i in 0..<Int(result.n_segments) {
            let segment = result.segments[i]
            if let text = segment.text {
                segments.append((
                    text: String(cString: text),
                    startMs: segment.start_ms,
                    endMs: segment.end_ms
                ))
            }
        }
        
        return segments
    }

    // MARK: - Memory Management

    /// Get memory usage statistics
    static func getMemoryUsage(ctx: ev_context) throws -> MemoryStats {
        var stats = ev_memory_stats()
        let error = ev_get_memory_usage(ctx, &stats)

        guard error == EV_SUCCESS else {
            throw mapError(error, ctx: ctx)
        }

        return MemoryStats(
            currentBytes: UInt64(stats.current_bytes),
            peakBytes:    UInt64(stats.peak_bytes),
            limitBytes:   UInt64(stats.limit_bytes),
            modelBytes:   UInt64(stats.model_bytes),
            contextBytes: UInt64(stats.context_bytes)
        )
    }

    /// Set memory limit
    static func setMemoryLimit(ctx: ev_context, limitBytes: UInt64) throws {
        let error = ev_set_memory_limit(ctx, Int(limitBytes))
        guard error == EV_SUCCESS else {
            throw mapError(error, ctx: ctx)
        }
    }

    /// Trigger memory cleanup
    static func memoryCleanup(ctx: ev_context) throws {
        let error = ev_memory_cleanup(ctx)
        guard error == EV_SUCCESS else {
            throw mapError(error, ctx: ctx)
        }
    }

    /// Set memory pressure callback
    static func setMemoryPressureCallback(
        ctx: ev_context,
        callback: ((UInt64, UInt64) -> Void)?
    ) throws {
        let ctxPtr = UnsafeMutableRawPointer(ctx)
        let key = NSValue(pointer: ctxPtr)
        
        callbackLock.lock()
        defer { callbackLock.unlock() }
        
        if let callback = callback {
            // Register callback
            memoryCallbacks.setObject(callback as AnyObject, forKey: key)
            let error = ev_set_memory_pressure_callback(ctx, cMemoryCallback, ctxPtr)
            guard error == EV_SUCCESS else {
                memoryCallbacks.removeObject(forKey: key)
                throw mapError(error, ctx: ctx)
            }
        } else {
            // Unregister callback
            memoryCallbacks.removeObject(forKey: key)
            let error = ev_set_memory_pressure_callback(ctx, nil, nil)
            guard error == EV_SUCCESS else {
                throw mapError(error, ctx: ctx)
            }
        }
    }

    // MARK: - Model Information

    /// Get model information
    static func getModelInfo(ctx: ev_context) throws -> [String: String] {
        var info = ev_model_info()
        let error = ev_get_model_info(ctx, &info)
        
        guard error == EV_SUCCESS else {
            throw mapError(error, ctx: ctx)
        }
        
        var result: [String: String] = [:]
        
        if let name = info.name {
            result["name"] = String(cString: name)
        }
        if let architecture = info.architecture {
            result["architecture"] = String(cString: architecture)
        }
        result["parameters"] = String(info.num_parameters)
        result["contextLength"] = String(info.context_length)
        result["embeddingDim"] = String(info.embedding_dim)
        result["numLayers"] = String(info.num_layers)
        
        return result
    }

    // MARK: - Context Reset

    /// Reset context state
    static func resetContext(ctx: ev_context) throws {
        let error = ev_reset(ctx)
        guard error == EV_SUCCESS else {
            throw mapError(error, ctx: ctx)
        }
    }

    // MARK: - Vision API

    /// Initialize vision context
    static func initVisionContext(
        modelPath: String,
        mmprojPath: String,
        threads: Int,
        contextSize: Int,
        gpuLayers: Int,
        batchSize: Int,
        useMmap: Bool
    ) throws -> ev_vision_context {
        var config = ev_vision_config()
        config.num_threads = Int32(threads)
        config.context_size = Int32(contextSize)
        config.batch_size = Int32(batchSize)
        config.memory_limit_bytes = 0
        config.gpu_layers = Int32(gpuLayers)
        config.use_mmap = useMmap
        config.reserved = nil

        var error: ev_error_t = EV_SUCCESS
        
        let ctx = modelPath.withCString { modelPtr in
            mmprojPath.withCString { mmprojPtr in
                var mutableConfig = config
                mutableConfig.model_path = modelPtr
                mutableConfig.mmproj_path = mmprojPtr
                return ev_vision_init(&mutableConfig, &error)
            }
        }
        
        guard ctx != nil && error == EV_SUCCESS else {
            throw mapVisionError(error, ctx: ctx)
        }
        
        return ctx!
    }

    /// Free vision context
    static func freeVisionContext(_ ctx: ev_vision_context) {
        ev_vision_free(ctx)
    }

    /// Check if vision context is valid
    static func isVisionValid(_ ctx: ev_vision_context) -> Bool {
        return ev_vision_is_valid(ctx)
    }

    /// Describe image
    static func describeImage(
        ctx: ev_vision_context,
        imageBytes: [UInt8],
        width: Int,
        height: Int,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float
    ) throws -> String {
        var params = ev_generation_params()
        params.max_tokens = Int32(maxTokens)
        params.temperature = temperature
        params.top_p = topP
        params.top_k = Int32(topK)
        params.repeat_penalty = repeatPenalty
        params.frequency_penalty = 0.0
        params.presence_penalty = 0.0
        params.stop_sequences = nil
        params.num_stop_sequences = 0
        params.reserved = nil

        var output: UnsafeMutablePointer<CChar>?
        
        let error = imageBytes.withUnsafeBytes { imagePtr in
            prompt.withCString { promptPtr in
                ev_vision_describe(
                    ctx,
                    imagePtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    Int32(width),
                    Int32(height),
                    promptPtr,
                    &params,
                    &output
                )
            }
        }
        
        guard error == EV_SUCCESS, let resultPtr = output else {
            throw mapVisionError(error, ctx: ctx)
        }
        
        defer { ev_free_string(resultPtr) }
        return String(cString: resultPtr)
    }

    /// Get vision timings
    static func getVisionTimings(ctx: ev_vision_context) throws -> (
        modelLoadMs: Double,
        imageEncodeMs: Double,
        promptEvalMs: Double,
        decodeMs: Double,
        promptTokens: Int,
        generatedTokens: Int
    ) {
        var timings = ev_timings_data()
        let error = ev_vision_get_last_timings(ctx, &timings)
        
        guard error == EV_SUCCESS else {
            throw mapVisionError(error, ctx: ctx)
        }
        
        return (
            modelLoadMs: timings.model_load_ms,
            imageEncodeMs: timings.image_encode_ms,
            promptEvalMs: timings.prompt_eval_ms,
            decodeMs: timings.decode_ms,
            promptTokens: Int(timings.prompt_tokens),
            generatedTokens: Int(timings.generated_tokens)
        )
    }

    // MARK: - Backend Detection

    /// Detect best backend
    static func detectBackend() -> Backend {
        let backend = ev_detect_backend()
        return Backend(cValue: backend) ?? .auto
    }

    /// Check if backend is available
    static func isBackendAvailable(_ backend: Backend) -> Bool {
        return ev_is_backend_available(backend.cValue)
    }

    /// Get backend name
    static func backendName(_ backend: Backend) -> String {
        guard let name = ev_backend_name(backend.cValue) else {
            return "Unknown"
        }
        return String(cString: name)
    }

    // MARK: - Utility

    /// Get version string
    static func version() -> String {
        guard let version = ev_version() else {
            return "Unknown"
        }
        return String(cString: version)
    }

    /// Enable verbose logging
    static func setVerbose(_ enable: Bool) {
        ev_set_verbose(enable)
    }

    // MARK: - Error Mapping

    private static func mapError(_ error: ev_error_t, ctx: ev_context?) -> EdgeVedaError {
        let message: String
        if let ctx = ctx, let lastError = ev_get_last_error(ctx) {
            message = String(cString: lastError)
        } else {
            message = String(cString: ev_error_string(error))
        }
        
        switch error {
        case EV_ERROR_INVALID_PARAM:
            return .invalidParameter(name: "unknown", value: message)
        case EV_ERROR_OUT_OF_MEMORY:
            return .outOfMemory
        case EV_ERROR_MODEL_LOAD_FAILED:
            return .loadFailed(reason: message)
        case EV_ERROR_BACKEND_INIT_FAILED:
            return .unsupportedBackend(.auto)
        case EV_ERROR_INFERENCE_FAILED:
            return .generationFailed(reason: message)
        case EV_ERROR_CONTEXT_INVALID:
            return .ffiError(message: "Invalid context")
        case EV_ERROR_UNSUPPORTED_BACKEND:
            return .unsupportedBackend(.auto)
        default:
            return .unknown(message: message)
        }
    }

    private static func mapVisionError(_ error: ev_error_t, ctx: ev_vision_context?) -> EdgeVedaError {
        let message = String(cString: ev_error_string(error))
        
        switch error {
        case EV_ERROR_INVALID_PARAM:
            return .invalidParameter(name: "unknown", value: message)
        case EV_ERROR_OUT_OF_MEMORY:
            return .outOfMemory
        case EV_ERROR_MODEL_LOAD_FAILED:
            return .loadFailed(reason: message)
        case EV_ERROR_BACKEND_INIT_FAILED:
            return .unsupportedBackend(.auto)
        case EV_ERROR_INFERENCE_FAILED:
            return .generationFailed(reason: message)
        default:
            return .unknown(message: message)
        }
    }

    private static func mapWhisperError(_ error: ev_error_t) -> EdgeVedaError {
        let message = String(cString: ev_error_string(error))
        
        switch error {
        case EV_ERROR_INVALID_PARAM:
            return .invalidParameter(name: "unknown", value: message)
        case EV_ERROR_OUT_OF_MEMORY:
            return .outOfMemory
        case EV_ERROR_MODEL_LOAD_FAILED:
            return .loadFailed(reason: message)
        case EV_ERROR_BACKEND_INIT_FAILED:
            return .unsupportedBackend(.auto)
        case EV_ERROR_INFERENCE_FAILED:
            return .generationFailed(reason: message)
        default:
            return .unknown(message: message)
        }
    }
}

// MARK: - Backend Extension

extension Backend {
    var cValue: ev_backend_t {
        switch self {
        case .cpu:
            return EV_BACKEND_CPU
        case .metal:
            return EV_BACKEND_METAL
        case .auto:
            return EV_BACKEND_AUTO
        }
    }
    
    init?(cValue: ev_backend_t) {
        switch cValue {
        case EV_BACKEND_CPU:
            self = .cpu
        case EV_BACKEND_METAL:
            self = .metal
        case EV_BACKEND_AUTO:
            self = .auto
        default:
            return nil
        }
    }
}