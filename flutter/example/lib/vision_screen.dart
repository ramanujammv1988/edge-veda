import 'dart:io' show File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:edge_veda/edge_veda.dart';
import 'package:file_picker/file_picker.dart';

// camera package only supports iOS/Android at runtime.
// The Dart code compiles on all platforms; usage is guarded by _cameraSupported.
import 'package:camera/camera.dart';

import 'app_theme.dart';
import 'model_selector.dart';
import 'soak_test_service.dart';

/// Whether the camera package is supported on this platform.
bool get _cameraSupported => Platform.isIOS || Platform.isAndroid;

/// Max pixels on the longest side before downscaling for inference.
/// Prevents OOM on high-res phone photos (typically 4032x3024).
const int _maxInferenceDimension = 768;

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
        // Android build is CPU-only (Vulkan disabled); GPU only on iOS (Metal).
        useGpu: Platform.isIOS,
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
          _statusMessage = _userFacingErrorMessage(e);
          _isDownloading = false;
        });
      }
      debugPrint('Vision init error: $e');
    }
  }

  /// Pick an image file and run single-shot vision inference.
  Future<void> _pickAndDescribeImage() async {
    if (_isProcessingFile || !_isVisionReady) return;

    // Pause camera so it doesn't compete with file inference
    _stopCameraStream();

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
      var rgb = Uint8List(width * height * 3);
      for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
        rgb[j] = rgba[i];
        rgb[j + 1] = rgba[i + 1];
        rgb[j + 2] = rgba[i + 2];
      }

      // Downscale high-res images to avoid OOM on mobile
      var inferWidth = width;
      var inferHeight = height;
      final longest = width > height ? width : height;
      if (longest > _maxInferenceDimension) {
        final scale = _maxInferenceDimension / longest;
        inferWidth = (width * scale).round();
        inferHeight = (height * scale).round();
        rgb = CameraUtils.resizeRgb(rgb, width, height, inferWidth, inferHeight);
      }

      final sw = Stopwatch()..start();
      final desc = await _visionWorker.describeFrame(
        rgb,
        inferWidth,
        inferHeight,
        prompt: ChatTemplate.format(
          template: ChatTemplateFormat.generic,
          messages: [
            ChatMessage(
              role: ChatRole.user,
              content: 'Describe what you see in this image in one sentence.',
              timestamp: DateTime.now(),
            ),
          ],
        ),
        maxTokens: 100,
      );
      sw.stop();
      SoakTestService.instance.recordExternalInference(
        source: 'Vision file',
        latencyMs: sw.elapsedMilliseconds,
        generatedTokens: desc.generatedTokens,
        workloadId: WorkloadId.vision,
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
          _statusMessage = _userFacingErrorMessage(e);
        });
      }
      debugPrint('File vision error: $e');
    }
  }

  /// Test vision with bundled evidence/1.jpeg asset (no camera needed).
  Future<void> _testWithBundledImage() async {
    if (_isProcessingFile || !_isVisionReady) return;

    // Pause camera while testing with file
    _stopCameraStream();

    setState(() {
      _isProcessingFile = true;
      _description = null;
      _statusMessage = 'Analyzing test image...';
    });

    try {
      final byteData = await rootBundle.load('assets/test_vision.jpeg');
      final bytes = byteData.buffer.asUint8List();

      final image = await decodeImageFromList(bytes);
      final width = image.width;
      final height = image.height;

      final imageByteData = await image.toByteData();
      if (imageByteData == null) throw Exception('Failed to read image data');

      // Convert RGBA to RGB888
      final rgba = imageByteData.buffer.asUint8List();
      var rgb = Uint8List(width * height * 3);
      for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
        rgb[j] = rgba[i];
        rgb[j + 1] = rgba[i + 1];
        rgb[j + 2] = rgba[i + 2];
      }

      // Downscale high-res images to avoid OOM on mobile
      var inferWidth = width;
      var inferHeight = height;
      final longest = width > height ? width : height;
      if (longest > _maxInferenceDimension) {
        final scale = _maxInferenceDimension / longest;
        inferWidth = (width * scale).round();
        inferHeight = (height * scale).round();
        rgb = CameraUtils.resizeRgb(rgb, width, height, inferWidth, inferHeight);
      }

      final sw = Stopwatch()..start();
      final desc = await _visionWorker.describeFrame(
        rgb,
        inferWidth,
        inferHeight,
        prompt: ChatTemplate.format(
          template: ChatTemplateFormat.generic,
          messages: [
            ChatMessage(
              role: ChatRole.user,
              content: 'Describe what you see in this image in one sentence.',
              timestamp: DateTime.now(),
            ),
          ],
        ),
        maxTokens: 100,
      );
      sw.stop();
      SoakTestService.instance.recordExternalInference(
        source: 'Vision test file',
        latencyMs: sw.elapsedMilliseconds,
        generatedTokens: desc.generatedTokens,
        workloadId: WorkloadId.vision,
      );

      if (mounted) {
        setState(() {
          _selectedImageBytes = bytes;
          _description = desc.description;
          _isProcessingFile = false;
          _statusMessage = 'Test complete';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingFile = false;
          _statusMessage = _userFacingErrorMessage(e);
        });
      }
      debugPrint('Test file vision error: $e');
    }
  }

  /// Resume camera stream after file test.
  void _resumeCamera() {
    setState(() {
      _selectedImageBytes = null;
      _description = null;
    });
    _startCameraStream();
  }

  String _userFacingErrorMessage(Object error) {
    final message = error.toString();
    final isNetworkLookupFailure = message.contains('Failed host lookup') ||
        message.contains('SocketException') ||
        message.contains('Unable to reach model host');

    if (isNetworkLookupFailure) {
      return 'Cannot reach model host. Check internet/DNS and try again.';
    }

    if (error is DownloadException ||
        message.contains('Failed to download model')) {
      return 'Model download failed. Please retry.';
    }

    return 'Vision error. Please try again.';
  }

  /// Use the best already-downloaded vision model pair; downloads SmolVLM2 as fallback.
  Future<void> _ensureModelsDownloaded() async {
    final selection = await ModelSelector.bestVision(_modelManager);

    if (selection.needsDownload) {
      setState(() {
        _isDownloading = true;
        _statusMessage =
            'Downloading ${selection.model.name} (${_formatBytes(selection.model.sizeBytes)})';
      });

      _modelManager.downloadProgress.listen((progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress.progress;
            _statusMessage =
                'Downloading: ${progress.progressPercent}% (${_formatBytes(progress.downloadedBytes)}/${_formatBytes(progress.totalBytes)})';
          });
        }
      });

      await _modelManager.downloadModel(selection.model);
      if (selection.mmproj != null) {
        await _modelManager.downloadModel(selection.mmproj!);
      }

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1.0;
        });
      }
    }

    _modelPath = await _modelManager.getModelPath(selection.model.id);
    _mmprojPath = selection.mmproj != null
        ? await _modelManager.getModelPath(selection.mmproj!.id)
        : null;
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
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
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
      final sw = Stopwatch()..start();
      final result = await _visionWorker.describeFrame(
        frame.rgb,
        frame.width,
        frame.height,
        prompt: ChatTemplate.format(
          template: ChatTemplateFormat.generic,
          messages: [
            ChatMessage(
              role: ChatRole.user,
              content: 'Describe what you see in this image in one sentence.',
              timestamp: DateTime.now(),
            ),
          ],
        ),
        maxTokens: 100,
      );
      sw.stop();
      SoakTestService.instance.recordExternalInference(
        source: 'Vision camera',
        latencyMs: sw.elapsedMilliseconds,
        generatedTokens: result.generatedTokens,
        workloadId: WorkloadId.vision,
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
          // Full-screen camera preview (hidden when test image is shown)
          if (_selectedImageBytes == null &&
              _cameraController != null &&
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

          // Test image preview (replaces camera when active)
          if (_selectedImageBytes != null)
            SizedBox.expand(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: Image.memory(_selectedImageBytes!,
                      fit: BoxFit.contain),
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
                      if (_frameQueue.isProcessing || _isProcessingFile)
                        const _PulsingDot(),
                      if (_frameQueue.isProcessing || _isProcessingFile)
                        const SizedBox(width: 12),
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

          // Processing indicator for file test
          if (_isProcessingFile)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),

          // Top-right action buttons
          if (_isVisionReady)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // "Test with File" button (visible when camera is active)
                      if (_selectedImageBytes == null && !_isProcessingFile)
                        ElevatedButton.icon(
                          onPressed: _testWithBundledImage,
                          icon: const Icon(Icons.image, size: 18),
                          label: const Text('Test with File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      // "Pick Image" button (visible when camera is active)
                      if (_selectedImageBytes == null && !_isProcessingFile) ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _pickAndDescribeImage,
                          icon: const Icon(Icons.photo_library, size: 18),
                          label: const Text('Pick Image'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                      // "Resume Camera" button (visible when test image shown)
                      if (_selectedImageBytes != null)
                        ElevatedButton.icon(
                          onPressed: _resumeCamera,
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: const Text('Resume Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Selected image preview
                            if (_selectedImageBytes != null)
                              Container(
                                constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight * 0.5,
                                  maxWidth: 760,
                                ),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(_selectedImageBytes!,
                                      fit: BoxFit.contain),
                                ),
                              ),

                            // Description
                            if (_description != null &&
                                _description!.isNotEmpty)
                              Container(
                                constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight * 0.28,
                                ),
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_isProcessingFile) const _PulsingDot(),
                                    if (_isProcessingFile)
                                      const SizedBox(width: 12),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: Text(
                                          _description!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Pick image button
                            ElevatedButton.icon(
                              onPressed: _isProcessingFile
                                  ? null
                                  : _pickAndDescribeImage,
                              icon: const Icon(Icons.image),
                              label: Text(_selectedImageBytes != null
                                  ? 'Pick Another Image'
                                  : 'Pick an Image'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: AppTheme.background,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),

                            if (_isProcessingFile)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                      color: AppTheme.accent),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Download/loading overlay
          if (_isDownloading || !_isVisionReady) _buildLoadingOverlay(),
        ],
      ),
    );
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
