import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// 20-minute sustained vision inference benchmark with live metrics.
///
/// Integrates all Phase 11 infrastructure:
/// - [VisionWorker]: persistent isolate (model loaded once)
/// - [FrameQueue]: drop-newest backpressure
/// - [PerfTrace]: JSONL per-frame timing + telemetry recording
/// - [TelemetryService]: thermal, battery, memory polling
/// - [RuntimePolicy]: QoS adaptation based on device pressure
///
/// Records every frame's timing data and periodic telemetry snapshots
/// to a JSONL file for offline analysis.
class SoakTestScreen extends StatefulWidget {
  const SoakTestScreen({super.key});

  @override
  State<SoakTestScreen> createState() => _SoakTestScreenState();
}

class _SoakTestScreenState extends State<SoakTestScreen> {
  // Components
  final VisionWorker _visionWorker = VisionWorker();
  final FrameQueue _frameQueue = FrameQueue();
  final TelemetryService _telemetry = TelemetryService();
  final RuntimePolicy _policy = RuntimePolicy();
  PerfTrace? _trace;
  final ModelManager _modelManager = ModelManager();

  // Camera
  CameraController? _cameraController;

  // Model paths
  String? _modelPath;
  String? _mmprojPath;

  // State
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

  // Budget enforcement
  Scheduler? _scheduler;
  int _actionableViolationCount = 0;
  int _observeOnlyViolationCount = 0;
  String? _lastViolation;
  MeasuredBaseline? _measuredBaseline;
  EdgeVedaBudget? _resolvedBudget;

  // Timers
  Timer? _telemetryTimer;
  Timer? _elapsedTimer;
  DateTime? _startTime;

  // Benchmark mode: managed (full Edge-Veda stack) vs raw (bare llama.cpp)
  bool _isManaged = true;

  // Test configuration
  static const _testDuration = Duration(minutes: 20);
  static const _telemetryInterval = Duration(seconds: 2);

  @override
  void dispose() {
    _stop();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Start Flow ─────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (_isRunning || _isInitializing) return;

    setState(() {
      _isInitializing = true;
      _statusMessage = 'Preparing soak test...';
    });

    try {
      // Step 1: Download models if needed
      await _ensureModelsDownloaded();
      if (!mounted) return;

      // Step 2: Spawn VisionWorker and init vision
      setState(() => _statusMessage = 'Loading vision model...');
      await _visionWorker.spawn();
      await _visionWorker.initVision(
        modelPath: _modelPath!,
        mmprojPath: _mmprojPath!,
        numThreads: 4,
        contextSize: 4096,
        useGpu: true,
      );
      if (!mounted) return;

      // Step 3: Initialize camera
      setState(() => _statusMessage = 'Initializing camera...');
      await _initializeCamera();
      if (!mounted) return;

      // Step 4: Create PerfTrace file
      final docsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .substring(0, 15);
      final modeLabel = _isManaged ? 'managed' : 'raw';
      final traceFile = File('${docsDir.path}/soak_${modeLabel}_$timestamp.jsonl');
      _trace = PerfTrace(traceFile);
      _traceFilePath = traceFile.path;

      // Record benchmark mode in trace header
      _trace!.record(
        stage: 'benchmark_mode',
        value: _isManaged ? 1.0 : 0.0,
        extra: {'mode': modeLabel},
      );

      // Step 4.5: Create Scheduler with budget (managed mode only)
      if (_isManaged) {
        _scheduler = Scheduler(
          telemetry: _telemetry,
          perfTrace: _trace,
        );
        _scheduler!.setBudget(EdgeVedaBudget.adaptive(BudgetProfile.balanced));
        _scheduler!.registerWorkload(
          WorkloadId.vision,
          priority: WorkloadPriority.high,
        );
        _scheduler!.onBudgetViolation.listen((violation) {
          if (!mounted) return;
          setState(() {
            if (violation.observeOnly) {
              _observeOnlyViolationCount++;
            } else {
              _actionableViolationCount++;
              _lastViolation = '${violation.constraint.name}: '
                  '${violation.currentValue.toStringAsFixed(1)} '
                  '(budget: ${violation.budgetValue.toStringAsFixed(1)})';
            }
          });
        });
        _scheduler!.start();
      }

      // Step 5: Reset counters
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

      // Step 6: Start telemetry polling
      _telemetryTimer = Timer.periodic(_telemetryInterval, (_) => _pollTelemetry());

      // Step 7: Start elapsed time timer
      _startTime = DateTime.now();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final now = DateTime.now();
        final newElapsed = now.difference(_startTime!);
        setState(() {
          _elapsed = newElapsed;
        });
        // Auto-stop after test duration
        if (newElapsed >= _testDuration) {
          _stop();
        }
      });

