/**
 * CameraUtils — Pixel-format conversion utilities for the Web SDK.
 *
 * Provides BGRA→RGB, YUV420→RGB (BT.601), and nearest-neighbor resize.
 * All methods operate on Uint8Array buffers and are pure functions
 * (no Canvas dependency) so they work in Web Workers too.
 */

/** Clamp a number to [0, 255] and truncate to integer. */
function clampToByte(v: number): number {
  return v < 0 ? 0 : v > 255 ? 255 : v | 0;
}

export class CameraUtils {
  /**
   * Convert a BGRA buffer to packed RGB.
   *
   * @param bgra  Source buffer — length must equal `width * height * 4`.
   * @param width  Image width in pixels.
   * @param height Image height in pixels.
   * @returns Uint8Array of length `width * height * 3`.
   */
  static convertBgraToRgb(
    bgra: Uint8Array,
    width: number,
    height: number,
  ): Uint8Array {
    const pixelCount = width * height;
    const expectedLen = pixelCount * 4;
    if (bgra.length !== expectedLen) {
      throw new Error(
        `CameraUtils.convertBgraToRgb: expected ${expectedLen} bytes, got ${bgra.length}`,
      );
    }

    const rgb = new Uint8Array(pixelCount * 3);
    let srcIdx = 0;
    let dstIdx = 0;

    for (let i = 0; i < pixelCount; i++) {
      // BGRA → RGB: swap B and R, drop A
      rgb[dstIdx] = bgra[srcIdx + 2]; // R
      rgb[dstIdx + 1] = bgra[srcIdx + 1]; // G
      rgb[dstIdx + 2] = bgra[srcIdx]; // B
      srcIdx += 4;
      dstIdx += 3;
    }

    return rgb;
  }

  /**
   * Convert planar YUV 420 to packed RGB using BT.601 coefficients.
   *
   * Chroma planes are half-resolution in both dimensions.
   * Coefficients:
   *   R = Y + 1.402  × (V − 128)
   *   G = Y − 0.3441 × (U − 128) − 0.7141 × (V − 128)
   *   B = Y + 1.772  × (U − 128)
   *
   * @param yPlane  Luma plane — length `width * height`.
   * @param uPlane  Cb plane  — length `(width >> 1) * (height >> 1)`.
   * @param vPlane  Cr plane  — length `(width >> 1) * (height >> 1)`.
   * @param width   Image width (must be even).
   * @param height  Image height (must be even).
   * @returns Uint8Array of length `width * height * 3`.
   */
  static convertYuv420ToRgb(
    yPlane: Uint8Array,
    uPlane: Uint8Array,
    vPlane: Uint8Array,
    width: number,
    height: number,
  ): Uint8Array {
    const pixelCount = width * height;
    const uvWidth = width >> 1;
    const uvHeight = height >> 1;

    if (yPlane.length !== pixelCount) {
      throw new Error(
        `CameraUtils.convertYuv420ToRgb: yPlane length ${yPlane.length} != ${pixelCount}`,
      );
    }
    if (uPlane.length !== uvWidth * uvHeight) {
      throw new Error(
        `CameraUtils.convertYuv420ToRgb: uPlane length ${uPlane.length} != ${uvWidth * uvHeight}`,
      );
    }
    if (vPlane.length !== uvWidth * uvHeight) {
      throw new Error(
        `CameraUtils.convertYuv420ToRgb: vPlane length ${vPlane.length} != ${uvWidth * uvHeight}`,
      );
    }

    const rgb = new Uint8Array(pixelCount * 3);
    let dstIdx = 0;

    for (let row = 0; row < height; row++) {
      const uvRow = row >> 1;
      for (let col = 0; col < width; col++) {
        const uvCol = col >> 1;

        const y = yPlane[row * width + col];
        const u = uPlane[uvRow * uvWidth + uvCol];
        const v = vPlane[uvRow * uvWidth + uvCol];

        const uShifted = u - 128;
        const vShifted = v - 128;

        rgb[dstIdx] = clampToByte(y + 1.402 * vShifted);
        rgb[dstIdx + 1] = clampToByte(y - 0.3441 * uShifted - 0.7141 * vShifted);
        rgb[dstIdx + 2] = clampToByte(y + 1.772 * uShifted);
        dstIdx += 3;
      }
    }

    return rgb;
  }

  /**
   * Nearest-neighbour resize of a packed RGB buffer.
   *
   * @param rgb   Source buffer — length `srcWidth * srcHeight * 3`.
   * @param srcWidth  Source width.
   * @param srcHeight Source height.
   * @param dstWidth  Target width.
   * @param dstHeight Target height.
   * @returns Uint8Array of length `dstWidth * dstHeight * 3`.
   */
  static resizeRgb(
    rgb: Uint8Array,
    srcWidth: number,
    srcHeight: number,
    dstWidth: number,
    dstHeight: number,
  ): Uint8Array {
    const expectedLen = srcWidth * srcHeight * 3;
    if (rgb.length !== expectedLen) {
      throw new Error(
        `CameraUtils.resizeRgb: expected ${expectedLen} bytes, got ${rgb.length}`,
      );
    }

    const out = new Uint8Array(dstWidth * dstHeight * 3);
    const xRatio = srcWidth / dstWidth;
    const yRatio = srcHeight / dstHeight;

    let dstIdx = 0;

    for (let dy = 0; dy < dstHeight; dy++) {
      const srcY = (dy * yRatio) | 0;
      for (let dx = 0; dx < dstWidth; dx++) {
        const srcX = (dx * xRatio) | 0;
        const srcIdx = (srcY * srcWidth + srcX) * 3;
        out[dstIdx] = rgb[srcIdx];
        out[dstIdx + 1] = rgb[srcIdx + 1];
        out[dstIdx + 2] = rgb[srcIdx + 2];
        dstIdx += 3;
      }
    }

    return out;
  }
}