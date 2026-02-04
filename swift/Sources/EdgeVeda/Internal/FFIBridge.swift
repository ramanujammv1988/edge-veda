import Foundation
import CEdgeVeda

/// Bridge between Swift and C FFI
/// Handles all unsafe pointer operations and C interop
internal enum FFIBridge {

    // MARK: - Model Management

    /// Load a model from disk
    static func loadModel(
        path: String,
        backend: Backend,
        threads: Int,
        contextSize: Int
    ) throws -> OpaquePointer {
        // Create C config struct
        var config = edge_veda_config()
        config.backend = backend.cValue
        config.threads = Int32(threads)
        config.context_size = Int32(contextSize)
        config.verbose = false

        // Call C function
        var errorBuffer = [CChar](repeating: 0, count: 512)
        guard let handle = path.withCString({ pathPtr in
            edge_veda_load_model(pathPtr, &config, &errorBuffer)
        }) else {
            let errorMessage = String(cString: errorBuffer)
            if errorMessage.contains("file not found") || errorMessage.contains("No such file") {
                throw EdgeVedaError.modelNotFound(path: path)
            } else if errorMessage.contains("out of memory") || errorMessage.contains("OOM") {
                throw EdgeVedaError.outOfMemory
            } else {
                throw EdgeVedaError.loadFailed(reason: errorMessage)
            }
        }

        return handle
    }

    /// Unload a model and free resources
    static func unloadModel(handle: OpaquePointer) {
        edge_veda_free_model(handle)
    }

    // MARK: - Text Generation

    /// Generate text synchronously
    static func generate(
        handle: OpaquePointer,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        stopSequences: [String]
    ) throws -> String {
        // Create generation params
        var params = edge_veda_generate_params()
        params.max_tokens = Int32(maxTokens)
        params.temperature = temperature
        params.top_p = topP
        params.top_k = Int32(topK)
        params.repeat_penalty = repeatPenalty

        // Convert stop sequences to C array
        let stopSeqPointers = stopSequences.map { $0.withCString { strdup($0) } }
        defer {
            stopSeqPointers.forEach { free($0) }
        }

        var cStopSequences = stopSeqPointers
        params.stop_sequences = &cStopSequences
        params.stop_sequences_count = Int32(stopSequences.count)

        // Call C function
        var errorBuffer = [CChar](repeating: 0, count: 512)
        guard let resultPtr = prompt.withCString({ promptPtr in
            edge_veda_generate(handle, promptPtr, &params, &errorBuffer)
        }) else {
            let errorMessage = String(cString: errorBuffer)
            throw EdgeVedaError.generationFailed(reason: errorMessage)
        }

        defer { edge_veda_free_string(resultPtr) }
        return String(cString: resultPtr)
    }

    /// Generate text with streaming callback
    static func generateStream(
        handle: OpaquePointer,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        stopSequences: [String],
        onToken: @escaping (String) -> Void
    ) async throws {
        // Create generation params
        var params = edge_veda_generate_params()
        params.max_tokens = Int32(maxTokens)
        params.temperature = temperature
        params.top_p = topP
        params.top_k = Int32(topK)
        params.repeat_penalty = repeatPenalty

        // Convert stop sequences to C array
        let stopSeqPointers = stopSequences.map { $0.withCString { strdup($0) } }
        defer {
            stopSeqPointers.forEach { free($0) }
        }

        var cStopSequences = stopSeqPointers
        params.stop_sequences = &cStopSequences
        params.stop_sequences_count = Int32(stopSequences.count)

        // Create callback context
        let callbackContext = UnsafeMutablePointer<(String) -> Void>.allocate(capacity: 1)
        callbackContext.initialize(to: onToken)
        defer {
            callbackContext.deinitialize(count: 1)
            callbackContext.deallocate()
        }

        // C callback wrapper
        let callback: edge_veda_stream_callback = { tokenPtr, _, contextPtr in
            guard let tokenPtr = tokenPtr,
                  let contextPtr = contextPtr else {
                return
            }

            let token = String(cString: tokenPtr)
            let onToken = contextPtr.assumingMemoryBound(to: ((String) -> Void).self).pointee
            onToken(token)
        }

        // Call C streaming function
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let result = prompt.withCString { promptPtr in
            edge_veda_generate_stream(
                handle,
                promptPtr,
                &params,
                callback,
                callbackContext,
                &errorBuffer
            )
        }

        if result != 0 {
            let errorMessage = String(cString: errorBuffer)
            throw EdgeVedaError.generationFailed(reason: errorMessage)
        }
    }

    // MARK: - Model Information

    /// Get current memory usage
    static func getMemoryUsage(handle: OpaquePointer) -> UInt64 {
        return edge_veda_get_memory_usage(handle)
    }

