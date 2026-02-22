import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// Record of a generated image for gallery display.
class _GeneratedImage {
  final Uint8List pngBytes;
  final String prompt;
  final DateTime timestamp;
  final double generationTimeMs;
  final bool isRaw;
  final int? rawWidth;
  final int? rawHeight;
  final int? rawChannels;

  const _GeneratedImage({
    required this.pngBytes,
    required this.prompt,
    required this.timestamp,
    required this.generationTimeMs,
    this.isRaw = false,
    this.rawWidth,
    this.rawHeight,
    this.rawChannels,
  });
}

/// Image generation demo tab with prompt input, progress display, gallery, and
/// advanced settings.
///
/// Uses [EdgeVeda.generateImage] for on-device image generation via
/// stable-diffusion.cpp. The SD model is downloaded on first use and stays
/// loaded for subsequent generations.
///
/// States:
/// 1. Ready -- prompt input, Generate button
/// 2. Downloading -- model download progress bar overlay
/// 3. Initializing -- loading model into memory
/// 4. Generating -- denoising progress (step N/M)
/// 5. Done -- generated image displayed, gallery strip
class ImageScreen extends StatefulWidget {
  const ImageScreen({super.key});

  @override
  State<ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  final EdgeVeda _edgeVeda = EdgeVeda();
  final ModelManager _modelManager = ModelManager();
  final TextEditingController _promptController = TextEditingController();

  // Model state
  bool _isModelDownloaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isModelLoaded = false;
  bool _isInitializing = false;

  // Generation state
  bool _isGenerating = false;
  int _currentStep = 0;
  int _totalSteps = 0;

  // Gallery
  final List<_GeneratedImage> _generatedImages = [];
  int _selectedImageIndex = -1;

  // Raw output toggle
  bool _useRawOutput = false;

  // Advanced settings
  bool _showAdvanced = false;
  int _steps = 4;
  double _cfgScale = 1.0;
  int _seed = -1;
  // Default 256x256 on Android (CPU-only) for faster generation
  int _width = 256;
  int _height = 256;
  ImageSampler _sampler = ImageSampler.eulerA;

