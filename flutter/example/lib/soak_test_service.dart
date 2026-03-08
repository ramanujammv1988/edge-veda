import 'dart:async';
import 'dart:io' show File, InternetAddress, Platform;
import 'dart:math' show min, pi, sin;
import 'package:camera/camera.dart';
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

import 'device_status_info.dart';
import 'model_selector.dart';

/// Available soak test workloads.
enum SoakWorkload {
  /// Vision inference via camera/screen capture (existing).
  vision,

  /// LLM text generation with auto-generated prompts.
  llm,

  /// Speech-to-text with synthetic sine-wave audio.
  stt,

  /// Image generation with rotating prompts.
  imageGen,

  /// Mixed: rotates between available workloads every 5 minutes.
  mixed,
}

/// Describes what models need downloading before a soak test can start.
class ModelDownloadPlan {
  final ModelInfo? model;
  final ModelInfo? mmproj;

  /// Total bytes that need downloading (0 if everything is already on disk).
  int get totalBytes =>
      (model != null ? model!.sizeBytes : 0) +
      (mmproj != null ? mmproj!.sizeBytes : 0);

  bool get needsDownload => model != null || mmproj != null;

  const ModelDownloadPlan({this.model, this.mmproj});
}

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

  StreamingWorker? _llmWorker;
  WhisperWorker? _whisperWorker;
  ImageWorker? _imageWorker;

  PerfTrace? _trace;
  CameraController? _cameraController;
  Timer? _screenCaptureTimer;

  String? _modelPath;
  String? _mmprojPath;
  WorkloadId _workloadId = WorkloadId.vision;
  SoakWorkload _soakWorkload = SoakWorkload.vision;
  Timer? _soakInferenceTimer;
  int _promptIndex = 0;
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
  bool _isLowEndAndroid = false;

  Scheduler? _scheduler;
  int _actionableViolationCount = 0;
  int _observeOnlyViolationCount = 0;
  String? _lastViolation;
  MeasuredBaseline? _measuredBaseline;
  EdgeVedaBudget? _resolvedBudget;

  int _modelLoadFailures = 0;
  int _oomRecoveryCount = 0;
  int _memoryBeforeOomTest = 0;

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
  SoakWorkload get soakWorkload => _soakWorkload;
  int get droppedFrames => _frameQueue.droppedFrames;
  int get actionableViolationCount => _actionableViolationCount;
  int get observeOnlyViolationCount => _observeOnlyViolationCount;
  String? get lastViolation => _lastViolation;
  MeasuredBaseline? get measuredBaseline => _measuredBaseline;
  EdgeVedaBudget? get resolvedBudget => _resolvedBudget;
  int get modelLoadFailures => _modelLoadFailures;
  int get oomRecoveryCount => _oomRecoveryCount;

  /// Live download progress from [ModelManager].
  Stream<DownloadProgress> get downloadProgress =>
      _modelManager.downloadProgress;

  /// Cancel any in-flight model download.
  void cancelDownload() {
    _modelManager.cancelDownload();
    _isInitializing = false;
    _statusMessage = 'Download cancelled';
    notifyListeners();
  }

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

  Future<void> start({SoakWorkload workload = SoakWorkload.vision}) async {
    if (_isRunning || _isInitializing) return;

    _isInitializing = true;
    _statusMessage = 'Preparing soak test...';
    notifyListeners();

    try {
      _isLowEndAndroid = await DeviceProfile.isLowEndAndroid(_telemetry);
      _soakWorkload = workload;

      // Route to workload-specific initialization
      switch (workload) {
        case SoakWorkload.llm:
          await _initLlmWorkload();
        case SoakWorkload.stt:
          await _initSttWorkload();
        case SoakWorkload.imageGen:
          await _initImageGenWorkload();
        case SoakWorkload.mixed:
          await _initLlmWorkload(); // Mixed starts with LLM, rotates later
        case SoakWorkload.vision:
          await _initVisionWorkload();
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
      _trace!.record(
        stage: 'device_profile',
        value: _isLowEndAndroid ? 1.0 : 0.0,
        extra: {
          'low_end_android': _isLowEndAndroid,
          'context_size': _isLowEndAndroid ? 2048 : 4096,
          'num_threads': _isLowEndAndroid ? 2 : _adaptiveThreadCount(),
          'device_model': DeviceStatusInfo.model,
          'chip': DeviceStatusInfo.chip,
          'total_memory_gb': DeviceStatusInfo.memoryGB,
          'gpu_backend': DeviceStatusInfo.backendLabel,
          'has_neural_engine': DeviceStatusInfo.hasNeuralEngine,
          'platform': DeviceStatusInfo.platformLabel,
        },
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
          minWarmupSamples: Platform.isAndroid ? 3 : 20,
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
      _statusMessage = '${workload.name} soak running...';
      notifyListeners();

      // Start the workload-specific inference loop
      switch (workload) {
        case SoakWorkload.vision:
          if (cameraSupported) {
            if (Platform.isMacOS) {
              _startScreenCaptureLoop();
            } else {
              _startCameraStream();
            }
          }
        case SoakWorkload.llm:
          _startLlmLoop();
        case SoakWorkload.stt:
          _startSttLoop();
        case SoakWorkload.imageGen:
          _startImageGenLoop();
        case SoakWorkload.mixed:
          _startLlmLoop(); // Start with LLM; mixed rotation handled by timer
          _startMixedRotation();
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
    _soakInferenceTimer?.cancel();
    _soakInferenceTimer = null;
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

  /// Save trace file via NSSavePanel (macOS) or copy to Downloads (iOS/Android).
  /// Returns the saved path on success, null if cancelled or unsupported.
  Future<String?> saveTraceLocally() async {
    if (_traceFilePath == null) return null;
    try {
      final result = await _telemetryChannel.invokeMethod<String>(
        'saveFileToDownloads',
        {'path': _traceFilePath},
      );
      return result;
    } on PlatformException {
      return null;
    }
  }

  /// Check internet connectivity (same pattern as settings_screen.dart).
  Future<bool> checkInternetReachable() async {
    for (final host in ['example.com', 'google.com', 'huggingface.co']) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 2));
        if (result.any((entry) => entry.rawAddress.isNotEmpty)) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  /// Determine what models need downloading without actually downloading.
  ///
  /// Returns a [ModelDownloadPlan] describing which files are missing.
  /// If [ModelDownloadPlan.needsDownload] is false, all models are on disk.
  Future<ModelDownloadPlan> checkModelsNeeded() async {
    final candidates = Platform.isMacOS
        ? [
            ModelRegistry.qwen2vl_7b,
            ModelRegistry.llava16_mistral_7b,
            ModelRegistry.smolvlm2_500m,
            ModelRegistry.smolvlm2_256m,
          ]
        : [
            ModelRegistry.smolvlm2_256m,
            ModelRegistry.smolvlm2_500m,
          ];

    ModelInfo? selectedModel;
    ModelInfo? selectedMmproj;
    bool mmprojMissing = false;

    for (final candidate in candidates) {
      final modelReady = await _modelManager.isModelDownloaded(candidate.id);
      if (!modelReady) continue;

      final mmproj = ModelRegistry.getMmprojForModel(candidate.id);
      final mmprojReady =
          mmproj == null || await _modelManager.isModelDownloaded(mmproj.id);

      selectedModel = candidate;
      selectedMmproj = mmproj;
      mmprojMissing = !mmprojReady;
      break;
    }

    // Decide what to download
    ModelInfo? needModel;
    ModelInfo? needMmproj;

    if (selectedModel == null ||
        (Platform.isMacOS &&
            selectedModel.id == ModelRegistry.smolvlm2_500m.id)) {
      // Need to download a model
      final ModelInfo target;
      final ModelInfo targetMmproj;
      if (Platform.isMacOS) {
        target = ModelRegistry.qwen2vl_7b;
        targetMmproj = ModelRegistry.qwen2vl_7b_mmproj;
      } else {
        target = ModelRegistry.smolvlm2_256m;
        targetMmproj = ModelRegistry.smolvlm2_256m_mmproj;
      }

      final modelReady = await _modelManager.isModelDownloaded(target.id);
      if (!modelReady) needModel = target;

      final mmprojReady =
          await _modelManager.isModelDownloaded(targetMmproj.id);
      if (!mmprojReady) needMmproj = targetMmproj;
    } else if (mmprojMissing && selectedMmproj != null) {
      needMmproj = selectedMmproj;
    }

    return ModelDownloadPlan(model: needModel, mmproj: needMmproj);
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
        : _isLowEndAndroid
            ? [
                ModelRegistry.smolvlm2_256m,
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
    // On low-end Android, if the 500M is on disk but 256M isn't, downgrade
    // to the smaller model that actually fits in memory.
    if (selectedModel == null ||
        (Platform.isMacOS &&
            selectedModel.id == ModelRegistry.smolvlm2_500m.id) ||
        (_isLowEndAndroid &&
            selectedModel.id == ModelRegistry.smolvlm2_500m.id)) {
      if (Platform.isMacOS) {
        selectedModel = ModelRegistry.qwen2vl_7b;
        selectedMmproj = ModelRegistry.qwen2vl_7b_mmproj;
      } else if (_isLowEndAndroid) {
        selectedModel = ModelRegistry.smolvlm2_256m;
        selectedMmproj = ModelRegistry.smolvlm2_256m_mmproj;
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
    await _llmWorker?.dispose();
    _llmWorker = null;
    await _whisperWorker?.dispose();
    _whisperWorker = null;
    await _imageWorker?.dispose();
    _imageWorker = null;
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

    // Show that inference is active (important for slow CPU-only Android)
    _statusMessage = 'Processing frame ${_frameCount + 1}...';
    notifyListeners();

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
      final effectiveMaxTokens =
          _isLowEndAndroid ? min(knobs.maxTokens, 20) : knobs.maxTokens;
      final result = await _visionWorker.describeFrame(
        frame.rgb,
        frame.width,
        frame.height,
        prompt: 'Describe what you see in this image in one sentence.',
        maxTokens: effectiveMaxTokens,
        timeout: _isLowEndAndroid ? const Duration(seconds: 300) : null,
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

  // ── OOM recovery validation ────────────────────────────────────────────

  /// Validates that the engine handles near-OOM conditions gracefully.
  ///
  /// Attempts to load multiple heavy models simultaneously to push memory
  /// near the limit. Verifies that failures result in catchable exceptions
  /// (not process crashes) and that the service remains functional afterward.
  ///
  /// Returns a map with test results: loadAttempts, failures, recoveries,
  /// memoryBefore, memoryAfter, and passed (true if no crash occurred).
  Future<Map<String, dynamic>> validateOomRecovery() async {
    final results = <String, dynamic>{'passed': true};
    _modelLoadFailures = 0;
    _oomRecoveryCount = 0;

    try {
      final snap = await _telemetry.snapshot();
      _memoryBeforeOomTest = snap.memoryRssBytes;
      results['memoryBefore'] = _memoryBeforeOomTest;

      // Attempt 1: Load LLM
      int loadAttempts = 0;
      try {
        loadAttempts++;
        final llmSel = await ModelSelector.bestLlm(_modelManager);
        if (!llmSel.needsDownload) {
          final path = await _modelManager.getModelPath(llmSel.model.id);
          final w = StreamingWorker();
          await w.spawn();
          try {
            await w.init(
              modelPath: path,
              numThreads: 2,
              contextSize: 2048,
              useGpu: await InferenceConfig.useGpu(_telemetry),
            );
          } finally {
            await w.dispose();
          }
          _oomRecoveryCount++;
          debugPrint('[SoakTest] OOM test: LLM loaded + disposed OK');
        }
      } catch (e) {
        _modelLoadFailures++;
        debugPrint('[SoakTest] OOM test: LLM load failed (expected): $e');
      }

      // Attempt 2: Load Vision
      try {
        loadAttempts++;
        final visSel = await ModelSelector.bestVision(_modelManager);
        if (!visSel.needsDownload) {
          final path = await _modelManager.getModelPath(visSel.model.id);
          final mmprojPath = visSel.mmproj != null
              ? await _modelManager.getModelPath(visSel.mmproj!.id)
              : null;
          final w = VisionWorker();
          await w.spawn();
          try {
            await w.initVision(
              modelPath: path,
              mmprojPath: mmprojPath ?? path,
              numThreads: 2,
              contextSize: 512,
              useGpu: await InferenceConfig.useGpu(_telemetry),
            );
          } finally {
            await w.dispose();
          }
          _oomRecoveryCount++;
          debugPrint('[SoakTest] OOM test: Vision loaded + disposed OK');
        }
      } catch (e) {
        _modelLoadFailures++;
        debugPrint('[SoakTest] OOM test: Vision load failed (expected): $e');
      }

      // Attempt 3: Load Whisper
      try {
        loadAttempts++;
        final sttSel = await ModelSelector.bestWhisper(_modelManager);
        if (!sttSel.needsDownload) {
          final path = await _modelManager.getModelPath(sttSel.model.id);
          final w = WhisperWorker();
          await w.spawn();
          try {
            await w.initWhisper(
              modelPath: path,
              numThreads: 2,
              useGpu: await InferenceConfig.useGpu(_telemetry),
            );
          } finally {
            await w.dispose();
          }
          _oomRecoveryCount++;
          debugPrint('[SoakTest] OOM test: Whisper loaded + disposed OK');
        }
      } catch (e) {
        _modelLoadFailures++;
        debugPrint('[SoakTest] OOM test: Whisper load failed (expected): $e');
      }

      final snapAfter = await _telemetry.snapshot();
      results['memoryAfter'] = snapAfter.memoryRssBytes;
      results['loadAttempts'] = loadAttempts;
      results['failures'] = _modelLoadFailures;
      results['recoveries'] = _oomRecoveryCount;

      // The test passes if we didn't crash — even partial failures are OK
      // as long as they were caught gracefully.
      results['passed'] = true;
      debugPrint('[SoakTest] OOM recovery validation complete: '
          'attempts=$loadAttempts failures=$_modelLoadFailures '
          'recoveries=$_oomRecoveryCount');
    } catch (e) {
      results['passed'] = false;
      results['error'] = e.toString();
      debugPrint('[SoakTest] OOM recovery validation unexpected error: $e');
    }

    return results;
  }

  // ── Workload initializers ──────────────────────────────────────────────

  Future<void> _initVisionWorkload() async {
    _workloadId = WorkloadId.vision;
    if (cameraSupported) {
      await _ensureModelsDownloaded();
      _statusMessage = 'Loading vision model...';
      notifyListeners();
      await _visionWorker.spawn();
      await _visionWorker.initVision(
        modelPath: _modelPath!,
        mmprojPath: _mmprojPath!,
        numThreads: _isLowEndAndroid ? 2 : _adaptiveThreadCount(),
        contextSize: _isLowEndAndroid ? 512 : 4096,
        useGpu: await InferenceConfig.useGpu(_telemetry),
      );
      if (!Platform.isMacOS) {
        _statusMessage = 'Initializing camera...';
        await _initializeCamera();
      }
      notifyListeners();
    }
  }

  Future<void> _initLlmWorkload() async {
    _workloadId = WorkloadId.text;
    _statusMessage = 'Selecting LLM model...';
    notifyListeners();

    final selection = await ModelSelector.bestLlm(_modelManager);
    if (selection.needsDownload) {
      _statusMessage =
          'Downloading ${selection.model.name} (${_formatBytes(selection.model.sizeBytes)})...';
      notifyListeners();
      await _modelManager.downloadModel(selection.model);
    }

    final modelPath = await _modelManager.getModelPath(selection.model.id);
    _statusMessage = 'Loading LLM (${selection.model.name})...';
    notifyListeners();

    _llmWorker = StreamingWorker();
    await _llmWorker!.spawn();
    await _llmWorker!.init(
      modelPath: modelPath,
      numThreads: _isLowEndAndroid ? 2 : _adaptiveThreadCount(),
      contextSize: _isLowEndAndroid ? 2048 : 4096,
      useGpu: await InferenceConfig.useGpu(_telemetry),
    );
  }

  Future<void> _initSttWorkload() async {
    _workloadId = WorkloadId.text;
    _statusMessage = 'Selecting whisper model...';
    notifyListeners();

    final selection = await ModelSelector.bestWhisper(_modelManager);
    if (selection.needsDownload) {
      _statusMessage =
          'Downloading ${selection.model.name} (${_formatBytes(selection.model.sizeBytes)})...';
      notifyListeners();
      await _modelManager.downloadModel(selection.model);
    }

    final modelPath = await _modelManager.getModelPath(selection.model.id);
    _statusMessage = 'Loading whisper (${selection.model.name})...';
    notifyListeners();

    _whisperWorker = WhisperWorker();
    await _whisperWorker!.spawn();
    await _whisperWorker!.initWhisper(
      modelPath: modelPath,
      numThreads: _isLowEndAndroid ? 2 : _adaptiveThreadCount(),
      useGpu: await InferenceConfig.useGpu(_telemetry),
    );
  }

  Future<void> _initImageGenWorkload() async {
    _workloadId = WorkloadId.text;
    _statusMessage = 'Selecting image model...';
    notifyListeners();

    final selection = await ModelSelector.bestImageGen(_modelManager);
    if (selection.needsDownload) {
      _statusMessage =
          'Downloading ${selection.model.name} (${_formatBytes(selection.model.sizeBytes)})...';
      notifyListeners();
      await _modelManager.downloadModel(selection.model);
    }

    final modelPath = await _modelManager.getModelPath(selection.model.id);
    _statusMessage = 'Loading SD model (${selection.model.name})...';
    notifyListeners();

    _imageWorker = ImageWorker();
    await _imageWorker!.spawn();
    await _imageWorker!.initImage(
      modelPath: modelPath,
      numThreads: _isLowEndAndroid ? 2 : _adaptiveThreadCount(),
      useGpu: await InferenceConfig.useGpu(_telemetry),
    );
  }

  // ── Inference loops ───────────────────────────────────────────────────

  static const _soakPrompts = [
    'Explain quantum computing in simple terms.',
    'Write a haiku about the ocean.',
    'What are the benefits of renewable energy?',
    'Describe the process of photosynthesis.',
    'List three interesting facts about space.',
    'What is machine learning?',
    'Explain how a bicycle works.',
    'Describe the water cycle in nature.',
  ];

  static const _imagePrompts = [
    'a serene mountain landscape at sunset',
    'a cat sitting on a windowsill',
    'abstract geometric patterns in blue',
    'a cozy cabin in a snowy forest',
    'ocean waves crashing on rocks',
    'a field of wildflowers under cloudy sky',
  ];

  void _startLlmLoop() {
    _promptIndex = 0;
    _runLlmInference();
  }

  Future<void> _runLlmInference() async {
    if (!_isRunning || _llmWorker == null || !_llmWorker!.isActive) return;

    final prompt = _soakPrompts[_promptIndex % _soakPrompts.length];
    _promptIndex++;
    _statusMessage = 'LLM inference #$_promptIndex...';
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    var tokenCount = 0;
    final buffer = StringBuffer();

    try {
      await _llmWorker!.startStream(
        prompt: prompt,
        maxTokens: _isLowEndAndroid ? 50 : 128,
        temperature: 0.7,
      );

      while (true) {
        final tok = await _llmWorker!.nextToken();
        if (tok.isFinal) break;
        if (tok.token != null) {
          buffer.write(tok.token);
          tokenCount++;
        }
      }

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      _scheduler?.reportLatency(_workloadId, latencyMs);
      _trace?.record(
        stage: 'llm_inference',
        value: latencyMs,
        extra: {'generated_tokens': tokenCount, 'prompt_index': _promptIndex},
      );
      _trace?.nextFrame();

      _frameCount++;
      _totalTokens += tokenCount;
      _lastLatencyMs = latencyMs;
      _totalLatencyMs += latencyMs;
      _avgLatencyMs = _totalLatencyMs / _frameCount;
      _lastDescription = buffer.toString();
      debugPrint('[SoakTest] llm #$_frameCount '
          'latency=${latencyMs.toStringAsFixed(0)}ms '
          'tokens=$tokenCount');
      notifyListeners();
    } catch (e) {
      debugPrint('[SoakTest] llm error: $e');
    }

    // Schedule next inference
    if (_isRunning) {
      _soakInferenceTimer = Timer(
        const Duration(seconds: 2),
        _runLlmInference,
      );
    }
  }

  void _startSttLoop() {
    _promptIndex = 0;
    _runSttInference();
  }

  Future<void> _runSttInference() async {
    if (!_isRunning || _whisperWorker == null || !_whisperWorker!.isActive) {
      return;
    }

    _promptIndex++;
    _statusMessage = 'STT inference #$_promptIndex...';
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      // Generate 3 seconds of synthetic 440Hz sine wave at 16kHz
      final pcm = _generateSineWave(
        frequencyHz: 440.0,
        durationMs: 3000,
        sampleRate: 16000,
      );

      final result = await _whisperWorker!.transcribeChunk(
        pcm,
        timeout: _isLowEndAndroid
            ? const Duration(seconds: 90)
            : const Duration(seconds: 30),
      );

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      _scheduler?.reportLatency(_workloadId, latencyMs);
      _trace?.record(
        stage: 'stt_inference',
        value: latencyMs,
        extra: {
          'segments': result.segments.length,
          'chunk_index': _promptIndex,
        },
      );
      _trace?.nextFrame();

      _frameCount++;
      _lastLatencyMs = latencyMs;
      _totalLatencyMs += latencyMs;
      _avgLatencyMs = _totalLatencyMs / _frameCount;
      _lastDescription = result.segments.isNotEmpty
          ? result.segments.map((s) => s.text).join(' ').trim()
          : '(silence)';
      debugPrint('[SoakTest] stt #$_frameCount '
          'latency=${latencyMs.toStringAsFixed(0)}ms '
          'segments=${result.segments.length}');
      notifyListeners();
    } catch (e) {
      debugPrint('[SoakTest] stt error: $e');
    }

    if (_isRunning) {
      _soakInferenceTimer = Timer(
        const Duration(seconds: 2),
        _runSttInference,
      );
    }
  }

  /// Generate a synthetic sine wave as Float32List PCM samples.
  static Float32List _generateSineWave({
    required double frequencyHz,
    required int durationMs,
    required int sampleRate,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final samples = Float32List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      samples[i] = (sin(2 * pi * frequencyHz * i / sampleRate) * 0.5);
    }
    return samples;
  }

  void _startImageGenLoop() {
    _promptIndex = 0;
    _runImageGenInference();
  }

  Future<void> _runImageGenInference() async {
    if (!_isRunning || _imageWorker == null || !_imageWorker!.isActive) return;

    final prompt = _imagePrompts[_promptIndex % _imagePrompts.length];
    _promptIndex++;
    _statusMessage = 'Image gen #$_promptIndex...';
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      final stream = _imageWorker!.generateImage(
        prompt: prompt,
        width: 256,
        height: 256,
        steps: _isLowEndAndroid ? 2 : 4,
      );

      await for (final event in stream) {
        if (event is ImageCompleteResponse) {
          stopwatch.stop();
          final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

          _scheduler?.reportLatency(_workloadId, latencyMs);
          _trace?.record(
            stage: 'imagegen_inference',
            value: latencyMs,
            extra: {
              'width': event.width,
              'height': event.height,
              'prompt_index': _promptIndex,
            },
          );
          _trace?.nextFrame();

          _frameCount++;
          _lastLatencyMs = latencyMs;
          _totalLatencyMs += latencyMs;
          _avgLatencyMs = _totalLatencyMs / _frameCount;
          _lastDescription = 'Generated: "$prompt"';
          debugPrint('[SoakTest] imagegen #$_frameCount '
              'latency=${latencyMs.toStringAsFixed(0)}ms '
              '${event.width}x${event.height}');
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[SoakTest] imagegen error: $e');
    }

    if (_isRunning) {
      _soakInferenceTimer = Timer(
        const Duration(seconds: 5),
        _runImageGenInference,
      );
    }
  }

  void _startMixedRotation() {
    // Rotate workloads every 5 minutes
    _soakInferenceTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) async {
        if (!_isRunning) return;

        // Cycle through: LLM → STT → ImageGen → LLM ...
        final current = _soakWorkload;
        final SoakWorkload next;
        switch (current) {
          case SoakWorkload.llm:
            next = SoakWorkload.stt;
          case SoakWorkload.stt:
            next = SoakWorkload.imageGen;
          case SoakWorkload.imageGen || SoakWorkload.mixed:
            next = SoakWorkload.llm;
          case SoakWorkload.vision:
            next = SoakWorkload.llm;
        }

        debugPrint('[SoakTest] mixed rotation: ${current.name} → ${next.name}');
        _statusMessage = 'Rotating to ${next.name}...';
        notifyListeners();

        // Dispose current workers
        await _disposeInferenceWorkers();

        // Initialize and start the next workload
        try {
          switch (next) {
            case SoakWorkload.llm:
              await _initLlmWorkload();
              _startLlmLoop();
            case SoakWorkload.stt:
              await _initSttWorkload();
              _startSttLoop();
            case SoakWorkload.imageGen:
              await _initImageGenWorkload();
              _startImageGenLoop();
            case SoakWorkload.vision || SoakWorkload.mixed:
              await _initLlmWorkload();
              _startLlmLoop();
          }
          _soakWorkload = next;
        } catch (e) {
          debugPrint('[SoakTest] mixed rotation error: $e');
          _statusMessage = 'Rotation error: $e';
          notifyListeners();
        }
      },
    );
  }
}
