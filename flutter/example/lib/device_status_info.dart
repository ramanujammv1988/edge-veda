import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Shared device/platform metadata used across example screens.
class DeviceStatusInfo {
  static _SysctlByNameDart? _sysctlbyname;

  static String? _cachedModel;
  static double? _cachedMemory;

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
    return '${gb.toStringAsFixed(2)} GB';
  }

  static bool get hasNeuralEngine => Platform.isIOS || Platform.isMacOS;

  static String get backendLabel =>
      (Platform.isIOS || Platform.isMacOS) ? 'Metal GPU' : 'CPU';

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
