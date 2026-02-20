import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Animated,
  Easing,
  Platform,
} from 'react-native';
import { AppTheme } from './theme';
import EdgeVeda, {
  ModelManager,
  ModelRegistry,
  WhisperSession,
  WhisperSegment,
} from 'edge-veda';

/**
 * Speech-to-Text screen using WhisperSession.
 *
 * Matches Flutter's stt_screen.dart:
 * - Circular mic button (teal = ready, pulsing red = recording)
 * - Scrollable transcript with segment text + timestamp badges
 * - Status bar showing current phase
 * - Processing time badge after each transcription
 */

type STTState =
  | 'downloading'
  | 'loading'
  | 'ready'
  | 'recording'
  | 'transcribing'
  | 'error';

interface TranscriptEntry {
  id: string;
  text: string;
  startMs: number;
  endMs: number;
  processingTimeMs: number;
}

export function STTScreen(): React.JSX.Element {
  const [sttState, setSttState] = useState<STTState>('downloading');
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [statusMessage, setStatusMessage] = useState('Checking for model…');
  const [transcript, setTranscript] = useState<TranscriptEntry[]>([]);
  const [lastProcessingMs, setLastProcessingMs] = useState<number | null>(null);

  const sessionRef = useRef<WhisperSession | null>(null);
  // Simulated audio buffer — in a real app, feed from react-native-audio-recorder-player
  const audioBufferRef = useRef<Float32Array | null>(null);
  const scrollRef = useRef<ScrollView>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const mm = ModelManager.create();
        const model = ModelRegistry.whisperTinyEn;

        const downloaded = await mm.isModelDownloaded(model.id);
        let modelPath: string;

        if (!downloaded) {
          setStatusMessage(`Downloading ${model.name}…`);
          modelPath = await mm.downloadModel(model, (p) => {
            setDownloadProgress(p.progress);
            setStatusMessage(`Downloading: ${p.progressPercent}%`);
          });
        } else {
          modelPath = (await mm.getModelPath(model.id))!;
        }

        if (cancelled) return;

        setSttState('loading');
        setStatusMessage('Loading Whisper model…');

        const session = EdgeVeda.createWhisperSession(modelPath);
        await session.initialize({ numThreads: 4 });
        sessionRef.current = session;

        setSttState('ready');
        setStatusMessage('Tap the mic to start recording');
      } catch (e: any) {
        setSttState('error');
        setStatusMessage(`Error: ${e.message}`);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  const handleMicPress = useCallback(async () => {
    if (sttState === 'ready') {
      // Start "recording" — in production, start audio capture here
      setSttState('recording');
      setStatusMessage('Recording… tap again to stop');
      // Simulate 2 seconds of audio capture for the demo
      audioBufferRef.current = _generateSilentPcm(16000 * 2);
    } else if (sttState === 'recording') {
      const pcm = audioBufferRef.current;
      if (!pcm || !sessionRef.current) {
        setSttState('ready');
        setStatusMessage('Tap the mic to start recording');
        return;
      }

      setSttState('transcribing');
      setStatusMessage('Transcribing…');

      try {
        const t0 = Date.now();
        const result = await sessionRef.current.transcribe(pcm, {
          language: 'en',
        });
        const processingTimeMs = Date.now() - t0;
        setLastProcessingMs(processingTimeMs);

        const entries: TranscriptEntry[] = result.segments.map((seg: WhisperSegment, i: number) => ({
          id: `${Date.now()}-${i}`,
          text: seg.text,
          startMs: seg.startMs,
          endMs: seg.endMs,
          processingTimeMs: i === 0 ? processingTimeMs : 0,
        }));

        // If no segments but there's fullText, add one entry
        if (entries.length === 0 && result.fullText) {
          entries.push({
            id: `${Date.now()}-0`,
            text: result.fullText,
            startMs: 0,
            endMs: 0,
            processingTimeMs,
          });
        }

        setTranscript((prev) => [...prev, ...entries]);
        setStatusMessage(`Done — ${processingTimeMs}ms`);

        setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
      } catch (e: any) {
        setStatusMessage(`Error: ${e.message}`);
      }

      setSttState('ready');
    }
  }, [sttState]);

  const clearTranscript = () => {
    setTranscript([]);
    setLastProcessingMs(null);
    setStatusMessage('Tap the mic to start recording');
  };

  const isActive = sttState === 'recording';
  const canRecord = sttState === 'ready' || sttState === 'recording';

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Speech-to-Text</Text>
        {transcript.length > 0 && (
          <TouchableOpacity onPress={clearTranscript} style={styles.headerBtn}>
            <Text style={styles.headerBtnText}>Clear</Text>
          </TouchableOpacity>
        )}
      </View>

      {/* Status bar */}
      <View style={styles.statusBar}>
        {(sttState === 'downloading' || sttState === 'loading' || sttState === 'transcribing') && (
          <ActivityIndicator size="small" color={AppTheme.accent} style={{ marginRight: 8 }} />
        )}
        <Text style={styles.statusText} numberOfLines={1}>{statusMessage}</Text>
        {lastProcessingMs != null && sttState === 'ready' && (
          <View style={styles.timeBadge}>
            <Text style={styles.timeBadgeText}>{lastProcessingMs}ms</Text>
          </View>
        )}
      </View>

      {/* Download progress bar */}
      {sttState === 'downloading' && (
        <View style={styles.progressBarBg}>
          <View style={[styles.progressBarFill, { width: `${Math.max(2, downloadProgress * 100)}%` }]} />
        </View>
      )}

      {/* Transcript list */}
      <ScrollView
        ref={scrollRef}
        style={styles.transcriptScroll}
        contentContainerStyle={styles.transcriptContent}
      >
        {transcript.length === 0 && sttState === 'ready' ? (
          <View style={styles.emptyState}>
            <Text style={styles.emptyIcon}>🎙️</Text>
            <Text style={styles.emptyTitle}>No transcript yet</Text>
            <Text style={styles.emptySub}>Press the mic and speak</Text>
          </View>
        ) : (
          transcript.map((entry) => (
            <View key={entry.id} style={styles.segmentCard}>
              <Text style={styles.segmentText}>{entry.text}</Text>
              {entry.endMs > 0 && (
                <View style={styles.segmentMeta}>
                  <View style={styles.timestampBadge}>
                    <Text style={styles.timestampText}>
                      {_msToTimestamp(entry.startMs)} – {_msToTimestamp(entry.endMs)}
                    </Text>
                  </View>
                  {entry.processingTimeMs > 0 && (
                    <View style={styles.processingBadge}>
                      <Text style={styles.processingText}>{entry.processingTimeMs}ms</Text>
                    </View>
                  )}
                </View>
              )}
            </View>
          ))
        )}
      </ScrollView>

      {/* Mic button */}
      <View style={styles.micArea}>
        {canRecord ? (
          <TouchableOpacity
            style={[styles.micButton, isActive && styles.micButtonActive]}
            onPress={handleMicPress}
            activeOpacity={0.8}
          >
            {isActive ? <PulsingRing /> : null}
            <Text style={styles.micIcon}>{isActive ? '⏹' : '🎙️'}</Text>
          </TouchableOpacity>
        ) : (
          <View style={[styles.micButton, styles.micButtonDisabled]}>
            <ActivityIndicator size="large" color={AppTheme.textSecondary} />
          </View>
        )}
        <Text style={styles.micHint}>
          {isActive ? 'Tap to stop & transcribe' : canRecord ? 'Tap to record' : ''}
        </Text>
      </View>
    </View>
  );
}

