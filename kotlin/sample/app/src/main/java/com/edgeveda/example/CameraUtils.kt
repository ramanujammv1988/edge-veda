package com.edgeveda.example

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Camera utility helpers for the VisionScreen.
 *
 * Converts raw YUV 420 plane buffers (from CameraX ImageAnalysis) to a packed
 * RGB888 byte array suitable for passing to VisionWorker.describeFrame().
 */
object CameraUtils {

    /**
     * Convert YUV 420 (3-plane) buffers to an interleaved RGB888 byte array.
     *
     * CameraX delivers frames in YUV_420_888 format with separate Y, U, V planes.
     * The U and V planes are subsampled 2× in both dimensions.
     *
     * @param yBytes  Luminance plane — one byte per pixel
     * @param uBytes  Cb/U plane — one byte per 2×2 block
     * @param vBytes  Cr/V plane — one byte per 2×2 block
     * @param width   Frame width in pixels
     * @param height  Frame height in pixels
     * @return Packed RGB888 byte array of length width × height × 3
     */
    fun convertYuv420ToRgb(
        yBytes: ByteArray,
        uBytes: ByteArray,
        vBytes: ByteArray,
        width: Int,
        height: Int,
    ): ByteArray {
        val rgb = ByteArray(width * height * 3)
        var rgbIndex = 0

        for (row in 0 until height) {
            for (col in 0 until width) {
                val yIndex = row * width + col
                val uvIndex = (row / 2) * (width / 2) + (col / 2)

                val y = (yBytes[yIndex].toInt() and 0xFF) - 16
                val u = (uBytes[uvIndex].toInt() and 0xFF) - 128
                val v = (vBytes[uvIndex].toInt() and 0xFF) - 128

                val r = (1.164f * y + 1.596f * v).toInt().coerceIn(0, 255)
                val g = (1.164f * y - 0.392f * u - 0.813f * v).toInt().coerceIn(0, 255)
                val b = (1.164f * y + 2.017f * u).toInt().coerceIn(0, 255)

                rgb[rgbIndex++] = r.toByte()
                rgb[rgbIndex++] = g.toByte()
                rgb[rgbIndex++] = b.toByte()
            }
        }

        return rgb
    }
}

/**
 * Single-slot frame queue with drop-newest backpressure.
 *
 * When a frame arrives while inference is still running the previous one, the
 * new frame replaces the pending slot (drop-newest strategy). This prevents
 * memory unbounded growth while keeping the most recent frame available.
 *
 * Usage:
 * ```kotlin
 * val queue = FrameQueue()
 *
 * // Analyzer thread:
 * queue.enqueue(rgb, width, height)
 *
 * // Coroutine on Dispatchers.Default:
 * val frame = queue.dequeue() ?: return
 * processFrame(frame.rgb, frame.width, frame.height)
 * queue.markDone()
 * ```
 */
class FrameQueue {

    data class Frame(val rgb: ByteArray, val width: Int, val height: Int)

    @Volatile private var pending: Frame? = null
    private val processing = AtomicBoolean(false)

    /**
     * Enqueue a new frame. If a previous unprocessed frame exists it is silently replaced.
     */
    fun enqueue(rgb: ByteArray, width: Int, height: Int) {
        pending = Frame(rgb, width, height)
    }

    /**
     * Dequeue the pending frame for processing.
     *
     * Returns null if another frame is already being processed or if no frame
     * is queued. On non-null return the caller **must** call [markDone] when finished.
     */
    fun dequeue(): Frame? {
        return if (processing.compareAndSet(false, true)) {
            pending?.also { pending = null } ?: run {
                processing.set(false)
                null
            }
        } else null
    }

    /** Signal that the current frame has been fully processed. Must be called after [dequeue]. */
    fun markDone() {
        processing.set(false)
    }
}
