import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:edge_veda/edge_veda.dart';
import 'package:ffi/ffi.dart';

/// Shared device/platform metadata used across example screens.
class DeviceStatusInfo {
  static _SysctlByNameDart? _sysctlbyname;

  static String? _cachedModel;
  static double? _cachedMemory;
  static String? _cachedChip;
  static bool? _cachedHasNeuralEngine;
  static String? _cachedBackend;
  static bool _androidInitDone = false;

  /// Async initialization for Android — fetches chip, memory, neural engine,
  /// and GPU backend via TelemetryService MethodChannel. No-op on iOS/macOS.
  static Future<void> initAndroid() async {
    if (_androidInitDone || !Platform.isAndroid) return;
    _androidInitDone = true;
    final telemetry = TelemetryService();
    final results = await Future.wait([
      telemetry.getChipName(),
      telemetry.getTotalMemory(),
      telemetry.hasNeuralEngine(),
      telemetry.getGpuBackend(),
    ]);
    final chipName = results[0] as String;
    final totalMem = results[1] as int;
    final neural = results[2] as bool;
    final backend = results[3] as String;

    if (chipName.isNotEmpty) _cachedChip = chipName;
    if (totalMem > 0) {
      _cachedMemory = totalMem / (1024 * 1024 * 1024);
    }
    _cachedHasNeuralEngine = neural;
    if (backend.isNotEmpty) _cachedBackend = backend;
  }

  static _SysctlByNameDart? get _sysctl {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return null;
    }

    _sysctlbyname ??= ffi.DynamicLibrary.process()
        .lookupFunction<_SysctlByNameC, _SysctlByNameDart>('sysctlbyname');
    return _sysctlbyname;
  }

  static String get model {
    if (_cachedModel != null) return _cachedModel!;
    if (Platform.isMacOS || Platform.isIOS) {
      try {
        _cachedModel = _readString('hw.machine');
      } catch (_) {
        _cachedModel = Platform.operatingSystem;
      }
    } else {
      _cachedModel = platformLabel;
    }
    return _cachedModel!;
  }

  static String get platformLabel {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  static String get deviceDisplay =>
      Platform.isMacOS ? '$platformLabel ($model)' : platformLabel;

  static String get chip {
    if (_cachedChip != null) return _cachedChip!;
    if (Platform.isIOS || Platform.isMacOS) return 'Apple Silicon';
    return 'Unknown';
  }

  static double get memoryGB {
    if (_cachedMemory != null) return _cachedMemory!;
    if (Platform.isMacOS || Platform.isIOS) {
      try {
        _cachedMemory = _readInt64('hw.memsize') / (1024 * 1024 * 1024);
      } catch (_) {
        _cachedMemory = 0;
      }
    } else {
      _cachedMemory = 0;
    }
    return _cachedMemory!;
  }

  static String get memoryString {
    final gb = memoryGB;
    if (gb <= 0) return 'Unknown';
    return '${gb.toStringAsFixed(1)} GB';
  }

  static bool get hasNeuralEngine {
    if (_cachedHasNeuralEngine != null) return _cachedHasNeuralEngine!;
    return Platform.isIOS || Platform.isMacOS;
  }

  static String get backendLabel {
    if (_cachedBackend != null) return _cachedBackend!;
    return (Platform.isIOS || Platform.isMacOS) ? 'Metal GPU' : 'CPU';
  }

  static String _readString(String name) {
    final sysctl = _sysctl;
    if (sysctl == null) {
      throw UnsupportedError('sysctlbyname is not available on this platform');
    }

    final namePtr = name.toNativeUtf8();
    final sizePtr = calloc<ffi.Size>();
    try {
      sysctl(namePtr.cast(), ffi.nullptr, sizePtr, ffi.nullptr, 0);
      final bufLen = sizePtr.value;
      if (bufLen == 0) return 'Unknown';

      final buf = calloc<ffi.Uint8>(bufLen);
      try {
        sysctl(namePtr.cast(), buf.cast(), sizePtr, ffi.nullptr, 0);
        return buf.cast<Utf8>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(sizePtr);
      calloc.free(namePtr);
    }
  }

  static int _readInt64(String name) {
    final sysctl = _sysctl;
    if (sysctl == null) {
      throw UnsupportedError('sysctlbyname is not available on this platform');
    }

    final namePtr = name.toNativeUtf8();
    final sizePtr = calloc<ffi.Size>();
    final valPtr = calloc<ffi.Int64>();
    try {
      sizePtr.value = ffi.sizeOf<ffi.Int64>();
      sysctl(namePtr.cast(), valPtr.cast(), sizePtr, ffi.nullptr, 0);
      return valPtr.value;
    } finally {
      calloc.free(valPtr);
      calloc.free(sizePtr);
      calloc.free(namePtr);
    }
  }
}

typedef _SysctlByNameC = ffi.Int Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>,
  ffi.Size,
);
typedef _SysctlByNameDart = int Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>,
  int,
);
