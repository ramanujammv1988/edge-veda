import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/model_manager.dart';
import 'package:edge_veda/src/telemetry_service.dart';
import 'package:edge_veda/src/types.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// A testable ModelManager that uses a temp directory instead of
/// path_provider (which requires a running Flutter engine).
class TestableModelManager extends ModelManager {
  final Directory _testDir;

  TestableModelManager(this._testDir);

  @override
  Future<Directory> getModelsDirectory() async => _testDir;

  @override
  Future<String> getModelPath(String modelId) async {
    final ext = modelId.startsWith('whisper-') ? 'bin' : 'gguf';
    return '${_testDir.path}/$modelId.$ext';
  }
}

/// Mock TelemetryService that returns a configurable free disk space value.
class MockTelemetryService extends TelemetryService {
  final int _freeDiskSpace;

  MockTelemetryService({int freeDiskSpace = -1})
    : _freeDiskSpace = freeDiskSpace;

  @override
  Future<int> getFreeDiskSpace() async => _freeDiskSpace;
}

/// Build a test ModelInfo with a download URL pointing to our mock server.
ModelInfo _testModel({
  String id = 'test-model',
  String name = 'Test Model',
  int sizeBytes = 1000,
  String downloadUrl = 'http://localhost/test-model.gguf',
  String? checksum,
}) {
  return ModelInfo(
    id: id,
    name: name,
    sizeBytes: sizeBytes,
    downloadUrl: downloadUrl,
    checksum: checksum,
  );
}

