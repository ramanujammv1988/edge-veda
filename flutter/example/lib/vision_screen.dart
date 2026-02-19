import 'dart:io' show File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';
import 'package:file_picker/file_picker.dart';

// camera package only supports iOS/Android at runtime.
// The Dart code compiles on all platforms; usage is guarded by _cameraSupported.
import 'package:camera/camera.dart';

import 'app_theme.dart';

/// Whether the camera package is supported on this platform.
bool get _cameraSupported => Platform.isIOS || Platform.isAndroid;

/// Vision tab with continuous camera scanning and description overlay.
///
/// On iOS/Android: Uses a persistent VisionWorker isolate and FrameQueue
/// with drop-newest backpressure for production-grade continuous vision.
///
/// On macOS: Camera is not supported. Uses file-picker-based image input
/// for single-shot vision inference instead.
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
  String? _description;
  double _downloadProgress = 0.0;
  String _statusMessage = 'Preparing vision...';

  // Camera (iOS/Android only)
  CameraController? _cameraController;

  // File-based input (macOS fallback)
  bool _isProcessingFile = false;
  Uint8List? _selectedImageBytes;

  // Model paths
  String? _modelPath;
  String? _mmprojPath;

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
        _startCameraStream();
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      // Tab became hidden — pause camera to save GPU/battery
      _stopCameraStream();
    }
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
      if (widget.isActive && _isVisionReady && _cameraController != null) {
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

      // Step 2: Initialize camera (iOS/Android only)
      if (_cameraSupported) {
        setState(() => _statusMessage = 'Initializing camera...');
        await _initializeCamera();
        if (!mounted) return;
      }

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
        _statusMessage = _cameraSupported
            ? 'Vision ready'
            : 'Vision ready — pick an image to describe';
      });

      // Step 4: Start continuous scanning (camera platforms only)
      if (_cameraSupported) {
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

  /// macOS: Pick an image file and run single-shot vision inference.
  Future<void> _pickAndDescribeImage() async {
    if (_isProcessingFile || !_isVisionReady) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    setState(() {
      _isProcessingFile = true;
      _description = null;
      _statusMessage = 'Analyzing image...';
    });

    try {
      final bytes = await File(filePath).readAsBytes();
      // Decode image to get dimensions for the worker
      final image = await decodeImageFromList(bytes);
      final width = image.width;
      final height = image.height;

      // Convert to RGB888 for the vision worker
      final byteData = await image.toByteData();
      if (byteData == null) throw Exception('Failed to read image data');

      // byteData is RGBA, convert to RGB
      final rgba = byteData.buffer.asUint8List();
      final rgb = Uint8List(width * height * 3);
      for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
        rgb[j] = rgba[i];
        rgb[j + 1] = rgba[i + 1];
        rgb[j + 2] = rgba[i + 2];
      }

      final desc = await _visionWorker.describeFrame(
        rgb,
        width,
        height,
        prompt: 'Describe what you see in this image in one sentence.',
        maxTokens: 100,
      );

      if (mounted) {
        setState(() {
          _selectedImageBytes = bytes;
          _description = desc.description;
          _isProcessingFile = false;
          _statusMessage = 'Vision ready — pick another image';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingFile = false;
          _statusMessage = 'Error: $e';
        });
      }
      debugPrint('File vision error: $e');
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
    // macOS: file-picker-based UI (no camera)
    if (!_cameraSupported) {
      return _buildDesktopVisionUI();
    }

    // iOS/Android: camera-based continuous scanning UI
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

  /// Desktop (macOS) vision UI: file picker + image display + description
  Widget _buildDesktopVisionUI() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          if (_isVisionReady)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Selected image preview
                  if (_selectedImageBytes != null)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 400, maxWidth: 600),
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(_selectedImageBytes!, fit: BoxFit.contain),
                      ),
                    ),

                  // Description
                  if (_description != null && _description!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          if (_isProcessingFile) const _PulsingDot(),
                          if (_isProcessingFile) const SizedBox(width: 12),
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

                  const SizedBox(height: 24),

                  // Pick image button
                  ElevatedButton.icon(
                    onPressed: _isProcessingFile ? null : _pickAndDescribeImage,
                    icon: const Icon(Icons.image),
                    label: Text(_selectedImageBytes != null
                        ? 'Pick Another Image'
                        : 'Pick an Image'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.background,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  if (_isProcessingFile)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: CircularProgressIndicator(color: AppTheme.accent),
                    ),
                ],
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