      // Step 8: Start camera stream
      setState(() {
        _isRunning = true;
        _isInitializing = false;
        _statusMessage = 'Running...';
      });

      _startCameraStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Error: $e';
        });
      }
      debugPrint('Soak test init error: $e');
    }
  }

  // ── Stop Flow ──────────────────────────────────────────────────────────

  Future<void> _stop() async {
    if (!_isRunning && !_isInitializing) return;

    // Stop camera stream
    _stopCameraStream();

    // Stop timers
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    // Stop Scheduler
    _scheduler?.dispose();
    _scheduler = null;

    // Close PerfTrace
    await _trace?.close();
    _trace = null;

    // Dispose VisionWorker
    await _visionWorker.dispose();

    // Reset FrameQueue
    _frameQueue.reset();

    if (mounted) {
      setState(() {
        _isRunning = false;
        _isInitializing = false;
        _statusMessage = _frameCount > 0
            ? 'Complete: $_frameCount frames, '
              '${_avgLatencyMs.toStringAsFixed(0)}ms avg'
            : 'Stopped';
      });
    }
  }

  // ── Model Download ─────────────────────────────────────────────────────

  Future<void> _ensureModelsDownloaded() async {
    final model = ModelRegistry.smolvlm2_500m;
    final mmproj = ModelRegistry.smolvlm2_500m_mmproj;

    final modelDownloaded = await _modelManager.isModelDownloaded(model.id);
    final mmprojDownloaded = await _modelManager.isModelDownloaded(mmproj.id);

    if (!modelDownloaded || !mmprojDownloaded) {
      setState(() => _statusMessage = 'Downloading vision model...');

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

  // ── Camera ─────────────────────────────────────────────────────────────

  Future<void> _initializeCamera() async {
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
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
  }

  void _startCameraStream() {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) {
      if (!_isRunning) return;

      // Convert to RGB
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
      _processNextFrame();
    });
  }

  void _stopCameraStream() {
    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        _cameraController!.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping camera stream: $e');
    }
  }

  // ── Per-frame Processing ───────────────────────────────────────────────

  Future<void> _processNextFrame() async {
    final frame = _frameQueue.dequeue();
    if (frame == null) return;

    // In managed mode, Scheduler controls QoS (may pause inference).
    // In raw mode, always run at full capacity — no throttling.
    final QoSKnobs knobs;
    if (_isManaged) {
      knobs = _scheduler?.getKnobsForWorkload(WorkloadId.vision) ?? _policy.knobs;
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

      // Report latency to Scheduler for p95 tracking
      _scheduler?.reportLatency(WorkloadId.vision, totalInferenceMs);

      // Record timing data to PerfTrace
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

      // Update live metrics
      _frameCount++;
      _totalTokens += result.generatedTokens;
      _lastLatencyMs = totalInferenceMs;
      _totalLatencyMs += totalInferenceMs;
      _avgLatencyMs = _totalLatencyMs / _frameCount;
      _lastDescription = result.description;

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Soak test inference error: $e');
    } finally {
      _frameQueue.markDone();
      // Process next pending frame if available
      if (_frameQueue.hasPending && mounted && _isRunning) {
        _processNextFrame();
      }
    }
  }

  // ── Telemetry Polling ──────────────────────────────────────────────────

  Future<void> _pollTelemetry() async {
    if (!_isRunning) return;

    try {
      final snap = await _telemetry.snapshot();

      // Record telemetry to PerfTrace
      _trace?.record(stage: 'rss_bytes', value: snap.memoryRssBytes.toDouble());
      _trace?.record(stage: 'thermal_state', value: snap.thermalState.toDouble());
      _trace?.record(stage: 'battery_level', value: snap.batteryLevel);
      _trace?.record(
        stage: 'available_memory',
        value: snap.availableMemoryBytes.toDouble(),
      );

      // Evaluate RuntimePolicy (display-only in managed mode, primary display in raw mode)
      final newQoS = _policy.evaluate(
        thermalState: snap.thermalState,
        batteryLevel: snap.batteryLevel,
        availableMemoryBytes: snap.availableMemoryBytes,
        isLowPowerMode: snap.isLowPowerMode,
      );

      // Pick up adaptive resolution state from Scheduler (managed mode only)
      final baseline = _isManaged ? _scheduler?.measuredBaseline : null;
      final resolved = _isManaged ? _scheduler?.resolvedBudget : null;

      if (mounted) {
        setState(() {
          _thermalState = snap.thermalState;
          _batteryLevel = snap.batteryLevel;
          _memoryRssBytes = snap.memoryRssBytes;
          _currentQoS = newQoS;
          _measuredBaseline = baseline;
          _resolvedBudget = resolved;
        });
      }
    } catch (e) {
      debugPrint('Telemetry poll error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _thermalString(int state) {
    return switch (state) {
      0 => 'Nominal',
      1 => 'Fair',
      2 => 'Serious',
      3 => 'Critical',
      _ => 'Unknown',
    };
  }

  Color _thermalColor(int state) {
    return switch (state) {
      0 => AppTheme.success,
      1 => AppTheme.accent,
      2 => AppTheme.warning,
      3 => AppTheme.danger,
      _ => AppTheme.textTertiary,
    };
  }

  Color _qosColor(QoSLevel level) {
    return switch (level) {
      QoSLevel.full => AppTheme.success,
      QoSLevel.reduced => AppTheme.accent,
      QoSLevel.minimal => AppTheme.warning,
      QoSLevel.paused => AppTheme.danger,
    };
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _formatMemoryMB(int bytes) {
    if (bytes <= 0) return '-';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  String _formatBattery(double level) {
    if (level < 0) return '-';
    return '${(level * 100).toStringAsFixed(0)}%';
  }

  double _tokensPerSecond() {
    if (_elapsed.inSeconds <= 0 || _totalTokens <= 0) return 0;
    return _totalTokens / _elapsed.inSeconds;
  }

  // ── Trace Export ─────────────────────────────────────────────────────

  static const _telemetryChannel =
      MethodChannel('com.edgeveda.edge_veda/telemetry');

  Future<void> _shareTrace() async {
    if (_traceFilePath == null) return;
    try {
      await _telemetryChannel.invokeMethod('shareFile', {
        'path': _traceFilePath,
      });
    } on PlatformException catch (e) {
      debugPrint('Share failed: $e');
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Soak Test'),
            const Spacer(),
            if (_isRunning)
              Text(
                _formatDuration(_elapsed),
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Camera preview (compact)
          if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            SizedBox(
              height: 200,
              width: double.infinity,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize!.height,
                    height: _cameraController!.value.previewSize!.width,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            ),

          // Last description (if any)
          if (_lastDescription != null && _lastDescription!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surface,
              child: Text(
                _lastDescription!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Metrics card
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMetricsCard(),
                const SizedBox(height: 16),
                _buildStatusCard(),
              ],
            ),
          ),

          // Mode selector + Start/Stop button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Mode selector (disabled while running)
                  if (!_isRunning && !_isInitializing) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isManaged = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _isManaged ? AppTheme.accent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  'Managed',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _isManaged ? AppTheme.background : AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isManaged = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !_isManaged ? AppTheme.danger : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  'Raw (Baseline)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: !_isManaged ? AppTheme.textPrimary : AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isManaged)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'No thermal/battery protection. Device may throttle.',
                          style: TextStyle(
                            color: AppTheme.warning,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isInitializing
                          ? null
                          : (_isRunning ? _stop : _start),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isRunning ? AppTheme.danger : AppTheme.accent,
                        foregroundColor: AppTheme.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isInitializing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.textPrimary,
                              ),
                            )
                          : Text(
                              _isRunning ? 'Stop' : 'Start ${_isManaged ? "Managed" : "Raw"} Soak Test',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'LIVE METRICS',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _isManaged ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.danger.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isManaged ? 'MANAGED' : 'RAW',
                  style: TextStyle(
                    color: _isManaged ? AppTheme.accent : AppTheme.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMetricRow('Frames Processed', '$_frameCount'),
          _buildMetricRow(
            'Avg Latency',
            _frameCount > 0
                ? '${_avgLatencyMs.toStringAsFixed(0)} ms'
                : '-',
          ),
          _buildMetricRow(
            'Last Latency',
            _lastLatencyMs > 0
                ? '${_lastLatencyMs.toStringAsFixed(0)} ms'
                : '-',
          ),
          _buildMetricRow(
            'Tokens/sec',
            _tokensPerSecond() > 0
                ? _tokensPerSecond().toStringAsFixed(1)
                : '-',
          ),
          _buildMetricRow(
            'Dropped Frames',
            '${_frameQueue.droppedFrames}',
          ),
          const Divider(color: AppTheme.border, height: 24),
          _buildMetricRow(
            'Thermal',
            _thermalString(_thermalState),
            valueColor: _thermalColor(_thermalState),
          ),
          _buildMetricRow(
            'Battery',
            _formatBattery(_batteryLevel),
          ),
          _buildMetricRow(
            'Memory RSS',
            _formatMemoryMB(_memoryRssBytes),
          ),
          _buildMetricRow(
            'QoS Level',
            _currentQoS.name,
            valueColor: _qosColor(_currentQoS),
          ),
          if (_isManaged) ...[
            const Divider(color: AppTheme.border, height: 24),
            const Text(
              'ADAPTIVE BUDGET',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            _buildMetricRow(
              'Profile',
              'balanced',
            ),
            _buildMetricRow(
              'Status',
              _resolvedBudget != null ? 'Resolved' : 'Warming up…',
              valueColor: _resolvedBudget != null ? AppTheme.success : AppTheme.textTertiary,
            ),
            if (_measuredBaseline != null) ...[
              _buildMetricRow(
                'Measured p95',
                '${_measuredBaseline!.measuredP95Ms.toStringAsFixed(0)} ms',
              ),
              _buildMetricRow(
                'Measured Drain',
                _measuredBaseline!.measuredDrainPerTenMin != null
                    ? '${_measuredBaseline!.measuredDrainPerTenMin!.toStringAsFixed(1)}%/10min'
                    : 'pending…',
                valueColor: _measuredBaseline!.measuredDrainPerTenMin != null
                    ? AppTheme.textPrimary
                    : AppTheme.textTertiary,
              ),
            ],
            if (_resolvedBudget != null) ...[
              _buildMetricRow(
                'Budget p95',
                '${_resolvedBudget!.p95LatencyMs ?? "-"} ms',
                valueColor: AppTheme.accent,
              ),
              _buildMetricRow(
                'Budget Thermal',
                '≤ ${_resolvedBudget!.maxThermalLevel ?? "-"}',
                valueColor: AppTheme.accent,
              ),
              if (_resolvedBudget!.batteryDrainPerTenMinutes != null)
                _buildMetricRow(
                  'Budget Drain',
                  '≤ ${_resolvedBudget!.batteryDrainPerTenMinutes!.toStringAsFixed(1)}%/10min',
                  valueColor: AppTheme.accent,
                ),
            ],
            const Divider(color: AppTheme.border, height: 24),
            _buildMetricRow(
              'Actionable Violations',
              '$_actionableViolationCount',
              valueColor: _actionableViolationCount > 0 ? AppTheme.warning : AppTheme.success,
            ),
            _buildMetricRow(
              'Observe-Only (memory)',
              '$_observeOnlyViolationCount',
              valueColor: AppTheme.textTertiary,
            ),
            if (_lastViolation != null)
              _buildMetricRow(
                'Last Violation',
                _lastViolation!,
                valueColor: AppTheme.warning,
              ),
          ] else ...[
            const Divider(color: AppTheme.border, height: 24),
            const Text(
              'RAW MODE',
              style: TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'No Scheduler, no budget enforcement, no QoS adaptation. '
              'Inference runs at full capacity regardless of device pressure.',
              style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TEST INFO',
            style: TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _buildMetricRow(
            'Duration',
            '${_formatDuration(_elapsed)} / ${_formatDuration(_testDuration)}',
          ),
          _buildMetricRow(
            'Total Tokens',
            '$_totalTokens',
          ),
          _buildMetricRow(
            'QoS Knobs',
            _isRunning
                ? () {
                    if (!_isManaged) return 'fps=2 res=640 tok=100 (fixed)';
                    final k = _scheduler?.getKnobsForWorkload(WorkloadId.vision) ?? _policy.knobs;
                    return 'fps=${k.maxFps} res=${k.resolution} tok=${k.maxTokens}';
                  }()
                : '-',
          ),
          if (_traceFilePath != null) ...[
            const Divider(color: AppTheme.border, height: 24),
            Text(
              'Trace: ${_traceFilePath!.split('/').last}',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _traceFilePath != null && !_isRunning
                  ? () => _shareTrace()
                  : null,
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Export Trace'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
