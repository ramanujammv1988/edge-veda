import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Switch,
} from 'react-native';
import { AppTheme } from './theme';
import EdgeVeda, {
  ModelManager,
  ModelRegistry,
  ChatSession,
  ChatTemplate,
  ToolRegistry,
  ToolDefinition,
  ToolCall,
  ToolResult,
  SystemPromptPreset,
} from 'edge-veda';

/**
 * Phone Detective — on-device behavioural insight using tool calling + LLM narration.
 *
 * Matches Flutter's detective_screen.dart:
 *
 * Phase 1: LLM calls tools (get_app_usage_stats, get_location_patterns, device_assert_offline)
 * Phase 2: Deterministic InsightEngine computes 6 ranked insights from tool data
 * Phase 3: ChatSession.sendStructured() generates a JSON detective report (Qwen3 0.6B)
 *
 * UI states: welcome → downloading → scanning (animated phases) → report
 */

type DetectiveState = 'welcome' | 'downloading' | 'scanning' | 'report' | 'error';

interface DetectiveReport {
  headline: string;
  deductions: string[];
  verdict: string;
}

interface ScanPhase {
  label: string;
  done: boolean;
  active: boolean;
}

// ---------------------------------------------------------------------------
// Mock data returned by tools (demo mode)
// ---------------------------------------------------------------------------

const MOCK_APP_USAGE = {
  topApps: ['Social Media', 'Productivity', 'News'],
  hourlyHistogram: [0, 0, 0, 0, 0, 1, 3, 8, 12, 10, 9, 11, 10, 9, 8, 10, 12, 14, 13, 10, 7, 5, 3, 1],
  weekdayTotal: 340,
  weekendTotal: 210,
};

const MOCK_LOCATION = {
  homeClusters: 2,
  officeClusters: 1,
  transitClusters: 3,
  avgDailyLocations: 4,
};

// ---------------------------------------------------------------------------
// InsightEngine — deterministic TS analysis
// ---------------------------------------------------------------------------

interface InsightData {
  appUsage: typeof MOCK_APP_USAGE;
  location: typeof MOCK_LOCATION;
}

function runInsightEngine(data: InsightData): string[] {
  const insights: string[] = [];
  const hourly = data.appUsage.hourlyHistogram;

  // Rule 1: Peak hours
  const peakHour = hourly.indexOf(Math.max(...hourly));
  const period = peakHour < 12 ? 'morning' : peakHour < 17 ? 'afternoon' : 'evening';
  insights.push(`Peak activity at ${peakHour}:00 — a ${period} person`);

  // Rule 2: Top app
  insights.push(`Most used category: ${data.appUsage.topApps[0]}`);

  // Rule 3: Location pattern
  const totalClusters = data.location.homeClusters + data.location.officeClusters + data.location.transitClusters;
  const label = totalClusters <= 3 ? 'home-based' : totalClusters <= 5 ? 'hybrid' : 'highly mobile';
  insights.push(`Lifestyle pattern: ${label} (${totalClusters} distinct location clusters)`);

  // Rule 4: Night owl vs early bird
  const nightActivity = (hourly[22] ?? 0) + (hourly[23] ?? 0) + (hourly[0] ?? 0);
  const morningActivity = (hourly[6] ?? 0) + (hourly[7] ?? 0) + (hourly[8] ?? 0);
  insights.push(nightActivity > morningActivity ? 'Night owl tendencies detected' : 'Early bird tendencies detected');

  // Rule 5: Weekday vs weekend
  const ratio = data.appUsage.weekdayTotal / Math.max(1, data.appUsage.weekendTotal);
  insights.push(ratio > 1.5 ? 'Significantly more active on weekdays' : 'Balanced weekday/weekend usage');

  // Rule 6: Surprising stat
  const avgHourly = hourly.reduce((a, b) => a + b, 0) / 24;
  insights.push(`Average ${Math.round(avgHourly * 60)} minutes of screen time per day`);

  return insights;
}

// ---------------------------------------------------------------------------
// Tool handlers
// ---------------------------------------------------------------------------

