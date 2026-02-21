import 'package:camera/camera.dart';
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'soak_test_service.dart';

/// Soak test view. Runtime is managed by [SoakTestService] so it can continue
/// after this screen is closed.
class SoakTestScreen extends StatefulWidget {
  const SoakTestScreen({super.key});

  @override
  State<SoakTestScreen> createState() => _SoakTestScreenState();
}

class _SoakTestScreenState extends State<SoakTestScreen> {
  final SoakTestService _service = SoakTestService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _start() => _service.start();

  Future<void> _stop() => _service.stop();

  Future<void> _shareTrace() => _service.shareTrace();

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
    if (_service.elapsed.inSeconds <= 0 || _service.totalTokens <= 0) {
      return 0;
    }
    return _service.totalTokens / _service.elapsed.inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _service.isRunning;
    final isInitializing = _service.isInitializing;
    final isManaged = _service.isManaged;
    final cameraController = _service.cameraController;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Soak Test'),
            const Spacer(),
            if (isRunning)
              Text(
                _formatDuration(_service.elapsed),
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
          if (_service.cameraSupported &&
              cameraController != null &&
              cameraController.value.isInitialized)
            SizedBox(
              height: 200,
              width: double.infinity,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraController.value.previewSize!.height,
                    height: cameraController.value.previewSize!.width,
                    child: CameraPreview(cameraController),
                  ),
                ),
              ),
            ),
          if (!_service.cameraSupported && isRunning)
            Container(
              height: 80,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppTheme.surface,
              child: const Center(
                child: Text(
                  'Manual soak monitoring (camera not available on macOS)',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ),
            ),
          if (_service.lastDescription != null &&
              _service.lastDescription!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surface,
              child: Text(
                _service.lastDescription!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (!isRunning && !isInitializing) ...[
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
                              onTap: () => _service.setManagedMode(true),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isManaged
                                      ? AppTheme.accent
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  'Managed',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isManaged
                                        ? AppTheme.background
                                        : AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _service.setManagedMode(false),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !isManaged
                                      ? AppTheme.danger
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  'Raw (Baseline)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: !isManaged
                                        ? AppTheme.textPrimary
                                        : AppTheme.textSecondary,
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
                    if (!isManaged)
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
                    _service.statusMessage,
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
                      onPressed:
                          isInitializing ? null : (isRunning ? _stop : _start),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isRunning ? AppTheme.danger : AppTheme.accent,
                        foregroundColor: AppTheme.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isInitializing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.textPrimary,
                              ),
                            )
                          : Text(
                              isRunning
                                  ? 'Stop'
                                  : 'Start ${isManaged ? "Managed" : "Raw"} Soak Test',
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
    final isManaged = _service.isManaged;

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
                  color: isManaged
                      ? AppTheme.accent.withValues(alpha: 0.2)
                      : AppTheme.danger.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isManaged ? 'MANAGED' : 'RAW',
                  style: TextStyle(
                    color: isManaged ? AppTheme.accent : AppTheme.danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMetricRow('Frames Processed', '${_service.frameCount}'),
          _buildMetricRow(
            'Avg Latency',
            _service.frameCount > 0
                ? '${_service.avgLatencyMs.toStringAsFixed(0)} ms'
                : '-',
          ),
          _buildMetricRow(
            'Last Latency',
            _service.lastLatencyMs > 0
                ? '${_service.lastLatencyMs.toStringAsFixed(0)} ms'
                : '-',
          ),
          _buildMetricRow(
            'Tokens/sec',
            _tokensPerSecond() > 0
                ? _tokensPerSecond().toStringAsFixed(1)
                : '-',
          ),
          _buildMetricRow('Dropped Frames', '${_service.droppedFrames}'),
          const Divider(color: AppTheme.border, height: 24),
          _buildMetricRow(
            'Thermal',
            _thermalString(_service.thermalState),
            valueColor: _thermalColor(_service.thermalState),
          ),
          _buildMetricRow('Battery', _formatBattery(_service.batteryLevel)),
          _buildMetricRow(
              'Memory RSS', _formatMemoryMB(_service.memoryRssBytes)),
          _buildMetricRow(
            'QoS Level',
            _service.currentQoS.name,
            valueColor: _qosColor(_service.currentQoS),
          ),
          if (isManaged) ...[
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
            _buildMetricRow('Profile', 'balanced'),
            _buildMetricRow(
              'Status',
              _service.resolvedBudget != null ? 'Resolved' : 'Warming up…',
              valueColor: _service.resolvedBudget != null
                  ? AppTheme.success
                  : AppTheme.textTertiary,
            ),
            if (_service.measuredBaseline != null) ...[
              _buildMetricRow(
                'Measured p95',
                '${_service.measuredBaseline!.measuredP95Ms.toStringAsFixed(0)} ms',
              ),
              _buildMetricRow(
                'Measured Drain',
                _service.measuredBaseline!.measuredDrainPerTenMin != null
                    ? '${_service.measuredBaseline!.measuredDrainPerTenMin!.toStringAsFixed(1)}%/10min'
                    : 'pending…',
                valueColor:
                    _service.measuredBaseline!.measuredDrainPerTenMin != null
                        ? AppTheme.textPrimary
                        : AppTheme.textTertiary,
              ),
            ],
            if (_service.resolvedBudget != null) ...[
              _buildMetricRow(
                'Budget p95',
                '${_service.resolvedBudget!.p95LatencyMs ?? "-"} ms',
                valueColor: AppTheme.accent,
              ),
              _buildMetricRow(
                'Budget Thermal',
                '≤ ${_service.resolvedBudget!.maxThermalLevel ?? "-"}',
                valueColor: AppTheme.accent,
              ),
              if (_service.resolvedBudget!.batteryDrainPerTenMinutes != null)
                _buildMetricRow(
                  'Budget Drain',
                  '≤ ${_service.resolvedBudget!.batteryDrainPerTenMinutes!.toStringAsFixed(1)}%/10min',
                  valueColor: AppTheme.accent,
                ),
            ],
            const Divider(color: AppTheme.border, height: 24),
            _buildMetricRow(
              'Actionable Violations',
              '${_service.actionableViolationCount}',
              valueColor: _service.actionableViolationCount > 0
                  ? AppTheme.warning
                  : AppTheme.success,
            ),
            _buildMetricRow(
              'Observe-Only (memory)',
              '${_service.observeOnlyViolationCount}',
              valueColor: AppTheme.textTertiary,
            ),
            if (_service.lastViolation != null)
              _buildMetricRow(
                'Last Violation',
                _service.lastViolation!,
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
            '${_formatDuration(_service.elapsed)} / ${_formatDuration(_service.testDuration)}',
          ),
          _buildMetricRow('Total Tokens', '${_service.totalTokens}'),
          _buildMetricRow(
            'QoS Knobs',
            _service.isRunning
                ? () {
                    if (!_service.isManaged) {
                      return 'fps=2 res=640 tok=100 (fixed)';
                    }
                    final k = _service.currentKnobs;
                    return 'fps=${k.maxFps} res=${k.resolution} tok=${k.maxTokens}';
                  }()
                : '-',
          ),
          if (_service.traceFilePath != null) ...[
            const Divider(color: AppTheme.border, height: 24),
            Text(
              'Trace: ${_service.traceFilePath!.split('/').last}',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _service.traceFilePath != null && !_service.isRunning
                  ? _shareTrace
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
