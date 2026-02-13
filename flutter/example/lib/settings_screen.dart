import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';
import 'detective_screen.dart';
import 'soak_test_screen.dart';

/// Settings tab with generation controls, storage overview, model management,
/// and about section.
///
/// Provides visual controls for temperature and max tokens, displays model
/// download status via ModelManager, and shows app/SDK version info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Generation settings (local state for display)
  double _temperature = 0.7;
  double _maxTokens = 256;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          _buildDeviceStatusSection(),
          const SizedBox(height: 24),
          _buildGenerationSection(),
          const SizedBox(height: 24),
          _buildStorageSection(),
          const SizedBox(height: 24),
          _buildModelsSection(),
          const SizedBox(height: 24),
          _buildDeveloperSection(),
          const SizedBox(height: 24),
          _buildAboutSection(),
          const SizedBox(height: 40),
          const SafeArea(
            top: false,
            child: SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── Section Header ──────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── Card Container ──────────────────────────────────────────────────────

  Widget _buildCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }

  // ── Section 0: Device Status ────────────────────────────────────────────

  Widget _buildDeviceStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Device Status'),
        _buildCard(
          child: Column(
            children: [
              _buildAboutRow(
                icon: Icons.phone_iphone,
                title: 'Model',
                value: _DeviceInfo.model,
              ),
              const Divider(
                  color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              _buildAboutRow(
                icon: Icons.developer_board,
                title: 'Chip',
                value: _DeviceInfo.chip,
              ),
              const Divider(
                  color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              _buildAboutRow(
                icon: Icons.memory,
                title: 'Memory',
                value: _DeviceInfo.memoryString,
              ),
              const Divider(
                  color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.psychology,
                        color: AppTheme.accent, size: 22),
                    const SizedBox(width: 12),
                    const Text(
                      'Neural Engine',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _DeviceInfo.hasNeuralEngine
                          ? Icons.check_circle
                          : Icons.cancel_outlined,
                      color: _DeviceInfo.hasNeuralEngine
                          ? AppTheme.success
                          : AppTheme.textTertiary,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section 1: Generation Settings ──────────────────────────────────────

  Widget _buildGenerationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Generation'),
        _buildCard(
          child: Column(
            children: [
              // Temperature
              _buildSettingRow(
                icon: Icons.thermostat,
                title: 'Temperature',
                value: _temperature.toStringAsFixed(1),
              ),
              Slider(
                value: _temperature,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                activeColor: AppTheme.accent,
                inactiveColor: AppTheme.border,
                onChanged: (v) => setState(() => _temperature = v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Precise',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      'Creative',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              const SizedBox(height: 8),
              // Max Tokens
              _buildSettingRow(
                icon: Icons.article_outlined,
                title: 'Max Tokens',
                value: _maxTokens.round().toString(),
              ),
              Slider(
                value: _maxTokens,
                min: 32,
                max: 1024,
                divisions: 31,
                activeColor: AppTheme.accent,
                inactiveColor: AppTheme.border,
                onChanged: (v) => setState(() => _maxTokens = v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Short',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      'Long',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section 2: Storage ──────────────────────────────────────────────────

  Widget _buildStorageSection() {
    // Sum known model sizes for the models used in the demo app
    final models = [
      ModelRegistry.llama32_1b,
      ModelRegistry.smolvlm2_500m,
      ModelRegistry.smolvlm2_500m_mmproj,
      ModelRegistry.qwen3_06b,
    ];
    final totalBytes = models.fold<int>(0, (sum, m) => sum + m.sizeBytes);
    final totalGb = totalBytes / (1024 * 1024 * 1024);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Storage'),
        _buildCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.storage, color: AppTheme.accent, size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Models',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '~${totalGb.toStringAsFixed(1)} GB',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Storage bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        // Background
                        Container(
                          decoration: const BoxDecoration(
                            color: AppTheme.surfaceVariant,
                          ),
                        ),
                        // Fill (proportional to ~1.3GB out of ~4GB capacity estimate)
                        FractionallySizedBox(
                          widthFactor: (totalGb / 4.0).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${totalGb.toStringAsFixed(1)} GB used',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Section 3: Models ───────────────────────────────────────────────────

  Widget _buildModelsSection() {
    final models = [
      ModelRegistry.llama32_1b,
      ModelRegistry.smolvlm2_500m,
      ModelRegistry.smolvlm2_500m_mmproj,
      ModelRegistry.qwen3_06b,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Models'),
        _buildCard(
          child: Column(
            children: [
              for (int i = 0; i < models.length; i++) ...[
                _ModelRow(model: models[i], onDeleted: () => setState(() {})),
                if (i < models.length - 1)
                  const Divider(
                    color: AppTheme.border,
                    indent: 16,
                    endIndent: 16,
                    height: 1,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Section 4: Developer ────────────────────────────────────────────────

  Widget _buildDeveloperSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Developer'),
        _buildCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.science, color: AppTheme.accent),
                title: const Text(
                  'Soak Test',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                subtitle: const Text(
                  '15-min sustained vision benchmark',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textTertiary,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SoakTestScreen(),
                    ),
                  );
                },
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              ListTile(
                leading: const Icon(Icons.policy, color: AppTheme.accent),
                title: const Text(
                  'Phone Detective',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                subtitle: const Text(
                  'On-device behavioral insights with Qwen3',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textTertiary,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DetectiveScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section 5: About ───────────────────────────────────────────────────

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('About'),
        _buildCard(
          child: Column(
            children: [
              _buildAboutRow(
                icon: Icons.auto_awesome,
                title: 'Veda',
                value: '1.1.0',
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              _buildAboutRow(
                icon: Icons.code,
                title: 'Veda SDK',
                value: '1.1.0',
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              _buildAboutRow(
                icon: Icons.memory,
                title: 'Backend',
                value: Platform.isIOS ? 'Metal GPU' : 'CPU',
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.accent, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privacy',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'All inference runs locally on device',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Helper: Setting Row ─────────────────────────────────────────────────

  Widget _buildSettingRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 22),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper: About Row ──────────────────────────────────────────────────

  Widget _buildAboutRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 22),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Model Row Widget (uses FutureBuilder for download status) ────────────

class _ModelRow extends StatefulWidget {
  final ModelInfo model;
  final VoidCallback? onDeleted;

  const _ModelRow({required this.model, this.onDeleted});

  @override
  State<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends State<_ModelRow> {
  bool _isDeleting = false;
  bool? _isDownloaded;

  String _formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '~${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '~${mb.round()} MB';
  }

  IconData _modelIcon() {
    if (widget.model.id.contains('mmproj')) return Icons.extension;
    if (widget.model.id.contains('vlm') || widget.model.id.contains('smol')) {
      return Icons.visibility;
    }
    return Icons.smart_toy;
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Model', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Delete "${widget.model.name}" (${_formatSize(widget.model.sizeBytes)})?\n\nIt will be re-downloaded when needed.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeleting = true);
      await ModelManager().deleteModel(widget.model.id);
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _isDownloaded = false;
        });
        widget.onDeleted?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isDownloaded != null
          ? Future.value(_isDownloaded!)
          : ModelManager().isModelDownloaded(widget.model.id),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? false;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(_modelIcon(), color: AppTheme.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.model.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatSize(widget.model.sizeBytes),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting || _isDeleting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                )
              else ...[
                Icon(
                  isDownloaded ? Icons.check_circle : Icons.cloud_download_outlined,
                  color: isDownloaded ? AppTheme.success : AppTheme.textTertiary,
                  size: 20,
                ),
                if (isDownloaded) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _confirmAndDelete,
                    child: const Icon(
                      Icons.delete_outline,
                      color: AppTheme.textTertiary,
                      size: 20,
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Device Info Helper (sysctlbyname FFI) ────────────────────────────────

typedef _SysctlByNameC = ffi.Int Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>,
  ffi.Size,
);
typedef _SysctlByNameDart = int Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>,
  int,
);

class _DeviceInfo {
  static final _sysctlbyname = ffi.DynamicLibrary.process()
      .lookupFunction<_SysctlByNameC, _SysctlByNameDart>('sysctlbyname');

  static String? _cachedModel;
  static double? _cachedMemory;

  static String get model {
    if (_cachedModel != null) return _cachedModel!;
    try {
      _cachedModel = _readString('hw.machine');
    } catch (_) {
      _cachedModel = Platform.operatingSystem;
    }
    return _cachedModel!;
  }

  static String get chip {
    if (Platform.isIOS || Platform.isMacOS) return 'Apple Silicon';
    return 'Unknown';
  }

  static double get memoryGB {
    if (_cachedMemory != null) return _cachedMemory!;
    try {
      _cachedMemory = _readInt64('hw.memsize') / (1024 * 1024 * 1024);
    } catch (_) {
      _cachedMemory = 0;
    }
    return _cachedMemory!;
  }

  static String get memoryString {
    final gb = memoryGB;
    if (gb <= 0) return 'Unknown';
    return '${gb.toStringAsFixed(2)} GB';
  }

  static bool get hasNeuralEngine => Platform.isIOS;

  static String _readString(String name) {
    final namePtr = name.toNativeUtf8();
    final sizePtr = calloc<ffi.Size>();
    try {
      _sysctlbyname(namePtr.cast(), ffi.nullptr, sizePtr, ffi.nullptr, 0);
      final bufLen = sizePtr.value;
      if (bufLen == 0) return 'Unknown';

      final buf = calloc<ffi.Uint8>(bufLen);
      try {
        _sysctlbyname(namePtr.cast(), buf.cast(), sizePtr, ffi.nullptr, 0);
        return buf.cast<Utf8>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(sizePtr);
      calloc.free(namePtr);
    }
  }

  static int _readInt64(String name) {
    final namePtr = name.toNativeUtf8();
    final sizePtr = calloc<ffi.Size>();
    final valPtr = calloc<ffi.Int64>();
    try {
      sizePtr.value = ffi.sizeOf<ffi.Int64>();
      _sysctlbyname(namePtr.cast(), valPtr.cast(), sizePtr, ffi.nullptr, 0);
      return valPtr.value;
    } finally {
      calloc.free(valPtr);
      calloc.free(sizePtr);
      calloc.free(namePtr);
    }
  }
}
