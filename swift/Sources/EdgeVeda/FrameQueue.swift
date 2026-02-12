//
//  FrameQueue.swift
//  EdgeVeda
//
//  Bounded frame queue with drop-newest backpressure policy for vision inference.
//
//  When inference is busy and a new frame arrives, the pending frame is
//  replaced (not accumulated). This ensures vision descriptions stay current
//  with the camera feed rather than falling behind.
//
//  Design decisions:
//  - Drop-newest policy: when processing is busy, new frames REPLACE the
//    pending slot (not queue up)
//  - Only 1 pending slot (capacity 1): at most 1 frame waits while inference runs
//  - droppedFrames is cumulative across the session for performance analysis
//  - reset() clears frame state but preserves drop counter
//  - Thread safety is NOT needed because this runs on the main actor
//
//  Usage:
//  1. Camera callback calls enqueue() with each frame
//  2. Processing loop calls dequeue() to get next frame
//  3. After inference completes, call markDone()
//  4. Check droppedFrames to track backpressure
//
//  Created: 2026-11-02
//

import Foundation

/// Frame data for vision inference.
///
/// Contains RGB888 pixel data and dimensions.
public struct FrameData: Sendable {
    /// Raw RGB888 pixel data (width * height * 3 bytes)
    public let rgb: Data
    
    /// Image width in pixels
    public let width: Int
    
    /// Image height in pixels
    public let height: Int
    
    /// Initialize frame data
    ///
    /// - Parameters:
    ///   - rgb: RGB888 pixel data
    ///   - width: Image width
    ///   - height: Image height
    public init(rgb: Data, width: Int, height: Int) {
        self.rgb = rgb
        self.width = width
        self.height = height
    }
}

/// Bounded frame queue with drop-newest backpressure policy.
///
/// Holds at most one pending frame. When inference is busy and a frame is
/// already pending, new frames replace the pending slot and increment the
/// droppedFrames counter.
///
/// This class is **not** thread-safe. It should be accessed from a single
/// thread or actor (typically the main actor for camera callbacks).
///
/// Example:
/// ```swift
/// let queue = FrameQueue()
///
/// // Camera callback
/// func onFrame(rgb: Data, width: Int, height: Int) {
///     let dropped = !queue.enqueue(rgb: rgb, width: width, height: height)
///     if dropped {
///         print("Warning: Frame dropped due to backpressure")
///     }
/// }
///
/// // Processing loop
/// while let frame = queue.dequeue() {
///     let result = await visionWorker.describeFrame(frame)
///     queue.markDone()
/// }
/// ```
public final class FrameQueue {
    /// Pending frame waiting to be processed
    private var pendingFrame: FrameData?
    
    /// Whether inference is currently processing a frame
    private var _isProcessing = false
    
    /// Number of frames dropped due to backpressure (cumulative)
    private var _droppedFrames = 0
    
    /// Number of frames dropped due to backpressure (cumulative).
    ///
    /// This counter is preserved across reset() calls and should only be
    /// cleared with resetCounters() at the start of a new test session.
    public var droppedFrames: Int {
        _droppedFrames
    }
    
    /// Whether inference is currently processing a frame.
    public var isProcessing: Bool {
        _isProcessing
    }
    
    /// Whether there is a frame waiting to be processed.
    public var hasPending: Bool {
        pendingFrame != nil
    }
    
    /// Initialize a new frame queue.
    public init() {}
    
    /// Enqueue a frame for processing.
    ///
    /// If inference is busy and a frame is already pending, the old pending
    /// frame is replaced (dropped) and droppedFrames is incremented.
    ///
    /// - Parameters:
    ///   - rgb: RGB888 pixel data (width * height * 3 bytes)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// - Returns: `true` if no frame was dropped, `false` if a pending frame was replaced
    @discardableResult
    public func enqueue(rgb: Data, width: Int, height: Int) -> Bool {
        let dropped = _isProcessing && pendingFrame != nil
        if dropped {
            _droppedFrames += 1
        }
        pendingFrame = FrameData(rgb: rgb, width: width, height: height)
        return !dropped
    }
    
    /// Dequeue the next frame for processing.
    ///
    /// Returns `nil` if no frame is pending or inference is already running.
    /// Sets isProcessing to `true` on success.
    ///
    /// - Returns: The next frame to process, or `nil` if unavailable
    public func dequeue() -> FrameData? {
        guard let frame = pendingFrame, !_isProcessing else {
            return nil
        }
        pendingFrame = nil
        _isProcessing = true
        return frame
    }
    
    /// Mark current inference as done. Allows next dequeue().
    ///
    /// Must be called after processing each frame to allow the queue to
    /// continue.
    public func markDone() {
        _isProcessing = false
    }
    
    /// Reset queue state (e.g., when stopping camera stream).
    ///
    /// Clears the pending frame and processing flag but preserves
    /// droppedFrames since it is cumulative for trace analysis.
    public func reset() {
        pendingFrame = nil
        _isProcessing = false
        // Note: droppedFrames is NOT reset - it's cumulative for analysis
    }
    
    /// Reset the dropped frames counter.
    ///
    /// Use at the start of a new soak test session or benchmark run.
    public func resetCounters() {
        _droppedFrames = 0
    }
}