    /// Get model metadata
    static func getModelMetadata(handle: OpaquePointer) -> [String: String] {
        var metadata: [String: String] = [:]

        // Get metadata count
        let count = edge_veda_get_metadata_count(handle)
        guard count > 0 else {
            return metadata
        }

        // Iterate through metadata entries
        for i in 0..<count {
            var keyBuffer = [CChar](repeating: 0, count: 256)
            var valueBuffer = [CChar](repeating: 0, count: 1024)

            if edge_veda_get_metadata_entry(handle, i, &keyBuffer, &valueBuffer) == 0 {
                let key = String(cString: keyBuffer)
                let value = String(cString: valueBuffer)
                metadata[key] = value
            }
        }

        return metadata
    }

    /// Reset context/KV cache
    static func resetContext(handle: OpaquePointer) {
        edge_veda_reset_context(handle)
    }

    // MARK: - Helper Functions

    /// Convert Swift string array to C string array
    private static func stringArrayToC(_ strings: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
        let cStrings = strings.map { $0.withCString { strdup($0) } }
        let cArray = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: cStrings.count + 1)

        for (index, cString) in cStrings.enumerated() {
            cArray[index] = cString
        }
        cArray[cStrings.count] = nil

        return cArray
    }

    /// Free C string array
    private static func freeCStringArray(_ cArray: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, count: Int) {
        for i in 0..<count {
            if let cString = cArray[i] {
                free(cString)
            }
        }
        cArray.deallocate()
    }

    /// Check if error occurred and throw if needed
    private static func checkError(_ errorBuffer: [CChar]) throws {
        let errorMessage = String(cString: errorBuffer)
        guard !errorMessage.isEmpty else {
            return
        }
        throw EdgeVedaError.ffiError(message: errorMessage)
    }
}

// MARK: - C Function Declarations (Placeholder)

// These will be provided by the C library (edge_veda.h)
// The actual implementation will come from the compiled C library

/// C configuration struct
internal struct edge_veda_config {
    var backend: Int32
    var threads: Int32
    var context_size: Int32
    var gpu_layers: Int32
    var batch_size: Int32
    var use_mmap: Bool
    var use_mlock: Bool
    var verbose: Bool

    init() {
        self.backend = 0
        self.threads = 0
        self.context_size = 2048
        self.gpu_layers = -1
        self.batch_size = 512
        self.use_mmap = true
        self.use_mlock = false
        self.verbose = false
    }
}

/// C generation parameters struct
internal struct edge_veda_generate_params {
    var max_tokens: Int32
    var temperature: Float
    var top_p: Float
    var top_k: Int32
    var repeat_penalty: Float
    var stop_sequences: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    var stop_sequences_count: Int32

    init() {
        self.max_tokens = 512
        self.temperature = 0.7
        self.top_p = 0.9
        self.top_k = 40
        self.repeat_penalty = 1.1
        self.stop_sequences = nil
        self.stop_sequences_count = 0
    }
}

/// Stream callback type
internal typealias edge_veda_stream_callback = @convention(c) (
    UnsafePointer<CChar>?,  // token
    Int32,                   // token_id
    UnsafeMutableRawPointer? // user_data
) -> Void

// MARK: - C Function Stubs (to be replaced by actual C library)

@_silgen_name("edge_veda_load_model")
internal func edge_veda_load_model(
    _ path: UnsafePointer<CChar>,
    _ config: UnsafePointer<edge_veda_config>,
    _ error: UnsafeMutablePointer<CChar>
) -> OpaquePointer?

@_silgen_name("edge_veda_free_model")
internal func edge_veda_free_model(_ handle: OpaquePointer)

@_silgen_name("edge_veda_generate")
internal func edge_veda_generate(
    _ handle: OpaquePointer,
    _ prompt: UnsafePointer<CChar>,
    _ params: UnsafePointer<edge_veda_generate_params>,
    _ error: UnsafeMutablePointer<CChar>
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("edge_veda_generate_stream")
internal func edge_veda_generate_stream(
    _ handle: OpaquePointer,
    _ prompt: UnsafePointer<CChar>,
    _ params: UnsafePointer<edge_veda_generate_params>,
    _ callback: edge_veda_stream_callback,
    _ user_data: UnsafeMutableRawPointer?,
    _ error: UnsafeMutablePointer<CChar>
) -> Int32

@_silgen_name("edge_veda_free_string")
internal func edge_veda_free_string(_ str: UnsafeMutablePointer<CChar>)

@_silgen_name("edge_veda_get_memory_usage")
internal func edge_veda_get_memory_usage(_ handle: OpaquePointer) -> UInt64

@_silgen_name("edge_veda_get_metadata_count")
internal func edge_veda_get_metadata_count(_ handle: OpaquePointer) -> Int32

@_silgen_name("edge_veda_get_metadata_entry")
internal func edge_veda_get_metadata_entry(
    _ handle: OpaquePointer,
    _ index: Int32,
    _ key: UnsafeMutablePointer<CChar>,
    _ value: UnsafeMutablePointer<CChar>
) -> Int32

@_silgen_name("edge_veda_reset_context")
internal func edge_veda_reset_context(_ handle: OpaquePointer)
