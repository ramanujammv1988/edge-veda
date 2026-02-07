import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// Vision tab with continuous camera scanning and description overlay
///
/// Uses a persistent VisionWorker isolate (model loaded once) and FrameQueue
/// with drop-newest backpressure for production-grade vision inference.
///
/// Implements a Google Lens-style continuous scanning UX:
/// - Camera feeds frames through FrameQueue (backpressure handles throttling)
/// - Description overlay at bottom of camera view (AR-style)
/// - Subtle pulsing indicator during inference
/// - Vision model downloads on first open, then initializes camera
class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

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
  String? _description;
  double _downloadProgress = 0.0;
  String _statusMessage = 'Preparing vision...';

  // Camera
  CameraController? _cameraController;

  // Model paths
  String? _modelPath;
  String? _mmprojPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeVision();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCameraStream();
    _cameraController?.dispose();
    _visionWorker.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopCameraStream();
    } else if (state == AppLifecycleState.resumed) {
      if (_isVisionReady && _cameraController != null) {
        _startCameraStream();
      }
    }
  }

  /// Full initialization flow: download models -> init camera -> init vision -> start scanning
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
      await _visionWorker.initVision(
        modelPath: _modelPath!,
        mmprojPath: _mmprojPath!,
        numThreads: 4,
        contextSize: 4096,
        useGpu: true,
      );

      if (!mounted) return;

      setState(() {
        _isVisionReady = true;
        _statusMessage = 'Vision ready';
      });

      // Step 4: Start continuous scanning
      _startCameraStream();
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
    final mmproj = ModelRegistry.smolvlm2_500m_mmproj;

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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
  }

  /// Start continuous camera frame processing via FrameQueue
  void _startCameraStream() {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isVisionReady) {
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
      setState(() {}); // Update UI to show processing state
    }

    try {
      final result = await _visionWorker.describeFrame(
        frame.rgb,
        frame.width,
        frame.height,
        prompt: 'Describe what you see in this image in one sentence.',
        maxTokens: 100,
      );
      if (mounted) {
        setState(() => _description = result.description);
      }
    } catch (e) {
      debugPrint('Vision inference error: $e');
    } finally {
      _frameQueue.markDone();
      if (mounted) {
        setState(() {}); // Update UI to clear processing state
      }
      // Process next pending frame if available
      if (_frameQueue.hasPending && mounted) {
        _processNextFrame();
      }
    }
  }

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

          // Description overlay at bottom (AR-style)
          if (_description != null && _description!.isNotEmpty)
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
                  child: Row(
                    children: [
                      // Pulsing indicator when processing
                      if (_frameQueue.isProcessing) const _PulsingDot(),
                      if (_frameQueue.isProcessing) const SizedBox(width: 12),
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
