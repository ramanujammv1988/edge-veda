import Foundation
import CEdgeVeda

/// Actor-based worker for vision inference operations
/// Maintains a persistent native vision context and manages frame processing with backpressure
public actor VisionWorker {
    
    // MARK: - State
    
    /// The C vision context pointer. Marked nonisolated(unsafe) because:
    /// - It's an opaque C pointer managed by the underlying C library
    /// - The C library handles thread safety internally
    /// - We need to access it from nonisolated deinit for cleanup
    private nonisolated(unsafe) var visionContext: ev_vision_context?
    private let frameQueue = FrameQueue()
    private var isProcessing = false
    private var config: VisionConfig?
    
    // MARK: - Initialization
    
    public init() {}
    
    /// Initialize the vision worker with model configuration
    /// Loads the VLM and multimodal projection model into memory (~600MB)
    /// This is a one-time operation - the context is reused for all subsequent frames
    ///
    /// - Parameter config: Vision configuration including model paths and settings
    /// - Returns: Result containing success or error message
    /// - Throws: EdgeVedaError if initialization fails
    public func initialize(config: VisionConfig) async throws {
        // Cleanup any existing context
        if let ctx = visionContext {
            FFIBridge.freeVisionContext(ctx)
            visionContext = nil
        }
        
        // Initialize new context
        let ctx = try FFIBridge.initVisionContext(
            modelPath: config.modelPath,
            mmprojPath: config.mmprojPath,
            threads: config.numThreads,
            contextSize: config.contextSize,
            gpuLayers: config.gpuLayers,
            batchSize: config.batchSize,
            useMmap: config.useMmap
        )
        
        // Verify context is valid
        guard FFIBridge.isVisionValid(ctx) else {
            FFIBridge.freeVisionContext(ctx)
            throw EdgeVedaError.loadFailed(reason: "Vision context initialization failed")
        }
        
        self.visionContext = ctx
        self.config = config
        frameQueue.reset()
    }
    
    /// Check if the worker is initialized and ready
    public var isInitialized: Bool {
        return visionContext != nil
    }
    
    // MARK: - Frame Processing
    
    /// Enqueue a frame for processing with backpressure management
    /// Uses drop-newest policy: if worker is busy and queue is full, replaces pending frame
    ///
    /// - Parameters:
    ///   - rgb: RGB888 image data (width * height * 3 bytes)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// - Returns: true if frame was queued, false if previous pending frame was dropped
    public func enqueueFrame(rgb: Data, width: Int, height: Int) -> Bool {
        return frameQueue.enqueue(rgb: rgb, width: width, height: height)
    }
    
    /// Process the next queued frame if available
    /// Returns nil if no frame is queued or worker is already processing
    ///
    /// - Parameters:
    ///   - prompt: The prompt for describing the image (default: "Describe what you see.")
    ///   - params: Generation parameters (default: VisionGenerationParams with sensible defaults)
    /// - Returns: VisionResult with description and timings, or nil if no frame available
    /// - Throws: EdgeVedaError if inference fails
    public func processNextFrame(
        prompt: String = "Describe what you see.",
        params: VisionGenerationParams = VisionGenerationParams()
    ) async throws -> VisionResult? {
        // Check if we have a frame to process
        guard let frame = frameQueue.dequeue() else {
            return nil
        }
        
        guard let ctx = visionContext else {
            frameQueue.markDone()
            throw EdgeVedaError.loadFailed(reason: "Vision worker not initialized")
        }
        
        isProcessing = true
        defer {
            frameQueue.markDone()
            isProcessing = false
        }
        
        // Convert Data to [UInt8]
        let imageBytes = [UInt8](frame.rgb)
        
        // Perform vision inference
        let description = try FFIBridge.describeImage(
            ctx: ctx,
            imageBytes: imageBytes,
            width: frame.width,
            height: frame.height,
            prompt: prompt,
            maxTokens: params.maxTokens,
            temperature: params.temperature,
            topP: params.topP,
            topK: params.topK,
            repeatPenalty: params.repeatPenalty
        )
        
        // Get timing information
        let timingsData = try FFIBridge.getVisionTimings(ctx: ctx)
        let timings = VisionTimings(
            modelLoadMs: timingsData.modelLoadMs,
            imageEncodeMs: timingsData.imageEncodeMs,
            promptEvalMs: timingsData.promptEvalMs,
            decodeMs: timingsData.decodeMs,
            promptTokens: timingsData.promptTokens,
            generatedTokens: timingsData.generatedTokens
        )
        
        return VisionResult(description: description, timings: timings)
    }
    
    /// Describe a single frame synchronously (bypasses queue)
    /// Use this for one-off inferences or when you need immediate results
    ///
    /// - Parameters:
    ///   - rgb: RGB888 image data (width * height * 3 bytes)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - prompt: The prompt for describing the image
    ///   - params: Generation parameters
    /// - Returns: VisionResult with description and timings
    /// - Throws: EdgeVedaError if inference fails
    public func describeFrame(
        rgb: Data,
        width: Int,
        height: Int,
        prompt: String = "Describe what you see.",
        params: VisionGenerationParams = VisionGenerationParams()
    ) async throws -> VisionResult {
        guard let ctx = visionContext else {
            throw EdgeVedaError.loadFailed(reason: "Vision worker not initialized")
        }
        
        let imageBytes = [UInt8](rgb)
        
        let description = try FFIBridge.describeImage(
            ctx: ctx,
            imageBytes: imageBytes,
            width: width,
            height: height,
            prompt: prompt,
            maxTokens: params.maxTokens,
            temperature: params.temperature,
            topP: params.topP,
            topK: params.topK,
            repeatPenalty: params.repeatPenalty
        )
        
        let timingsData = try FFIBridge.getVisionTimings(ctx: ctx)
        let timings = VisionTimings(
            modelLoadMs: timingsData.modelLoadMs,
            imageEncodeMs: timingsData.imageEncodeMs,
            promptEvalMs: timingsData.promptEvalMs,
            decodeMs: timingsData.decodeMs,
            promptTokens: timingsData.promptTokens,
            generatedTokens: timingsData.generatedTokens
        )
        
        return VisionResult(description: description, timings: timings)
    }
    
    // MARK: - Queue Management
    
    /// Get the number of frames dropped due to backpressure
    public var droppedFrames: Int {
        return frameQueue.droppedFrames
    }
    
    /// Reset the dropped frames counter
    public func resetCounters() {
        frameQueue.resetCounters()
    }
    
    /// Reset the frame queue (clears pending frames)
    public func resetQueue() {
        frameQueue.reset()
    }
    
    // MARK: - Cleanup
    
    /// Cleanup and free the native vision context
    /// Should be called when done with the worker to release memory (~600MB)
    public func cleanup() {
        if let ctx = visionContext {
            FFIBridge.freeVisionContext(ctx)
            visionContext = nil
        }
        frameQueue.reset()
        config = nil
    }
    
    deinit {
        // Note: deinit is not async, so we can't await cleanup
        // The cleanup() method should be called explicitly before deallocation
        if let ctx = visionContext {
            FFIBridge.freeVisionContext(ctx)
        }
    }
}