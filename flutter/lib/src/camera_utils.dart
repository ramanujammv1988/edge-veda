/// Camera frame format conversion utilities for Edge Veda Vision
///
/// Converts platform-specific camera frame formats to RGB888
/// expected by ev_vision_describe().
///
/// iOS camera frames: BGRA8888
/// Android camera frames: YUV420 (NV21)
library;

import 'dart:typed_data';

/// Utility class for converting camera image formats to RGB888
///
/// These conversions are pure Dart with no native dependencies,
/// so they can be used without importing any camera package.
///
/// Example:
/// ```dart
/// // iOS: Convert BGRA camera frame to RGB
/// final rgb = CameraUtils.convertBgraToRgb(bgraBytes, 640, 480);
///
/// // Android: Convert YUV420 camera frame to RGB
/// final rgb = CameraUtils.convertYuv420ToRgb(
///   yPlane, uPlane, vPlane, 640, 480,
///   yRowStride, uvRowStride, uvPixelStride,
/// );
///
/// // Then describe the image
/// final description = await edgeVeda.describeImage(rgb, width: 640, height: 480);
/// ```
class CameraUtils {
  CameraUtils._(); // Prevent instantiation

  /// Convert BGRA8888 bytes (iOS camera format) to RGB888
  ///
  /// [bgra] is the raw BGRA pixel data from CameraImage.planes[0].bytes
  /// [width] and [height] are the image dimensions
  /// Returns RGB888 bytes (width * height * 3)
  static Uint8List convertBgraToRgb(Uint8List bgra, int width, int height) {
    final expectedLength = width * height * 4;
    if (bgra.length < expectedLength) {
      throw ArgumentError(
        'BGRA buffer too small: expected $expectedLength bytes '
        '(${width}x${height}x4), got ${bgra.length}',
      );
    }

    final rgb = Uint8List(width * height * 3);
    for (int i = 0, j = 0; i < expectedLength && j < rgb.length; i += 4, j += 3) {
      rgb[j] = bgra[i + 2];     // R (from B position in BGRA)
      rgb[j + 1] = bgra[i + 1]; // G
      rgb[j + 2] = bgra[i];     // B (from R position in BGRA)
      // Alpha (bgra[i + 3]) is discarded
    }
    return rgb;
  }

  /// Convert YUV420 (NV21) camera frames (Android) to RGB888
  ///
  /// [yPlane] is the Y (luminance) plane bytes
  /// [uPlane] is the U (chrominance) plane bytes
  /// [vPlane] is the V (chrominance) plane bytes
  /// [width] and [height] are image dimensions
  /// [yRowStride] is the row stride for the Y plane
  /// [uvRowStride] is the row stride for UV planes
  /// [uvPixelStride] is the pixel stride for UV planes
  ///
  /// Returns RGB888 bytes (width * height * 3)
  static Uint8List convertYuv420ToRgb(
    Uint8List yPlane,
    Uint8List uPlane,
    Uint8List vPlane,
    int width,
    int height,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
  ) {
    final rgb = Uint8List(width * height * 3);
    int rgbIndex = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x;
        final uvIndex = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;

        final yVal = yPlane[yIndex] & 0xFF;
        final uVal = (uvIndex < uPlane.length ? uPlane[uvIndex] : 128) & 0xFF;
        final vVal = (uvIndex < vPlane.length ? vPlane[uvIndex] : 128) & 0xFF;

        // YUV to RGB conversion (BT.601)
        final r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
        final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round().clamp(0, 255);
        final b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

        rgb[rgbIndex++] = r;
        rgb[rgbIndex++] = g;
        rgb[rgbIndex++] = b;
      }
    }

    return rgb;
  }

  /// Resize RGB888 image to target dimensions using nearest-neighbor
  ///
  /// VLM models may expect specific input sizes. This provides a fast
  /// resize for camera frames. For SmolVLM2, the model handles arbitrary
  /// sizes via mtmd, so this is optional.
  ///
  /// [rgb] is the source RGB888 pixel data
  /// [srcWidth] and [srcHeight] are the source dimensions
  /// [dstWidth] and [dstHeight] are the target dimensions
  /// Returns resized RGB888 bytes (dstWidth * dstHeight * 3)
  static Uint8List resizeRgb(
    Uint8List rgb,
    int srcWidth,
    int srcHeight,
    int dstWidth,
    int dstHeight,
  ) {
    final expectedLength = srcWidth * srcHeight * 3;
    if (rgb.length < expectedLength) {
      throw ArgumentError(
        'RGB buffer too small: expected $expectedLength bytes '
        '(${srcWidth}x${srcHeight}x3), got ${rgb.length}',
      );
    }

    final dst = Uint8List(dstWidth * dstHeight * 3);

    for (int y = 0; y < dstHeight; y++) {
      final srcY = (y * srcHeight ~/ dstHeight).clamp(0, srcHeight - 1);
      for (int x = 0; x < dstWidth; x++) {
        final srcX = (x * srcWidth ~/ dstWidth).clamp(0, srcWidth - 1);
        final srcIdx = (srcY * srcWidth + srcX) * 3;
        final dstIdx = (y * dstWidth + x) * 3;
        dst[dstIdx] = rgb[srcIdx];
        dst[dstIdx + 1] = rgb[srcIdx + 1];
        dst[dstIdx + 2] = rgb[srcIdx + 2];
      }
    }

    return dst;
  }
}
