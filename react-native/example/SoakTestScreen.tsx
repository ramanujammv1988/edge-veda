import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  ScrollView,
  Clipboard,
} from 'react-native';
import { AppTheme } from './theme';
import {
  VisionWorker,
  ModelManager,
  ModelRegistry,
  Scheduler,
  Budget,
  BudgetProfile,
  ThermalMonitor,
  BatteryDrainTracker,
  LatencyTracker,
  RuntimePolicyEnforcer,
  RuntimePolicyPresets,
  Telemetry,
  PerfTrace,
  TaskPriority,
} from 'edge-veda';

/**
 * 20-minute sustained vision inference benchmark.
 *
 * Matches Flutter's soak_test_screen.dart:
 * - Managed mode: full Scheduler + Budget + Thermal + Battery + Latency stack
 * - Raw mode: bare VisionWorker with fixed QoS
 * - Live metrics card: frames, latency, tok/s, dropped, thermal, battery, memory
 * - Auto-stop after 20 minutes
 * - Export trace (JSONL) to clipboard
 */

const SOAK_DURATION_MS = 20 * 60 * 1000; // 20 minutes
const FRAME_INTERVAL_MS = 500; // 2 fps target

type SoakMode = 'managed' | 'raw';
type SoakState = 'idle' | 'downloading' | 'loading' | 'running' | 'stopped';

interface LiveMetrics {
  framesProcessed: number;
  avgLatencyMs: number;
  lastLatencyMs: number;
  tokensPerSec: number;
  droppedFrames: number;
  thermalEmoji: string;
  batteryPct: number;
  memoryMb: number;
  elapsedMs: number;
}

const DEFAULT_METRICS: LiveMetrics = {
  framesProcessed: 0,
  avgLatencyMs: 0,
  lastLatencyMs: 0,
  tokensPerSec: 0,
  droppedFrames: 0,
  thermalEmoji: '❄️',
  batteryPct: 100,
  memoryMb: 0,
  elapsedMs: 0,
};

function _thermalEmoji(state: string): string {
  switch (state) {
    case 'critical': return '⚠️';
    case 'high': return '🔥';
    case 'warm': return '🌡️';
    default: return '❄️';
  }
}

