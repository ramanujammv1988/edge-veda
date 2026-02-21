import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:camera/camera.dart';
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// App-level soak runner that keeps running even when the Soak screen is closed.
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

  static const _testDuration = Duration(minutes: 10);
  static const _telemetryInterval = Duration(seconds: 2);
  static const _telemetryChannel =
      MethodChannel('com.edgeveda.edge_veda/telemetry');

  bool get cameraSupported => Platform.isIOS || Platform.isAndroid;
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
          numThreads: 4,
          contextSize: 4096,
          useGpu: true,
        );
        _statusMessage = 'Initializing camera...';
        notifyListeners();
        await _initializeCamera();
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
          ? 'Running in background...'
          : 'Monitoring user activity in background...';
      notifyListeners();

      if (cameraSupported) {
        _startCameraStream();
      }
    } catch (e) {
      _stopCameraStream();
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
    const model = ModelRegistry.smolvlm2_500m;
    const mmproj = ModelRegistry.smolvlm2_500m_mmproj;

    final modelDownloaded = await _modelManager.isModelDownloaded(model.id);
    final mmprojDownloaded = await _modelManager.isModelDownloaded(mmproj.id);

    if (!modelDownloaded || !mmprojDownloaded) {
      _statusMessage = 'Downloading vision model...';
      notifyListeners();

      if (!modelDownloaded) {
        _modelPath = await _modelManager.downloadModel(model);
      } else {
        _modelPath = await _modelManager.getModelPath(model.id);
      }

      if (!mmprojDownloaded) {
        _mmprojPath = await _modelManager.downloadModel(mmproj);
      } else {
        _mmprojPath = await _modelManager.getModelPath(mmproj.id);
      }
    } else {
      _modelPath = await _modelManager.getModelPath(model.id);
      _mmprojPath = await _modelManager.getModelPath(mmproj.id);
    }
  }

  Future<void> _disposeInferenceWorkers() async {
    await _visionWorker.dispose();
  }

  Future<void> _initializeCamera() async {
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

  void _startCameraStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) {
      if (!_isRunning) return;

      final rgb = Platform.isIOS
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

      _frameQueue.enqueue(rgb, image.width, image.height);
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
      notifyListeners();
    } catch (_) {
      // Ignore transient per-frame failures while keeping soak active.
    } finally {
      _frameQueue.markDone();
      if (_frameQueue.hasPending && _isRunning) {
        unawaited(_processNextFrame());
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
}
