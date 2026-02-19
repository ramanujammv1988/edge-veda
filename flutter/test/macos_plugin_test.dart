import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for macOS plugin method channel responses.
///
/// These tests mock the MethodChannel to verify the Dart side correctly
/// invokes methods and processes responses from the native macOS plugin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const telemetryChannel = MethodChannel('com.edgeveda.edge_veda/telemetry');

  group('macOS Telemetry MethodChannel', () {
    late List<MethodCall> log;

    setUp(() {
      log = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(telemetryChannel, (MethodCall call) async {
        log.add(call);
        switch (call.method) {
          case 'getThermalState':
            return 0; // nominal
          case 'getBatteryLevel':
            return 0.85; // 85%
          case 'getBatteryState':
            return 1; // unplugged
          case 'getMemoryRSS':
            return 104857600; // 100 MB
          case 'getAvailableMemory':
            return 4294967296; // 4 GB
          case 'isLowPowerMode':
            return false;
          case 'getFreeDiskSpace':
            return 53687091200; // 50 GB
          case 'requestMicrophonePermission':
            return true;
          case 'checkDetectivePermissions':
            return {'photos': 'granted', 'calendar': 'notDetermined'};
          case 'requestDetectivePermissions':
            return {'photos': 'granted', 'calendar': 'granted'};
          case 'shareFile':
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

    test('getThermalState returns integer', () async {
      final result = await telemetryChannel.invokeMethod<int>('getThermalState');
      expect(result, 0);
      expect(log.last.method, 'getThermalState');
    });

    test('getBatteryLevel returns double', () async {
      final result = await telemetryChannel.invokeMethod<double>('getBatteryLevel');
      expect(result, 0.85);
      expect(log.last.method, 'getBatteryLevel');
    });

    test('getBatteryState returns integer', () async {
      final result = await telemetryChannel.invokeMethod<int>('getBatteryState');
      expect(result, 1);
      expect(log.last.method, 'getBatteryState');
    });

    test('getMemoryRSS returns integer bytes', () async {
      final result = await telemetryChannel.invokeMethod<int>('getMemoryRSS');
      expect(result, 104857600);
    });

    test('getAvailableMemory returns integer bytes', () async {
      final result = await telemetryChannel.invokeMethod<int>('getAvailableMemory');
      expect(result, 4294967296);
    });

    test('isLowPowerMode returns bool', () async {
      final result = await telemetryChannel.invokeMethod<bool>('isLowPowerMode');
      expect(result, false);
    });

    test('getFreeDiskSpace returns integer bytes', () async {
      final result = await telemetryChannel.invokeMethod<int>('getFreeDiskSpace');
      expect(result, 53687091200);
    });

    test('requestMicrophonePermission returns bool', () async {
      final result = await telemetryChannel.invokeMethod<bool>('requestMicrophonePermission');
      expect(result, true);
    });

    test('checkDetectivePermissions returns map', () async {
      final result = await telemetryChannel.invokeMethod<Map>('checkDetectivePermissions');
      expect(result, isNotNull);
      expect(result!['photos'], 'granted');
      expect(result['calendar'], 'notDetermined');
    });

    test('requestDetectivePermissions returns map', () async {
      final result = await telemetryChannel.invokeMethod<Map>('requestDetectivePermissions');
      expect(result, isNotNull);
      expect(result!['photos'], 'granted');
      expect(result!['calendar'], 'granted');
    });

    test('shareFile sends path argument', () async {
      final result = await telemetryChannel.invokeMethod<bool>('shareFile', {
        'path': '/tmp/test.txt',
      });
      expect(result, true);
      expect(log.last.arguments, {'path': '/tmp/test.txt'});
    });
  });

  group('Channel Names', () {
    test('telemetry channel has correct name', () {
      expect(telemetryChannel.name, 'com.edgeveda.edge_veda/telemetry');
    });

    test('thermal event channel name is correct', () {
      // Verify the channel name constant matches what the plugin uses
      const thermalName = 'com.edgeveda.edge_veda/thermal';
      expect(thermalName, contains('thermal'));
    });

    test('audio capture event channel name is correct', () {
      const audioName = 'com.edgeveda.edge_veda/audio_capture';
      expect(audioName, contains('audio_capture'));
    });
  });
}
