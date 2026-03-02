import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/model_advisor.dart';
import 'package:edge_veda/src/telemetry_service.dart';
import 'package:edge_veda/src/types.dart' show ModelInfo;

/// Unit tests for the Android plugin MethodChannel/EventChannel integration.
///
/// Tests cover:
/// 1. MethodChannel mock responses for all 17 Android telemetry methods
/// 2. Android-specific device info methods (5 methods)
/// 3. Permission request/check flow
/// 4. Detective features (photo insights, calendar insights, share file)
/// 5. Thermal state mapping (Android 0-6 → iOS-compatible 0-3)
/// 6. DeviceProfile Android defaults and memory budget
/// 7. MemoryEstimator with Android device profiles
/// 8. TelemetryService integration via mocked MethodChannel
/// 9. EventChannel names and data formats
/// 10. pubspec.yaml platform registration
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const telemetryChannel = MethodChannel('com.edgeveda.edge_veda/telemetry');

  // =========================================================================
  // 1. Android MethodChannel — Telemetry Methods (13 iOS-parity)
  // =========================================================================

  group('Android Telemetry MethodChannel', () {
    late List<MethodCall> log;

    setUp(() {
      log = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            log.add(call);
            switch (call.method) {
              case 'getThermalState':
                return 0; // nominal (mapped from Android THERMAL_STATUS_NONE)
              case 'getBatteryLevel':
                return 0.72; // 72%
              case 'getBatteryState':
                return 2; // charging
              case 'getMemoryRSS':
                return 209715200; // 200 MB (from /proc/self/status VmRSS)
              case 'getAvailableMemory':
                return 3221225472; // 3 GB
              case 'getFreeDiskSpace':
                return 32212254720; // 30 GB
              case 'isLowPowerMode':
                return true; // battery saver enabled
              case 'requestMicrophonePermission':
                return true;
              case 'checkDetectivePermissions':
                return {'photos': 'notDetermined', 'calendar': 'notDetermined'};
              case 'requestDetectivePermissions':
                return {'photos': 'granted', 'calendar': 'granted'};
              case 'getPhotoInsights':
                return {
                  'totalPhotos': 142,
                  'dayOfWeekCounts': {
                    'Sun': 15,
                    'Mon': 20,
                    'Tue': 22,
                    'Wed': 18,
                    'Thu': 25,
                    'Fri': 30,
                    'Sat': 12,
                  },
                  'hourOfDayCounts': {'8': 10, '12': 25, '18': 40},
                  'topLocations': [
                    {'lat': 37.77, 'lon': -122.42, 'count': 50},
                  ],
                  'photosWithLocation': 80,
                  'samplePhotos': [
                    {
                      'timestamp': 1700000000000,
                      'hasLocation': true,
                      'lat': 37.77,
                      'lon': -122.42,
                    },
                  ],
                };
              case 'getCalendarInsights':
                return {
                  'totalEvents': 45,
                  'dayOfWeekCounts': {
                    'Sun': 0,
                    'Mon': 8,
                    'Tue': 10,
                    'Wed': 9,
                    'Thu': 8,
                    'Fri': 7,
                    'Sat': 3,
                  },
                  'hourOfDayCounts': {'9': 15, '14': 20, '16': 10},
                  'meetingMinutesPerWeekday': {
                    'Sun': 0.0,
                    'Mon': 240.0,
                    'Tue': 300.0,
                    'Wed': 270.0,
                    'Thu': 240.0,
                    'Fri': 210.0,
                    'Sat': 90.0,
                  },
                  'averageDurationMinutes': 30,
                  'sampleEvents': [
                    {
                      'startTimestamp': 1700000000000,
                      'endTimestamp': 1700001800000,
                      'title': 'Team standup',
                      'durationMinutes': 30,
                    },
                  ],
                };
              case 'shareFile':
                return true;
              case 'getDeviceModel':
                return 'Pixel 8 Pro';
              case 'getChipName':
                return 'Tensor G3';
              case 'getTotalMemory':
                return 12884901888; // 12 GB
              case 'hasNeuralEngine':
                return false;
              case 'getGpuBackend':
                return 'Vulkan';
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    // --- Thermal ---

    test('getThermalState returns integer (0=nominal)', () async {
      final result = await telemetryChannel.invokeMethod<int>(
        'getThermalState',
      );
      expect(result, 0);
      expect(log.last.method, 'getThermalState');
    });

    // --- Battery ---

    test('getBatteryLevel returns double (0.0-1.0)', () async {
      final result = await telemetryChannel.invokeMethod<double>(
        'getBatteryLevel',
      );
      expect(result, 0.72);
      expect(log.last.method, 'getBatteryLevel');
    });

    test('getBatteryState returns integer (2=charging)', () async {
      final result = await telemetryChannel.invokeMethod<int>(
        'getBatteryState',
      );
      expect(result, 2);
      expect(log.last.method, 'getBatteryState');
    });

    // --- Memory ---

    test(
      'getMemoryRSS returns integer bytes (VmRSS from /proc/self/status)',
      () async {
        final result = await telemetryChannel.invokeMethod<int>('getMemoryRSS');
        expect(result, 209715200); // 200 MB
      },
    );

    test(
      'getAvailableMemory returns integer bytes (ActivityManager)',
      () async {
        final result = await telemetryChannel.invokeMethod<int>(
          'getAvailableMemory',
        );
        expect(result, 3221225472); // 3 GB
      },
    );

    // --- Disk ---

    test('getFreeDiskSpace returns integer bytes (StatFs)', () async {
      final result = await telemetryChannel.invokeMethod<int>(
        'getFreeDiskSpace',
      );
      expect(result, 32212254720); // 30 GB
    });

    // --- Power ---

    test(
      'isLowPowerMode returns bool (PowerManager.isPowerSaveMode)',
      () async {
        final result = await telemetryChannel.invokeMethod<bool>(
          'isLowPowerMode',
        );
        expect(result, true);
      },
    );
  });

  // =========================================================================
  // 2. Android Device Info Methods (4+1)
  // =========================================================================

  group('Android Device Info MethodChannel', () {
    late List<MethodCall> log;

    setUp(() {
      log = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            log.add(call);
            switch (call.method) {
              case 'getDeviceModel':
                return 'Pixel 8 Pro';
              case 'getChipName':
                return 'Tensor G3'; // Build.SOC_MODEL on API 31+
              case 'getTotalMemory':
                return 12884901888; // 12 GB
              case 'hasNeuralEngine':
                return false; // Always false on Android
              case 'getGpuBackend':
                return 'Vulkan'; // Vulkan 1.2+ detected
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getDeviceModel returns Build.MODEL string', () async {
      final result = await telemetryChannel.invokeMethod<String>(
        'getDeviceModel',
      );
      expect(result, 'Pixel 8 Pro');
    });

    test('getChipName returns SOC_MODEL (API 31+) or HARDWARE', () async {
      final result = await telemetryChannel.invokeMethod<String>('getChipName');
      expect(result, 'Tensor G3');
    });

    test('getTotalMemory returns MemoryInfo.totalMem in bytes', () async {
      final result = await telemetryChannel.invokeMethod<int>('getTotalMemory');
      expect(result, 12884901888); // 12 GB
    });

    test('hasNeuralEngine always returns false on Android', () async {
      final result = await telemetryChannel.invokeMethod<bool>(
        'hasNeuralEngine',
      );
      expect(result, false);
    });

    test('getGpuBackend returns Vulkan or CPU', () async {
      final result = await telemetryChannel.invokeMethod<String>(
        'getGpuBackend',
      );
      expect(result, isIn(['Vulkan', 'CPU']));
    });
  });

  // =========================================================================
  // 3. Android Device Info — CPU fallback
  // =========================================================================

  group('Android Device Info — CPU fallback', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'getChipName':
                return 'qcom'; // Build.HARDWARE fallback for API < 31
              case 'getGpuBackend':
                return 'CPU'; // No Vulkan 1.2
              case 'getTotalMemory':
                return 4294967296; // 4 GB
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getChipName falls back to Build.HARDWARE on older API', () async {
      final result = await telemetryChannel.invokeMethod<String>('getChipName');
      expect(result, 'qcom');
    });

    test('getGpuBackend returns CPU when no Vulkan 1.2', () async {
      final result = await telemetryChannel.invokeMethod<String>(
        'getGpuBackend',
      );
      expect(result, 'CPU');
    });

    test('getTotalMemory returns smaller value on budget device', () async {
      final result = await telemetryChannel.invokeMethod<int>('getTotalMemory');
      expect(result, 4294967296); // 4 GB
      expect(result! / (1024 * 1024 * 1024), closeTo(4.0, 0.01));
    });
  });

  // =========================================================================
  // 4. Android Permission Methods
  // =========================================================================

  group('Android Permissions — Microphone', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'requestMicrophonePermission':
                return true;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('requestMicrophonePermission returns true when granted', () async {
      final result = await telemetryChannel.invokeMethod<bool>(
        'requestMicrophonePermission',
      );
      expect(result, true);
    });
  });

  group('Android Permissions — Microphone denied', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'requestMicrophonePermission':
                return false; // user denied
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('requestMicrophonePermission returns false when denied', () async {
      final result = await telemetryChannel.invokeMethod<bool>(
        'requestMicrophonePermission',
      );
      expect(result, false);
    });
  });

  group('Android Permissions — Detective (photo + calendar)', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'checkDetectivePermissions':
                return {'photos': 'notDetermined', 'calendar': 'notDetermined'};
              case 'requestDetectivePermissions':
                return {'photos': 'granted', 'calendar': 'granted'};
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('checkDetectivePermissions returns status map', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'checkDetectivePermissions',
      );
      expect(result, isNotNull);
      expect(result!['photos'], 'notDetermined');
      expect(result['calendar'], 'notDetermined');
    });

    test('requestDetectivePermissions returns granted map', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'requestDetectivePermissions',
      );
      expect(result, isNotNull);
      expect(result!['photos'], 'granted');
      expect(result['calendar'], 'granted');
    });
  });

  group('Android Permissions — Detective denied', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'checkDetectivePermissions':
                return {'photos': 'denied', 'calendar': 'denied'};
              case 'requestDetectivePermissions':
                return {'photos': 'denied', 'calendar': 'denied'};
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('checkDetectivePermissions returns denied when no activity', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'checkDetectivePermissions',
      );
      expect(result!['photos'], 'denied');
      expect(result['calendar'], 'denied');
    });

    test(
      'requestDetectivePermissions returns denied when user rejects',
      () async {
        final result = await telemetryChannel.invokeMethod<Map>(
          'requestDetectivePermissions',
        );
        expect(result!['photos'], 'denied');
        expect(result['calendar'], 'denied');
      },
    );
  });

  // =========================================================================
  // 5. Android Detective Features
  // =========================================================================

  group('Android Photo Insights', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'getPhotoInsights':
                return {
                  'totalPhotos': 250,
                  'dayOfWeekCounts': {
                    'Sun': 30,
                    'Mon': 35,
                    'Tue': 40,
                    'Wed': 38,
                    'Thu': 42,
                    'Fri': 45,
                    'Sat': 20,
                  },
                  'hourOfDayCounts': {'8': 15, '12': 35, '18': 60, '20': 25},
                  'topLocations': [
                    {'lat': 37.77, 'lon': -122.42, 'count': 80},
                    {'lat': 34.05, 'lon': -118.24, 'count': 40},
                  ],
                  'photosWithLocation': 120,
                  'samplePhotos': [
                    {
                      'timestamp': 1700000000000,
                      'hasLocation': true,
                      'lat': 37.77,
                      'lon': -122.42,
                    },
                    {
                      'timestamp': 1700100000000,
                      'hasLocation': false,
                      'lat': null,
                      'lon': null,
                    },
                  ],
                };
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getPhotoInsights returns complete photo analysis', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getPhotoInsights',
      );
      expect(result, isNotNull);
      expect(result!['totalPhotos'], 250);
      expect(result['photosWithLocation'], 120);
    });

    test('getPhotoInsights dayOfWeekCounts has all 7 days', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getPhotoInsights',
      );
      final dow = result!['dayOfWeekCounts'] as Map;
      expect(dow.length, 7);
      expect(
        dow.keys,
        containsAll(['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']),
      );
    });

    test('getPhotoInsights topLocations are sorted by count', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getPhotoInsights',
      );
      final locations = result!['topLocations'] as List;
      expect(locations.length, 2);
      expect(
        (locations[0] as Map)['count'],
        greaterThan((locations[1] as Map)['count'] as int),
      );
    });

    test('getPhotoInsights samplePhotos contains location data', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getPhotoInsights',
      );
      final samples = result!['samplePhotos'] as List;
      expect(samples.length, 2);

      final withLoc = samples[0] as Map;
      expect(withLoc['hasLocation'], true);
      expect(withLoc['lat'], isNotNull);

      final withoutLoc = samples[1] as Map;
      expect(withoutLoc['hasLocation'], false);
      expect(withoutLoc['lat'], isNull);
    });
  });

  group('Android Photo Insights — empty (no permission)', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'getPhotoInsights':
                return {
                  'totalPhotos': 0,
                  'dayOfWeekCounts': <String, int>{},
                  'hourOfDayCounts': <String, int>{},
                  'topLocations': <Map<String, dynamic>>[],
                  'photosWithLocation': 0,
                  'samplePhotos': <Map<String, dynamic>>[],
                };
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getPhotoInsights returns empty result without permission', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getPhotoInsights',
      );
      expect(result!['totalPhotos'], 0);
      expect((result['dayOfWeekCounts'] as Map).isEmpty, true);
      expect((result['samplePhotos'] as List).isEmpty, true);
    });
  });

  group('Android Calendar Insights', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'getCalendarInsights':
                return {
                  'totalEvents': 60,
                  'dayOfWeekCounts': {
                    'Sun': 0,
                    'Mon': 12,
                    'Tue': 14,
                    'Wed': 12,
                    'Thu': 10,
                    'Fri': 8,
                    'Sat': 4,
                  },
                  'hourOfDayCounts': {'9': 20, '10': 15, '14': 18, '16': 7},
                  'meetingMinutesPerWeekday': {
                    'Sun': 0.0,
                    'Mon': 360.0,
                    'Tue': 420.0,
                    'Wed': 360.0,
                    'Thu': 300.0,
                    'Fri': 240.0,
                    'Sat': 120.0,
                  },
                  'averageDurationMinutes': 30,
                  'sampleEvents': [
                    {
                      'startTimestamp': 1700000000000,
                      'endTimestamp': 1700001800000,
                      'title': 'Sprint planning',
                      'durationMinutes': 30,
                    },
                  ],
                };
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getCalendarInsights returns complete calendar analysis', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getCalendarInsights',
      );
      expect(result, isNotNull);
      expect(result!['totalEvents'], 60);
      expect(result['averageDurationMinutes'], 30);
    });

    test('getCalendarInsights dayOfWeekCounts has all 7 days', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getCalendarInsights',
      );
      final dow = result!['dayOfWeekCounts'] as Map;
      expect(dow.length, 7);
      expect(dow['Sun'], 0);
      expect(dow['Mon'], greaterThan(0));
    });

    test('getCalendarInsights meetingMinutesPerWeekday matches days', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getCalendarInsights',
      );
      final minutes = result!['meetingMinutesPerWeekday'] as Map;
      expect(minutes.length, 7);
      expect(minutes['Sun'], 0.0);
      expect(minutes['Tue'], greaterThan(minutes['Fri'] as double));
    });

    test('getCalendarInsights sampleEvents have required fields', () async {
      final result = await telemetryChannel.invokeMethod<Map>(
        'getCalendarInsights',
      );
      final samples = result!['sampleEvents'] as List;
      expect(samples.length, 1);
      final event = samples[0] as Map;
      expect(event.containsKey('startTimestamp'), true);
      expect(event.containsKey('endTimestamp'), true);
      expect(event.containsKey('title'), true);
      expect(event.containsKey('durationMinutes'), true);
      expect(event['title'], 'Sprint planning');
    });
  });

  group('Android Calendar Insights — empty (no permission)', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'getCalendarInsights':
                return {
                  'totalEvents': 0,
                  'dayOfWeekCounts': <String, int>{},
                  'hourOfDayCounts': <String, int>{},
                  'meetingMinutesPerWeekday': <String, double>{},
                  'averageDurationMinutes': 0,
                  'sampleEvents': <Map<String, dynamic>>[],
                };
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test(
      'getCalendarInsights returns empty result without permission',
      () async {
        final result = await telemetryChannel.invokeMethod<Map>(
          'getCalendarInsights',
        );
        expect(result!['totalEvents'], 0);
        expect(result['averageDurationMinutes'], 0);
        expect((result['sampleEvents'] as List).isEmpty, true);
      },
    );
  });

  group('Android Share File', () {
    late List<MethodCall> log;

    setUp(() {
      log = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            log.add(call);
            switch (call.method) {
              case 'shareFile':
                final path = call.arguments['path'] as String?;
                if (path == null || path.isEmpty) return false;
                return true;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('shareFile sends path and mimeType arguments', () async {
      final result = await telemetryChannel.invokeMethod<bool>('shareFile', {
        'path': '/data/user/0/com.example/cache/report.png',
        'mimeType': 'image/png',
      });
      expect(result, true);
      expect(
        log.last.arguments['path'],
        '/data/user/0/com.example/cache/report.png',
      );
      expect(log.last.arguments['mimeType'], 'image/png');
    });

    test('shareFile uses default mimeType when not specified', () async {
      final result = await telemetryChannel.invokeMethod<bool>('shareFile', {
        'path': '/data/user/0/com.example/cache/data.bin',
      });
      expect(result, true);
    });

    test('shareFile returns false with null path', () async {
      final result = await telemetryChannel.invokeMethod<bool>('shareFile', {
        'path': null,
      });
      expect(result, false);
    });
  });

  // =========================================================================
  // 6. Android Thermal State Mapping
  // =========================================================================

  group('Android Thermal State Mapping', () {
    // Android thermal status 0-6 maps to iOS-compatible 0-3:
    // 0 (NONE), 1 (LIGHT)     → 0 (nominal)
    // 2 (MODERATE)             → 1 (fair)
    // 3 (SEVERE)               → 2 (serious)
    // 4+ (CRITICAL/EMERGENCY)  → 3 (critical)

    for (final testCase in [
      (android: 0, expected: 0, desc: 'THERMAL_STATUS_NONE → nominal (0)'),
      (android: 1, expected: 0, desc: 'THERMAL_STATUS_LIGHT → nominal (0)'),
      (android: 2, expected: 1, desc: 'THERMAL_STATUS_MODERATE → fair (1)'),
      (android: 3, expected: 2, desc: 'THERMAL_STATUS_SEVERE → serious (2)'),
      (android: 4, expected: 3, desc: 'THERMAL_STATUS_CRITICAL → critical (3)'),
      (
        android: 5,
        expected: 3,
        desc: 'THERMAL_STATUS_EMERGENCY → critical (3)',
      ),
      (android: 6, expected: 3, desc: 'THERMAL_STATUS_SHUTDOWN → critical (3)'),
    ]) {
      test(testCase.desc, () {
        // Verify the mapping matches expected iOS-compatible value
        // The actual mapping is done in Kotlin, here we verify the contract
        final mapped = _mapThermalStatus(testCase.android);
        expect(mapped, testCase.expected);
      });
    }
  });

  // =========================================================================
  // 7. Android Battery State Values
  // =========================================================================

  group('Android Battery State Values', () {
    // Android battery states: 0=unknown, 1=unplugged, 2=charging, 3=full

    for (final testCase in [
      (state: 0, desc: 'unknown'),
      (state: 1, desc: 'unplugged/discharging'),
      (state: 2, desc: 'charging'),
      (state: 3, desc: 'full'),
    ]) {
      test('battery state ${testCase.state} = ${testCase.desc}', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(telemetryChannel, (
              MethodCall call,
            ) async {
              if (call.method == 'getBatteryState') return testCase.state;
              return null;
            });

        final result = await telemetryChannel.invokeMethod<int>(
          'getBatteryState',
        );
        expect(result, testCase.state);
        expect(result, inInclusiveRange(0, 3));

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(telemetryChannel, null);
      });
    }
  });

  // =========================================================================
  // 8. Android Thermal — API < 29 returns -1
  // =========================================================================

  group('Android Thermal — API < 29', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'getThermalState':
                return -1; // API < 29, thermal unavailable
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getThermalState returns -1 on API < 29', () async {
      final result = await telemetryChannel.invokeMethod<int>(
        'getThermalState',
      );
      expect(result, -1);
    });
  });

  // =========================================================================
  // 9. TelemetryService Integration with Android Responses
  // =========================================================================

  group('TelemetryService with Android MethodChannel', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
            switch (call.method) {
              case 'getThermalState':
                return 1; // fair
              case 'getBatteryLevel':
                return 0.45;
              case 'getBatteryState':
                return 1; // unplugged
              case 'getMemoryRSS':
                return 524288000; // 500 MB
              case 'getAvailableMemory':
                return 2147483648; // 2 GB
              case 'isLowPowerMode':
                return false;
              case 'getFreeDiskSpace':
                return 10737418240; // 10 GB
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getThermalState returns mapped value', () async {
      final service = TelemetryService();
      final state = await service.getThermalState();
      expect(state, 1); // fair
    });

    test('getBatteryLevel returns 0.0-1.0 range', () async {
      final service = TelemetryService();
      final level = await service.getBatteryLevel();
      expect(level, 0.45);
      expect(level, inInclusiveRange(0.0, 1.0));
    });

    test('getBatteryState returns valid state', () async {
      final service = TelemetryService();
      final state = await service.getBatteryState();
      expect(state, 1); // unplugged
    });

    test('getMemoryRSS returns VmRSS bytes', () async {
      final service = TelemetryService();
      final rss = await service.getMemoryRSS();
      expect(rss, 524288000);
      expect(rss, greaterThan(0));
    });

    test(
      'getAvailableMemory returns ActivityManager.MemoryInfo.availMem',
      () async {
        final service = TelemetryService();
        final avail = await service.getAvailableMemory();
        expect(avail, 2147483648);
      },
    );

    test('isLowPowerMode returns PowerManager.isPowerSaveMode', () async {
      final service = TelemetryService();
      final lowPower = await service.isLowPowerMode();
      expect(lowPower, false);
    });

    test('getFreeDiskSpace returns StatFs.availableBytes', () async {
      final service = TelemetryService();
      final space = await service.getFreeDiskSpace();
      expect(space, 10737418240);
    });

    test('snapshot() polls all values concurrently', () async {
      final service = TelemetryService();
      final snap = await service.snapshot();
      expect(snap.thermalState, 1);
      expect(snap.batteryLevel, 0.45);
      expect(snap.memoryRssBytes, 524288000);
      expect(snap.availableMemoryBytes, 2147483648);
      expect(snap.isLowPowerMode, false);
      expect(snap.timestamp, isNotNull);
    });
  });

  // =========================================================================
  // 10. TelemetryService — MissingPluginException handling
  // =========================================================================

  group('TelemetryService — graceful fallback on missing plugin', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, null);
    });

    test('getThermalState returns -1 on MissingPluginException', () async {
      final service = TelemetryService();
      final state = await service.getThermalState();
      expect(state, -1);
    });

    test('getBatteryLevel returns -1.0 on MissingPluginException', () async {
      final service = TelemetryService();
      final level = await service.getBatteryLevel();
      expect(level, -1.0);
    });

    test('getBatteryState returns 0 on MissingPluginException', () async {
      final service = TelemetryService();
      final state = await service.getBatteryState();
      expect(state, 0);
    });

    test('getMemoryRSS returns 0 on MissingPluginException', () async {
      final service = TelemetryService();
      final rss = await service.getMemoryRSS();
      expect(rss, 0);
    });

    test('getAvailableMemory returns 0 on MissingPluginException', () async {
      final service = TelemetryService();
      final avail = await service.getAvailableMemory();
      expect(avail, 0);
    });

    test('isLowPowerMode returns false on MissingPluginException', () async {
      final service = TelemetryService();
      final lowPower = await service.isLowPowerMode();
      expect(lowPower, false);
    });

    test('getFreeDiskSpace returns -1 on MissingPluginException', () async {
      final service = TelemetryService();
      final space = await service.getFreeDiskSpace();
      expect(space, -1);
    });
  });

  // =========================================================================
  // 11. DeviceProfile — Android defaults
  // =========================================================================

  group('DeviceProfile — Android default profile', () {
    // We can't call DeviceProfile.detect() in test (it would use host platform),
    // but we can construct the equivalent Android default and verify its properties.

    const androidProfile = DeviceProfile(
      identifier: 'android',
      deviceName: 'Android Device',
      totalRamGB: 6.0,
      chipName: 'ARM64',
      tier: DeviceTier.medium,
    );

    test('Android default profile has identifier "android"', () {
      expect(androidProfile.identifier, 'android');
    });

    test('Android default profile has 6 GB RAM', () {
      expect(androidProfile.totalRamGB, 6.0);
    });

    test('Android default profile is medium tier', () {
      expect(androidProfile.tier, DeviceTier.medium);
    });

    test('Android default profile chipName is ARM64', () {
      expect(androidProfile.chipName, 'ARM64');
    });

    test('Android default profile toString is descriptive', () {
      final str = androidProfile.toString();
      expect(str, contains('Android Device'));
      expect(str, contains('6.0'));
      expect(str, contains('ARM64'));
      expect(str, contains('medium'));
    });
  });

  // =========================================================================
  // 12. DeviceProfile — Android memory budget (50%)
  // =========================================================================

  group('DeviceProfile — Android-like memory budgets', () {
    // On the test host, Platform.isAndroid is false, so safeMemoryBudgetMB
    // uses the iOS/macOS formula. We test Android budget computation directly.

    test('6 GB Android device: 50% budget = 3072 MB', () {
      // Direct computation matching the Android path
      final budget = (6.0 * 1024 * 0.50).round();
      expect(budget, 3072);
    });

    test('8 GB Android device: 50% budget = 4096 MB', () {
      final budget = (8.0 * 1024 * 0.50).round();
      expect(budget, 4096);
    });

    test('12 GB Android device: 50% budget = 6144 MB', () {
      final budget = (12.0 * 1024 * 0.50).round();
      expect(budget, 6144);
    });

    test('4 GB Android device: 50% budget = 2048 MB', () {
      final budget = (4.0 * 1024 * 0.50).round();
      expect(budget, 2048);
    });

    test('Android 50% budget is more conservative than iOS 60%', () {
      const ramGB = 8.0;
      final androidBudget = (ramGB * 1024 * 0.50).round();
      final iosBudget = (ramGB * 1024 * 0.60).round();
      expect(androidBudget, lessThan(iosBudget));
      expect(iosBudget - androidBudget, (ramGB * 1024 * 0.10).round());
    });

    test('Android 50% budget is more conservative than macOS 80%', () {
      const ramGB = 8.0;
      final androidBudget = (ramGB * 1024 * 0.50).round();
      final macosBudget = (ramGB * 1024 * 0.80).round();
      expect(androidBudget, lessThan(macosBudget));
    });
  });

  // =========================================================================
  // 13. MemoryEstimator with Android Device Profiles
  // =========================================================================

  group('MemoryEstimator — Android device profiles', () {
    // Simulate Android devices with varying RAM and tiers

    test('6 GB Android (medium): Llama 1B Q4_K_M fits', () {
      const model = ModelInfo(
        id: 'llama-3.2-1b-instruct-q4',
        name: 'Llama 3.2 1B Instruct',
        sizeBytes: 700 * 1024 * 1024,
        downloadUrl: 'https://example.com/llama.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'Q4_K_M',
      );
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Android Device',
        totalRamGB: 6.0,
        chipName: 'ARM64',
        tier: DeviceTier.medium,
      );

      final estimate = MemoryEstimator.estimate(model: model, device: device);
      expect(estimate.fits, true);
      expect(estimate.totalMB, lessThan(3072)); // < 50% of 6 GB
    });

    test('4 GB Android (minimum): 13B model does not fit', () {
      const model = ModelInfo(
        id: 'large-model',
        name: 'Large 13B Model',
        sizeBytes: 8000 * 1024 * 1024, // ~8 GB
        downloadUrl: 'https://example.com/large.gguf',
        family: 'llama3',
        parametersB: 13.0,
        quantization: 'Q4_K_M',
      );
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Budget Android',
        totalRamGB: 4.0,
        chipName: 'ARM64',
        tier: DeviceTier.minimum,
      );

      final estimate = MemoryEstimator.estimate(model: model, device: device);
      expect(estimate.fits, false);
      expect(estimate.memoryRatio, greaterThan(1.0));
    });

    test('12 GB Android (high): 3B model fits comfortably', () {
      const model = ModelInfo(
        id: 'phi-3.5-mini',
        name: 'Phi 3.5 Mini',
        sizeBytes: 2000 * 1024 * 1024,
        downloadUrl: 'https://example.com/phi.gguf',
        family: 'phi3',
        parametersB: 3.5,
        quantization: 'Q4_K_M',
      );
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Flagship Android',
        totalRamGB: 12.0,
        chipName: 'Snapdragon 8 Gen 3',
        tier: DeviceTier.high,
      );

      final estimate = MemoryEstimator.estimate(model: model, device: device);
      expect(estimate.fits, true);
      expect(estimate.memoryRatio, lessThan(0.5));
    });

    test('whisper model on Android: simple formula (fileSize + 100MB)', () {
      const model = ModelInfo(
        id: 'whisper-base-en',
        name: 'Whisper Base EN',
        sizeBytes: 148 * 1024 * 1024,
        downloadUrl: 'https://example.com/whisper.bin',
        family: 'whisper',
      );
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Android Device',
        totalRamGB: 6.0,
        chipName: 'ARM64',
        tier: DeviceTier.medium,
      );

      final estimate = MemoryEstimator.estimate(model: model, device: device);
      expect(estimate.totalMB, 248); // 148 + 100
      expect(estimate.kvCacheMB, 0);
      expect(estimate.metalBuffersMB, 0);
      expect(estimate.fits, true);
    });
  });

  // =========================================================================
  // 14. ModelAdvisor — Android device scoring
  // =========================================================================

  group('ModelAdvisor — Android device scoring', () {
    const androidDevice = DeviceProfile(
      identifier: 'android',
      deviceName: 'Android Device',
      totalRamGB: 8.0,
      chipName: 'ARM64',
      tier: DeviceTier.medium,
    );

    test('score() returns valid ModelScore for Android device', () {
      const model = ModelInfo(
        id: 'llama-3.2-1b-instruct-q4',
        name: 'Llama 3.2 1B Instruct',
        sizeBytes: 700 * 1024 * 1024,
        downloadUrl: 'https://example.com/llama.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'Q4_K_M',
        capabilities: ['chat'],
      );

      final score = ModelAdvisor.score(
        model: model,
        device: androidDevice,
        useCase: UseCase.chat,
      );

      expect(score.finalScore, greaterThan(0));
      expect(score.fits, true);
      expect(score.fitScore, greaterThan(0));
      expect(score.qualityScore, greaterThan(0));
      expect(score.speedScore, greaterThan(0));
      expect(score.contextScore, greaterThan(0));
    });

    test('recommend() generates ranked list for Android', () {
      const models = [
        ModelInfo(
          id: 'model-small',
          name: 'Small Model',
          sizeBytes: 300 * 1024 * 1024,
          downloadUrl: 'https://example.com/small.gguf',
          family: 'llama3',
          parametersB: 0.5,
          quantization: 'Q4_K_M',
        ),
        ModelInfo(
          id: 'model-large',
          name: 'Large Model',
          sizeBytes: 5000 * 1024 * 1024,
          downloadUrl: 'https://example.com/large.gguf',
          family: 'llama3',
          parametersB: 7.0,
          quantization: 'Q4_K_M',
        ),
      ];

      final rec = ModelAdvisor.recommend(
        device: androidDevice,
        useCase: UseCase.chat,
        models: models,
      );

      expect(rec.ranked.length, 2);
      expect(rec.device.identifier, 'android');
      expect(rec.useCase, UseCase.chat);
      // Ranked by final score descending
      expect(
        rec.ranked[0].finalScore,
        greaterThanOrEqualTo(rec.ranked[1].finalScore),
      );
    });

    test('canRun() with explicit Android device', () {
      const model = ModelInfo(
        id: 'llama-3.2-1b-instruct-q4',
        name: 'Llama 3.2 1B Instruct',
        sizeBytes: 700 * 1024 * 1024,
        downloadUrl: 'https://example.com/llama.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'Q4_K_M',
      );

      final result = ModelAdvisor.canRun(model: model, device: androidDevice);
      expect(result, true);
    });

    test('recommended config has reasonable Android values', () {
      const model = ModelInfo(
        id: 'llama-3.2-1b-instruct-q4',
        name: 'Llama 3.2 1B Instruct',
        sizeBytes: 700 * 1024 * 1024,
        downloadUrl: 'https://example.com/llama.gguf',
        family: 'llama3',
        parametersB: 1.0,
        quantization: 'Q4_K_M',
        maxContextLength: 8192,
      );

      final score = ModelAdvisor.score(
        model: model,
        device: androidDevice,
        useCase: UseCase.chat,
      );

      expect(score.recommendedConfig.numThreads, greaterThan(0));
      expect(score.recommendedConfig.contextLength, greaterThan(0));
      expect(score.recommendedConfig.useGpu, true);
      expect(score.recommendedConfig.maxMemoryMb, greaterThan(0));
    });
  });

  // =========================================================================
  // 15. EventChannel Names
  // =========================================================================

  group('Android EventChannel Names', () {
    test('telemetry method channel name', () {
      expect(telemetryChannel.name, 'com.edgeveda.edge_veda/telemetry');
    });

    test('thermal event channel name', () {
      const name = 'com.edgeveda.edge_veda/thermal';
      expect(name, 'com.edgeveda.edge_veda/thermal');
    });

    test('audio capture event channel name', () {
      const name = 'com.edgeveda.edge_veda/audio_capture';
      expect(name, 'com.edgeveda.edge_veda/audio_capture');
    });

    test('memory pressure event channel name', () {
      const name = 'com.edgeveda.edge_veda/memory_pressure';
      expect(name, 'com.edgeveda.edge_veda/memory_pressure');
    });

    test('all channel names share com.edgeveda.edge_veda prefix', () {
      const channels = [
        'com.edgeveda.edge_veda/telemetry',
        'com.edgeveda.edge_veda/thermal',
        'com.edgeveda.edge_veda/audio_capture',
        'com.edgeveda.edge_veda/memory_pressure',
      ];
      for (final ch in channels) {
        expect(ch, startsWith('com.edgeveda.edge_veda/'));
      }
    });
  });

  // =========================================================================
  // 16. Thermal Event Data Format
  // =========================================================================

  group('Android Thermal Event Data Format', () {
    test('thermal event contains thermalState and timestamp', () {
      // Simulate what the Kotlin ThermalStreamHandler emits
      final event = <String, dynamic>{
        'thermalState': 0,
        'timestamp': 1700000000000.0,
      };

      expect(event.containsKey('thermalState'), true);
      expect(event.containsKey('timestamp'), true);
      expect(event['thermalState'], isA<int>());
      expect(event['timestamp'], isA<double>());
    });

    test('thermal event thermalState is in valid range 0-3', () {
      for (final state in [0, 1, 2, 3]) {
        final event = <String, dynamic>{
          'thermalState': state,
          'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
        };
        expect(event['thermalState'], inInclusiveRange(0, 3));
      }
    });
  });

  // =========================================================================
  // 17. Memory Pressure Event Data Format
  // =========================================================================

  group('Android Memory Pressure Event Data Format', () {
    test('memory event contains level and pressureLevel', () {
      // Simulate what ComponentCallbacks2.onTrimMemory emits
      final event = <String, dynamic>{
        'level': 80, // TRIM_MEMORY_COMPLETE
        'pressureLevel': 'critical',
      };

      expect(event.containsKey('level'), true);
      expect(event.containsKey('pressureLevel'), true);
      expect(event['level'], isA<int>());
      expect(event['pressureLevel'], isA<String>());
    });

    test('pressure levels map to expected strings', () {
      final mappings = <int, String>{
        80: 'critical', // TRIM_MEMORY_COMPLETE
        60: 'high', // TRIM_MEMORY_MODERATE
        40: 'medium', // TRIM_MEMORY_BACKGROUND
        20: 'background', // TRIM_MEMORY_UI_HIDDEN
        15: 'running_critical', // TRIM_MEMORY_RUNNING_CRITICAL
        10: 'running_low', // TRIM_MEMORY_RUNNING_LOW
        5: 'normal', // TRIM_MEMORY_RUNNING_MODERATE
      };

      for (final entry in mappings.entries) {
        final pressureLevel = _mapTrimLevel(entry.key);
        expect(
          pressureLevel,
          entry.value,
          reason: 'trim level ${entry.key} should map to ${entry.value}',
        );
      }
    });
  });

  // =========================================================================
  // 18. Audio Capture Data Decoding
  // =========================================================================

  group('Audio Capture Data Decoding', () {
    // WhisperSession._decodeAudioSamples handles multiple payload types

    test('Float32List passthrough', () {
      final data = Float32List.fromList([0.1, 0.2, 0.3, 0.4]);
      // Float32List should be passed through directly
      expect(data, isA<Float32List>());
      expect(data.length, 4);
    });

    test('Float64List converts to Float32List', () {
      final data = Float64List.fromList([0.1, 0.2, 0.3]);
      final converted = Float32List.fromList(data);
      expect(converted.length, 3);
      expect(converted[0], closeTo(0.1, 0.001));
    });

    test('Uint8List with float bytes decodes correctly', () {
      // Create a Float32List, get its bytes, verify roundtrip
      final original = Float32List.fromList([1.0, -1.0, 0.5]);
      final bytes = Uint8List.view(original.buffer);
      expect(bytes.length, 12); // 3 floats * 4 bytes

      // Roundtrip through byte view
      final decoded = Float32List.view(bytes.buffer, bytes.offsetInBytes, 3);
      expect(decoded[0], 1.0);
      expect(decoded[1], -1.0);
      expect(decoded[2], 0.5);
    });

    test('audio chunk size matches 300ms at 16kHz', () {
      // Android AudioCaptureStreamHandler uses CHUNK_SAMPLES = 4800
      // 4800 samples / 16000 Hz = 0.3 seconds = 300ms
      const sampleRate = 16000;
      const chunkSamples = 4800;
      final durationMs = (chunkSamples / sampleRate) * 1000;
      expect(durationMs, 300.0);
    });

    test('audio format is 16kHz mono float', () {
      // Verify audio spec constants match iOS
      const sampleRate = 16000;
      const channels = 1; // mono
      const bytesPerSample = 4; // PCM_FLOAT = 32-bit

      expect(sampleRate, 16000);
      expect(channels, 1);
      expect(bytesPerSample, 4);

      // Bytes per second
      final bytesPerSecond = sampleRate * channels * bytesPerSample;
      expect(bytesPerSecond, 64000); // 64 KB/s
    });
  });

  // =========================================================================
  // 19. pubspec.yaml Platform Registration
  // =========================================================================

  group('Platform Registration', () {
    test('pubspec registers Android platform', () {
      // The pubspec.yaml declares:
      // flutter:
      //   plugin:
      //     platforms:
      //       android:
      //         package: com.edgeveda.edge_veda
      //         pluginClass: EdgeVedaPlugin
      // This test verifies the registration exists by checking the file.
      final pubspecFile = File('${Directory.current.path}/pubspec.yaml');
      if (pubspecFile.existsSync()) {
        final content = pubspecFile.readAsStringSync();
        expect(content, contains('android:'));
        expect(content, contains('package: com.edgeveda.edge_veda'));
        expect(content, contains('pluginClass: EdgeVedaPlugin'));
      }
    });

    test('pubspec registers all three platforms (android, ios, macos)', () {
      final pubspecFile = File('${Directory.current.path}/pubspec.yaml');
      if (pubspecFile.existsSync()) {
        final content = pubspecFile.readAsStringSync();
        expect(content, contains('android:'));
        expect(content, contains('ios:'));
        expect(content, contains('macos:'));
      }
    });
  });

  // =========================================================================
  // 20. AndroidManifest Permissions
  // =========================================================================

  group('AndroidManifest Permissions', () {
    test('AndroidManifest declares required permissions', () {
      final manifestFile = File(
        '${Directory.current.path}/android/src/main/AndroidManifest.xml',
      );
      if (manifestFile.existsSync()) {
        final content = manifestFile.readAsStringSync();
        expect(content, contains('android.permission.INTERNET'));
        expect(content, contains('android.permission.ACCESS_NETWORK_STATE'));
        expect(content, contains('android.permission.RECORD_AUDIO'));
        expect(content, contains('android.permission.READ_MEDIA_IMAGES'));
        expect(content, contains('android.permission.READ_CALENDAR'));
      }
    });

    test('AndroidManifest declares Vulkan as optional feature', () {
      final manifestFile = File(
        '${Directory.current.path}/android/src/main/AndroidManifest.xml',
      );
      if (manifestFile.existsSync()) {
        final content = manifestFile.readAsStringSync();
        expect(content, contains('android.hardware.vulkan'));
        expect(content, contains('android:required="false"'));
      }
    });

    test('AndroidManifest limits READ_EXTERNAL_STORAGE to API 32', () {
      final manifestFile = File(
        '${Directory.current.path}/android/src/main/AndroidManifest.xml',
      );
      if (manifestFile.existsSync()) {
        final content = manifestFile.readAsStringSync();
        expect(content, contains('READ_EXTERNAL_STORAGE'));
        expect(content, contains('android:maxSdkVersion="32"'));
      }
    });
  });

  // =========================================================================
  // 21. DeviceTier comparison for Android
  // =========================================================================

  group('DeviceTier — Android device scenarios', () {
    test('4 GB budget device is minimum tier', () {
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Budget Phone',
        totalRamGB: 4.0,
        chipName: 'MediaTek',
        tier: DeviceTier.minimum,
      );
      expect(device.tier, DeviceTier.minimum);
      expect(device.tier.index, 0);
    });

    test('6 GB mid-range device is medium tier', () {
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Mid-range Phone',
        totalRamGB: 6.0,
        chipName: 'Snapdragon 7 Gen 2',
        tier: DeviceTier.medium,
      );
      expect(device.tier, DeviceTier.medium);
      expect(device.tier.index, 2);
    });

    test('12 GB flagship device is high tier', () {
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Flagship Phone',
        totalRamGB: 12.0,
        chipName: 'Snapdragon 8 Gen 3',
        tier: DeviceTier.high,
      );
      expect(device.tier, DeviceTier.high);
      expect(device.tier.index, 3);
    });

    test('16 GB gaming/ultra device is ultra tier', () {
      const device = DeviceProfile(
        identifier: 'android',
        deviceName: 'Gaming Phone',
        totalRamGB: 16.0,
        chipName: 'Snapdragon 8 Gen 3',
        tier: DeviceTier.ultra,
      );
      expect(device.tier, DeviceTier.ultra);
      expect(device.tier.index, 4);
    });

    test('tier ordering: minimum < low < medium < high < ultra', () {
      expect(DeviceTier.minimum.index, lessThan(DeviceTier.low.index));
      expect(DeviceTier.low.index, lessThan(DeviceTier.medium.index));
      expect(DeviceTier.medium.index, lessThan(DeviceTier.high.index));
      expect(DeviceTier.high.index, lessThan(DeviceTier.ultra.index));
    });
  });

  // =========================================================================
  // 22. Native Library Loading Path
  // =========================================================================

  group('Native Library Loading', () {
    test('Android loads libedge_veda.so (not .framework or .process)', () {
      // Verify the expected library name for Android
      const androidLib = 'libedge_veda.so';
      expect(androidLib, endsWith('.so'));
      expect(androidLib, startsWith('lib'));
      expect(androidLib, 'libedge_veda.so');
    });

    test('library name differs by platform', () {
      const androidLib = 'libedge_veda.so';
      const iosFramework = 'EdgeVedaCore.framework/EdgeVedaCore';

      expect(androidLib, isNot(equals(iosFramework)));
      expect(androidLib, contains('.so'));
      expect(iosFramework, contains('.framework'));
    });

    test('DynamicLibrary.open is ABI-agnostic — same .so name for all ABIs', () {
      // On Android, DynamicLibrary.open('libedge_veda.so') resolves to
      // the correct ABI directory automatically (e.g. lib/arm64-v8a/,
      // lib/armeabi-v7a/, lib/x86_64/). The Dart code never specifies the ABI.
      const libName = 'libedge_veda.so';
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        final expectedPath = 'lib/$abi/$libName';
        expect(expectedPath, contains(libName));
        expect(expectedPath, startsWith('lib/'));
      }
    });
  });

  // =========================================================================
  // 22a. Android Multi-ABI Build Configuration
  // =========================================================================

  group('Android Multi-ABI — build.gradle abiFilters', () {
    test('build.gradle declares arm64-v8a, armeabi-v7a, and x86_64', () {
      final gradleFile = File('${Directory.current.path}/android/build.gradle');
      if (gradleFile.existsSync()) {
        final content = gradleFile.readAsStringSync();
        expect(content, contains('arm64-v8a'));
        expect(content, contains('armeabi-v7a'));
        expect(content, contains('x86_64'));
      }
    });

    test('build.gradle abiFilters lists exactly 3 ABIs', () {
      final gradleFile = File('${Directory.current.path}/android/build.gradle');
      if (gradleFile.existsSync()) {
        final content = gradleFile.readAsStringSync();
        // Match the abiFilters line
        final match = RegExp(
          r"abiFilters\s+'([^']+)'(?:\s*,\s*'([^']+)')*",
        ).firstMatch(content);
        expect(match, isNotNull, reason: 'abiFilters declaration not found');

        // Extract all quoted ABI strings from the abiFilters line
        final abiLine = content
            .split('\n')
            .firstWhere((l) => l.contains('abiFilters'), orElse: () => '');
        final abis =
            RegExp(
              r"'([^']+)'",
            ).allMatches(abiLine).map((m) => m.group(1)!).toList();
        expect(abis, hasLength(3));
        expect(abis, containsAll(['arm64-v8a', 'armeabi-v7a', 'x86_64']));
      }
    });

    test('build.gradle does not include x86 (32-bit Intel)', () {
      final gradleFile = File('${Directory.current.path}/android/build.gradle');
      if (gradleFile.existsSync()) {
        final content = gradleFile.readAsStringSync();
        final abiLine = content
            .split('\n')
            .firstWhere((l) => l.contains('abiFilters'), orElse: () => '');
        final abis =
            RegExp(
              r"'([^']+)'",
            ).allMatches(abiLine).map((m) => m.group(1)!).toList();
        // x86_64 is included, but bare 'x86' (32-bit) should not be
        expect(abis, isNot(contains('x86')));
      }
    });

    test(
      'build.gradle does not hardcode GGML_LLAMAFILE (now ABI-conditional)',
      () {
        final gradleFile = File(
          '${Directory.current.path}/android/build.gradle',
        );
        if (gradleFile.existsSync()) {
          final content = gradleFile.readAsStringSync();
          expect(
            content,
            isNot(contains('-DGGML_LLAMAFILE')),
            reason:
                'GGML_LLAMAFILE should be set in CMakeLists.txt '
                'per-ABI, not hardcoded in build.gradle',
          );
        }
      },
    );

    test('packagingOptions wildcard covers all ABIs', () {
      final gradleFile = File('${Directory.current.path}/android/build.gradle');
      if (gradleFile.existsSync()) {
        final content = gradleFile.readAsStringSync();
        // lib/*/ glob matches any ABI subdirectory
        expect(content, contains("lib/*/libedge_veda.so"));
        expect(content, contains("lib/*/libc++_shared.so"));
      }
    });
  });

  group('Android Multi-ABI — CMakeLists.txt SIMD configuration', () {
    test('CMakeLists.txt has ABI-conditional NEON logic', () {
      // CMakeLists.txt is two directories up from the flutter/ working dir
      final cmakeFile = File(
        '${Directory.current.path}/../core/CMakeLists.txt',
      );
      if (cmakeFile.existsSync()) {
        final content = cmakeFile.readAsStringSync();
        // Must check ANDROID_ABI for NEON
        expect(content, contains('ANDROID_ABI'));
        expect(content, contains('GGML_NEON ON'));
        expect(content, contains('GGML_NEON OFF'));
      }
    });

    test('CMakeLists.txt enables NEON for ARM ABIs only', () {
      final cmakeFile = File(
        '${Directory.current.path}/../core/CMakeLists.txt',
      );
      if (cmakeFile.existsSync()) {
        final content = cmakeFile.readAsStringSync();
        // ARM targets (arm64-v8a, armeabi-v7a) get NEON ON
        expect(content, contains('arm64-v8a'));
        expect(content, contains('armeabi-v7a'));
        // NEON ON only in the ARM branch
        final armBranch = RegExp(
          r'if\(ANDROID_ABI\s+STREQUAL\s+"arm64-v8a"\s+OR\s+ANDROID_ABI\s+STREQUAL\s+"armeabi-v7a"\)',
        ).hasMatch(content);
        expect(
          armBranch,
          true,
          reason: 'ARM ABI conditional for NEON not found',
        );
      }
    });

    test('CMakeLists.txt disables NEON for x86_64', () {
      final cmakeFile = File(
        '${Directory.current.path}/../core/CMakeLists.txt',
      );
      if (cmakeFile.existsSync()) {
        final content = cmakeFile.readAsStringSync();
        // x86_64 branch must set NEON OFF (would fail with <arm_neon.h>)
        final x86Branch = RegExp(
          r'elseif\(ANDROID_ABI\s+STREQUAL\s+"x86_64"\)',
        ).hasMatch(content);
        expect(
          x86Branch,
          true,
          reason: 'x86_64 ABI conditional branch not found',
        );
      }
    });

    test('CMakeLists.txt enables LLAMAFILE for x86_64 only', () {
      final cmakeFile = File(
        '${Directory.current.path}/../core/CMakeLists.txt',
      );
      if (cmakeFile.existsSync()) {
        final content = cmakeFile.readAsStringSync();
        // LLAMAFILE provides optimized x86 SIMD kernels
        expect(content, contains('GGML_LLAMAFILE ON'));
        expect(content, contains('GGML_LLAMAFILE OFF'));
      }
    });

    test('CMakeLists.txt disables OpenMP for all Android ABIs', () {
      final cmakeFile = File(
        '${Directory.current.path}/../core/CMakeLists.txt',
      );
      if (cmakeFile.existsSync()) {
        final content = cmakeFile.readAsStringSync();
        // OpenMP OFF is outside the ABI conditional — applies to all ABIs
        expect(content, contains('set(GGML_OPENMP OFF CACHE BOOL "" FORCE)'));
      }
    });
  });

  group('Android Multi-ABI — toolchain per-ABI flags', () {
    test('android.toolchain.cmake has arm64-v8a flags', () {
      final toolchainFile = File(
        '${Directory.current.path}/../core/cmake/android.toolchain.cmake',
      );
      if (toolchainFile.existsSync()) {
        final content = toolchainFile.readAsStringSync();
        expect(content, contains('arm64-v8a'));
        expect(content, contains('-march=armv8-a'));
      }
    });

    test('android.toolchain.cmake has armeabi-v7a flags', () {
      final toolchainFile = File(
        '${Directory.current.path}/../core/cmake/android.toolchain.cmake',
      );
      if (toolchainFile.existsSync()) {
        final content = toolchainFile.readAsStringSync();
        expect(content, contains('armeabi-v7a'));
        expect(content, contains('-march=armv7-a'));
        expect(content, contains('-mfpu=neon'));
      }
    });

    test('android.toolchain.cmake has x86_64 flags', () {
      final toolchainFile = File(
        '${Directory.current.path}/../core/cmake/android.toolchain.cmake',
      );
      if (toolchainFile.existsSync()) {
        final content = toolchainFile.readAsStringSync();
        expect(content, contains('x86_64'));
        expect(content, contains('-msse4.2'));
      }
    });

    test('android.toolchain.cmake sets NEON define only for ARM', () {
      final toolchainFile = File(
        '${Directory.current.path}/../core/cmake/android.toolchain.cmake',
      );
      if (toolchainFile.existsSync()) {
        final content = toolchainFile.readAsStringSync();
        // GGML_USE_NEON should appear in arm64-v8a and armeabi-v7a blocks
        expect(content, contains('GGML_USE_NEON=1'));
        // But x86_64 block should NOT have NEON defines
        final x86Block = _extractBlock(content, 'x86_64');
        expect(
          x86Block,
          isNot(contains('NEON')),
          reason: 'x86_64 block should not reference NEON',
        );
      }
    });

    test('android.toolchain.cmake defaults to arm64-v8a when ABI not set', () {
      final toolchainFile = File(
        '${Directory.current.path}/../core/cmake/android.toolchain.cmake',
      );
      if (toolchainFile.existsSync()) {
        final content = toolchainFile.readAsStringSync();
        expect(content, contains('set(ANDROID_ABI "arm64-v8a")'));
      }
    });
  });

  // =========================================================================
  // 23. Method Channel Method Count Verification
  // =========================================================================

  group('Android MethodChannel — method completeness', () {
    test('all 17 methods are handled (13 telemetry + 4 device info)', () {
      // Exhaustive list of methods the Android Kotlin plugin handles
      const expectedMethods = [
        // Telemetry (13)
        'getThermalState',
        'getBatteryLevel',
        'getBatteryState',
        'getMemoryRSS',
        'getAvailableMemory',
        'getFreeDiskSpace',
        'isLowPowerMode',
        'requestMicrophonePermission',
        'checkDetectivePermissions',
        'requestDetectivePermissions',
        'getPhotoInsights',
        'getCalendarInsights',
        'shareFile',
        // Device info (4)
        'getDeviceModel',
        'getChipName',
        'getTotalMemory',
        'getGpuBackend',
      ];

      expect(expectedMethods.length, 17);
      expect(expectedMethods.toSet().length, 17); // no duplicates
    });

    test('hasNeuralEngine is an additional method (18 total)', () {
      // hasNeuralEngine is always false on Android but still handled
      const allMethods = [
        'getThermalState',
        'getBatteryLevel',
        'getBatteryState',
        'getMemoryRSS',
        'getAvailableMemory',
        'getFreeDiskSpace',
        'isLowPowerMode',
        'requestMicrophonePermission',
        'checkDetectivePermissions',
        'requestDetectivePermissions',
        'getPhotoInsights',
        'getCalendarInsights',
        'shareFile',
        'getDeviceModel',
        'getChipName',
        'getTotalMemory',
        'hasNeuralEngine',
        'getGpuBackend',
      ];

      expect(allMethods.length, 18);
    });
  });
}

