import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' show min;
import 'package:camera/camera.dart';
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

/// App-level soak runner that keeps running even when the Soak screen is closed.
///
/// **Behavior change (v2.1.0):** Default soak duration increased from 30 to
/// 35 minutes across all platforms. The extra 5 minutes improves thermal
/// steady-state coverage — SD845 testing showed thermal ramp-up can take
/// 25+ minutes before reaching steady state.
///
/// **Known limitation (CPU-only Android):** On devices without Vulkan GPU
/// support (e.g. Snapdragon 845), soak tests run CPU-only with very low
/// throughput (~0.05 tok/s, 60+ second latency per frame). The SD845
/// evidence shows 2/6 criteria PASS (no crash, no memory leak) while
/// thermal monitoring and battery drain assertions fail due to sustained
/// CPU load. This is an expected hardware constraint, not a software bug.
/// Full soak parity requires Vulkan GPU acceleration (Phase 7).
class SoakTestService extends ChangeNotifier {
  SoakTestService._();

  static final SoakTestService instance = SoakTestService._();

  final VisionWorker _visionWorker = VisionWorker();
  final FrameQueue _frameQueue = FrameQueue();
  final TelemetryService _telemetry = TelemetryService();
  final RuntimePolicy _policy = RuntimePolicy();
  final ModelManager _modelManager = ModelManager();

  PerfTrace? _trace;
  CameraController? _cameraController;
  Timer? _screenCaptureTimer;

  String? _modelPath;
  String? _mmprojPath;
  WorkloadId _workloadId = WorkloadId.vision;
  bool _isRunning = false;
  bool _isInitializing = false;
  int _frameCount = 0;
  int _totalTokens = 0;
  double _lastLatencyMs = 0;
  double _avgLatencyMs = 0;
  double _totalLatencyMs = 0;
  int _thermalState = -1;
  double _batteryLevel = -1.0;
  int _memoryRssBytes = 0;
  QoSLevel _currentQoS = QoSLevel.full;
  Duration _elapsed = Duration.zero;
  String _statusMessage = 'Ready';
  String? _traceFilePath;
  String? _lastDescription;

  Scheduler? _scheduler;
  int _actionableViolationCount = 0;
  int _observeOnlyViolationCount = 0;
  String? _lastViolation;
  MeasuredBaseline? _measuredBaseline;
  EdgeVedaBudget? _resolvedBudget;

  Timer? _telemetryTimer;
  Timer? _elapsedTimer;
  DateTime? _startTime;
  bool _isManaged = true;

  static const _testDuration = Duration(minutes: 35);
  static const _telemetryInterval = Duration(seconds: 2);
  static const _telemetryChannel =
      MethodChannel('com.edgeveda.edge_veda/telemetry');

  /// True on any platform that can feed frames into the Vision pipeline
  bool get cameraSupported =>
      Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  CameraController? get cameraController => _cameraController;
  bool get isRunning => _isRunning;
  bool get isInitializing => _isInitializing;
  bool get isManaged => _isManaged;
  int get frameCount => _frameCount;
  int get totalTokens => _totalTokens;
  double get lastLatencyMs => _lastLatencyMs;
  double get avgLatencyMs => _avgLatencyMs;
  int get thermalState => _thermalState;
  double get batteryLevel => _batteryLevel;
  int get memoryRssBytes => _memoryRssBytes;
  QoSLevel get currentQoS => _currentQoS;
  Duration get elapsed => _elapsed;
  Duration get testDuration => _testDuration;
  String get statusMessage => _statusMessage;
  String? get traceFilePath => _traceFilePath;
  String? get lastDescription => _lastDescription;
  int get droppedFrames => _frameQueue.droppedFrames;
  int get actionableViolationCount => _actionableViolationCount;
  int get observeOnlyViolationCount => _observeOnlyViolationCount;
  String? get lastViolation => _lastViolation;
  MeasuredBaseline? get measuredBaseline => _measuredBaseline;
  EdgeVedaBudget? get resolvedBudget => _resolvedBudget;

  QoSKnobs get currentKnobs {
    if (!_isRunning) return _policy.knobs;
    if (!_isManaged) {
      return const QoSKnobs(maxFps: 2, resolution: 640, maxTokens: 100);
    }
    return _scheduler?.getKnobsForWorkload(_workloadId) ?? _policy.knobs;
  }

  void setManagedMode(bool value) {
    if (_isRunning || _isInitializing) return;
    if (_isManaged == value) return;
    _isManaged = value;
    notifyListeners();
  }