function PulsingRing(): React.JSX.Element {
  const scale = useRef(new Animated.Value(1)).current;
  const opacity = useRef(new Animated.Value(0.6)).current;

  useEffect(() => {
    const pulse = Animated.loop(
      Animated.parallel([
        Animated.sequence([
          Animated.timing(scale, { toValue: 1.4, duration: 900, easing: Easing.out(Easing.ease), useNativeDriver: true }),
          Animated.timing(scale, { toValue: 1, duration: 900, easing: Easing.in(Easing.ease), useNativeDriver: true }),
        ]),
        Animated.sequence([
          Animated.timing(opacity, { toValue: 0, duration: 900, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 0.6, duration: 900, useNativeDriver: true }),
        ]),
      ]),
    );
    pulse.start();
    return () => pulse.stop();
  }, [scale, opacity]);

  return (
    <Animated.View
      style={[styles.pulsingRing, { transform: [{ scale }], opacity }]}
    />
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function _msToTimestamp(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return `${min}:${sec.toString().padStart(2, '0')}`;
}

/** Generate silent 16kHz mono PCM samples (demo placeholder) */
function _generateSilentPcm(numSamples: number): Float32Array {
  return new Float32Array(numSamples);
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
  headerBtn: { padding: 8 },
  headerBtnText: { fontSize: 14, color: AppTheme.accent, fontWeight: '600' },

  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: AppTheme.surface,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: AppTheme.border,
  },
  statusText: { flex: 1, fontSize: 12, color: AppTheme.textSecondary },

  timeBadge: {
    backgroundColor: `${AppTheme.accent}33`,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: `${AppTheme.accent}66`,
  },
  timeBadgeText: { fontSize: 11, color: AppTheme.accent, fontWeight: '600' },

  progressBarBg: {
    height: 3,
    backgroundColor: AppTheme.surfaceVariant,
  },
  progressBarFill: {
    height: 3,
    backgroundColor: AppTheme.accent,
  },

  transcriptScroll: { flex: 1 },
  transcriptContent: { padding: 16, paddingBottom: 24 },

  emptyState: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingTop: 80 },
  emptyIcon: { fontSize: 48, marginBottom: 16 },
  emptyTitle: { fontSize: 16, color: AppTheme.textTertiary },
  emptySub: { fontSize: 13, color: AppTheme.textTertiary, marginTop: 8 },

  segmentCard: {
    backgroundColor: AppTheme.surface,
    borderRadius: 12,
    padding: 14,
    marginBottom: 10,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  segmentText: { fontSize: 15, color: AppTheme.textPrimary, lineHeight: 22 },
  segmentMeta: { flexDirection: 'row', alignItems: 'center', marginTop: 8, gap: 8 },

  timestampBadge: {
    backgroundColor: AppTheme.surfaceVariant,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 8,
  },
  timestampText: { fontSize: 11, color: AppTheme.textTertiary },

  processingBadge: {
    backgroundColor: `${AppTheme.success}22`,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 8,
  },
  processingText: { fontSize: 11, color: AppTheme.success },

  micArea: {
    alignItems: 'center',
    paddingVertical: 28,
    borderTopWidth: 1,
    borderTopColor: AppTheme.border,
  },
  micButton: {
    width: 88,
    height: 88,
    borderRadius: 44,
    backgroundColor: AppTheme.accentDim,
    alignItems: 'center',
    justifyContent: 'center',
  },
  micButtonActive: {
    backgroundColor: AppTheme.danger,
  },
  micButtonDisabled: {
    backgroundColor: AppTheme.surfaceVariant,
  },
  micIcon: { fontSize: 36 },
  micHint: {
    fontSize: 13,
    color: AppTheme.textTertiary,
    marginTop: 12,
  },

  pulsingRing: {
    position: 'absolute',
    width: 88,
    height: 88,
    borderRadius: 44,
    borderWidth: 2,
    borderColor: AppTheme.danger,
  },
});
