import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

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
          _buildGenerationSection(),
          const SizedBox(height: 24),
          _buildStorageSection(),
          const SizedBox(height: 24),
          _buildModelsSection(),
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
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Models'),
        _buildCard(
          child: Column(
            children: [
              for (int i = 0; i < models.length; i++) ...[
                _ModelRow(model: models[i]),
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

  // ── Section 4: About ───────────────────────────────────────────────────

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

class _ModelRow extends StatelessWidget {
  final ModelInfo model;

  const _ModelRow({required this.model});

  String _formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '~${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '~${mb.round()} MB';
  }

  IconData _modelIcon() {
    if (model.id.contains('mmproj')) return Icons.extension;
    if (model.id.contains('vlm') || model.id.contains('smol')) {
      return Icons.visibility;
    }
    return Icons.smart_toy;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ModelManager().isModelDownloaded(model.id),
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
                      model.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatSize(model.sizeBytes),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                )
              else
                Icon(
                  isDownloaded ? Icons.check_circle : Icons.cloud_download_outlined,
                  color: isDownloaded ? AppTheme.success : AppTheme.textTertiary,
                  size: 20,
                ),
            ],
          ),
        );
      },
    );
  }
}
