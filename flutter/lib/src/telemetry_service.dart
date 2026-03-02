import 'dart:async';

import 'package:flutter/services.dart';

/// Cross-platform service for querying thermal, battery, and memory telemetry.
///
/// Supported on iOS (Metal), Android (CPU/Vulkan), and macOS. Uses
/// MethodChannel for on-demand polling and EventChannel for push thermal
/// state change notifications. Gracefully returns defaults on unsupported
/// platforms (catches [MissingPluginException]).
class TelemetryService {
  static const _methodChannel = MethodChannel(
    'com.edgeveda.edge_veda/telemetry',
  );
  static const _thermalEventChannel = EventChannel(
    'com.edgeveda.edge_veda/thermal',
  );

  Stream<Map<String, dynamic>>? _thermalStream;

  /// Get current thermal state: 0=nominal, 1=fair, 2=serious, 3=critical.
  ///
  /// On iOS/macOS uses ProcessInfo.thermalState, on Android (API 29+) uses
  /// PowerManager.currentThermalStatus. Returns -1 on unsupported platforms.
  Future<int> getThermalState() async {
    try {
      final result = await _methodChannel.invokeMethod<int>('getThermalState');
      return result ?? -1;
    } on PlatformException {
      return -1;
    } on MissingPluginException {
      return -1; // Unsupported platform
    }
  }

  /// Get current battery level: 0.0 to 1.0.
  ///
  /// Returns -1.0 on error or unknown.
  Future<double> getBatteryLevel() async {
    try {
      final result = await _methodChannel.invokeMethod<double>(
        'getBatteryLevel',
      );
      return result ?? -1.0;
    } on PlatformException {
      return -1.0;
    } on MissingPluginException {
      return -1.0;
    }
  }

  /// Get current battery state: 0=unknown, 1=unplugged, 2=charging, 3=full.
  Future<int> getBatteryState() async {
    try {
      final result = await _methodChannel.invokeMethod<int>('getBatteryState');
      return result ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Get current process RSS (resident set size) in bytes.
  ///
  /// Returns 0 on error.
  Future<int> getMemoryRSS() async {
    try {
      final result = await _methodChannel.invokeMethod<int>('getMemoryRSS');
      return result ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Get available memory in bytes.
  ///
  /// On iOS/macOS uses os_proc_available_memory, on Android uses
  /// ActivityManager.MemoryInfo.availMem. Returns 0 on error.
  Future<int> getAvailableMemory() async {
    try {
      final result = await _methodChannel.invokeMethod<int>(
        'getAvailableMemory',
      );
      return result ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Get free disk space in bytes.
  ///
  /// On iOS/macOS uses NSFileManager, on Android uses StatFs. Returns -1
  /// on unsupported platforms or error.
  Future<int> getFreeDiskSpace() async {
    try {
      final result = await _methodChannel.invokeMethod<int>('getFreeDiskSpace');
      return result ?? -1;
    } on PlatformException {
      return -1;
    } on MissingPluginException {
      return -1;
    }
  }

  /// Whether power-saving mode is enabled.
  ///
  /// On iOS checks Low Power Mode, on Android checks Battery Saver.
  /// Returns false on unsupported platforms.
  Future<bool> isLowPowerMode() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isLowPowerMode');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Get chip/SoC name (e.g. "Snapdragon 845", "Apple A12").
  ///
  /// On Android returns [Build.SOC_MODEL] (API 31+) or [Build.HARDWARE].
  /// On iOS/macOS returns "Apple Silicon". Returns empty string on error.
  Future<String> getChipName() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getChipName');
      return result ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Get total physical RAM in bytes.
  ///
  /// On Android uses [ActivityManager.MemoryInfo.totalMem].
  /// Returns 0 on error.
  Future<int> getTotalMemory() async {
    try {
      final result = await _methodChannel.invokeMethod<int>('getTotalMemory');
      return result ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Whether the device has a dedicated neural engine / NPU.
  ///
  /// Returns true on iOS/macOS (ANE), false on Android.
  Future<bool> hasNeuralEngine() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('hasNeuralEngine');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Get GPU backend label (e.g. "Metal GPU", "Vulkan 1.2", "CPU").
  Future<String> getGpuBackend() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getGpuBackend');
      return result ?? 'CPU';
    } on PlatformException {
      return 'CPU';
    } on MissingPluginException {
      return 'CPU';
    }
  }

  /// Stream of thermal state changes pushed from the native platform.
  ///
  /// Each event is a [Map] with keys:
  /// - `'thermalState'` ([int]): 0=nominal, 1=fair, 2=serious, 3=critical
  /// - `'timestamp'` ([double]): milliseconds since epoch
  ///
  /// On unsupported platforms, this stream will emit an error and then close.
  /// Callers should handle errors gracefully.
  Stream<Map<String, dynamic>> get thermalStateChanges {
    _thermalStream ??= _thermalEventChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event as Map),
    );
    return _thermalStream!;
  }

  /// Poll all telemetry values at once. Convenient for periodic sampling.
  ///
  /// Issues all MethodChannel calls concurrently via [Future.wait].
  Future<TelemetrySnapshot> snapshot() async {
    final results = await Future.wait([
      getThermalState(),
      getBatteryLevel(),
      getMemoryRSS(),
      getAvailableMemory(),
      isLowPowerMode(),
    ]);
    return TelemetrySnapshot(
      thermalState: results[0] as int,
      batteryLevel: results[1] as double,
      memoryRssBytes: results[2] as int,
      availableMemoryBytes: results[3] as int,
      isLowPowerMode: results[4] as bool,
      timestamp: DateTime.now(),
    );
  }
}

/// A point-in-time snapshot of all telemetry values.
class TelemetrySnapshot {
  /// Thermal state: 0=nominal, 1=fair, 2=serious, 3=critical, -1=unknown
  final int thermalState;

  /// Battery level: 0.0 to 1.0, or -1.0 if unknown
  final double batteryLevel;

  /// Process resident set size in bytes, or 0 if unavailable
  final int memoryRssBytes;

  /// Available memory in bytes, or 0 if unavailable
  final int availableMemoryBytes;

  /// Whether power-saving mode is enabled (iOS Low Power / Android Battery Saver)
  final bool isLowPowerMode;

  /// When this snapshot was taken
  final DateTime timestamp;

  const TelemetrySnapshot({
    required this.thermalState,
    required this.batteryLevel,
    required this.memoryRssBytes,
    required this.availableMemoryBytes,
    required this.isLowPowerMode,
    required this.timestamp,
  });

  @override
  String toString() =>
      'TelemetrySnapshot(thermal=$thermalState, battery=$batteryLevel, '
      'rss=${(memoryRssBytes / 1024 / 1024).toStringAsFixed(1)}MB, '
      'avail=${(availableMemoryBytes / 1024 / 1024).toStringAsFixed(1)}MB, '
      'lowPower=$isLowPowerMode)';
}