  Future<void> start() async {
    if (_isRunning || _isInitializing) return;

    _isInitializing = true;
    _statusMessage = 'Preparing soak test...';
    notifyListeners();

    try {
      _workloadId = cameraSupported ? WorkloadId.vision : WorkloadId.text;
      if (cameraSupported) {
        await _ensureModelsDownloaded();
        _statusMessage = 'Loading vision model...';
        notifyListeners();
        await _visionWorker.spawn();
        await _visionWorker.initVision(
          modelPath: _modelPath!,
          mmprojPath: _mmprojPath!,
          numThreads: _adaptiveThreadCount(),
          contextSize: 4096,
          useGpu: Platform.isIOS,
        );
        if (Platform.isMacOS) {
          _statusMessage = 'Initializing screen capture...';
        } else {
          _statusMessage = 'Initializing camera...';
          await _initializeCamera();
        }
        notifyListeners();
      } else {
        _statusMessage = 'Monitoring user activity (manual soak mode)...';
        notifyListeners();
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .substring(0, 15);
      final modeLabel = _isManaged ? 'managed' : 'raw';
      final traceFile =
          File('${docsDir.path}/soak_${modeLabel}_$timestamp.jsonl');
      _trace = PerfTrace(traceFile);
      _traceFilePath = traceFile.path;

      _trace!.record(
        stage: 'benchmark_mode',
        value: _isManaged ? 1.0 : 0.0,
        extra: {'mode': modeLabel},
      );

      if (_isManaged) {
        _scheduler = Scheduler(
          telemetry: _telemetry,
          perfTrace: _trace,
        );
        _scheduler!.setBudget(EdgeVedaBudget.adaptive(BudgetProfile.balanced));
        _scheduler!.registerWorkload(
          _workloadId,
          priority: WorkloadPriority.high,
        );
        _scheduler!.onBudgetViolation.listen((violation) {
          if (violation.observeOnly) {
            _observeOnlyViolationCount++;
          } else {
            _actionableViolationCount++;
            _lastViolation = '${violation.constraint.name}: '
                '${violation.currentValue.toStringAsFixed(1)} '
                '(budget: ${violation.budgetValue.toStringAsFixed(1)})';
          }
          notifyListeners();
        });
        _scheduler!.start();
      }

      _frameCount = 0;
      _totalTokens = 0;
      _lastLatencyMs = 0;
      _avgLatencyMs = 0;
      _totalLatencyMs = 0;
      _actionableViolationCount = 0;
      _observeOnlyViolationCount = 0;
      _lastViolation = null;
      _measuredBaseline = null;
      _resolvedBudget = null;
      _frameQueue.resetCounters();
      _policy.reset();

      _telemetryTimer =
          Timer.periodic(_telemetryInterval, (_) => _pollTelemetry());

      _startTime = DateTime.now();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isRunning || _startTime == null) return;
        final now = DateTime.now();
        _elapsed = now.difference(_startTime!);
        notifyListeners();
        if (_elapsed >= _testDuration) {
          stop();
        }
      });

      _isRunning = true;
      _isInitializing = false;
      _statusMessage = cameraSupported
          ? (Platform.isMacOS
              ? 'Screen capture running...'
              : 'Running in background...')
          : 'Monitoring user activity in background...';
      notifyListeners();

