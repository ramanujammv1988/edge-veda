/**
 * Camera Utilities for Edge Veda Kotlin SDK
 *
 * Pixel-format converters matching Flutter's CameraUtils:
 * - BGRA → RGB (non-standard sources)
 * - YUV420 → RGB (Android camera ImageFormat.YUV_420_888, BT.601 coefficients)
 * - Nearest-neighbor resize
 */
package com.edgeveda.sdk

/**
 * Camera pixel-format conversion and image resizing utilities.
 *
 * These helpers convert raw camera frame buffers into the RGB888 format
 * expected by the vision inference pipeline.
 */
object CameraUtils {

    // ── BGRA → RGB ──────────────────────────────────────────────────────

    /**
     * Convert BGRA8888 pixel data to RGB888.
     *
     * Strips the alpha channel and reorders B-G-R-A → R-G-B.
     *
     * @param bgra Raw BGRA pixel data (width × height × 4 bytes).
     * @param width Frame width in pixels.
     * @param height Frame height in pixels.
     * @return RGB888 data (width × height × 3 bytes).
     * @throws IllegalArgumentException if buffer size is wrong.
     */
    fun convertBgraToRgb(bgra: ByteArray, width: Int, height: Int): ByteArray {
        val expectedSize = width * height * 4
        require(bgra.size >= expectedSize) {
            "BGRA buffer too small: expected $expectedSize bytes, got ${bgra.size}"
        }

        val pixelCount = width * height
        val rgb = ByteArray(pixelCount * 3)

        for (i in 0 until pixelCount) {
            val srcOff = i * 4
            val dstOff = i * 3
            rgb[dstOff]     = bgra[srcOff + 2] // R (from BGRA position 2)
            rgb[dstOff + 1] = bgra[srcOff + 1] // G (from BGRA position 1)
            rgb[dstOff + 2] = bgra[srcOff]     // B (from BGRA position 0)
        }

        return rgb
    }

    // ── YUV420 → RGB (BT.601) ───────────────────────────────────────────

    /**
     * Convert YUV420 planar data to RGB888 using BT.601 coefficients.
     *
     * This matches the conversion used by Flutter's `CameraUtils` for Android
     * camera frames (`ImageFormat.YUV_420_888`).
     *
     * BT.601 coefficients:
     * ```
     * R = Y + 1.402  × (V - 128)
     * G = Y - 0.3441 × (U - 128) - 0.7141 × (V - 128)
     * B = Y + 1.772  × (U - 128)
     * ```
     *
     * @param yPlane Luminance plane (width × height bytes).
     * @param uPlane Chrominance U plane (width/2 × height/2 bytes).
     * @param vPlane Chrominance V plane (width/2 × height/2 bytes).
     * @param width Frame width in pixels (must be even).
     * @param height Frame height in pixels (must be even).
     * @return RGB888 data (width × height × 3 bytes).
     * @throws IllegalArgumentException if buffer sizes are wrong.
     */
    fun convertYuv420ToRgb(
        yPlane: ByteArray,
        uPlane: ByteArray,
        vPlane: ByteArray,
        width: Int,
        height: Int
    ): ByteArray {
        val expectedY = width * height
        val expectedUV = (width / 2) * (height / 2)

        require(yPlane.size >= expectedY) {
            "Y plane too small: expected $expectedY, got ${yPlane.size}"
        }
        require(uPlane.size >= expectedUV) {
            "U plane too small: expected $expectedUV, got ${uPlane.size}"
        }
        require(vPlane.size >= expectedUV) {
            "V plane too small: expected $expectedUV, got ${vPlane.size}"
        }

        val pixelCount = width * height
        val rgb = ByteArray(pixelCount * 3)
        val uvWidth = width / 2

        for (row in 0 until height) {
            for (col in 0 until width) {
                val yIdx = row * width + col
                val uvIdx = (row / 2) * uvWidth + (col / 2)

                val yVal = (yPlane[yIdx].toInt() and 0xFF).toFloat()
                val uVal = (uPlane[uvIdx].toInt() and 0xFF).toFloat() - 128f
                val vVal = (vPlane[uvIdx].toInt() and 0xFF).toFloat() - 128f

                val r = yVal + 1.402f * vVal
                val g = yVal - 0.3441f * uVal - 0.7141f * vVal
                val b = yVal + 1.772f * uVal

                val dstOff = yIdx * 3
                rgb[dstOff]     = clampToByte(r)
                rgb[dstOff + 1] = clampToByte(g)
                rgb[dstOff + 2] = clampToByte(b)
            }
        }

        return rgb
    }

    // ── Nearest-Neighbor Resize ─────────────────────────────────────────

    /**
     * Resize RGB888 image data using nearest-neighbor interpolation.
     *
     * A fast, low-quality resize suitable for preparing camera frames
     * for vision model input where sub-pixel accuracy is not critical.
     *
     * @param rgb Source RGB888 data (srcWidth × srcHeight × 3 bytes).
     * @param srcWidth Source width in pixels.
     * @param srcHeight Source height in pixels.
     * @param dstWidth Destination width in pixels.
     * @param dstHeight Destination height in pixels.
     * @return Resized RGB888 data (dstWidth × dstHeight × 3 bytes).
     * @throws IllegalArgumentException if buffer size is wrong or dimensions invalid.
     */
    fun resizeRgb(
        rgb: ByteArray,
        srcWidth: Int,
        srcHeight: Int,
        dstWidth: Int,
        dstHeight: Int
    ): ByteArray {
        val expectedSize = srcWidth * srcHeight * 3
        require(rgb.size >= expectedSize) {
            "RGB buffer too small: expected $expectedSize bytes, got ${rgb.size}"
        }
        require(dstWidth > 0 && dstHeight > 0) {
            "Destination dimensions must be positive: ${dstWidth}×${dstHeight}"
        }

        // Short-circuit: no resize needed
        if (srcWidth == dstWidth && srcHeight == dstHeight) {
            return rgb.copyOf()
        }

        val result = ByteArray(dstWidth * dstHeight * 3)
        val xRatio = srcWidth.toFloat() / dstWidth.toFloat()
        val yRatio = srcHeight.toFloat() / dstHeight.toFloat()

        for (dstY in 0 until dstHeight) {
            val srcY = minOf((dstY * yRatio).toInt(), srcHeight - 1)
            for (dstX in 0 until dstWidth) {
                val srcX = minOf((dstX * xRatio).toInt(), srcWidth - 1)

                val srcOff = (srcY * srcWidth + srcX) * 3
                val dstOff = (dstY * dstWidth + dstX) * 3

                result[dstOff]     = rgb[srcOff]
                result[dstOff + 1] = rgb[srcOff + 1]
                result[dstOff + 2] = rgb[srcOff + 2]
            }
        }

        return result
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    /** Clamp a float to the 0–255 byte range. */
    private fun clampToByte(value: Float): Byte {
        return value.coerceIn(0f, 255f).toInt().toByte()
    }
}