function handleToolCall(call: ToolCall): Record<string, unknown> {
  switch (call.name) {
    case 'get_app_usage_stats':
      return MOCK_APP_USAGE as unknown as Record<string, unknown>;
    case 'get_location_patterns':
      return MOCK_LOCATION as unknown as Record<string, unknown>;
    case 'device_assert_offline':
      return { offline: true, verifiedAt: new Date().toISOString() };
    default:
      return { error: `Unknown tool: ${call.name}` };
  }
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const TOOL_DEFINITIONS = [
  new ToolDefinition({
    name: 'get_app_usage_stats',
    description: 'Returns hourly app usage histogram and top app categories for the current user',
    parameters: {
      type: 'object',
      properties: {
        days: { type: 'number', description: 'Number of days to analyse (1-7)' },
      },
      required: [],
    },
  }),
  new ToolDefinition({
    name: 'get_location_patterns',
    description: 'Returns anonymised location cluster counts (home, office, transit)',
    parameters: {
      type: 'object',
      properties: {},
      required: [],
    },
  }),
  new ToolDefinition({
    name: 'device_assert_offline',
    description: 'Confirms that no data leaves the device during this analysis',
    parameters: {
      type: 'object',
      properties: {},
      required: [],
    },
  }),
];

const REPORT_SCHEMA = {
  type: 'object',
  properties: {
    headline: { type: 'string', description: 'One punchy detective headline (max 12 words)' },
    deductions: {
      type: 'array',
      items: { type: 'string' },
      minItems: 3,
      maxItems: 3,
      description: 'Exactly 3 deductions, each one sentence',
    },
    verdict: { type: 'string', description: 'One-sentence verdict on the subject' },
  },
  required: ['headline', 'deductions', 'verdict'],
};

// ---------------------------------------------------------------------------
// Screen component
// ---------------------------------------------------------------------------

export function DetectiveScreen(): React.JSX.Element {
  const [state, setState] = useState<DetectiveState>('welcome');
  const [demoMode, setDemoMode] = useState(true);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [statusMessage, setStatusMessage] = useState('');
  const [phases, setPhases] = useState<ScanPhase[]>([
    { label: 'Collecting data…', done: false, active: false },
    { label: 'Analysing patterns…', done: false, active: false },
    { label: 'Narrating findings…', done: false, active: false },
  ]);
  const [report, setReport] = useState<DetectiveReport | null>(null);
  const [errorMessage, setErrorMessage] = useState('');

  const edgeVedaRef = useRef<typeof EdgeVeda | null>(null);

  const setPhaseActive = (index: number) => {
    setPhases((prev) =>
      prev.map((p, i) => ({
        ...p,
        active: i === index,
        done: i < index,
      })),
    );
  };

  const setPhasesDone = () => {
    setPhases((prev) => prev.map((p) => ({ ...p, active: false, done: true })));
  };

  const runDetective = async () => {
    setState('scanning');

    try {
      // Phase 0: Download + init model
      const mm = ModelManager.create();
      const model = ModelRegistry.qwen3_06b;

      const downloaded = await mm.isModelDownloaded(model.id);
      let modelPath: string;

      if (!downloaded) {
        setState('downloading');
        setStatusMessage(`Downloading ${model.name}…`);
        modelPath = await mm.downloadModel(model, (p) => {
          setDownloadProgress(p.progress);
          setStatusMessage(`Downloading: ${p.progressPercent}%`);
        });
        setState('scanning');
      } else {
        modelPath = (await mm.getModelPath(model.id))!;
      }

      setStatusMessage('Loading model…');
      const ev = EdgeVeda.create();
      await ev.init(modelPath, {
        backend: 'auto',
        numThreads: 4,
        contextSize: 2048,
      });
      edgeVedaRef.current = ev as unknown as typeof EdgeVeda;

      // Phase 1: Tool calling to collect data
      setPhaseActive(0);
      setStatusMessage('Calling on-device tools…');

      const registry = new ToolRegistry(TOOL_DEFINITIONS);
      const session = new ChatSession(ev as unknown as any, {
        systemPrompt: SystemPromptPreset.ASSISTANT,
        template: ChatTemplate.QWEN3,
        tools: registry,
        maxContextLength: 2048,
      });

      const collectedData: { appUsage?: typeof MOCK_APP_USAGE; location?: typeof MOCK_LOCATION } = {};

      await session.sendWithTools(
        '/nothink Analyse the user\'s device usage patterns. Call all available tools to collect data, then summarise what you found.',
        async (call: ToolCall) => {
          const result = handleToolCall(call);
          if (call.name === 'get_app_usage_stats') {
            collectedData.appUsage = result as unknown as typeof MOCK_APP_USAGE;
          } else if (call.name === 'get_location_patterns') {
            collectedData.location = result as unknown as typeof MOCK_LOCATION;
          }
          return ToolResult.success(call.id, result);
        },
        { maxTokens: 256, temperature: 0.1 },
      );

      // Phase 2: InsightEngine
      setPhaseActive(1);
      setStatusMessage('Running InsightEngine…');

      const appData = collectedData.appUsage ?? MOCK_APP_USAGE;
      const locData = collectedData.location ?? MOCK_LOCATION;
      const insights = runInsightEngine({ appUsage: appData, location: locData });
      await _sleep(600); // slight pause for UX

      // Phase 3: LLM narration
      setPhaseActive(2);
      setStatusMessage('Narrating detective report…');

      const narrationPrompt =
        `/nothink You are a noir detective. Based on these insights:\n` +
        insights.map((s, i) => `${i + 1}. ${s}`).join('\n') +
        `\n\nWrite a concise detective report in JSON format.`;

      const rawReport = await session.sendStructured(narrationPrompt, REPORT_SCHEMA, {
        maxTokens: 256,
        temperature: 0.4,
      });

      setPhasesDone();

      setReport({
        headline: String(rawReport.headline ?? 'Curious subject identified'),
        deductions: Array.isArray(rawReport.deductions)
          ? (rawReport.deductions as string[]).slice(0, 3)
          : insights.slice(0, 3),
        verdict: String(rawReport.verdict ?? 'The evidence speaks for itself.'),
      });

      setState('report');
    } catch (e: any) {
      setErrorMessage(e.message ?? 'Unknown error');
      setState('error');
    }
  };

  const reset = () => {
    setState('welcome');
    setReport(null);
    setErrorMessage('');
    setPhases([
      { label: 'Collecting data…', done: false, active: false },
      { label: 'Analysing patterns…', done: false, active: false },
      { label: 'Narrating findings…', done: false, active: false },
    ]);
    edgeVedaRef.current = null;
  };

  // ---- Render ----

  if (state === 'welcome' || state === 'error') {
    return (
      <View style={styles.container}>
        <Header title="Phone Detective" onBack={undefined} />
        <View style={styles.centerContent}>
          <Text style={styles.detectiveIcon}>🕵️</Text>
          <Text style={styles.welcomeTitle}>Analyse Your Habits</Text>
          <Text style={styles.welcomeSub}>
            An on-device AI detective will analyse your usage patterns.
            {'\n'}No data ever leaves your device.
          </Text>

          {state === 'error' && (
            <View style={styles.errorCard}>
              <Text style={styles.errorText}>{errorMessage}</Text>
            </View>
          )}

          <View style={styles.demoRow}>
            <Text style={styles.demoLabel}>Demo mode (mock data)</Text>
            <Switch
              value={demoMode}
              onValueChange={setDemoMode}
              trackColor={{ true: AppTheme.accent, false: AppTheme.surfaceVariant }}
              thumbColor={AppTheme.textPrimary}
            />
          </View>

          <TouchableOpacity style={styles.startBtn} onPress={runDetective} activeOpacity={0.85}>
            <Text style={styles.startBtnText}>Start Investigation</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  if (state === 'downloading') {
    return (
      <View style={styles.container}>
        <Header title="Phone Detective" onBack={undefined} />
        <View style={styles.centerContent}>
          <ActivityIndicator size="large" color={AppTheme.accent} />
          <Text style={styles.downloadLabel}>{statusMessage}</Text>
          <View style={styles.progressBarBg}>
            <View style={[styles.progressBarFill, { width: `${Math.max(2, downloadProgress * 100)}%` }]} />
          </View>
        </View>
      </View>
    );
  }

  if (state === 'scanning') {
    return (
      <View style={styles.container}>
        <Header title="Phone Detective" onBack={undefined} />
        <View style={styles.centerContent}>
          <Text style={styles.detectiveIcon}>🔍</Text>
          <Text style={styles.scanningTitle}>Investigating…</Text>
          <Text style={styles.scanningStatus}>{statusMessage}</Text>
          <View style={styles.phaseTimeline}>
            {phases.map((phase, i) => (
              <View key={i} style={styles.phaseRow}>
                <View style={[
                  styles.phaseIndicator,
                  phase.done && styles.phaseIndicatorDone,
                  phase.active && styles.phaseIndicatorActive,
                ]}>
                  {phase.active ? (
                    <ActivityIndicator size="small" color={AppTheme.accent} />
                  ) : phase.done ? (
                    <Text style={styles.phaseCheck}>✓</Text>
                  ) : (
                    <View style={styles.phaseDot} />
                  )}
                </View>
                {i < phases.length - 1 && (
                  <View style={[styles.phaseConnector, phase.done && styles.phaseConnectorDone]} />
                )}
                <Text style={[
                  styles.phaseLabel,
                  phase.active && styles.phaseLabelActive,
                  phase.done && styles.phaseLabelDone,
                ]}>
                  {phase.label}
                </Text>
              </View>
            ))}
          </View>
        </View>
      </View>
    );
  }

  if (state === 'report' && report) {
    return (
      <View style={styles.container}>
        <Header title="Phone Detective" onBack={reset} />
        <ScrollView contentContainerStyle={styles.reportScroll}>
          <View style={styles.reportCard}>
            <Text style={styles.reportBadge}>CASE FILE</Text>
            <Text style={styles.reportHeadline}>{report.headline}</Text>

            <View style={styles.divider} />

            <Text style={styles.reportSectionTitle}>DEDUCTIONS</Text>
            {report.deductions.map((d, i) => (
              <View key={i} style={styles.deductionRow}>
                <Text style={styles.deductionNumber}>{i + 1}</Text>
                <Text style={styles.deductionText}>{d}</Text>
              </View>
            ))}

            <View style={styles.divider} />

            <Text style={styles.reportSectionTitle}>VERDICT</Text>
            <Text style={styles.verdictText}>{report.verdict}</Text>

            <View style={styles.privacyRow}>
              <Text style={styles.privacyIcon}>🛡️</Text>
              <Text style={styles.privacyText}>All analysis ran on-device. No data was shared.</Text>
            </View>
          </View>

          <TouchableOpacity style={styles.newInvestigationBtn} onPress={reset}>
            <Text style={styles.newInvestigationText}>New Investigation</Text>
          </TouchableOpacity>
        </ScrollView>
      </View>
    );
  }

  return <View style={styles.container} />;
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function Header({ title, onBack }: { title: string; onBack?: () => void }) {
  return (
    <View style={styles.header}>
      {onBack ? (
        <TouchableOpacity onPress={onBack} style={styles.backBtn}>
          <Text style={styles.backBtnText}>← Back</Text>
        </TouchableOpacity>
      ) : (
        <View style={styles.backBtn} />
      )}
      <Text style={styles.headerTitle}>{title}</Text>
      <View style={styles.backBtn} />
    </View>
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function _sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: AppTheme.background },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  headerTitle: { fontSize: 18, fontWeight: '700', color: AppTheme.textPrimary },
  backBtn: { minWidth: 60 },
  backBtnText: { fontSize: 14, color: AppTheme.accent },

  centerContent: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
  },

  detectiveIcon: { fontSize: 64, marginBottom: 24 },

  welcomeTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: AppTheme.textPrimary,
    textAlign: 'center',
    marginBottom: 12,
  },
  welcomeSub: {
    fontSize: 14,
    color: AppTheme.textSecondary,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 32,
  },

  errorCard: {
    backgroundColor: `${AppTheme.danger}22`,
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: `${AppTheme.danger}44`,
    marginBottom: 24,
    width: '100%',
  },
  errorText: { fontSize: 13, color: AppTheme.danger, textAlign: 'center' },

  demoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 28,
    gap: 12,
  },
  demoLabel: { fontSize: 14, color: AppTheme.textSecondary },

  startBtn: {
    backgroundColor: AppTheme.accent,
    paddingHorizontal: 40,
    paddingVertical: 16,
    borderRadius: 28,
  },
  startBtnText: { fontSize: 16, fontWeight: '700', color: AppTheme.background },

  downloadLabel: {
    fontSize: 14,
    color: AppTheme.textSecondary,
    marginTop: 20,
    marginBottom: 16,
    textAlign: 'center',
  },
  progressBarBg: {
    width: 240,
    height: 6,
    borderRadius: 3,
    backgroundColor: AppTheme.surfaceVariant,
  },
  progressBarFill: {
    height: 6,
    borderRadius: 3,
    backgroundColor: AppTheme.accent,
  },

  scanningTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: AppTheme.textPrimary,
    marginTop: 20,
    marginBottom: 8,
  },
  scanningStatus: {
    fontSize: 13,
    color: AppTheme.textSecondary,
    marginBottom: 36,
    textAlign: 'center',
  },

  phaseTimeline: { width: '100%', gap: 0 },
  phaseRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 0,
  },
  phaseIndicator: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: AppTheme.surfaceVariant,
    borderWidth: 1,
    borderColor: AppTheme.border,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
    flexShrink: 0,
  },
  phaseIndicatorDone: {
    backgroundColor: `${AppTheme.success}33`,
    borderColor: AppTheme.success,
  },
  phaseIndicatorActive: {
    backgroundColor: `${AppTheme.accent}22`,
    borderColor: AppTheme.accent,
  },
  phaseConnector: {
    position: 'absolute',
    left: 15,
    top: 32,
    width: 2,
    height: 24,
    backgroundColor: AppTheme.border,
  },
  phaseConnectorDone: { backgroundColor: AppTheme.success },
  phaseDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: AppTheme.textTertiary },
  phaseCheck: { fontSize: 14, color: AppTheme.success },
  phaseLabel: {
    fontSize: 14,
    color: AppTheme.textTertiary,
    paddingTop: 6,
    paddingBottom: 20,
  },
  phaseLabelActive: { color: AppTheme.textPrimary, fontWeight: '600' },
  phaseLabelDone: { color: AppTheme.textSecondary },

  reportScroll: { padding: 16, paddingBottom: 40 },
  reportCard: {
    backgroundColor: AppTheme.surface,
    borderRadius: 20,
    padding: 24,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  reportBadge: {
    fontSize: 11,
    fontWeight: '700',
    color: AppTheme.accent,
    letterSpacing: 2,
    marginBottom: 12,
  },
  reportHeadline: {
    fontSize: 22,
    fontWeight: '800',
    color: AppTheme.textPrimary,
    lineHeight: 30,
    marginBottom: 16,
  },
  divider: {
    height: 1,
    backgroundColor: AppTheme.border,
    marginVertical: 16,
  },
  reportSectionTitle: {
    fontSize: 11,
    fontWeight: '700',
    color: AppTheme.accent,
    letterSpacing: 1.5,
    marginBottom: 12,
  },
  deductionRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 12,
  },
  deductionNumber: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: `${AppTheme.accent}33`,
    textAlign: 'center',
    lineHeight: 24,
    fontSize: 12,
    fontWeight: '700',
    color: AppTheme.accent,
    marginRight: 12,
    flexShrink: 0,
  },
  deductionText: {
    flex: 1,
    fontSize: 14,
    color: AppTheme.textPrimary,
    lineHeight: 22,
  },
  verdictText: {
    fontSize: 15,
    color: AppTheme.textPrimary,
    fontStyle: 'italic',
    lineHeight: 24,
  },
  privacyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 24,
    backgroundColor: `${AppTheme.success}11`,
    borderRadius: 10,
    padding: 12,
  },
  privacyIcon: { fontSize: 16, marginRight: 8 },
  privacyText: { fontSize: 12, color: AppTheme.success, flex: 1 },

  newInvestigationBtn: {
    marginTop: 20,
    alignSelf: 'center',
    paddingHorizontal: 28,
    paddingVertical: 14,
    borderRadius: 24,
    borderWidth: 1,
    borderColor: AppTheme.accent,
  },
  newInvestigationText: { fontSize: 15, color: AppTheme.accent, fontWeight: '600' },
});