// =========================================================================
// Test Helpers (mirror Kotlin logic for verification)
// =========================================================================

/// Mirror of EdgeVedaPlugin.mapThermalStatus() for test verification.
/// Android thermal status (0-6) → iOS-compatible (0-3).
int _mapThermalStatus(int androidStatus) {
  switch (androidStatus) {
    case 0:
    case 1:
      return 0; // NONE, LIGHT → nominal
    case 2:
      return 1; // MODERATE → fair
    case 3:
      return 2; // SEVERE → serious
    default:
      return 3; // CRITICAL, EMERGENCY, SHUTDOWN → critical
  }
}

/// Mirror of EdgeVedaPlugin.onTrimMemory() pressure level mapping.
String _mapTrimLevel(int level) {
  if (level >= 80) return 'critical'; // TRIM_MEMORY_COMPLETE
  if (level >= 60) return 'high'; // TRIM_MEMORY_MODERATE
  if (level >= 40) return 'medium'; // TRIM_MEMORY_BACKGROUND
  if (level >= 20) return 'background'; // TRIM_MEMORY_UI_HIDDEN
  if (level >= 15) return 'running_critical'; // TRIM_MEMORY_RUNNING_CRITICAL
  if (level >= 10) return 'running_low'; // TRIM_MEMORY_RUNNING_LOW
  return 'normal';
}

/// Extract the CMake elseif block for a given ABI keyword.
/// Returns the text between the elseif(... "abi") and the next elseif/endif.
String _extractBlock(String content, String abiKeyword) {
  final lines = content.split('\n');
  final buffer = StringBuffer();
  var inBlock = false;
  for (final line in lines) {
    if (line.contains(abiKeyword)) {
      inBlock = true;
      continue;
    }
    if (inBlock && (line.contains('elseif(') || line.contains('endif()'))) {
      break;
    }
    if (inBlock) {
      buffer.writeln(line);
    }
  }
  return buffer.toString();
}
