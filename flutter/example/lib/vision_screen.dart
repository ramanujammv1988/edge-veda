import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// Vision tab with camera preview and image description.
///
/// On iOS (Metal GPU): continuous scanning via FrameQueue.
/// On Android (CPU-only): manual capture mode with "Describe" button,
/// since CPU inference takes several minutes per frame.
class VisionScreen extends StatefulWidget {
  /// Whether this tab is currently visible to the user.
  /// When false, the camera stream is paused to save GPU/battery.
  final bool isActive;

  const VisionScreen({super.key, this.isActive = true});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen>
    with WidgetsBindingObserver {
  final VisionWorker _visionWorker = VisionWorker();
  final FrameQueue _frameQueue = FrameQueue();
  final ModelManager _modelManager = ModelManager();

  // Vision state
  bool _isVisionReady = false;
  bool _isDownloading = false;
  bool _hasInitialized = false;
  bool _isInferring = false;
  String? _description;
  double _downloadProgress = 0.0;
  String _statusMessage = 'Preparing vision...';

  // Elapsed time tracking for CPU inference
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  // Camera
  CameraController? _cameraController;

  // Model paths
  String? _modelPath;
  String? _mmprojPath;

  /// Whether to use continuous scanning (GPU) or manual capture (CPU)
  bool get _useContinuousScanning => Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Only initialize if tab is already active (e.g. deep-linked)
    if (widget.isActive) {
      _hasInitialized = true;
      _initializeVision();
    }
  }

