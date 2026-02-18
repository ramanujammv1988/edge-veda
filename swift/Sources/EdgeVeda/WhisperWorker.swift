import Foundation
import CEdgeVeda

/// Actor-based worker for speech-to-text transcription operations
/// Maintains a persistent native Whisper context and manages audio processing
public actor WhisperWorker {
    
    // MARK: - State
    
    /// The C whisper context pointer. Marked nonisolated(unsafe) because:
    /// - It's an opaque C pointer managed by the underlying C library
    /// - The C library handles thread safety internally
    /// - We need to access it from nonisolated deinit for cleanup
    private nonisolated(unsafe) var whisperContext: ev_whisper_context?
    private var config: WhisperConfig?
    
    // MARK: - Initialization
    
    public init() {}
    
    /// Initialize the Whisper worker with model configuration
    /// Loads the Whisper model into memory (~75-500MB depending on model size)
    /// This is a one-time operation - the context is reused for all subsequent transcriptions
    ///
    /// - Parameter config: Whisper configuration including model path and settings
    /// - Throws: EdgeVedaError if initialization fails
    public func initialize(config: WhisperConfig) async throws {
        // Cleanup any existing context
        if let ctx = whisperContext {
            FFIBridge.freeWhisperContext(ctx)
            whisperContext = nil
        }
        
        // Initialize new context
        // Note: FFIBridge Whisper API is simplified - maps to ev_whisper_config
        let ctx = try FFIBridge.initWhisperContext(
            modelPath: config.modelPath,
            threads: config.threads,
            useGpu: config.gpuLayers > 0
        )
        
        // Verify context is valid
        guard FFIBridge.isWhisperValid(ctx) else {
            FFIBridge.freeWhisperContext(ctx)
            throw EdgeVedaError.loadFailed(reason: "Whisper context initialization failed")
        }
        
        self.whisperContext = ctx
        self.config = config
    }
    
    /// Check if the worker is initialized and ready
    public var isInitialized: Bool {
        return whisperContext != nil
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio samples to text
    /// Audio should be mono, Float32 format, typically at 16kHz sample rate
    ///
    /// - Parameters:
    ///   - audioData: Audio samples as Float32 array (mono, typically 16kHz)
    ///   - params: Transcription parameters (language, translation, etc.)
    /// - Returns: WhisperResult with transcribed text and segment timing information
    /// - Throws: EdgeVedaError if transcription fails
    /// - Example:
    /// ```swift
    /// let params = WhisperParams(language: "en", threads: 4)
    /// let result = try await worker.transcribe(audioData: samples, params: params)
    /// print("Transcribed: \(result.text)")
    /// for segment in result.segments {
    ///     print("[\(segment.startTime)ms - \(segment.endTime)ms]: \(segment.text)")
    /// }
    /// ```
    public func transcribe(
        audioData: [Float],
        params: WhisperParams = .default
    ) async throws -> WhisperResult {
        guard let ctx = whisperContext else {
            throw EdgeVedaError.loadFailed(reason: "Whisper worker not initialized")
        }
        
        let startTime = Date()
        
        // Perform transcription - FFIBridge returns simplified tuple array
        let segmentTuples = try FFIBridge.transcribe(
            ctx: ctx,
            audioData: audioData,
            language: params.language,
            translate: params.translate
        )
        
        let processingTime = Date().timeIntervalSince(startTime) * 1000.0 // Convert to ms
        
        // Convert tuples to WhisperSegment objects
        let segments = segmentTuples.map { tuple in
            WhisperSegment(
                text: tuple.text,
                startTime: tuple.startMs,
                endTime: tuple.endMs
            )
        }
        
        // Combine all segment texts to get full transcription
        let fullText = segments.map { $0.text }.joined(separator: " ")
        
        // Use provided language or "unknown" if auto-detected
        let detectedLanguage = params.language ?? "unknown"
        
        return WhisperResult(
            text: fullText,
            segments: segments,
            detectedLanguage: detectedLanguage,
            processingTime: processingTime
        )
    }
    
    // MARK: - Cleanup
    
    /// Cleanup and free the native Whisper context
    /// Should be called when done with the worker to release memory (~75-500MB)
    public func cleanup() {
        if let ctx = whisperContext {
            FFIBridge.freeWhisperContext(ctx)
            whisperContext = nil
        }
        config = nil
    }
    
    deinit {
        // Note: deinit is not async, so we can't await cleanup
        // The cleanup() method should be called explicitly before deallocation
        if let ctx = whisperContext {
            FFIBridge.freeWhisperContext(ctx)
        }
    }
}