export function SoakTestScreen(): React.JSX.Element {
  const [soakState, setSoakState] = useState<SoakState>('idle');
  const [mode, setMode] = useState<SoakMode>('managed');
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [statusMessage, setStatusMessage] = useState('');
  const [metrics, setMetrics] = useState<LiveMetrics>(DEFAULT_METRICS);
  const [traceLines, setTraceLines] = useState<string[]>([]);

  // SDK references
  const visionWorkerRef = useRef(new VisionWorker());
  const schedulerRef = useRef<Scheduler | null>(null);
  const budgetRef = useRef<Budget | null>(null);
  const thermalRef = useRef<ThermalMonitor | null>(null);
  const batteryRef = useRef<BatteryDrainTracker | null>(null);
  const latencyRef = useRef<LatencyTracker | null>(null);
  const telemetryRef = useRef<Telemetry | null>(null);
  const enforcerRef = useRef<RuntimePolicyEnforcer | null>(null);
  const perfTraceRef = useRef<PerfTrace | null>(null);

  // Timing
  const startTimeRef = useRef<number>(0);
  const frameCountRef = useRef(0);
  const droppedRef = useRef(0);
  const latencySumRef = useRef(0);
  const tokenCountRef = useRef(0);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const stopTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isProcessingRef = useRef(false);
  const isRunningRef = useRef(false);

  // Synthetic frame (blank RGB 64×64 for demo — real app uses camera)
  const syntheticFrame = useRef<Uint8Array>(new Uint8Array(64 * 64 * 3));

  const stop = useCallback(async () => {
    isRunningRef.current = false;
    if (intervalRef.current) clearInterval(intervalRef.current);
    if (stopTimeoutRef.current) clearTimeout(stopTimeoutRef.current);

    batteryRef.current?.stopTracking();
    await visionWorkerRef.current.cleanup().catch(() => {});

    setSoakState('stopped');
    setStatusMessage('Test complete. Export trace to analyse results.');
  }, []);

  const start = async () => {
    if (soakState === 'running') return;

    setSoakState('downloading');
    setStatusMessage('Checking vision model…');
    setMetrics(DEFAULT_METRICS);
    setTraceLines([]);
    frameCountRef.current = 0;
    droppedRef.current = 0;
    latencySumRef.current = 0;
    tokenCountRef.current = 0;

    try {
      // Ensure model is available
      const mm = ModelManager.create();
      const model = ModelRegistry.smolvlm2_500m;
      const mmproj = ModelRegistry.smolvlm2_500m_mmproj;

      for (const m of [model, mmproj]) {
        if (!(await mm.isModelDownloaded(m.id))) {
          setStatusMessage(`Downloading ${m.name}…`);
          await mm.downloadModel(m, (p) => {
            setDownloadProgress(p.progress);
          });
        }
      }

      setSoakState('loading');
      setStatusMessage('Loading vision model…');

      const modelPath = (await mm.getModelPath(model.id))!;
      const mmprojPath = (await mm.getModelPath(mmproj.id))!;

      await visionWorkerRef.current.initialize({
        modelPath,
        mmprojPath,
        threads: 4,
        contextSize: 4096,
      });

      // Initialise supervision stack (managed mode only)
      if (mode === 'managed') {
        schedulerRef.current = new Scheduler();
        budgetRef.current = new Budget(BudgetProfile.Normal);
        thermalRef.current = new ThermalMonitor();
        batteryRef.current = new BatteryDrainTracker();
        latencyRef.current = new LatencyTracker();
        telemetryRef.current = new Telemetry();
        enforcerRef.current = new RuntimePolicyEnforcer(RuntimePolicyPresets.Balanced);
        perfTraceRef.current = new PerfTrace();

        batteryRef.current.startTracking();
      }

      setSoakState('running');
      setStatusMessage(mode === 'managed' ? 'Managed mode running…' : 'Raw mode running…');

      startTimeRef.current = Date.now();
      isRunningRef.current = true;

      // Auto-stop after SOAK_DURATION_MS
      stopTimeoutRef.current = setTimeout(stop, SOAK_DURATION_MS);

      // Per-frame interval
      intervalRef.current = setInterval(async () => {
        if (!isRunningRef.current || isProcessingRef.current) {
          droppedRef.current++;
          return;
        }

        isProcessingRef.current = true;
        const t0 = Date.now();

        try {
          const result = await visionWorkerRef.current.describeFrame(
            syntheticFrame.current,
            64,
            64,
            'Describe this image in one sentence.',
            { maxTokens: mode === 'managed' ? 60 : 100 },
          );

          const latencyMs = Date.now() - t0;
          frameCountRef.current++;
          latencySumRef.current += latencyMs;
          // Rough token estimate from description length
          const tokens = Math.round((result.description?.length ?? 0) / 4);
          tokenCountRef.current += tokens;

          // Record to supervision stack
          if (mode === 'managed') {
            latencyRef.current?.recordLatency('vision', latencyMs);
            telemetryRef.current?.recordLatency('vision', latencyMs);
            perfTraceRef.current?.record('frame', latencyMs, { tokens, dropped: droppedRef.current });
          }

          // Update live metrics
          const elapsedMs = Date.now() - startTimeRef.current;
          const elapsedSec = elapsedMs / 1000;
          const avgLatency = latencySumRef.current / Math.max(1, frameCountRef.current);
          const tps = tokenCountRef.current / Math.max(1, elapsedSec);
          const thermalState = mode === 'managed' && thermalRef.current
            ? thermalRef.current.getState()
            : 'nominal';
          const batteryPct = mode === 'managed' && batteryRef.current
            ? 100 // BatteryDrainTracker tracks drain rate, not level; show 100% as placeholder
            : 100;

          setMetrics({
            framesProcessed: frameCountRef.current,
            avgLatencyMs: Math.round(avgLatency),
            lastLatencyMs: latencyMs,
            tokensPerSec: Math.round(tps * 10) / 10,
            droppedFrames: droppedRef.current,
            thermalEmoji: _thermalEmoji(thermalState),
            batteryPct,
            memoryMb: 0, // Filled by native ResourceMonitor in real integration
            elapsedMs,
          });

          // Append a trace line every 10 frames
          if (frameCountRef.current % 10 === 0) {
            const line = JSON.stringify({
              frame: frameCountRef.current,
              latencyMs,
              avgLatencyMs: Math.round(avgLatency),
              tps: Math.round(tps * 10) / 10,
              dropped: droppedRef.current,
              elapsedMs,
              mode,
            });
            setTraceLines((prev) => [...prev.slice(-200), line]);
          }
        } catch {
          droppedRef.current++;
        }

        isProcessingRef.current = false;
      }, FRAME_INTERVAL_MS);
    } catch (e: any) {
      setSoakState('stopped');
      setStatusMessage(`Error: ${e.message}`);
    }
  };

  const exportTrace = () => {
    const content = traceLines.join('\n');
    Clipboard.setString(content);
    setStatusMessage('Trace copied to clipboard!');
  };

  const reset = async () => {
    await stop();
    setSoakState('idle');
    setMetrics(DEFAULT_METRICS);
    setTraceLines([]);
    setStatusMessage('');

    // Re-create vision worker for next run
    visionWorkerRef.current = new VisionWorker();
  };

  useEffect(() => {
    return () => {
      isRunningRef.current = false;
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (stopTimeoutRef.current) clearTimeout(stopTimeoutRef.current);
      visionWorkerRef.current.cleanup().catch(() => {});
    };
  }, []);

  const elapsedSec = Math.floor(metrics.elapsedMs / 1000);
  const elapsedMin = Math.floor(elapsedSec / 60);
  const elapsedSecRem = elapsedSec % 60;
  const elapsedStr = `${String(elapsedMin).padStart(2, '0')}:${String(elapsedSecRem).padStart(2, '0')}`;
  const totalMin = SOAK_DURATION_MS / 60000;
  const progressPct = Math.min(100, (metrics.elapsedMs / SOAK_DURATION_MS) * 100);

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Soak Test</Text>
        <Text style={styles.headerSub}>{totalMin}-min Vision Benchmark</Text>
      </View>

      <ScrollView contentContainerStyle={styles.scroll}>
        {/* Mode selector */}
        <View style={styles.modeRow}>
          {(['managed', 'raw'] as SoakMode[]).map((m) => (
            <TouchableOpacity
              key={m}
              style={[styles.modeBtn, mode === m && styles.modeBtnActive]}
              onPress={() => { if (soakState === 'idle' || soakState === 'stopped') setMode(m); }}
            >
              <Text style={[styles.modeBtnText, mode === m && styles.modeBtnTextActive]}>
                {m === 'managed' ? '🧠 Managed' : '⚡ Raw'}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
        <Text style={styles.modeDesc}>
          {mode === 'managed'
            ? 'Full supervision: Scheduler, Budget, Thermal, Battery, Latency tracking'
            : 'Bare inference: Fixed 2fps, 64×64, 100 tokens — no supervision'}
        </Text>

        {/* Status */}
        {statusMessage.length > 0 && (
          <View style={styles.statusBar}>
            {(soakState === 'downloading' || soakState === 'loading') && (
              <ActivityIndicator size="small" color={AppTheme.accent} style={{ marginRight: 8 }} />
            )}
            <Text style={styles.statusText}>{statusMessage}</Text>
          </View>
        )}

        {/* Download progress */}
        {soakState === 'downloading' && (
          <View style={styles.progressBarBg}>
            <View style={[styles.progressBarFill, { width: `${Math.max(2, downloadProgress * 100)}%` }]} />
          </View>
        )}

        {/* Elapsed + progress */}
        {soakState === 'running' && (
          <View style={styles.timerRow}>
            <Text style={styles.timerText}>{elapsedStr}</Text>
            <Text style={styles.timerMax}>/ {totalMin}:00</Text>
          </View>
        )}
        {soakState === 'running' && (
          <View style={styles.progressBarBg}>
            <View style={[styles.progressBarFill, { width: `${progressPct}%` }]} />
          </View>
        )}

        {/* Live metrics card */}
        {(soakState === 'running' || soakState === 'stopped') && (
          <View style={styles.metricsCard}>
            <Text style={styles.metricsTitle}>LIVE METRICS</Text>
            <View style={styles.metricsGrid}>
              <MetricCell label="Frames" value={String(metrics.framesProcessed)} />
              <MetricCell label="Avg Latency" value={`${metrics.avgLatencyMs}ms`} />
              <MetricCell label="Last" value={`${metrics.lastLatencyMs}ms`} />
              <MetricCell label="Tok/s" value={String(metrics.tokensPerSec)} />
              <MetricCell label="Dropped" value={String(metrics.droppedFrames)} />
              <MetricCell label="Thermal" value={metrics.thermalEmoji} />
              <MetricCell label="Battery" value={`${metrics.batteryPct}%`} />
              <MetricCell label="Memory" value={metrics.memoryMb > 0 ? `${metrics.memoryMb}MB` : '–'} />
            </View>
          </View>
        )}

        {/* Trace preview */}
        {traceLines.length > 0 && (
          <View style={styles.traceCard}>
            <View style={styles.traceHeader}>
              <Text style={styles.traceTitle}>TRACE ({traceLines.length} lines)</Text>
              <TouchableOpacity onPress={exportTrace}>
                <Text style={styles.exportBtn}>Copy JSONL</Text>
              </TouchableOpacity>
            </View>
            <ScrollView style={styles.traceScroll} nestedScrollEnabled>
              {traceLines.slice(-5).map((line, i) => (
                <Text key={i} style={styles.traceLine}>{line}</Text>
              ))}
            </ScrollView>
          </View>
        )}
      </ScrollView>

      {/* Action button */}
      <View style={styles.actionArea}>
        {soakState === 'idle' || soakState === 'stopped' ? (
          <TouchableOpacity style={styles.startBtn} onPress={start} activeOpacity={0.85}>
            <Text style={styles.startBtnText}>▶  Start Soak Test</Text>
          </TouchableOpacity>
        ) : soakState === 'running' ? (
          <TouchableOpacity style={[styles.startBtn, styles.stopBtn]} onPress={stop} activeOpacity={0.85}>
            <Text style={styles.startBtnText}>■  Stop</Text>
          </TouchableOpacity>
        ) : (
          <View style={[styles.startBtn, { opacity: 0.5 }]}>
            <ActivityIndicator size="small" color={AppTheme.background} />
          </View>
        )}
        {soakState === 'stopped' && (
          <TouchableOpacity style={styles.resetBtn} onPress={reset}>
            <Text style={styles.resetBtnText}>Reset</Text>
          </TouchableOpacity>
        )}
      </View>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function MetricCell({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metricCell}>
      <Text style={styles.metricValue}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: AppTheme.background },

  header: {
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 8,
  },
  headerTitle: { fontSize: 18, fontWeight: '700', color: AppTheme.textPrimary },
  headerSub: { fontSize: 12, color: AppTheme.textTertiary, marginTop: 2 },

  scroll: { padding: 16, paddingBottom: 32 },

  modeRow: {
    flexDirection: 'row',
    backgroundColor: AppTheme.surface,
    borderRadius: 12,
    padding: 4,
    gap: 4,
    marginBottom: 8,
  },
  modeBtn: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 10,
    alignItems: 'center',
  },
  modeBtnActive: { backgroundColor: AppTheme.accent },
  modeBtnText: { fontSize: 14, color: AppTheme.textSecondary, fontWeight: '600' },
  modeBtnTextActive: { color: AppTheme.background },

  modeDesc: {
    fontSize: 12,
    color: AppTheme.textTertiary,
    textAlign: 'center',
    marginBottom: 16,
    lineHeight: 18,
  },

  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: AppTheme.surface,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  statusText: { fontSize: 13, color: AppTheme.textSecondary, flex: 1 },

  progressBarBg: {
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.surfaceVariant,
    marginBottom: 16,
  },
  progressBarFill: {
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.accent,
  },

  timerRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'center',
    marginBottom: 8,
  },
  timerText: { fontSize: 36, fontWeight: '700', color: AppTheme.textPrimary, fontVariant: ['tabular-nums'] },
  timerMax: { fontSize: 14, color: AppTheme.textTertiary, marginLeft: 8 },

  metricsCard: {
    backgroundColor: AppTheme.surface,
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: AppTheme.border,
    marginBottom: 16,
  },
  metricsTitle: {
    fontSize: 11,
    fontWeight: '700',
    color: AppTheme.accent,
    letterSpacing: 1.5,
    marginBottom: 12,
  },
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  metricCell: {
    width: '25%',
    alignItems: 'center',
    paddingVertical: 10,
  },
  metricValue: { fontSize: 16, fontWeight: '700', color: AppTheme.textPrimary },
  metricLabel: { fontSize: 10, color: AppTheme.textTertiary, marginTop: 2 },

  traceCard: {
    backgroundColor: AppTheme.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: AppTheme.border,
    overflow: 'hidden',
    marginBottom: 16,
  },
  traceHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: AppTheme.border,
  },
  traceTitle: { fontSize: 11, fontWeight: '700', color: AppTheme.accent, letterSpacing: 1.5 },
  exportBtn: { fontSize: 13, color: AppTheme.accent, fontWeight: '600' },
  traceScroll: { maxHeight: 120 },
  traceLine: {
    fontFamily: 'monospace',
    fontSize: 10,
    color: AppTheme.textTertiary,
    paddingHorizontal: 14,
    paddingVertical: 2,
  },

  actionArea: {
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: AppTheme.border,
    gap: 10,
  },
  startBtn: {
    backgroundColor: AppTheme.accent,
    borderRadius: 28,
    paddingVertical: 16,
    alignItems: 'center',
  },
  stopBtn: { backgroundColor: AppTheme.danger },
  startBtnText: { fontSize: 16, fontWeight: '700', color: AppTheme.background },
  resetBtn: {
    alignSelf: 'center',
    paddingVertical: 10,
    paddingHorizontal: 24,
  },
  resetBtnText: { fontSize: 14, color: AppTheme.textSecondary },
});
