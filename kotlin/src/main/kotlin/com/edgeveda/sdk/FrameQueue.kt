package com.edgeveda.sdk

/**
 * Bounded frame queue with drop-newest backpressure policy.
 *
 * When inference is busy and a new frame arrives, the pending frame is
 * replaced (not accumulated). This ensures vision descriptions stay
 * current with the camera feed rather than falling behind.
 *
 * Design decisions:
 * - Drop-newest policy: when processing is busy, new frames REPLACE the
 *   pending slot (not queue up)
 * - Only 1 pending slot (capacity 1): at most 1 frame waits while inference runs
 * - droppedFrames is cumulative across the session for performance analysis
 * - reset() clears frame state but preserves drop counter
 * - Thread-safe using synchronized blocks
 *
 * Usage:
 * 1. Camera callback calls enqueue() with each frame
 * 2. Processing loop calls dequeue() to get next frame
 * 3. After inference completes, call markDone()
 * 4. Check droppedFrames to track backpressure
 *
 * Example:
 * ```kotlin
 * val queue = FrameQueue()
 *
 * // Camera callback
 * fun onFrame(rgb: ByteArray, width: Int, height: Int) {
 *     val dropped = !queue.enqueue(rgb, width, height)
 *     if (dropped) {
 *         println("Warning: Frame dropped due to backpressure")
 *     }
 * }
 *
 * // Processing loop
 * launch {
 *     while (isActive) {
 *         queue.dequeue()?.let { frame ->
 *             val result = visionWorker.describeFrame(frame)
 *             queue.markDone()
 *         }
 *         delay(10)
 *     }
 * }
 * ```
 */
class FrameQueue {
    private var pendingFrame: FrameData? = null
    private var _isProcessing = false
    private var _droppedFrames = 0

    /**
     * Number of frames dropped due to backpressure (cumulative).
     *
     * This counter is preserved across reset() calls and should only be
     * cleared with resetCounters() at the start of a new test session.
     */
    val droppedFrames: Int
        @Synchronized get() = _droppedFrames

    /**
     * Whether inference is currently processing a frame.
     */
    val isProcessing: Boolean
        @Synchronized get() = _isProcessing

    /**
     * Whether there is a frame waiting to be processed.
     */
    val hasPending: Boolean
        @Synchronized get() = pendingFrame != null

    /**
     * Enqueue a frame for processing.
     *
     * If inference is busy and a frame is already pending, the old pending
     * frame is replaced (dropped) and droppedFrames is incremented.
     *
     * @param rgb RGB888 pixel data (width * height * 3 bytes)
     * @param width Image width in pixels
     * @param height Image height in pixels
     * @return true if no frame was dropped, false if a pending frame was replaced
     */
    @Synchronized
    fun enqueue(rgb: ByteArray, width: Int, height: Int): Boolean {
        val dropped = _isProcessing && pendingFrame != null
        if (dropped) {
            _droppedFrames++
        }
        pendingFrame = FrameData(rgb, width, height)
        return !dropped
    }

    /**
     * Dequeue the next frame for processing.
     *
     * Returns null if no frame is pending or inference is already running.
     * Sets isProcessing to true on success.
     *
     * @return The next frame to process, or null if unavailable
     */
    @Synchronized
    fun dequeue(): FrameData? {
        val frame = pendingFrame
        if (frame == null || _isProcessing) {
            return null
        }
        pendingFrame = null
        _isProcessing = true
        return frame
    }

    /**
     * Mark current inference as done. Allows next dequeue().
     *
     * Must be called after processing each frame to allow the queue to
     * continue.
     */
    @Synchronized
    fun markDone() {
        _isProcessing = false
    }

    /**
     * Reset queue state (e.g., when stopping camera stream).
     *
     * Clears the pending frame and processing flag but preserves
     * droppedFrames since it is cumulative for trace analysis.
     */
    @Synchronized
    fun reset() {
        pendingFrame = null
        _isProcessing = false
        // Note: droppedFrames is NOT reset - it's cumulative for analysis
    }

    /**
     * Reset the dropped frames counter.
     *
     * Use at the start of a new soak test session or benchmark run.
     */
    @Synchronized
    fun resetCounters() {
        _droppedFrames = 0
    }
}