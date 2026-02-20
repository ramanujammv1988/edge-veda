import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Platform,
} from 'react-native';
import { AppTheme } from './theme';
import { ModelManager, ModelRegistry, ModelInfo } from 'edge-veda';

interface ModelSelectionSheetProps {
  onClose: () => void;
}

/**
 * Model selection bottom sheet matching Flutter's ModelSelectionSheet.
 *
 * Shows device status header, available models with download/select actions.
 */
export function ModelSelectionSheet({ onClose }: ModelSelectionSheetProps): React.JSX.Element {
  const models = [
    ModelRegistry.llama32_1b,
    ModelRegistry.smolvlm2_500m,
    ModelRegistry.smolvlm2_500m_mmproj,
  ];

  return (
    <View style={styles.container}>
      {/* Handle */}
      <View style={styles.handleRow}>
        <View style={styles.handle} />
      </View>

      {/* Title */}
      <View style={styles.titleRow}>
        <Text style={styles.title}>Models</Text>
        <TouchableOpacity onPress={onClose}>
          <Text style={styles.closeBtn}>✕</Text>
        </TouchableOpacity>
      </View>

      {/* Device status card */}
      <View style={styles.deviceCard}>
        <View style={styles.deviceIcon}>
          <Text style={{ fontSize: 20 }}>📱</Text>
        </View>
        <View style={{ marginLeft: 12 }}>
          <Text style={styles.deviceName}>{Platform.OS === 'ios' ? 'iPhone' : 'Android Device'}</Text>
          <Text style={styles.deviceMeta}>
            {Platform.OS} {Platform.Version} • {Platform.OS === 'ios' ? 'Metal GPU' : 'CPU'}
          </Text>
        </View>
      </View>

      {/* Section title */}
      <Text style={styles.sectionTitle}>AVAILABLE MODELS</Text>

      {/* Model cards */}
      {models.map((model) => (
        <SheetModelCard key={model.id} model={model} />
      ))}
    </View>
  );
}

function SheetModelCard({ model }: { model: ModelInfo }) {
  const [isDownloaded, setIsDownloaded] = useState<boolean | null>(null);
  const [isDownloading, setIsDownloading] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(0);

  useEffect(() => {
    (async () => {
      const mm = ModelManager.create();
      setIsDownloaded(await mm.isModelDownloaded(model.id));
    })();
  }, [model.id]);

  const icon = model.id.includes('mmproj')
    ? '🧩'
    : model.id.includes('vlm') || model.id.includes('smol')
    ? '👁️'
    : '🤖';

  const sizeMb = model.sizeBytes / (1024 * 1024);
  const sizeLabel = sizeMb >= 1024 ? `${(sizeMb / 1024).toFixed(1)} GB` : `${Math.round(sizeMb)} MB`;

  const handleDownload = async () => {
    setIsDownloading(true);
    try {
      const mm = ModelManager.create();
      await mm.downloadModel(model, (p: any) => {
        setDownloadProgress(p.progress);
      });
      setIsDownloaded(true);
    } catch {}
    setIsDownloading(false);
  };

  return (
    <View style={styles.modelCard}>
      {/* Icon */}
      <View style={styles.modelIconBox}>
        <Text style={{ fontSize: 20 }}>{icon}</Text>
      </View>

      {/* Info */}
      <View style={{ flex: 1, marginLeft: 12 }}>
        <Text style={styles.modelName}>{model.name}</Text>
        <View style={{ flexDirection: 'row', gap: 8, marginTop: 4 }}>
          <Text style={styles.modelMeta}>{sizeLabel}</Text>
          <Text style={styles.modelMetaDot}>•</Text>
          <Text style={styles.modelMeta}>{model.quantization}</Text>
        </View>
      </View>

      {/* Status */}
      {isDownloading ? (
        <View style={{ alignItems: 'center' }}>
          <ActivityIndicator size="small" color={AppTheme.accent} />
          <Text style={styles.dlPct}>{Math.round(downloadProgress * 100)}%</Text>
        </View>
      ) : isDownloaded === true ? (
        <View style={styles.statusCircleGreen}>
          <Text style={{ color: AppTheme.success, fontSize: 14 }}>✓</Text>
        </View>
      ) : isDownloaded === false ? (
        <TouchableOpacity style={styles.statusCircleTeal} onPress={handleDownload}>
          <Text style={{ color: AppTheme.accent, fontSize: 14 }}>↓</Text>
        </TouchableOpacity>
      ) : (
        <ActivityIndicator size="small" color={AppTheme.accent} />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingBottom: 40,
  },
  handleRow: {
    alignItems: 'center',
    paddingTop: 8,
    paddingBottom: 16,
  },
  handle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.textTertiary,
  },
  titleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    marginBottom: 16,
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    color: AppTheme.textPrimary,
  },
  closeBtn: {
    fontSize: 20,
    color: AppTheme.textSecondary,
    padding: 4,
  },

  deviceCard: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    padding: 16,
    backgroundColor: AppTheme.surfaceVariant,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  deviceIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: `${AppTheme.accent}26`,
    alignItems: 'center',
    justifyContent: 'center',
  },
  deviceName: { fontSize: 14, fontWeight: '600', color: AppTheme.textPrimary },
  deviceMeta: { fontSize: 12, color: AppTheme.textSecondary, marginTop: 2 },

  sectionTitle: {
    fontSize: 12,
    fontWeight: '600',
    color: AppTheme.textTertiary,
    letterSpacing: 1,
    marginLeft: 20,
    marginTop: 20,
    marginBottom: 8,
  },

  modelCard: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginBottom: 8,
    padding: 16,
    backgroundColor: AppTheme.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  modelIconBox: {
    width: 44,
    height: 44,
    borderRadius: 10,
    backgroundColor: AppTheme.surfaceVariant,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modelName: { fontSize: 14, fontWeight: '600', color: AppTheme.textPrimary },
  modelMeta: { fontSize: 12, color: AppTheme.textSecondary },
  modelMetaDot: { fontSize: 12, color: AppTheme.textTertiary },
  dlPct: { fontSize: 10, color: AppTheme.textSecondary, marginTop: 4 },

  statusCircleGreen: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: `${AppTheme.success}26`,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusCircleTeal: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: `${AppTheme.accent}26`,
    alignItems: 'center',
    justifyContent: 'center',
  },
});