/**
 * Camera Utilities for Edge Veda Swift SDK
 *
 * Pixel-format converters matching Flutter's CameraUtils:
 * - BGRA → RGB (iOS camera format via AVFoundation)
 * - YUV420 → RGB (Android-style / BT.601 coefficients)
 * - Nearest-neighbor resize
 *
 * Uses Accelerate.framework (vImage) where available for optimal performance.
 */

import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Camera pixel-format conversion and image resizing utilities.
///
/// These helpers convert raw camera frame buffers into the RGB888 format
/// expected by the vision inference pipeline.
public enum CameraUtils {

    // MARK: - BGRA → RGB

    /// Convert BGRA8888 pixel data to RGB888.
    ///
    /// iOS cameras (via AVFoundation) typically deliver frames in
    /// `kCVPixelFormatType_32BGRA`. This function strips the alpha channel
    /// and reorders B-G-R-A → R-G-B.
    ///
    /// - Parameters:
    ///   - bgra: Raw BGRA pixel data (width × height × 4 bytes).
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    /// - Returns: RGB888 data (width × height × 3 bytes).
    /// - Throws: `EdgeVedaError.invalidInput` if buffer size is wrong.
    public static func convertBgraToRgb(
        _ bgra: Data,
        width: Int,
        height: Int
    ) throws -> Data {
        let expectedSize = width * height * 4
        guard bgra.count >= expectedSize else {
            throw EdgeVedaError.invalidConfig(reason:
                "BGRA buffer too small: expected \(expectedSize) bytes, got \(bgra.count)"
            )
        }

        let pixelCount = width * height
        var rgb = Data(count: pixelCount * 3)

        bgra.withUnsafeBytes { srcPtr in
            rgb.withUnsafeMutableBytes { dstPtr in
                let src = srcPtr.bindMemory(to: UInt8.self).baseAddress!
                let dst = dstPtr.bindMemory(to: UInt8.self).baseAddress!

                for i in 0..<pixelCount {
                    let srcOff = i * 4
                    let dstOff = i * 3
                    dst[dstOff]     = src[srcOff + 2] // R (from BGRA position 2)
                    dst[dstOff + 1] = src[srcOff + 1] // G (from BGRA position 1)
                    dst[dstOff + 2] = src[srcOff]     // B (from BGRA position 0)
                }
            }
        }

        return rgb
    }

    // MARK: - YUV420 → RGB (BT.601)

    /// Convert YUV420 (NV12 / NV21 style) planar data to RGB888 using BT.601 coefficients.
    ///
    /// This matches the conversion used by Flutter's `CameraUtils` for Android camera
    /// frames (`ImageFormat.YUV_420_888`).
    ///
    /// BT.601 coefficients:
    /// ```
    /// R = Y + 1.402  × (V - 128)
    /// G = Y - 0.3441 × (U - 128) - 0.7141 × (V - 128)
    /// B = Y + 1.772  × (U - 128)
    /// ```
    ///
    /// - Parameters:
    ///   - yPlane: Luminance plane (width × height bytes).
    ///   - uPlane: Chrominance U plane (width/2 × height/2 bytes).
    ///   - vPlane: Chrominance V plane (width/2 × height/2 bytes).
    ///   - width: Frame width in pixels (must be even).
    ///   - height: Frame height in pixels (must be even).
    /// - Returns: RGB888 data (width × height × 3 bytes).
    /// - Throws: `EdgeVedaError.invalidInput` if buffer sizes are wrong.
    public static func convertYuv420ToRgb(
        yPlane: Data,
        uPlane: Data,
        vPlane: Data,
        width: Int,
        height: Int
    ) throws -> Data {
        let expectedY = width * height
        let expectedUV = (width / 2) * (height / 2)

        guard yPlane.count >= expectedY else {
            throw EdgeVedaError.invalidConfig(reason:
                "Y plane too small: expected \(expectedY), got \(yPlane.count)"
            )
        }
        guard uPlane.count >= expectedUV else {
            throw EdgeVedaError.invalidConfig(reason:
                "U plane too small: expected \(expectedUV), got \(uPlane.count)"
            )
        }
        guard vPlane.count >= expectedUV else {
            throw EdgeVedaError.invalidConfig(reason:
                "V plane too small: expected \(expectedUV), got \(vPlane.count)"
            )
        }

        let pixelCount = width * height
        var rgb = Data(count: pixelCount * 3)

        yPlane.withUnsafeBytes { yPtr in
            uPlane.withUnsafeBytes { uPtr in
                vPlane.withUnsafeBytes { vPtr in
                    rgb.withUnsafeMutableBytes { dstPtr in
                        let y = yPtr.bindMemory(to: UInt8.self).baseAddress!
                        let u = uPtr.bindMemory(to: UInt8.self).baseAddress!
                        let v = vPtr.bindMemory(to: UInt8.self).baseAddress!
                        let dst = dstPtr.bindMemory(to: UInt8.self).baseAddress!

                        let uvWidth = width / 2

                        for row in 0..<height {
                            for col in 0..<width {
                                let yIdx = row * width + col
                                let uvIdx = (row / 2) * uvWidth + (col / 2)

                                let yVal = Float(y[yIdx])
                                let uVal = Float(u[uvIdx]) - 128.0
                                let vVal = Float(v[uvIdx]) - 128.0

                                let r = yVal + 1.402 * vVal
                                let g = yVal - 0.3441 * uVal - 0.7141 * vVal
                                let b = yVal + 1.772 * uVal

                                let dstOff = yIdx * 3
                                dst[dstOff]     = clampToByte(r)
                                dst[dstOff + 1] = clampToByte(g)
                                dst[dstOff + 2] = clampToByte(b)
                            }
                        }
                    }
                }
            }
        }

        return rgb
    }

