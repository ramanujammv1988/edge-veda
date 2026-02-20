import 'package:flutter/services.dart';

/// Platform channel helper for Android device detection.
///
/// Uses a MethodChannel to query Build.MODEL, Build.HARDWARE, etc. from
/// the Android plugin. Falls back gracefully when the channel is unavailable
/// (e.g. on iOS/macOS or when the native side hasn't registered the handler).
class DeviceInfoAndroid {
  DeviceInfoAndroid._();

  static const _channel = MethodChannel('com.edgeveda.edge_veda/device_info');

  /// Get the device model name (e.g. "Pixel 8 Pro").
  static Future<String> getDeviceModel() async {
    try {
      final result = await _channel.invokeMethod<String>('getDeviceModel');
      return result ?? 'Unknown';
    } on MissingPluginException {
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  /// Get the chip/SoC name (e.g. "Tensor G3").
  static Future<String> getChipName() async {
    try {
      final result = await _channel.invokeMethod<String>('getChipName');
      return result ?? 'Unknown';
    } on MissingPluginException {
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  /// Get total device memory in bytes.
  static Future<int> getTotalMemory() async {
    try {
      final result = await _channel.invokeMethod<int>('getTotalMemory');
      return result ?? 0;
    } on MissingPluginException {
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Check if the device has a neural accelerator (NNAPI on Android).
  static Future<bool> hasNeuralEngine() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasNeuralEngine');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
