import 'dart:async';

import 'package:flutter/services.dart';

/// Service for querying device thermal, battery, and memory telemetry.
///
/// Supports iOS and Android platforms. Uses MethodChannel for on-demand polling
/// and EventChannel for push thermal state change notifications (iOS only).
/// Gracefully returns defaults on unsupported platforms (catches [MissingPluginException]).
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
  /// Returns -1 on unsupported platforms, Android (no thermal state API), or error.
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
  /// iOS 13+: os_proc_available_memory, Android: ActivityManager.MemoryInfo.availMem
  /// Returns 0 on error.
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

  /// Get free disk space in bytes via platform file system APIs.
  ///
  /// Returns -1 on unsupported platforms or error.
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

  /// Whether device power saving mode is enabled.
  ///
  /// iOS: Low Power Mode, Android: PowerManager.isPowerSaveMode
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

  /// Stream of thermal state changes (iOS only - push-based notifications).
  ///
  /// Each event is a [Map] with keys:
  /// - `'thermalState'` ([int]): 0=nominal, 1=fair, 2=serious, 3=critical
  /// - `'timestamp'` ([double]): milliseconds since epoch
  ///
  /// Android does not support thermal state push notifications (use polling via getThermalState).
  /// On non-iOS platforms, this stream will emit an error and then close.
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
  /// Thermal state: 0=nominal, 1=fair, 2=serious, 3=critical, -1=unknown/unsupported
  final int thermalState;

  /// Battery level: 0.0 to 1.0, or -1.0 if unknown
  final double batteryLevel;

  /// Process resident set size in bytes, or 0 if unavailable
  final int memoryRssBytes;

  /// Available memory in bytes (iOS: os_proc_available_memory, Android: MemoryInfo.availMem), or 0 if unavailable
  final int availableMemoryBytes;

  /// Whether device power saving mode is enabled (iOS: Low Power Mode, Android: PowerManager.isPowerSaveMode)
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