  @override
  void didUpdateWidget(VisionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // Tab became visible
      if (!_hasInitialized) {
        _hasInitialized = true;
        _initializeVision();
      } else if (_isVisionReady && _cameraController != null) {
        if (_useContinuousScanning) _startCameraStream();
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      // Tab became hidden — pause camera to save GPU/battery
      if (_useContinuousScanning) _stopCameraStream();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _elapsedTimer?.cancel();
    _stopCameraStream();
    _cameraController?.dispose();
    _visionWorker.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_useContinuousScanning) _stopCameraStream();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActive &&
          _isVisionReady &&
          _cameraController != null &&
          _useContinuousScanning) {
        _startCameraStream();
      }
    }
  }

  /// Full initialization flow: download models -> init camera -> init vision
  Future<void> _initializeVision() async {
    try {
      // Step 1: Check and download VLM model
      await _ensureModelsDownloaded();

      if (!mounted) return;

      // Step 2: Initialize camera
      setState(() => _statusMessage = 'Initializing camera...');
      await _initializeCamera();

      if (!mounted) return;

      // Step 3: Spawn persistent vision worker and load model once
      setState(() => _statusMessage = 'Loading vision model...');
      await _visionWorker.spawn();
      // Use GPU on iOS (Metal), CPU on Android (Vulkan 1.2 usually unavailable)
      final useGpu = Platform.isIOS;
      // Use more threads on CPU to utilize all cores (Snapdragon 845 = 8 cores)
      final numThreads = useGpu ? 4 : 8;
      debugPrint('EdgeVeda Vision: Loading model (useGpu=$useGpu, threads=$numThreads)...');
      await _visionWorker.initVision(
        modelPath: _modelPath!,
        mmprojPath: _mmprojPath!,
        numThreads: numThreads,
        contextSize: 1024,
        useGpu: useGpu,
      );
      debugPrint('EdgeVeda Vision: Model loaded successfully');

      if (!mounted) return;

      setState(() {
        _isVisionReady = true;
        _statusMessage = 'Vision ready';
      });

      // Step 4: Start continuous scanning on GPU, or just show camera on CPU
      if (_useContinuousScanning) {
        _startCameraStream();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error: $e';
          _isDownloading = false;
        });
      }
      debugPrint('Vision init error: $e');
    }
  }

  /// Download SmolVLM2 model + mmproj if not already cached
  Future<void> _ensureModelsDownloaded() async {
    final model = ModelRegistry.smolvlm2_500m;
    // Use Q8_0 mmproj on Android (CPU) for faster inference, F16 on iOS (GPU)
    final mmproj = Platform.isIOS
        ? ModelRegistry.smolvlm2_500m_mmproj
        : ModelRegistry.smolvlm2_500m_mmproj_q8;

    final modelDownloaded = await _modelManager.isModelDownloaded(model.id);
    final mmprojDownloaded = await _modelManager.isModelDownloaded(mmproj.id);

    if (!modelDownloaded || !mmprojDownloaded) {
      setState(() {
        _isDownloading = true;
        _statusMessage = 'Downloading vision model...';
      });

      _modelManager.downloadProgress.listen((progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress.progress;
            _statusMessage =
                'Downloading: ${progress.progressPercent}%';
          });
        }
      });

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

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1.0;
        });
      }
    } else {
      _modelPath = await _modelManager.getModelPath(model.id);
      _mmprojPath = await _modelManager.getModelPath(mmproj.id);
    }
  }

  /// Initialize camera with back-facing lens
  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No cameras available');
    }

    // Prefer back camera
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      camera,
      // Lower resolution on Android (CPU) to reduce image processing overhead
      Platform.isIOS ? ResolutionPreset.medium : ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
  }

  // ===========================================================================
  // Continuous scanning mode (iOS / GPU)
  // ===========================================================================

  /// Start continuous camera frame processing via FrameQueue
  void _startCameraStream() {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isVisionReady ||
        _cameraController!.value.isStreamingImages) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) {
      if (!_isVisionReady) return;

      // Convert platform-specific format to RGB888
      final Uint8List rgb;
      if (Platform.isIOS) {
        rgb = CameraUtils.convertBgraToRgb(
          image.planes[0].bytes,
          image.width,
          image.height,
        );
      } else {
        rgb = CameraUtils.convertYuv420ToRgb(
          image.planes[0].bytes,
          image.planes[1].bytes,
          image.planes[2].bytes,
          image.width,
          image.height,
          image.planes[0].bytesPerRow,
          image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel ?? 1,
        );
      }

      // Enqueue frame (drops old pending if busy)
      _frameQueue.enqueue(rgb, image.width, image.height);

      // Start processing if not already
      _processNextFrame();
    });
  }

  /// Stop camera image stream
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

  /// Pull next frame from FrameQueue and process via VisionWorker
  Future<void> _processNextFrame() async {
    final frame = _frameQueue.dequeue();
    if (frame == null) return; // nothing to process or already processing

    if (mounted) {
      setState(() => _isInferring = true);
    }

    try {
      debugPrint(
          'EdgeVeda Vision: Describing frame ${frame.width}x${frame.height}...');
      final stopwatch = Stopwatch()..start();
      final result = await _visionWorker.describeFrame(
        frame.rgb,
        frame.width,
        frame.height,
        prompt: 'Describe what you see in this image in one sentence.',
        maxTokens: 60,
      );
      stopwatch.stop();
      debugPrint(
          'EdgeVeda Vision: Frame described in ${stopwatch.elapsedMilliseconds}ms: '
          '${result.description.substring(0, result.description.length.clamp(0, 80))}');
      if (mounted) {
        setState(() => _description = result.description);
      }
    } catch (e) {
      debugPrint('Vision inference error: $e');
    } finally {
      _frameQueue.markDone();
      if (mounted) {
        setState(() => _isInferring = false);
      }
      // Process next pending frame if available
      if (_frameQueue.hasPending && mounted) {
        _processNextFrame();
      }
    }
  }

  // ===========================================================================
  // Manual capture mode (Android / CPU)
  // ===========================================================================

  /// Capture a single frame from the camera and run vision inference
  Future<void> _captureAndDescribe() async {
    if (!_isVisionReady ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isInferring) {
      return;
    }

    setState(() {
      _isInferring = true;
      _elapsedSeconds = 0;
    });

    // Start elapsed timer
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });

    try {
      // Start image stream, capture one frame, stop stream
      final completer = Completer<Uint8List>();
      int capturedWidth = 0;
      int capturedHeight = 0;

      _cameraController!.startImageStream((CameraImage image) {
        if (completer.isCompleted) return;

        // Convert to RGB
        final Uint8List rgb;
        if (Platform.isIOS) {
          rgb = CameraUtils.convertBgraToRgb(
            image.planes[0].bytes,
            image.width,
            image.height,
          );
        } else {
          rgb = CameraUtils.convertYuv420ToRgb(
            image.planes[0].bytes,
            image.planes[1].bytes,
            image.planes[2].bytes,
            image.width,
            image.height,
            image.planes[0].bytesPerRow,
            image.planes[1].bytesPerRow,
            image.planes[1].bytesPerPixel ?? 1,
          );
        }

        capturedWidth = image.width;
        capturedHeight = image.height;
        completer.complete(rgb);
      });

      final rgb = await completer.future.timeout(
        const Duration(seconds: 5),
      );

      // Stop stream immediately after capture
      try {
        if (_cameraController!.value.isStreamingImages) {
          _cameraController!.stopImageStream();
        }
      } catch (_) {}

      debugPrint(
          'EdgeVeda Vision: Captured frame ${capturedWidth}x$capturedHeight, running inference...');
      final stopwatch = Stopwatch()..start();

      final result = await _visionWorker.describeFrame(
        rgb,
        capturedWidth,
        capturedHeight,
        prompt: 'What is in this image?',
        maxTokens: 20,
      );

      stopwatch.stop();
      debugPrint(
          'EdgeVeda Vision: Frame described in ${stopwatch.elapsedMilliseconds}ms: '
          '${result.description.substring(0, result.description.length.clamp(0, 80))}');

      if (mounted) {
        setState(() => _description = result.description);
      }
    } catch (e) {
      debugPrint('Vision capture/inference error: $e');
      if (mounted) {
        setState(() {
          _description = 'Inference timed out. CPU vision is very slow '
              'without GPU acceleration. Try again.';
        });
      }
    } finally {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      // Stop stream if still running
      try {
        if (_cameraController != null &&
            _cameraController!.value.isStreamingImages) {
          _cameraController!.stopImageStream();
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _isInferring = false);
      }
    }
  }

  // ===========================================================================
  // UI
  // ===========================================================================

  /// Build the loading/download overlay
  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isDownloading) ...[
              const Icon(
                Icons.cloud_download,
                size: 64,
                color: Colors.white70,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              _statusMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen camera preview
          if (_cameraController != null &&
              _cameraController!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // CPU inference processing indicator
          if (_isInferring && !_useContinuousScanning)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Analyzing on CPU... ${_elapsedSeconds}s elapsed',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // GPU continuous scanning processing indicator (first result)
          if (_isInferring && _useContinuousScanning && _description == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Analyzing frame...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Description overlay at bottom (AR-style)
          if (_description != null && _description!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: _useContinuousScanning ? 0 : 80,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Pulsing indicator when processing
                      if (_isInferring) const _PulsingDot(),
                      if (_isInferring) const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _description!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Manual capture button (Android / CPU mode)
          if (!_useContinuousScanning && _isVisionReady && !_isInferring)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ElevatedButton.icon(
                    onPressed: _captureAndDescribe,
                    icon: const Icon(Icons.camera_alt, size: 24),
                    label: const Text(
                      'Describe What I See',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Download/loading overlay
          if (_isDownloading || !_isVisionReady) _buildLoadingOverlay(),
        ],
      ),
    );
  }
}

/// Subtle pulsing dot indicator for active inference
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Opacity(
        opacity: 0.3 + 0.7 * _controller.value,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppTheme.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