/// Compute SHA256 hex string for the given bytes.
String _sha256Hex(List<int> bytes) {
  return sha256.convert(bytes).toString();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('model_manager_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  // ── Resume tests ────────────────────────────────────────────────────────

  group('Byte-range resume', () {
    test('sends Range header when .tmp file exists', () async {
      final manager = TestableModelManager(tmpDir);
      // Suppress disk space check
      manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

      final model = _testModel(sizeBytes: 100);
      final modelPath = await manager.getModelPath(model.id);
      final tempFile = File('$modelPath.tmp');

      // Create a .tmp file with 50 bytes of prior data
      tempFile.writeAsBytesSync(List.filled(50, 0x41)); // 50 bytes of 'A'

      // Use a real local HTTP server to capture the request
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverCompleter = Completer<HttpRequest>();
      server.listen((request) {
        serverCompleter.complete(request);
        // Return 206 with remaining bytes
        request.response.statusCode = 206;
        request.response.headers.contentLength = 50;
        request.response.add(List.filled(50, 0x42));
        request.response.close();
      });

      final localModel = _testModel(
        sizeBytes: 100,
        downloadUrl: 'http://localhost:$port/test-model.gguf',
      );

      // Run download - it should send Range header
      await manager.downloadModel(localModel, verifyChecksum: false);

      final capturedRequest = await serverCompleter.future;
      expect(capturedRequest.headers.value('Range'), 'bytes=50-');

      await server.close(force: true);
      manager.dispose();
    });

    test('appends to .tmp on 206 response', () async {
      final manager = TestableModelManager(tmpDir);
      manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

      final model = _testModel(sizeBytes: 8);
      final modelPath = await manager.getModelPath(model.id);
      final tempFile = File('$modelPath.tmp');

      // Write initial 4 bytes
      tempFile.writeAsBytesSync([0x41, 0x41, 0x41, 0x41]); // "AAAA"

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.statusCode = 206;
        request.response.headers.contentLength = 4;
        request.response.add([0x42, 0x42, 0x42, 0x42]); // "BBBB"
        request.response.close();
      });

      final localModel = _testModel(
        sizeBytes: 8,
        downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
      );

      final resultPath = await manager.downloadModel(
        localModel,
        verifyChecksum: false,
      );

      // Final file should be the complete model (renamed from .tmp)
      final finalFile = File(resultPath);
      expect(finalFile.existsSync(), true);
      final contents = finalFile.readAsBytesSync();
      expect(contents, [0x41, 0x41, 0x41, 0x41, 0x42, 0x42, 0x42, 0x42]);

      await server.close(force: true);
      manager.dispose();
    });

    test(
      'restarts download when server returns 200 despite Range header',
      () async {
        final manager = TestableModelManager(tmpDir);
        manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

        final model = _testModel(sizeBytes: 4);
        final modelPath = await manager.getModelPath(model.id);
        final tempFile = File('$modelPath.tmp');

        // Create a .tmp file with stale data
        tempFile.writeAsBytesSync([0x41, 0x41, 0x41, 0x41]); // 4 bytes

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) {
          // Server ignores Range header and returns full 200
          request.response.statusCode = 200;
          request.response.headers.contentLength = 4;
          request.response.add([0x43, 0x43, 0x43, 0x43]); // "CCCC" fresh
          request.response.close();
        });

        final localModel = _testModel(
          sizeBytes: 4,
          downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
        );

        final resultPath = await manager.downloadModel(
          localModel,
          verifyChecksum: false,
        );

        // Final file should contain only the new data (not appended)
        final finalFile = File(resultPath);
        final contents = finalFile.readAsBytesSync();
        expect(contents, [0x43, 0x43, 0x43, 0x43]);

        await server.close(force: true);
        manager.dispose();
      },
    );

    test('progress includes resumed bytes', () async {
      final manager = TestableModelManager(tmpDir);
      manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

      final model = _testModel(sizeBytes: 1000);
      final modelPath = await manager.getModelPath(model.id);
      final tempFile = File('$modelPath.tmp');

      // 500 bytes already downloaded
      tempFile.writeAsBytesSync(List.filled(500, 0x41));

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.statusCode = 206;
        request.response.headers.contentLength = 500;
        request.response.add(List.filled(500, 0x42));
        request.response.close();
      });

      final localModel = _testModel(
        sizeBytes: 1000,
        downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
      );

      // Collect progress events
      final progressEvents = <DownloadProgress>[];
      final sub = manager.downloadProgress.listen(progressEvents.add);

      await manager.downloadModel(localModel, verifyChecksum: false);

      // Give stream events time to propagate
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      // First event should show resumeOffset as initial downloaded bytes
      expect(progressEvents.isNotEmpty, true);
      final firstEvent = progressEvents.first;
      expect(firstEvent.downloadedBytes, 500);
      expect(firstEvent.totalBytes, 1000);

      // Last event should be 100%
      final lastEvent = progressEvents.last;
      expect(lastEvent.downloadedBytes, 1000);
      expect(lastEvent.totalBytes, 1000);

      await server.close(force: true);
      manager.dispose();
    });

    test('fresh download works without .tmp file', () async {
      final manager = TestableModelManager(tmpDir);
      manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? receivedRange;
      server.listen((request) {
        receivedRange = request.headers.value('Range');
        request.response.statusCode = 200;
        request.response.headers.contentLength = 8;
        request.response.add([0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44]);
        request.response.close();
      });

      final localModel = _testModel(
        sizeBytes: 8,
        downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
      );

      final resultPath = await manager.downloadModel(
        localModel,
        verifyChecksum: false,
      );

      // No Range header should have been sent
      expect(receivedRange, isNull);

      // File should contain fresh data
      final contents = File(resultPath).readAsBytesSync();
      expect(contents.length, 8);
      expect(contents, List.filled(8, 0x44));

      await server.close(force: true);
      manager.dispose();
    });

    test('checksum verified on full file after resume', () async {
      final manager = TestableModelManager(tmpDir);
      manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

      final partA = List.filled(4, 0x41);
      final partB = List.filled(4, 0x42);
      final fullContent = [...partA, ...partB];
      final correctChecksum = _sha256Hex(fullContent);

      final model = _testModel(sizeBytes: 8);
      final modelPath = await manager.getModelPath(model.id);
      final tempFile = File('$modelPath.tmp');

      // Write part A as existing .tmp
      tempFile.writeAsBytesSync(partA);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.statusCode = 206;
        request.response.headers.contentLength = 4;
        request.response.add(partB);
        request.response.close();
      });

      final localModel = _testModel(
        sizeBytes: 8,
        downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
        checksum: correctChecksum,
      );

      // Should succeed with correct checksum
      final resultPath = await manager.downloadModel(localModel);
      expect(File(resultPath).existsSync(), true);
      expect(File(resultPath).readAsBytesSync(), fullContent);

      await server.close(force: true);
      manager.dispose();
    });

    test(
      'checksum mismatch after resume throws ModelValidationException',
      () async {
        final manager = TestableModelManager(tmpDir);
        manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

        final partA = List.filled(4, 0x41);
        final partB = List.filled(4, 0x42);

        final model = _testModel(sizeBytes: 8);
        final modelPath = await manager.getModelPath(model.id);
        final tempFile = File('$modelPath.tmp');

        tempFile.writeAsBytesSync(partA);

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        // Keep server alive to handle retry attempts from _downloadWithRetry
        server.listen((request) {
          final rangeHeader = request.headers.value('Range');
          if (rangeHeader != null) {
            // Resume request
            request.response.statusCode = 206;
            request.response.headers.contentLength = 4;
            request.response.add(partB);
          } else {
            // Fresh download (after .tmp deleted by checksum failure)
            request.response.statusCode = 200;
            request.response.headers.contentLength = 8;
            request.response.add([...partA, ...partB]);
          }
          request.response.close();
        });

        final localModel = _testModel(
          sizeBytes: 8,
          downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
          checksum:
              'deadbeef0000000000000000000000000000000000000000000000000000dead',
        );

        try {
          await manager.downloadModel(localModel);
          fail('Should have thrown');
        } on ModelValidationException {
          // Expected
        }

        await server.close(force: true);
        manager.dispose();
      },
    );
  });

  // ── Disk space tests ────────────────────────────────────────────────────

  group('Disk space pre-check', () {
    test('throws DownloadException when insufficient disk space', () async {
      final manager = TestableModelManager(tmpDir);
      // 50MB free, model needs 100MB + 100MB buffer = 200MB
      manager.telemetryService = MockTelemetryService(
        freeDiskSpace: 50 * 1024 * 1024,
      );

      final model = _testModel(
        sizeBytes: 100 * 1024 * 1024, // 100MB model
        downloadUrl: 'http://localhost:1/unreachable',
      );

      expect(
        () => manager.downloadModel(model, verifyChecksum: false),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            'Insufficient disk space',
          ),
        ),
      );

      manager.dispose();
    });

    test('allows download when disk space is sufficient', () async {
      final manager = TestableModelManager(tmpDir);
      // 500MB free, model needs 8 bytes + 100MB buffer -- plenty of space
      manager.telemetryService = MockTelemetryService(
        freeDiskSpace: 500 * 1024 * 1024,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.statusCode = 200;
        request.response.headers.contentLength = 8;
        request.response.add(List.filled(8, 0x45));
        request.response.close();
      });

      final localModel = _testModel(
        sizeBytes: 8,
        downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
      );

      final result = await manager.downloadModel(
        localModel,
        verifyChecksum: false,
      );
      expect(File(result).existsSync(), true);

      await server.close(force: true);
      manager.dispose();
    });

    test('skips disk space check when platform returns -1', () async {
      final manager = TestableModelManager(tmpDir);
      // -1 means platform cannot determine free space -- optimistic fallback
      manager.telemetryService = MockTelemetryService(freeDiskSpace: -1);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.statusCode = 200;
        request.response.headers.contentLength = 4;
        request.response.add(List.filled(4, 0x46));
        request.response.close();
      });

      final localModel = _testModel(
        sizeBytes: 999999999999, // Huge model, but disk check is skipped
        downloadUrl: 'http://localhost:${server.port}/test-model.gguf',
      );

      // Should NOT throw despite huge model size -- disk check returns -1
      final result = await manager.downloadModel(
        localModel,
        verifyChecksum: false,
      );
      expect(File(result).existsSync(), true);

      await server.close(force: true);
      manager.dispose();
    });

    test('disk space error message includes MB values', () async {
      final manager = TestableModelManager(tmpDir);
      manager.telemetryService = MockTelemetryService(
        freeDiskSpace: 150 * 1024 * 1024, // 150MB free
      );

      final model = _testModel(
        name: 'Big Model',
        sizeBytes: 200 * 1024 * 1024, // 200MB (needs 200 + 100 = 300MB)
        downloadUrl: 'http://localhost:1/unreachable',
      );

      try {
        await manager.downloadModel(model, verifyChecksum: false);
        fail('Should have thrown');
      } on DownloadException catch (e) {
        expect(e.details, contains('150MB free'));
        expect(e.details, contains('200MB required'));
        expect(e.details, contains('Big Model'));
      }

      manager.dispose();
    });
  });

  // ── importModel tests ───────────────────────────────────────────────────

  group('importModel', () {
    test('copies file to model cache atomically', () async {
      final manager = TestableModelManager(tmpDir);
      final sourceDir = Directory.systemTemp.createTempSync('import_source_');

      try {
        final sourceContent = List.filled(256, 0x41);
        final sourceFile = File('${sourceDir.path}/model.gguf');
        sourceFile.writeAsBytesSync(sourceContent);

        final model = _testModel(sizeBytes: 256);
        final resultPath = await manager.importModel(
          model,
          sourcePath: sourceFile.path,
          verifyChecksum: false,
        );

        // Final model file exists with correct content
        final finalFile = File(resultPath);
        expect(finalFile.existsSync(), true);
        expect(finalFile.readAsBytesSync(), sourceContent);

        // No .tmp file left behind
        expect(File('$resultPath.tmp').existsSync(), false);
      } finally {
        sourceDir.deleteSync(recursive: true);
        manager.dispose();
      }
    });

    test('returns cached model without re-copy when already exists', () async {
      final manager = TestableModelManager(tmpDir);

      final model = _testModel(sizeBytes: 100);
      final modelPath = await manager.getModelPath(model.id);

      // Pre-create the cached model file
      File(modelPath).writeAsBytesSync(List.filled(100, 0x42));

      // Call importModel with a non-existent source -- cache check happens first
      final resultPath = await manager.importModel(
        model,
        sourcePath: '/non/existent/path.gguf',
        verifyChecksum: false,
      );

      expect(resultPath, modelPath);
      // Verify content is unchanged (no re-copy happened)
      expect(File(resultPath).readAsBytesSync(), List.filled(100, 0x42));

      manager.dispose();
    });

    test('verifies SHA256 checksum on success', () async {
      final manager = TestableModelManager(tmpDir);
      final sourceDir = Directory.systemTemp.createTempSync('import_source_');

      try {
        final sourceContent = [0x48, 0x65, 0x6C, 0x6C, 0x6F]; // "Hello"
        final correctChecksum = _sha256Hex(sourceContent);
        final sourceFile = File('${sourceDir.path}/model.gguf');
        sourceFile.writeAsBytesSync(sourceContent);

        final model = _testModel(
          sizeBytes: sourceContent.length,
          checksum: correctChecksum,
        );

        final resultPath = await manager.importModel(
          model,
          sourcePath: sourceFile.path,
        );

        expect(File(resultPath).existsSync(), true);
        expect(File(resultPath).readAsBytesSync(), sourceContent);
      } finally {
        sourceDir.deleteSync(recursive: true);
        manager.dispose();
      }
    });

    test('throws ModelValidationException on checksum mismatch', () async {
      final manager = TestableModelManager(tmpDir);
      final sourceDir = Directory.systemTemp.createTempSync('import_source_');

      try {
        final sourceContent = List.filled(64, 0x43);
        final sourceFile = File('${sourceDir.path}/model.gguf');
        sourceFile.writeAsBytesSync(sourceContent);

        final model = _testModel(
          sizeBytes: 64,
          checksum:
              'deadbeef0000000000000000000000000000000000000000000000000000dead',
        );

        try {
          await manager.importModel(model, sourcePath: sourceFile.path);
          fail('Should have thrown');
        } on ModelValidationException catch (e) {
          expect(e.message, 'SHA256 checksum mismatch');
        }

        // Verify .tmp file is cleaned up
        final modelPath = await manager.getModelPath(model.id);
        expect(File('$modelPath.tmp').existsSync(), false);
      } finally {
        sourceDir.deleteSync(recursive: true);
        manager.dispose();
      }
    });

    test('throws ModelValidationException when source file missing', () async {
      final manager = TestableModelManager(tmpDir);

      final model = _testModel(sizeBytes: 100);

      try {
        await manager.importModel(
          model,
          sourcePath: '/non/existent/file.gguf',
          verifyChecksum: false,
        );
        fail('Should have thrown');
      } on ModelValidationException catch (e) {
        expect(e.message, 'Source file not found');
        expect(e.details, '/non/existent/file.gguf');
      }

      manager.dispose();
    });

    test('throws ModelValidationException on size mismatch', () async {
      final manager = TestableModelManager(tmpDir);
      final sourceDir = Directory.systemTemp.createTempSync('import_source_');

      try {
        // Create source file with 100 bytes
        final sourceFile = File('${sourceDir.path}/model.gguf');
        sourceFile.writeAsBytesSync(List.filled(100, 0x44));

        // Declare model expects 200 bytes
        final model = _testModel(sizeBytes: 200);

        try {
          await manager.importModel(
            model,
            sourcePath: sourceFile.path,
            verifyChecksum: false,
          );
          fail('Should have thrown');
        } on ModelValidationException catch (e) {
          expect(e.message, 'Source file size mismatch');
          expect(e.details, contains('200'));
          expect(e.details, contains('100'));
        }
      } finally {
        sourceDir.deleteSync(recursive: true);
        manager.dispose();
      }
    });

    test('reports progress via onProgress callback', () async {
      final manager = TestableModelManager(tmpDir);
      final sourceDir = Directory.systemTemp.createTempSync('import_source_');

      try {
        // Create a 256KB source file
        final sourceContent = List.filled(256 * 1024, 0x45);
        final sourceFile = File('${sourceDir.path}/model.gguf');
        sourceFile.writeAsBytesSync(sourceContent);

        final model = _testModel(sizeBytes: 256 * 1024);
        final progressCalls = <(int, int)>[];

        await manager.importModel(
          model,
          sourcePath: sourceFile.path,
          verifyChecksum: false,
          onProgress: (bytesCopied, totalBytes) {
            progressCalls.add((bytesCopied, totalBytes));
          },
        );

        // At least 2 progress calls (stream may deliver in chunks)
        expect(progressCalls.length, greaterThanOrEqualTo(1));

        // Last call should have bytesCopied == totalBytes
        final lastCall = progressCalls.last;
        expect(lastCall.$1, lastCall.$2);
        expect(lastCall.$2, 256 * 1024);
      } finally {
        sourceDir.deleteSync(recursive: true);
        manager.dispose();
      }
    });

    test('cleans up .tmp on checksum verification error', () async {
      final manager = TestableModelManager(tmpDir);
      final sourceDir = Directory.systemTemp.createTempSync('import_source_');

      try {
        final sourceContent = List.filled(128, 0x46);
        final sourceFile = File('${sourceDir.path}/model.gguf');
        sourceFile.writeAsBytesSync(sourceContent);

        final model = _testModel(
          sizeBytes: 128,
          checksum:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );

        try {
          await manager.importModel(model, sourcePath: sourceFile.path);
          fail('Should have thrown');
        } on ModelValidationException {
          // Expected
        }

        // .tmp file should have been cleaned up
        final modelPath = await manager.getModelPath(model.id);
        expect(File('$modelPath.tmp').existsSync(), false);
        // Final file should NOT exist either
        expect(File(modelPath).existsSync(), false);
      } finally {
        sourceDir.deleteSync(recursive: true);
        manager.dispose();
      }
    });

    test(
      're-validates cached model when checksum provided and cached exists',
      () async {
        final manager = TestableModelManager(tmpDir);
        final sourceDir = Directory.systemTemp.createTempSync('import_source_');

        try {
          final correctContent = [0x47, 0x6F, 0x6F, 0x64]; // "Good"
          final correctChecksum = _sha256Hex(correctContent);

          // Pre-create a cached model with WRONG content
          final model = _testModel(
            sizeBytes: correctContent.length,
            checksum: correctChecksum,
          );
          final modelPath = await manager.getModelPath(model.id);
          File(modelPath).writeAsBytesSync([0x42, 0x61, 0x64, 0x21]); // "Bad!"

          // Source has correct content
          final sourceFile = File('${sourceDir.path}/model.gguf');
          sourceFile.writeAsBytesSync(correctContent);

          final resultPath = await manager.importModel(
            model,
            sourcePath: sourceFile.path,
          );

          // Should have replaced bad cache with correct content
          expect(File(resultPath).readAsBytesSync(), correctContent);
        } finally {
          sourceDir.deleteSync(recursive: true);
          manager.dispose();
        }
      },
    );

    test('saves metadata after successful import', () async {
      final manager = TestableModelManager(tmpDir);
      final sourceDir = Directory.systemTemp.createTempSync('import_source_');

      try {
        final sourceContent = List.filled(50, 0x48);
        final sourceFile = File('${sourceDir.path}/model.gguf');
        sourceFile.writeAsBytesSync(sourceContent);

        final model = _testModel(id: 'import-test-model', sizeBytes: 50);

        await manager.importModel(
          model,
          sourcePath: sourceFile.path,
          verifyChecksum: false,
        );

        // Verify metadata was saved
        final metadata = await manager.getModelMetadata('import-test-model');
        expect(metadata, isNotNull);
        expect(metadata!.id, 'import-test-model');
      } finally {
        sourceDir.deleteSync(recursive: true);
        manager.dispose();
      }
    });
  });
}