      if (cameraSupported) {
        if (Platform.isMacOS) {
          _startScreenCaptureLoop();
        } else {
          _startCameraStream();
        }
      }
    } catch (e) {
      _stopCameraStream();
      _stopScreenCaptureLoop();
      _telemetryTimer?.cancel();
      _telemetryTimer = null;
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _scheduler?.dispose();
      _scheduler = null;
      await _trace?.close();
      _trace = null;
      await _disposeInferenceWorkers();
      _frameQueue.reset();
      _isInitializing = false;
      _isRunning = false;
      _statusMessage = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!_isRunning && !_isInitializing) return;

    _isRunning = false;
    _isInitializing = false;

    _stopCameraStream();
    _stopScreenCaptureLoop();
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _scheduler?.dispose();
    _scheduler = null;

    await _trace?.close();
    _trace = null;

    await _disposeInferenceWorkers();
    _frameQueue.reset();

    _statusMessage = _frameCount > 0
        ? 'Complete: $_frameCount frames, ${_avgLatencyMs.toStringAsFixed(0)}ms avg'
        : 'Stopped';
    notifyListeners();
  }

  Future<void> shareTrace() async {
    if (_traceFilePath == null) return;
    try {
      await _telemetryChannel.invokeMethod('shareFile', {
        'path': _traceFilePath,
      });
    } on PlatformException {
      // Ignore share failures here, caller UI can remain responsive.
    }
  }

  Future<void> _ensureModelsDownloaded() async {
    // ── Step 1: find the best vision model already on disk ─────────────────
    // Priority: prefer larger/more capable models on macOS, smaller on mobile.
    // Accept a candidate even if only the mmproj is missing — we'll fetch it.
    final candidates = Platform.isMacOS
        ? [
            ModelRegistry.qwen2vl_7b,
            ModelRegistry.llava16_mistral_7b,
            ModelRegistry.smolvlm2_500m,
          ]
        : [
            ModelRegistry.smolvlm2_500m,
          ];

    ModelInfo? selectedModel;
    ModelInfo? selectedMmproj;
    bool mmprojMissing = false;

    for (final candidate in candidates) {
      final modelReady = await _modelManager.isModelDownloaded(candidate.id);
      if (!modelReady) continue; // model itself missing — skip

      final mmproj = ModelRegistry.getMmprojForModel(candidate.id);
      final mmprojReady =
          mmproj == null || await _modelManager.isModelDownloaded(mmproj.id);

      selectedModel = candidate;
      selectedMmproj = mmproj;
      mmprojMissing = !mmprojReady;
      debugPrint(
          '[SoakTest] matched model: ${candidate.id} (mmprojMissing=$mmprojMissing)');
      break;
    }

    // ── Step 2: upgrade or download the best model for this platform ──────
    // On macOS, if only the mobile-tier SmolVLM2 is available, upgrade to
    // Qwen2-VL 7B which produces far better screen descriptions.
    if (selectedModel == null ||
        (Platform.isMacOS &&
            selectedModel.id == ModelRegistry.smolvlm2_500m.id)) {
      if (Platform.isMacOS) {
        selectedModel = ModelRegistry.qwen2vl_7b;
        selectedMmproj = ModelRegistry.qwen2vl_7b_mmproj;
      } else {
        selectedModel = ModelRegistry.smolvlm2_500m;
        selectedMmproj = ModelRegistry.smolvlm2_500m_mmproj;
      }

      final modelReady =
          await _modelManager.isModelDownloaded(selectedModel.id);
      if (!modelReady) {
        _statusMessage =
            'Downloading ${selectedModel.name} (${_formatBytes(selectedModel.sizeBytes)})...';
        notifyListeners();
        await _modelManager.downloadModel(selectedModel);
      }
      mmprojMissing = true; // always check mmproj for the new model
    }

    // ── Step 2b: download missing mmproj only ──────────────────────────────
    if (mmprojMissing && selectedMmproj != null) {
      _statusMessage = 'Downloading mmproj for ${selectedModel.id}...';
      notifyListeners();
      await _modelManager.downloadModel(selectedMmproj);
    }

    // ── Step 3: resolve on-disk paths ───────────────────────────────────────
    _modelPath = await _modelManager.getModelPath(selectedModel.id);
    _mmprojPath = selectedMmproj != null
        ? await _modelManager.getModelPath(selectedMmproj.id)
        : null;

    debugPrint('[SoakTest] model=$_modelPath');
    debugPrint('[SoakTest] mmproj=$_mmprojPath');
  }

  Future<void> _disposeInferenceWorkers() async {
    await _visionWorker.dispose();
  }

  Future<void> _initializeCamera() async {
    // macOS uses screen capture instead of a camera.
    if (Platform.isMacOS) return;

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }
    await _cameraController?.dispose();
    _cameraController = null;

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
  }

  // ── macOS Screen Capture ──────────────────────────────────────────────────

  String? _cachedTempPath;
  int _lastFrameHash = 0;

  /// On macOS, poll the desktop at ~1 FPS and funnel each frame through the
  /// same [FrameQueue] / [_processNextFrame] pipeline used by the camera stream.
  void _startScreenCaptureLoop() {
    _screenCaptureTimer?.cancel();
    _screenCaptureTimer = Timer.periodic(
      const Duration(milliseconds: 1500), // ~0.7 FPS — gentle on GPU
      (_) async {
        if (!_isRunning) return;
        try {
          _cachedTempPath ??=
              '${(await getTemporaryDirectory()).path}/screen_frame.png';

          final capturedData = await ScreenCapturer.instance.capture(
            mode: CaptureMode.screen,
            imagePath: _cachedTempPath!,
            copyToClipboard: false,
            silent: true,
          );
          if (capturedData?.imageBytes == null) return;

          // Decode PNG → raw RGB using the `image` package (dart-native).
          final decoded = img.decodePng(capturedData!.imageBytes!);
          if (decoded == null) return;

          // Down-scale to 320-wide — CLIP patch count is proportional to
          // resolution squared; 320 vs 640 gives ~4× fewer patches and
          // proportionally faster image encoding (~750ms vs ~3000ms).
          final scaled = decoded.width > 320
              ? img.copyResize(decoded, width: 320)
              : decoded;

          // Bulk-extract bytes in RGB order (avoids slow per-pixel getPixel).
          final rgb =
              Uint8List.fromList(scaled.getBytes(order: img.ChannelOrder.rgb));

          // Frame-diff: skip if the screen hasn't changed. Sample 64 evenly
          // spaced pixels and hash them. Identical hash = identical frame.
          final stride = rgb.length ~/ 64;
          var hash = 0;
          for (int i = 0; i < rgb.length; i += stride) {
            hash = (hash * 31 + rgb[i]) & 0x7FFFFFFF;
          }
          if (hash == _lastFrameHash) return; // screen unchanged — skip
          _lastFrameHash = hash;

          _frameQueue.enqueue(rgb, scaled.width, scaled.height);
          unawaited(_processNextFrame());
        } catch (e) {
          debugPrint('[SoakTest] screen capture error: $e');
        }
      },
    );
  }

  void _stopScreenCaptureLoop() {
    _screenCaptureTimer?.cancel();
    _screenCaptureTimer = null;
  }

  /// Grab-and-stop: start the camera stream, capture ONE frame, immediately
  /// stop the stream to eliminate GC pressure during inference. On CPU-only
  /// devices the camera plugin delivers 30 CameraImage objects/sec even when
  /// frames are unused; each ~500 KB YUV allocation triggers GC that competes
  /// with the native inference thread for CPU time.
  void _startCameraStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) {
      if (!_isRunning) return;

      var rgb = Platform.isIOS
          ? CameraUtils.convertBgraToRgb(
              image.planes[0].bytes,
              image.width,
              image.height,
            )
          : CameraUtils.convertYuv420ToRgb(
              image.planes[0].bytes,
              image.planes[1].bytes,
              image.planes[2].bytes,
              image.width,
              image.height,
              image.planes[0].bytesPerRow,
              image.planes[1].bytesPerRow,
              image.planes[1].bytesPerPixel ?? 1,
            );

      // Stop the camera stream immediately after grabbing one frame.
      // This frees CPU and eliminates GC pressure while inference runs.
      _stopCameraStream();

      // Downscale to 128px longest side for CPU-only devices.
      // CLIP patch count scales quadratically (720x480 → ~1734 patches;
      // 128x85 → ~54 patches → ~1000x faster attention on CPU).
      var frameWidth = image.width;
      var frameHeight = image.height;
      const maxDim = 128;
      final longest = frameWidth > frameHeight ? frameWidth : frameHeight;
      if (longest > maxDim) {
        final scale = maxDim / longest;
        final newW = (frameWidth * scale).round();
        final newH = (frameHeight * scale).round();
        rgb = CameraUtils.resizeRgb(rgb, frameWidth, frameHeight, newW, newH);
        frameWidth = newW;
        frameHeight = newH;
      }

      _frameQueue.enqueue(rgb, frameWidth, frameHeight);
      unawaited(_processNextFrame());
    });
  }

  void _stopCameraStream() {
    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        _cameraController!.stopImageStream();
      }
    } catch (_) {
      // Ignore stop-stream errors.
    }
  }

  /// Record a user-driven inference event while soak monitoring is active.
  void recordExternalInference({
    required String source,
    required int latencyMs,
    int generatedTokens = 0,
    WorkloadId? workloadId,
  }) {
    if (!_isRunning || latencyMs <= 0) return;
    final id = workloadId ?? _workloadId;
    final latency = latencyMs.toDouble();

    _scheduler?.reportLatency(id, latency);
    _trace?.record(
      stage: 'user_inference',
      value: latency,
      extra: {
        'source': source,
        'generated_tokens': generatedTokens,
      },
    );
    _trace?.nextFrame();

    _frameCount++;
    _totalTokens += generatedTokens;
    _lastLatencyMs = latency;
    _totalLatencyMs += latency;
    _avgLatencyMs = _totalLatencyMs / _frameCount;
    _lastDescription = '$source inference: $latencyMs ms, $generatedTokens tok';
    _statusMessage = 'Monitoring user activity... ($_frameCount events)';
    notifyListeners();
  }

  Future<void> _processNextFrame() async {
    if (!_isRunning) return;

    final frame = _frameQueue.dequeue();
    if (frame == null) return;

    final QoSKnobs knobs;
    if (_isManaged) {
      knobs = _scheduler?.getKnobsForWorkload(_workloadId) ?? _policy.knobs;
      if (knobs.maxFps == 0) {
        _frameQueue.markDone();
        return;
      }
    } else {
      knobs = const QoSKnobs(maxFps: 2, resolution: 640, maxTokens: 100);
    }

    final stopwatch = Stopwatch()..start();

    try {
      final result = await _visionWorker.describeFrame(
        frame.rgb,
        frame.width,
        frame.height,
        prompt: 'Describe what you see in this image in one sentence.',
        maxTokens: knobs.maxTokens,
      );

      stopwatch.stop();
      final totalInferenceMs = stopwatch.elapsedMilliseconds.toDouble();

      _scheduler?.reportLatency(_workloadId, totalInferenceMs);
      _trace?.record(stage: 'image_encode', value: result.imageEncodeMs);
      _trace?.record(stage: 'prompt_eval', value: result.promptEvalMs);
      _trace?.record(stage: 'decode', value: result.decodeMs);
      _trace?.record(
        stage: 'total_inference',
        value: totalInferenceMs,
        extra: {
          'prompt_tokens': result.promptTokens,
          'generated_tokens': result.generatedTokens,
        },
      );
      _trace?.nextFrame();

      _frameCount++;
      _totalTokens += result.generatedTokens;
      _lastLatencyMs = totalInferenceMs;
      _totalLatencyMs += totalInferenceMs;
      _avgLatencyMs = _totalLatencyMs / _frameCount;
      _lastDescription = result.description;
      debugPrint('[SoakTest] frame=$_frameCount '
          'latency=${totalInferenceMs.toStringAsFixed(0)}ms '
          'encode=${result.imageEncodeMs.toStringAsFixed(0)}ms '
          'tokens=${result.generatedTokens}');
      notifyListeners();
    } catch (e) {
      debugPrint('[SoakTest] frame error: $e');
    } finally {
      _frameQueue.markDone();
      if (_isRunning) {
        // Restart camera to grab the next frame (grab-and-stop pattern).
        _startCameraStream();
      }
    }
  }

  Future<void> _pollTelemetry() async {
    if (!_isRunning) return;

    try {
      final snap = await _telemetry.snapshot();

      _trace?.record(stage: 'rss_bytes', value: snap.memoryRssBytes.toDouble());
      _trace?.record(
          stage: 'thermal_state', value: snap.thermalState.toDouble());
      _trace?.record(stage: 'battery_level', value: snap.batteryLevel);
      _trace?.record(
        stage: 'available_memory',
        value: snap.availableMemoryBytes.toDouble(),
      );

      final newQoS = _policy.evaluate(
        thermalState: snap.thermalState,
        batteryLevel: snap.batteryLevel,
        availableMemoryBytes: snap.availableMemoryBytes,
        isLowPowerMode: snap.isLowPowerMode,
      );

      final baseline = _isManaged ? _scheduler?.measuredBaseline : null;
      final resolved = _isManaged ? _scheduler?.resolvedBudget : null;

      _thermalState = snap.thermalState;
      _batteryLevel = snap.batteryLevel;
      _memoryRssBytes = snap.memoryRssBytes;
      _currentQoS = newQoS;
      _measuredBaseline = baseline;
      _resolvedBudget = resolved;
      notifyListeners();
    } catch (_) {
      // Ignore telemetry poll errors to keep soak running.
    }
  }

  /// Adaptive thread count based on platform and available cores.
  ///
  /// Android CPU-only: cap at half-cores (max 4) to prevent thermal throttle
  /// on big.LITTLE SoCs. macOS: up to 6 for screen capture inference.
  /// iOS: up to 4 (Metal handles GPU work).
  static int _adaptiveThreadCount() {
    final cores = Platform.numberOfProcessors;
    if (Platform.isMacOS) {
      return min(cores, 6);
    }
    // Android/iOS: cap at half of available cores, max 4 for thermal safety
    return min((cores / 2).ceil(), 4);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
