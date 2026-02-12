/**
 * Camera Utilities for Edge Veda React Native SDK
 *
 * Pixel-format converters matching Flutter's CameraUtils:
 * - BGRA → RGB (iOS camera format)
 * - YUV420 → RGB (Android camera format, BT.601 coefficients)
 * - Nearest-neighbor resize
 *
 * Uses native bridge when available for performance, with
 * pure-JS fallbacks for all operations.
 */

/**
 * Camera pixel-format conversion and image resizing utilities.
 *
 * These helpers convert raw camera frame buffers into the RGB888 format
 * expected by the vision inference pipeline.
 */
export class CameraUtils {
  // ── BGRA → RGB ──────────────────────────────────────────────────────

  /**
   * Convert BGRA8888 pixel data to RGB888.
   *
   * iOS cameras (via AVFoundation) typically deliver frames in
   * kCVPixelFormatType_32BGRA. This function strips the alpha channel
   * and reorders B-G-R-A → R-G-B.
   *
   * @param bgra - Raw BGRA pixel data (width × height × 4 bytes).
   * @param width - Frame width in pixels.
   * @param height - Frame height in pixels.
   * @returns RGB888 data (width × height × 3 bytes).
   * @throws Error if buffer size is wrong.
   */
  static convertBgraToRgb(
    bgra: Uint8Array,
    width: number,
    height: number,
  ): Uint8Array {
    const expectedSize = width * height * 4;
    if (bgra.length < expectedSize) {
      throw new Error(
        `BGRA buffer too small: expected ${expectedSize} bytes, got ${bgra.length}`,
      );
    }

    const pixelCount = width * height;
    const rgb = new Uint8Array(pixelCount * 3);

    for (let i = 0; i < pixelCount; i++) {
      const srcOff = i * 4;
      const dstOff = i * 3;
      rgb[dstOff] = bgra[srcOff + 2]; // R (from BGRA position 2)
      rgb[dstOff + 1] = bgra[srcOff + 1]; // G (from BGRA position 1)
      rgb[dstOff + 2] = bgra[srcOff]; // B (from BGRA position 0)
    }

    return rgb;
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
   * @param yPlane - Luminance plane (width × height bytes).
   * @param uPlane - Chrominance U plane (width/2 × height/2 bytes).
   * @param vPlane - Chrominance V plane (width/2 × height/2 bytes).
   * @param width - Frame width in pixels (must be even).
   * @param height - Frame height in pixels (must be even).
   * @returns RGB888 data (width × height × 3 bytes).
   * @throws Error if buffer sizes are wrong.
   */
  static convertYuv420ToRgb(
    yPlane: Uint8Array,
    uPlane: Uint8Array,
    vPlane: Uint8Array,
    width: number,
    height: number,
  ): Uint8Array {
    const expectedY = width * height;
    const expectedUV = (width >> 1) * (height >> 1);

    if (yPlane.length < expectedY) {
      throw new Error(
        `Y plane too small: expected ${expectedY}, got ${yPlane.length}`,
      );
    }
    if (uPlane.length < expectedUV) {
      throw new Error(
        `U plane too small: expected ${expectedUV}, got ${uPlane.length}`,
      );
    }
    if (vPlane.length < expectedUV) {
      throw new Error(
        `V plane too small: expected ${expectedUV}, got ${vPlane.length}`,
      );
    }

    const pixelCount = width * height;
    const rgb = new Uint8Array(pixelCount * 3);
    const uvWidth = width >> 1;

    for (let row = 0; row < height; row++) {
      for (let col = 0; col < width; col++) {
        const yIdx = row * width + col;
        const uvIdx = (row >> 1) * uvWidth + (col >> 1);

        const yVal = yPlane[yIdx];
        const uVal = uPlane[uvIdx] - 128;
        const vVal = vPlane[uvIdx] - 128;

        const r = yVal + 1.402 * vVal;
        const g = yVal - 0.3441 * uVal - 0.7141 * vVal;
        const b = yVal + 1.772 * uVal;

        const dstOff = yIdx * 3;
        rgb[dstOff] = clampToByte(r);
        rgb[dstOff + 1] = clampToByte(g);
        rgb[dstOff + 2] = clampToByte(b);
      }
    }

    return rgb;
  }

  // ── Nearest-Neighbor Resize ─────────────────────────────────────────

  /**
   * Resize RGB888 image data using nearest-neighbor interpolation.
   *
   * A fast, low-quality resize suitable for preparing camera frames
   * for vision model input where sub-pixel accuracy is not critical.
   *
   * @param rgb - Source RGB888 data (srcWidth × srcHeight × 3 bytes).
   * @param srcWidth - Source width in pixels.
   * @param srcHeight - Source height in pixels.
   * @param dstWidth - Destination width in pixels.
   * @param dstHeight - Destination height in pixels.
   * @returns Resized RGB888 data (dstWidth × dstHeight × 3 bytes).
   * @throws Error if buffer size is wrong or dimensions invalid.
   */
  static resizeRgb(
    rgb: Uint8Array,
    srcWidth: number,
    srcHeight: number,
    dstWidth: number,
    dstHeight: number,
  ): Uint8Array {
    const expectedSize = srcWidth * srcHeight * 3;
    if (rgb.length < expectedSize) {
      throw new Error(
        `RGB buffer too small: expected ${expectedSize} bytes, got ${rgb.length}`,
      );
    }
    if (dstWidth <= 0 || dstHeight <= 0) {
      throw new Error(
        `Destination dimensions must be positive: ${dstWidth}×${dstHeight}`,
      );
    }

    // Short-circuit: no resize needed
    if (srcWidth === dstWidth && srcHeight === dstHeight) {
      return new Uint8Array(rgb);
    }

    const result = new Uint8Array(dstWidth * dstHeight * 3);
    const xRatio = srcWidth / dstWidth;
    const yRatio = srcHeight / dstHeight;

    for (let dstY = 0; dstY < dstHeight; dstY++) {
      const srcY = Math.min(Math.floor(dstY * yRatio), srcHeight - 1);
      for (let dstX = 0; dstX < dstWidth; dstX++) {
        const srcX = Math.min(Math.floor(dstX * xRatio), srcWidth - 1);

        const srcOff = (srcY * srcWidth + srcX) * 3;
        const dstOff = (dstY * dstWidth + dstX) * 3;

        result[dstOff] = rgb[srcOff];
        result[dstOff + 1] = rgb[srcOff + 1];
        result[dstOff + 2] = rgb[srcOff + 2];
      }
    }

    return result;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────

/** Clamp a number to the 0–255 byte range. */
function clampToByte(value: number): number {
  return value < 0 ? 0 : value > 255 ? 255 : value | 0;
}