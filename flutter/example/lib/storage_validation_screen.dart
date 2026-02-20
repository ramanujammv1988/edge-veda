import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// Sub-screen showing storage and memory validation details:
/// - StorageCheck: disk space analysis
/// - MemoryValidation: memory pressure status
/// - MemoryEstimator: model memory estimates
class StorageValidationScreen extends StatefulWidget {
  const StorageValidationScreen({super.key});

  @override
  State<StorageValidationScreen> createState() => _StorageValidationScreenState();
}

class _StorageValidationScreenState extends State<StorageValidationScreen> {
  StorageCheck? _storageCheck;
  MemoryValidation? _memoryValidation;
  MemoryEstimate? _memoryEstimate;
  bool _isLoading = false;
  ModelInfo _selectedModel = ModelRegistry.llama32_1b;

  final _models = [
    ModelRegistry.llama32_1b,
    ModelRegistry.smolvlm2_500m,
    ModelRegistry.qwen3_06b,
  ];

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() => _isLoading = true);

    try {
      final device = DeviceProfile.detect();

      // Run storage check
      final storage = await ModelAdvisor.checkStorageAvailability(
        model: _selectedModel,
      );

      // Run memory validation (requires initialized EdgeVeda — graceful fallback)
      MemoryValidation? memory;
      try {
        final edgeVeda = EdgeVeda();
        memory = await ModelAdvisor.validateMemoryAfterLoad(edgeVeda);
      } catch (_) {
        memory = const MemoryValidation(
          usagePercent: 0,
          isHighPressure: false,
          isCritical: false,
          status: 'No model loaded',
        );
      }

      final estimate = MemoryEstimator.estimate(
        model: _selectedModel,
        device: device,
      );

      if (mounted) {
        setState(() {
          _storageCheck = storage;
          _memoryValidation = memory;
          _memoryEstimate = estimate;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Storage & Memory'),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 40),
              children: [
                _buildStorageSection(),
                const SizedBox(height: 24),
                _buildMemoryValidationSection(),
                const SizedBox(height: 24),
                _buildMemoryEstimatorSection(),
              ],
            ),
    );
  }

  // ── Storage Check ────────────────────────────────────────────────────

  Widget _buildStorageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Storage Check'),
        _buildCard(
          child: _storageCheck == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No data', style: TextStyle(color: AppTheme.textTertiary)),
                )
              : Column(
                  children: [
                    _buildInfoRow(
                      Icons.sd_storage,
                      'Free Disk',
                      _storageCheck!.freeDiskBytes >= 0
                          ? _formatBytes(_storageCheck!.freeDiskBytes)
                          : 'Unavailable',
                    ),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildInfoRow(
                      Icons.file_download,
                      'Required',
                      _formatBytes(_storageCheck!.requiredBytes),
                    ),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildStatusRow(
                      'Sufficient Space',
                      _storageCheck!.hasSufficientSpace,
                    ),
                    if (_storageCheck!.warning != null) ...[
                      const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: AppTheme.warning, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _storageCheck!.warning!,
                                style: const TextStyle(
                                  color: AppTheme.warning,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ── Memory Validation ────────────────────────────────────────────────

  Widget _buildMemoryValidationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Memory Validation'),
        _buildCard(
          child: _memoryValidation == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No data', style: TextStyle(color: AppTheme.textTertiary)),
                )
              : Column(
                  children: [
                    _buildInfoRow(
                      Icons.memory,
                      'Usage',
                      '${(_memoryValidation!.usagePercent * 100).toStringAsFixed(1)}%',
                    ),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildStatusRow(
                      'High Pressure',
                      !_memoryValidation!.isHighPressure,
                      trueLabel: 'No',
                      falseLabel: 'Yes',
                    ),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildStatusRow(
                      'Critical',
                      !_memoryValidation!.isCritical,
                      trueLabel: 'No',
                      falseLabel: 'Yes',
                    ),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildInfoRow(
                      Icons.info_outline,
                      'Status',
                      _memoryValidation!.status,
                    ),
                    if (_memoryValidation!.warning != null) ...[
                      const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: AppTheme.warning, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _memoryValidation!.warning!,
                                style: const TextStyle(
                                  color: AppTheme.warning,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ── Memory Estimator ─────────────────────────────────────────────────

  Widget _buildMemoryEstimatorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Memory Estimator'),
        // Model selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ModelInfo>(
                value: _selectedModel,
                isExpanded: true,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textTertiary),
                items: _models.map((m) {
                  return DropdownMenuItem(value: m, child: Text(m.name));
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedModel = v);
                    _runChecks();
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          child: _memoryEstimate == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No data', style: TextStyle(color: AppTheme.textTertiary)),
                )
              : Column(
                  children: [
                    _buildInfoRow(Icons.memory, 'Total', '${_memoryEstimate!.totalMB} MB'),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildInfoRow(Icons.layers, 'Model Weights', '${_memoryEstimate!.modelWeightsMB} MB'),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildInfoRow(Icons.view_column, 'KV Cache', '${_memoryEstimate!.kvCacheMB} MB'),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildInfoRow(Icons.developer_board, 'Metal Buffers', '${_memoryEstimate!.metalBuffersMB} MB'),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildInfoRow(Icons.settings, 'Runtime Overhead', '${_memoryEstimate!.runtimeOverheadMB} MB'),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildInfoRow(Icons.pie_chart, 'Memory Ratio', '${(_memoryEstimate!.memoryRatio * 100).toStringAsFixed(0)}%'),
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                    _buildStatusRow('Fits Device', _memoryEstimate!.fits),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Shared Helpers ───────────────────────────────────────────────────

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 22),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String title, bool isGood, {String trueLabel = 'Yes', String falseLabel = 'No'}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            isGood ? Icons.check_circle : Icons.cancel_outlined,
            color: isGood ? AppTheme.success : AppTheme.danger,
            size: 22,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          const Spacer(),
          Text(
            isGood ? trueLabel : falseLabel,
            style: TextStyle(
              color: isGood ? AppTheme.success : AppTheme.danger,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
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
}
