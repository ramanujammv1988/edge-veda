import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  FlatList,
  StyleSheet,
  ActivityIndicator,
  Modal,
} from 'react-native';
import { AppTheme } from './theme';
import EdgeVeda, {
  ChatSession,
  ChatMessage,
  ChatRole,
  SystemPromptPreset,
  ModelRegistry,
  ModelManager,
} from 'edge-veda';
import { ModelSelectionSheet } from './ModelSelectionSheet';

/**
 * Chat screen matching Flutter's ChatScreen exactly.
 *
 * Features: ChatSession streaming, persona chips, metrics bar,
 * context indicator, message bubbles with avatars, benchmark mode.
 */
export function ChatScreen(): React.JSX.Element {
  const [isInitialized, setIsInitialized] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isStreaming, setIsStreaming] = useState(false);
  const [isDownloading, setIsDownloading] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [statusMessage, setStatusMessage] = useState('Ready to initialize');
  const [promptText, setPromptText] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [streamingText, setStreamingText] = useState('');
  const [selectedPreset, setSelectedPreset] = useState(SystemPromptPreset.ASSISTANT);
  const [showModelSheet, setShowModelSheet] = useState(false);
  const [modelPath, setModelPath] = useState<string | null>(null);

  // Metrics
  const [ttft, setTtft] = useState<number | null>(null);
  const [speed, setSpeed] = useState<number | null>(null);
  const [memory, setMemory] = useState<number | null>(null);
  const [turnCount, setTurnCount] = useState(0);
  const [contextUsage, setContextUsage] = useState(0);

  const edgeVedaRef = useRef<EdgeVeda | null>(null);
  const sessionRef = useRef<ChatSession | null>(null);
  const flatListRef = useRef<FlatList>(null);

  // Auto-download model on mount
  useEffect(() => {
    checkAndDownloadModel();
    return () => {
      edgeVedaRef.current?.close();
    };
  }, []);

  const checkAndDownloadModel = async () => {
    setIsDownloading(true);
    setStatusMessage('Checking for model...');
    try {
      const model = ModelRegistry.llama32_1b;
      const mm = ModelManager.create();
      const downloaded = await mm.isModelDownloaded(model.id);
      let path: string;
      if (!downloaded) {
        setStatusMessage(`Downloading model (${model.name})...`);
        path = await mm.downloadModel(model, (progress) => {
          setDownloadProgress(progress.progress);
          setStatusMessage(`Downloading: ${progress.progressPercent}%`);
        });
      } else {
        path = (await mm.getModelPath(model.id))!;
      }
      setModelPath(path);
      setIsDownloading(false);
      setStatusMessage('Model ready. Tap "Initialize" to start.');
    } catch (e: any) {
      setIsDownloading(false);
      setStatusMessage(`Error: ${e.message}`);
    }
  };

  const initialize = async () => {
    if (!modelPath) return;
    setIsLoading(true);
    setStatusMessage('Initializing Veda...');
    try {
      const ev = EdgeVeda.create();
      await ev.init(modelPath, { backend: 'auto', numThreads: 4, contextSize: 2048 });
      edgeVedaRef.current = ev;
      sessionRef.current = new ChatSession(ev, selectedPreset);
      setIsInitialized(true);
      setIsLoading(false);
      setStatusMessage('Ready to chat!');
    } catch (e: any) {
      setIsLoading(false);
      setStatusMessage('Initialization failed');
    }
  };

  const sendMessage = async () => {
    const prompt = promptText.trim();
    if (!prompt || !isInitialized || isStreaming) return;
    setPromptText('');
    setIsStreaming(true);
    setIsLoading(true);
    setStreamingText('');
    setTtft(null);
    setSpeed(null);

    const start = Date.now();
    let receivedFirst = false;
    let tokenCount = 0;
    let accumulated = '';

    try {
      const session = sessionRef.current!;
      setStatusMessage('Streaming...');

      await session.sendStream(
        prompt,
        (token: string) => {
          if (!receivedFirst) {
            setTtft(Date.now() - start);
            receivedFirst = true;
          }
          accumulated += token;
          tokenCount++;
          setStreamingText(accumulated);
          if (tokenCount % 3 === 0) {
            setStatusMessage(`Streaming... (${tokenCount} tokens)`);
          }
        },
        { maxTokens: 256, temperature: 0.7, topP: 0.9 },
      );

      const elapsed = (Date.now() - start) / 1000;
      const tps = tokenCount > 0 ? tokenCount / elapsed : 0;
      setSpeed(tps);
      setStatusMessage(`Complete (${tokenCount} tokens, ${tps.toFixed(1)} tok/s)`);

      setMessages([...session.messages]);
      setTurnCount(session.turnCount);
      setContextUsage(session.contextUsage);
      setMemory(edgeVedaRef.current?.memoryUsage ?? null);
      setStreamingText('');
    } catch (e: any) {
      setStatusMessage('Stream error');
      setStreamingText('');
    }

    setIsStreaming(false);
    setIsLoading(false);
  };

  const cancelGeneration = () => {
    edgeVedaRef.current?.cancelGeneration();
    setIsStreaming(false);
    setIsLoading(false);
    setStatusMessage('Cancelled');
  };

  const resetChat = () => {
    sessionRef.current?.reset();
    setMessages([]);
    setStreamingText('');
    setTtft(null);
    setSpeed(null);
    setMemory(null);
    setTurnCount(0);
    setContextUsage(0);
    setStatusMessage('Ready to chat!');
  };

  const changePreset = (preset: SystemPromptPreset) => {
    if (preset === selectedPreset && sessionRef.current) return;
    setSelectedPreset(preset);
    if (isInitialized && edgeVedaRef.current) {
      sessionRef.current = new ChatSession(edgeVedaRef.current, preset);
      setMessages([]);
      setStreamingText('');
      setStatusMessage('Ready to chat!');
    }
  };

  const ttftText = ttft != null ? `${ttft}ms` : '-';
  const speedText = speed != null ? `${speed.toFixed(1)} tok/s` : '-';
  const memoryText = memory != null ? `${Math.round(memory / (1024 * 1024))} MB` : '-';

  const displayMessages: ChatMessage[] = [
    ...messages,
    ...(isStreaming && streamingText ? [{ role: ChatRole.ASSISTANT, content: streamingText }] : []),
  ];

  const renderMessage = ({ item }: { item: ChatMessage }) => {
    if (item.role === ChatRole.SYSTEM || item.role === ChatRole.SUMMARY) {
      return (
        <View style={styles.systemRow}>
          <Text style={styles.systemText}>
            {item.role === ChatRole.SUMMARY ? `[Context summary] ${item.content}` : item.content}
          </Text>
        </View>
      );
    }

    const isUser = item.role === ChatRole.USER;
    return (
      <View style={[styles.bubbleRow, isUser ? styles.bubbleRowUser : styles.bubbleRowAssistant]}>
        {!isUser && (
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>✨</Text>
          </View>
        )}
        <View
          style={[
            styles.bubble,
            isUser ? styles.userBubble : styles.assistantBubble,
          ]}
        >
          <Text style={styles.bubbleText}>{item.content}</Text>
        </View>
        {isUser && (
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>👤</Text>
          </View>
        )}
      </View>
    );
  };

  return (
    <View style={styles.container}>
      {/* Top bar */}
      <View style={styles.topBar}>
        <Text style={styles.topTitle}>Veda</Text>
        <View style={styles.topActions}>
          {isInitialized && (
            <TouchableOpacity onPress={resetChat} style={styles.iconBtn}>
              <Text style={styles.iconText}>🔄</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity onPress={() => setShowModelSheet(true)} style={styles.iconBtn}>
            <Text style={styles.iconText}>📦</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Status bar */}
      <View style={styles.statusBar}>
        {(isDownloading || isLoading) && (
          <ActivityIndicator size="small" color={AppTheme.accent} style={{ marginRight: 8 }} />
        )}
        <Text
          style={[styles.statusText, { color: isInitialized ? AppTheme.success : AppTheme.warning }]}
          numberOfLines={1}
        >
          {statusMessage}
        </Text>
        {!isInitialized && !isLoading && !isDownloading && modelPath && (
          <TouchableOpacity style={styles.initButton} onPress={initialize}>
            <Text style={styles.initButtonText}>Initialize</Text>
          </TouchableOpacity>
        )}
      </View>

      {/* Metrics bar */}
      {isInitialized && (
        <View style={styles.metricsBar}>
          <MetricChip label="TTFT" value={ttftText} />
          <MetricChip label="Speed" value={speedText} />
          <MetricChip label="Memory" value={memoryText} />
        </View>
      )}

      {/* Persona picker or context indicator */}
      {isInitialized && messages.length === 0 && !isStreaming ? (
        <View style={styles.personaRow}>
          <Text style={styles.personaLabel}>Choose a persona</Text>
          <View style={styles.personaChips}>
            {([
              { label: 'Assistant', preset: SystemPromptPreset.ASSISTANT },
              { label: 'Coder', preset: SystemPromptPreset.CODER },
              { label: 'Creative', preset: SystemPromptPreset.CREATIVE },
            ] as const).map(({ label, preset }) => {
              const isSelected = preset === selectedPreset;
              return (
                <TouchableOpacity
                  key={label}
                  style={[styles.chip, isSelected && styles.chipActive]}
                  onPress={() => changePreset(preset)}
                >
                  <Text style={[styles.chipText, isSelected && styles.chipTextActive]}>
                    {label}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>
        </View>
      ) : isInitialized ? (
        <View style={styles.contextRow}>
          <Text style={styles.contextText}>
            {turnCount} {turnCount === 1 ? 'turn' : 'turns'}
          </Text>
          <View style={styles.contextBarBg}>
            <View
              style={[
                styles.contextBarFill,
                {
                  width: `${Math.min(100, contextUsage * 100)}%`,
                  backgroundColor: contextUsage > 0.8 ? AppTheme.warning : AppTheme.accent,
                },
              ]}
            />
          </View>
          <Text style={[styles.contextPct, contextUsage > 0.8 && { color: AppTheme.warning }]}>
            {Math.round(contextUsage * 100)}%
          </Text>
        </View>
      ) : null}

      {/* Messages */}
      <View style={styles.messageArea}>
        {displayMessages.length === 0 ? (
          <View style={styles.emptyState}>
            <Text style={styles.emptyIcon}>💭</Text>
            <Text style={styles.emptyTitle}>Start a conversation</Text>
            <Text style={styles.emptySub}>Ask anything. It runs on your device.</Text>
          </View>
        ) : (
          <FlatList
            ref={flatListRef}
            data={displayMessages}
            renderItem={renderMessage}
            keyExtractor={(_, i) => String(i)}
            contentContainerStyle={{ padding: 16 }}
            ItemSeparatorComponent={() => <View style={{ height: 12 }} />}
            onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: true })}
          />
        )}
      </View>

      {/* Input bar */}
      <View style={styles.inputBar}>
        <TextInput
          style={styles.input}
          value={promptText}
          onChangeText={setPromptText}
          placeholder="Message..."
          placeholderTextColor={AppTheme.textTertiary}
          editable={isInitialized && !isLoading && !isStreaming}
          multiline
          maxLength={2000}
        />
        <TouchableOpacity
          style={[styles.sendBtn, isStreaming && { backgroundColor: AppTheme.danger }]}
          onPress={isStreaming ? cancelGeneration : sendMessage}
          disabled={!isStreaming && (!isInitialized || isLoading)}
        >
          <Text style={styles.sendBtnText}>{isStreaming ? '■' : '↑'}</Text>
        </TouchableOpacity>
      </View>

      {/* Model sheet modal */}
      <Modal visible={showModelSheet} animationType="slide" transparent>
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <ModelSelectionSheet onClose={() => setShowModelSheet(false)} />
          </View>
        </View>
      </Modal>
    </View>
  );
}

function MetricChip({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metricChip}>
      <Text style={styles.metricLabel}>{label}</Text>
      <Text style={styles.metricValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: AppTheme.background },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  topTitle: { fontSize: 18, fontWeight: '700', color: AppTheme.textPrimary },
  topActions: { flexDirection: 'row', gap: 4 },
  iconBtn: { padding: 8 },
  iconText: { fontSize: 18 },

  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: AppTheme.surface,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: AppTheme.border,
  },
  statusText: { flex: 1, fontSize: 12 },
  initButton: {
    backgroundColor: AppTheme.accent,
    paddingHorizontal: 16,
    paddingVertical: 6,
    borderRadius: 16,
  },
  initButtonText: { color: AppTheme.background, fontSize: 14, fontWeight: '600' },

  metricsBar: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    backgroundColor: AppTheme.surface,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: AppTheme.border,
  },
  metricChip: { alignItems: 'center' },
  metricLabel: { fontSize: 10, color: AppTheme.textTertiary, fontWeight: '500' },
  metricValue: { fontSize: 14, fontWeight: '700', color: AppTheme.textPrimary, marginTop: 2 },

  personaRow: {
    backgroundColor: AppTheme.surface,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: AppTheme.border,
  },
  personaLabel: { fontSize: 12, color: AppTheme.textTertiary, fontWeight: '500', marginBottom: 8 },
  personaChips: { flexDirection: 'row', gap: 8 },
  chip: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: AppTheme.surfaceVariant,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  chipActive: {
    backgroundColor: `${AppTheme.accent}33`,
    borderColor: AppTheme.accent,
  },
  chipText: { fontSize: 13, color: AppTheme.textSecondary },
  chipTextActive: { color: AppTheme.accent },

  contextRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: AppTheme.surface,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: AppTheme.border,
  },
  contextText: { fontSize: 12, color: AppTheme.textSecondary, fontWeight: '500' },
  contextBarBg: {
    flex: 1,
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.surfaceVariant,
    marginHorizontal: 8,
  },
  contextBarFill: { height: 4, borderRadius: 2 },
  contextPct: { fontSize: 11, color: AppTheme.textTertiary, fontWeight: '500' },

  messageArea: { flex: 1 },
  emptyState: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyIcon: { fontSize: 48, marginBottom: 16 },
  emptyTitle: { fontSize: 16, color: AppTheme.textTertiary },
  emptySub: { fontSize: 13, color: AppTheme.textTertiary, marginTop: 8 },

  systemRow: { alignItems: 'center', paddingVertical: 4 },
  systemText: {
    fontSize: 12,
    color: AppTheme.textSecondary,
    backgroundColor: AppTheme.surfaceVariant,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 12,
    overflow: 'hidden',
  },
  bubbleRow: { flexDirection: 'row', alignItems: 'flex-end' },
  bubbleRowUser: { justifyContent: 'flex-end' },
  bubbleRowAssistant: { justifyContent: 'flex-start' },
  avatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: AppTheme.surfaceVariant,
    alignItems: 'center',
    justifyContent: 'center',
    marginHorizontal: 8,
  },
  avatarText: { fontSize: 14 },
  bubble: { maxWidth: 280, borderRadius: 20, paddingHorizontal: 16, paddingVertical: 12 },
  userBubble: { backgroundColor: AppTheme.userBubble },
  assistantBubble: {
    backgroundColor: AppTheme.assistantBubble,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  bubbleText: { color: AppTheme.textPrimary, lineHeight: 22 },

  inputBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: AppTheme.background,
    borderTopWidth: 1,
    borderTopColor: AppTheme.border,
  },
  input: {
    flex: 1,
    backgroundColor: AppTheme.surfaceVariant,
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 10,
    color: AppTheme.textPrimary,
    fontSize: 15,
    maxHeight: 100,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  sendBtn: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: AppTheme.accent,
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: 8,
  },
  sendBtnText: { fontSize: 20, color: AppTheme.background, fontWeight: '700' },

  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: AppTheme.surface,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    maxHeight: '80%',
  },
});