  // Subscriptions
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _promptController.dispose();
    _edgeVeda.disposeImageGeneration();
    _modelManager.dispose();
    super.dispose();
  }

  Future<void> _checkModel() async {
    final downloaded =
        await _modelManager.isModelDownloaded(ModelRegistry.sdV21Turbo.id);
    if (mounted) {
      setState(() {
        _isModelDownloaded = downloaded;
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    _downloadSubscription = _modelManager.downloadProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _downloadProgress = progress.progress;
        });
      }
    });

    try {
      await _modelManager.downloadModel(ModelRegistry.sdV21Turbo);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isModelDownloaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      _downloadSubscription?.cancel();
      _downloadSubscription = null;
    }
  }

  Future<void> _initModel() async {
    setState(() {
      _isInitializing = true;
    });

    try {
      final modelPath =
          await _modelManager.getModelPath(ModelRegistry.sdV21Turbo.id);
      await _edgeVeda.initImageGeneration(modelPath: modelPath);

      if (mounted) {
        setState(() {
          _isModelLoaded = true;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model init failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    // Download model if needed
    if (!_isModelDownloaded) {
      await _downloadModel();
      if (!_isModelDownloaded) return;
    }

    // Load model if needed
    if (!_isModelLoaded) {
      await _initModel();
      if (!_isModelLoaded) return;
    }

    setState(() {
      _isGenerating = true;
      _currentStep = 0;
      _totalSteps = _steps;
    });

    try {
      final config = ImageGenerationConfig(
        width: _width,
        height: _height,
        steps: _steps,
        cfgScale: _cfgScale,
        seed: _seed,
        sampler: _sampler,
      );

      final stopwatch = Stopwatch()..start();

      if (_useRawOutput) {
        // Use generateImageRaw() for raw RGB output
        final result = await _edgeVeda.generateImageRaw(
          prompt,
          config: config,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _currentStep = progress.step;
                _totalSteps = progress.totalSteps;
              });
            }
          },
        );

        stopwatch.stop();

        if (mounted) {
          // Convert raw RGB to displayable PNG (use the raw data directly for display info)
          // For display, we also generate a PNG version
          final pngBytes = await _edgeVeda.generateImage(
            prompt,
            config: config,
          );

          final newImage = _GeneratedImage(
            pngBytes: pngBytes,
            prompt: prompt,
            timestamp: DateTime.now(),
            generationTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
            isRaw: true,
            rawWidth: result.width,
            rawHeight: result.height,
            rawChannels: result.channels,
          );

          setState(() {
            _generatedImages.add(newImage);
            _selectedImageIndex = _generatedImages.length - 1;
            _isGenerating = false;
            _currentStep = 0;
          });
        }
      } else {
        // Standard PNG output
        final pngBytes = await _edgeVeda.generateImage(
          prompt,
          config: config,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _currentStep = progress.step;
                _totalSteps = progress.totalSteps;
              });
            }
          },
        );

        stopwatch.stop();

        if (mounted) {
          final newImage = _GeneratedImage(
            pngBytes: pngBytes,
            prompt: prompt,
            timestamp: DateTime.now(),
            generationTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
          );

          setState(() {
            _generatedImages.add(newImage);
            _selectedImageIndex = _generatedImages.length - 1;
            _isGenerating = false;
            _currentStep = 0;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStep = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generation failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // UI Builders
  // ===========================================================================

  Widget _buildImageArea() {
    // Generating state
    if (_isGenerating || _isDownloading || _isInitializing) {
      return _buildProgressArea();
    }

    // Has selected image
    if (_selectedImageIndex >= 0 &&
        _selectedImageIndex < _generatedImages.length) {
      final image = _generatedImages[_selectedImageIndex];
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  image.pngBytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          // Image info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '"${image.prompt}"',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Column(
              children: [
                Text(
                  '${(image.generationTimeMs / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
                if (image.isRaw && image.rawWidth != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Raw RGB: ${image.rawWidth}x${image.rawHeight} (${image.rawChannels}ch, ${image.rawWidth! * image.rawHeight! * image.rawChannels!} bytes)',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Empty placeholder
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 72,
            color: AppTheme.border,
          ),
          SizedBox(height: 16),
          Text(
            'Generate your first image',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Images are generated entirely on your device',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressArea() {
    String statusText;
    double? progressValue;

    if (_isDownloading) {
      statusText = 'Downloading model... ${(_downloadProgress * 100).toInt()}%';
      progressValue = _downloadProgress > 0 ? _downloadProgress : null;
    } else if (_isInitializing) {
      statusText = 'Loading model into memory...';
      progressValue = null;
    } else {
      // Generating
      if (_currentStep > 0 && _totalSteps > 0) {
        statusText = 'Step $_currentStep/$_totalSteps';
        progressValue = _currentStep / _totalSteps;
      } else {
        statusText = 'Generating...';
        progressValue = null;
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator.adaptive(
                value: progressValue,
                strokeWidth: 3,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              statusText,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
              ),
            ),
            if (_isGenerating && _currentStep > 0 && _totalSteps > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _currentStep / _totalSteps,
                    color: AppTheme.accent,
                    backgroundColor: AppTheme.surfaceVariant,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryStrip() {
    if (_generatedImages.length < 2) return const SizedBox.shrink();

    return Container(
      height: 106,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _generatedImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final image = _generatedImages[index];
          final isSelected = index == _selectedImageIndex;
          return GestureDetector(
            onTap: () {
              if (!_isGenerating) {
                setState(() {
                  _selectedImageIndex = index;
                });
              }
            },
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppTheme.accent : AppTheme.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      image.pngBytes,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 64,
                  child: Text(
                    image.prompt,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.textPrimary
                          : AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPromptInput() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Prompt row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Describe your image...',
                        hintStyle: const TextStyle(
                          color: AppTheme.textTertiary,
                        ),
                        filled: true,
                        fillColor: AppTheme.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              const BorderSide(color: AppTheme.accent, width: 1),
                        ),
                      ),
                      maxLines: 2,
                      minLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _generate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Generate button
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          (_isGenerating || _isDownloading || _isInitializing)
                              ? null
                              : _generate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.background,
                        disabledBackgroundColor:
                            AppTheme.accent.withValues(alpha: 0.3),
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.auto_awesome, size: 22),
                    ),
                  ),
                ],
              ),
            ),

            // Advanced settings toggle
            _buildAdvancedPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle row
        GestureDetector(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Text(
                  'Advanced',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showAdvanced
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppTheme.textTertiary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),

        // Advanced content
        if (_showAdvanced) _buildAdvancedContent(),
      ],
    );
  }

  Widget _buildAdvancedContent() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          // Steps slider
          _buildSliderRow(
            label: 'Steps',
            value: _steps.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            displayValue: '$_steps',
            onChanged: (v) => setState(() => _steps = v.round()),
          ),

          // Guidance Scale slider
          _buildSliderRow(
            label: 'Guidance',
            value: _cfgScale,
            min: 0.0,
            max: 20.0,
            divisions: 40,
            displayValue: _cfgScale.toStringAsFixed(1),
            onChanged: (v) => setState(() => _cfgScale = v),
          ),

          const SizedBox(height: 4),

          // Seed + Size row
          Row(
            children: [
              // Seed
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Seed',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            hintText: '-1 (random)',
                            hintStyle: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: AppTheme.surfaceVariant,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              signed: true),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null) {
                              setState(() => _seed = parsed);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Size preset chips
              _buildSizeChip('256', 256),
              const SizedBox(width: 6),
              _buildSizeChip('512', 512),
            ],
          ),

          const SizedBox(height: 8),

          // Sampler selector
          Row(
            children: [
              const Text(
                'Sampler',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: _buildSamplerDropdown(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Raw RGB output toggle
          Row(
            children: [
              const Text(
                'Raw RGB',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Switch.adaptive(
                  value: _useRawOutput,
                  onChanged: (v) => setState(() => _useRawOutput = v),
                  activeTrackColor: AppTheme.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.surfaceVariant,
              thumbColor: AppTheme.accent,
              overlayColor: AppTheme.accent.withValues(alpha: 0.12),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            displayValue,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSizeChip(String label, int size) {
    final isSelected = _width == size;
    return GestureDetector(
      onTap: () => setState(() {
        _width = size;
        _height = size;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accent : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          '${label}x$label',
          style: TextStyle(
            color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSamplerDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ImageSampler>(
          value: _sampler,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppTheme.textTertiary,
            size: 18,
          ),
          items: const [
            DropdownMenuItem(
              value: ImageSampler.eulerA,
              child: Text('Euler A'),
            ),
            DropdownMenuItem(
              value: ImageSampler.euler,
              child: Text('Euler'),
            ),
            DropdownMenuItem(
              value: ImageSampler.dpmPlusPlus2m,
              child: Text('DPM++ 2M'),
            ),
            DropdownMenuItem(
              value: ImageSampler.dpmPlusPlus2sA,
              child: Text('DPM++ 2S a'),
            ),
            DropdownMenuItem(
              value: ImageSampler.lcm,
              child: Text('LCM'),
            ),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => _sampler = v);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Image',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.background,
        actions: [
          // Model status indicator
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isModelLoaded
                        ? AppTheme.success
                        : AppTheme.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isModelLoaded ? 'Loaded' : 'Not loaded',
                  style: TextStyle(
                    color: _isModelLoaded
                        ? AppTheme.success
                        : AppTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Image display area
          Expanded(child: _buildImageArea()),

          // Gallery strip (only when 2+ images)
          _buildGalleryStrip(),

          // Prompt input + advanced
          _buildPromptInput(),
        ],
      ),
    );
  }
}