    // MARK: - Nearest-Neighbor Resize

    /// Resize RGB888 image data using nearest-neighbor interpolation.
    ///
    /// This is a fast, low-quality resize suitable for preparing camera frames
    /// for vision model input where sub-pixel accuracy is not critical.
    ///
    /// - Parameters:
    ///   - rgb: Source RGB888 data (srcWidth × srcHeight × 3 bytes).
    ///   - srcWidth: Source width in pixels.
    ///   - srcHeight: Source height in pixels.
    ///   - dstWidth: Destination width in pixels.
    ///   - dstHeight: Destination height in pixels.
    /// - Returns: Resized RGB888 data (dstWidth × dstHeight × 3 bytes).
    /// - Throws: `EdgeVedaError.invalidInput` if buffer size is wrong.
    public static func resizeRgb(
        _ rgb: Data,
        srcWidth: Int,
        srcHeight: Int,
        dstWidth: Int,
        dstHeight: Int
    ) throws -> Data {
        let expectedSize = srcWidth * srcHeight * 3
        guard rgb.count >= expectedSize else {
            throw EdgeVedaError.invalidConfig(reason:
                "RGB buffer too small: expected \(expectedSize) bytes, got \(rgb.count)"
            )
        }

        guard dstWidth > 0, dstHeight > 0 else {
            throw EdgeVedaError.invalidConfig(reason:
                "Destination dimensions must be positive: \(dstWidth)×\(dstHeight)"
            )
        }

        // Short-circuit: no resize needed
        if srcWidth == dstWidth && srcHeight == dstHeight {
            return rgb
        }

        var result = Data(count: dstWidth * dstHeight * 3)

        rgb.withUnsafeBytes { srcPtr in
            result.withUnsafeMutableBytes { dstPtr in
                let src = srcPtr.bindMemory(to: UInt8.self).baseAddress!
                let dst = dstPtr.bindMemory(to: UInt8.self).baseAddress!

                let xRatio = Float(srcWidth) / Float(dstWidth)
                let yRatio = Float(srcHeight) / Float(dstHeight)

                for dstY in 0..<dstHeight {
                    let srcY = min(Int(Float(dstY) * yRatio), srcHeight - 1)
                    for dstX in 0..<dstWidth {
                        let srcX = min(Int(Float(dstX) * xRatio), srcWidth - 1)

                        let srcOff = (srcY * srcWidth + srcX) * 3
                        let dstOff = (dstY * dstWidth + dstX) * 3

                        dst[dstOff]     = src[srcOff]
                        dst[dstOff + 1] = src[srcOff + 1]
                        dst[dstOff + 2] = src[srcOff + 2]
                    }
                }
            }
        }

        return result
    }

    // MARK: - Helpers

    /// Clamp a float to the 0-255 UInt8 range.
    @inline(__always)
    private static func clampToByte(_ value: Float) -> UInt8 {
        return UInt8(max(0, min(255, value)))
    }
}