import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';
import 'performance_trackers.dart';

/// Sub-screen showing live performance metrics:
/// - LatencyTracker percentiles (p50/p95/p99)
/// - BatteryDrainTracker drain rate
/// - isMemoryPressure() check with threshold slider
/// - MemoryPressureEvent Android listener status
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  Timer? _refreshTimer;
  double _memoryThreshold = 0.8;
  bool? _isUnderPressure;
  bool _checkingPressure = false;

  @override
  void initState() {
    super.initState();
    // Refresh UI every 2 seconds for live values
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkMemoryPressure() async {
    setState(() => _checkingPressure = true);
    try {
      final edgeVeda = EdgeVeda();
      final result = await edgeVeda.isMemoryPressure(threshold: _memoryThreshold);
      if (mounted) {
        setState(() {
          _isUnderPressure = result;
          _checkingPressure = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUnderPressure = null;
          _checkingPressure = false;
        });
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
        title: const Text('Performance'),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          _buildLatencyPanel(),
          const SizedBox(height: 24),
          _buildBatteryPanel(),
          const SizedBox(height: 24),
          _buildMemoryPressurePanel(),
          const SizedBox(height: 24),
          _buildMemoryPressureEventPanel(),
        ],
      ),
    );
  }

  // ── Latency Tracker Panel ────────────────────────────────────────────

  Widget _buildLatencyPanel() {
    final tracker = PerformanceTrackers.latency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Latency Tracker'),
        _buildCard(
          child: Column(
            children: [
              // Percentile cards
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildPercentileCard('p50', tracker.p50),
                    const SizedBox(width: 12),
                    _buildPercentileCard('p95', tracker.p95),
                    const SizedBox(width: 12),
                    _buildPercentileCard('p99', tracker.p99),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              // Status row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      tracker.isWarmedUp ? Icons.check_circle : Icons.hourglass_top,
                      color: tracker.isWarmedUp ? AppTheme.success : AppTheme.warning,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tracker.isWarmedUp ? 'Warmed up' : 'Warming up...',
                      style: TextStyle(
                        color: tracker.isWarmedUp ? AppTheme.success : AppTheme.warning,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${tracker.sampleCount} samples',
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              // Reset button
              ListTile(
                leading: const Icon(Icons.refresh, color: AppTheme.accent, size: 20),
                title: const Text(
                  'Reset Latency Data',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  PerformanceTrackers.latency.reset();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPercentileCard(String label, double? value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value != null ? '${value.toStringAsFixed(0)}ms' : '--',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Battery Drain Panel ──────────────────────────────────────────────

  Widget _buildBatteryPanel() {
    final tracker = PerformanceTrackers.battery;
    final drain = tracker.drainPerTenMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Battery Drain Tracker'),
        _buildCard(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.battery_alert, color: AppTheme.accent, size: 22),
                    const SizedBox(width: 12),
                    const Text(
                      'Drain / 10 min',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      drain != null ? '${drain.toStringAsFixed(1)}%' : 'No data',
                      style: TextStyle(
                        color: drain != null ? AppTheme.accent : AppTheme.textTertiary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Text(
                      'Add battery readings from your monitoring code',
                      style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              ListTile(
                leading: const Icon(Icons.refresh, color: AppTheme.accent, size: 20),
                title: const Text(
                  'Reset Battery Data',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  PerformanceTrackers.battery.reset();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Memory Pressure Check Panel ──────────────────────────────────────

  Widget _buildMemoryPressurePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Memory Pressure Check'),
        _buildCard(
          child: Column(
            children: [
              // Threshold slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.memory, color: AppTheme.accent, size: 22),
                    const SizedBox(width: 12),
                    const Text(
                      'Threshold',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '${(_memoryThreshold * 100).round()}%',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Slider(
                value: _memoryThreshold,
                min: 0.5,
                max: 0.95,
                divisions: 9,
                activeColor: AppTheme.accent,
                inactiveColor: AppTheme.border,
                onChanged: (v) => setState(() {
                  _memoryThreshold = v;
                  _isUnderPressure = null; // Reset result on threshold change
                }),
              ),
              const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
              // Check button + result
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _checkingPressure ? null : _checkMemoryPressure,
                        icon: _checkingPressure
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background),
                              )
                            : const Icon(Icons.play_arrow, size: 20),
                        label: const Text('Check Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.background,
                        ),
                      ),
                    ),
                    if (_isUnderPressure != null) ...[
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isUnderPressure!
                              ? AppTheme.danger.withValues(alpha: 0.15)
                              : AppTheme.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isUnderPressure!
                                ? AppTheme.danger.withValues(alpha: 0.4)
                                : AppTheme.success.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isUnderPressure! ? Icons.warning : Icons.check_circle,
                              color: _isUnderPressure! ? AppTheme.danger : AppTheme.success,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isUnderPressure! ? 'Pressure!' : 'OK',
                              style: TextStyle(
                                color: _isUnderPressure! ? AppTheme.danger : AppTheme.success,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
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
          ),
        ),
      ],
    );
  }

  // ── Memory Pressure Event Panel ──────────────────────────────────────

  Widget _buildMemoryPressureEventPanel() {
    final isAndroid = Platform.isAndroid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Memory Pressure Events'),
        _buildCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isAndroid ? Icons.notifications_active : Icons.notifications_off,
                  color: isAndroid ? AppTheme.accent : AppTheme.textTertiary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAndroid ? 'EventChannel Active' : 'Android Only',
                        style: TextStyle(
                          color: isAndroid ? AppTheme.textPrimary : AppTheme.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAndroid
                            ? 'Listening for onTrimMemory events'
                            : 'MemoryPressureEvent uses Android EventChannel (not available on this platform)',
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAndroid
                        ? AppTheme.success.withValues(alpha: 0.15)
                        : AppTheme.textTertiary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAndroid ? 'Active' : 'N/A',
                    style: TextStyle(
                      color: isAndroid ? AppTheme.success : AppTheme.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

  // ── Shared Helpers ───────────────────────────────────────────────────

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
