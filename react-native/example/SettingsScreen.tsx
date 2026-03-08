import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  Platform,
  TouchableOpacity,
  ActivityIndicator,
} from 'react-native';
import { AppTheme } from './theme';
import { ModelManager, ModelRegistry, ModelInfo } from 'edge-veda';

export interface SettingsScreenProps {
  onNavigate?: (screen: 'detective' | 'soaktest') => void;
}

/**
 * Settings screen matching Flutter's SettingsScreen.
 *
 * Sections: Device Status, Generation (sliders), Storage, Models, About.
 */
export function SettingsScreen({ onNavigate }: SettingsScreenProps = {}): React.JSX.Element {
  const [temperature, setTemperature] = useState(0.7);
  const [maxTokens, setMaxTokens] = useState(256);

  return (
    <View style={styles.container}>
      <Text style={styles.header}>Settings</Text>

      <ScrollView style={styles.scroll} contentContainerStyle={{ paddingBottom: 40 }}>
        {/* Device Status */}
        <SectionTitle title="DEVICE STATUS" />
        <Card>
          <InfoRow icon="📱" label="Platform" value={Platform.OS === 'ios' ? 'iOS' : 'Android'} />
          <Divider />
          <InfoRow icon="🧠" label="OS Version" value={String(Platform.Version)} />
          <Divider />
          <InfoRow icon="⚡" label="Backend" value={Platform.OS === 'ios' ? 'Metal GPU' : 'CPU'} />
        </Card>

        {/* Generation */}
        <SectionTitle title="GENERATION" />
        <Card>
          <View style={styles.sliderRow}>
            <Text style={styles.sliderIcon}>🌡️</Text>
            <Text style={styles.sliderLabel}>Temperature</Text>
            <Text style={styles.sliderValue}>{temperature.toFixed(1)}</Text>
          </View>
          <SliderBar
            value={temperature}
            min={0}
            max={2}
            onChange={setTemperature}
          />
          <View style={styles.sliderHints}>
            <Text style={styles.hintText}>Precise</Text>
            <Text style={styles.hintText}>Creative</Text>
          </View>
          <Divider />
          <View style={styles.sliderRow}>
            <Text style={styles.sliderIcon}>📝</Text>
            <Text style={styles.sliderLabel}>Max Tokens</Text>
            <Text style={styles.sliderValue}>{maxTokens}</Text>
          </View>
          <SliderBar
            value={maxTokens}
            min={32}
            max={1024}
            onChange={(v) => setMaxTokens(Math.round(v))}
          />
          <View style={styles.sliderHints}>
            <Text style={styles.hintText}>Short</Text>
            <Text style={styles.hintText}>Long</Text>
          </View>
        </Card>

        {/* Storage */}
        <SectionTitle title="STORAGE" />
        <StorageCard />

        {/* Models */}
        <SectionTitle title="MODELS" />
        <ModelsCard />

        {/* Developer */}
        <SectionTitle title="DEVELOPER" />
        <Card>
          <TouchableOpacity style={styles.infoRow} onPress={() => onNavigate?.('detective')}>
            <Text style={styles.rowIcon}>🕵️</Text>
            <Text style={styles.rowLabel}>Phone Detective</Text>
            <View style={{ flex: 1 }} />
            <Text style={styles.rowValue}>›</Text>
          </TouchableOpacity>
          <Divider />
          <TouchableOpacity style={styles.infoRow} onPress={() => onNavigate?.('soaktest')}>
            <Text style={styles.rowIcon}>📊</Text>
            <Text style={styles.rowLabel}>Soak Test</Text>
            <View style={{ flex: 1 }} />
            <Text style={styles.rowValue}>›</Text>
          </TouchableOpacity>
        </Card>

        {/* About */}
        <SectionTitle title="ABOUT" />
        <Card>
          <InfoRow icon="✨" label="Veda" value="1.1.0" />
          <Divider />
          <InfoRow icon="💻" label="Veda SDK" value="1.1.0" />
          <Divider />
          <InfoRow icon="🧠" label="Backend" value={Platform.OS === 'ios' ? 'Metal GPU' : 'CPU'} />
          <Divider />
          <View style={styles.infoRow}>
            <Text style={styles.rowIcon}>🛡️</Text>
            <View>
              <Text style={styles.rowLabel}>Privacy</Text>
              <Text style={styles.rowSub}>All inference runs locally on device</Text>
            </View>
          </View>
        </Card>
      </ScrollView>
    </View>
  );
}

function SectionTitle({ title }: { title: string }) {
  return <Text style={styles.sectionTitle}>{title}</Text>;
}

function Card({ children }: { children: React.ReactNode }) {
  return <View style={styles.card}>{children}</View>;
}

function Divider() {
  return <View style={styles.divider} />;
}

function InfoRow({ icon, label, value }: { icon: string; label: string; value: string }) {
  return (
    <View style={styles.infoRow}>
      <Text style={styles.rowIcon}>{icon}</Text>
      <Text style={styles.rowLabel}>{label}</Text>
      <View style={{ flex: 1 }} />
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

function SliderBar({
  value,
  min,
  max,
  onChange,
}: {
  value: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
}) {
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <View style={styles.sliderTrack}>
      <View style={[styles.sliderFill, { width: `${pct}%` }]} />
      <View style={[styles.sliderThumb, { left: `${pct}%` }]} />
      {/* Touch handling simplified for example — use react-native Slider in production */}
    </View>
  );
}

const ALL_MODELS = [
  ModelRegistry.llama32_1b,
  ModelRegistry.smolvlm2_500m,
  ModelRegistry.smolvlm2_500m_mmproj,
  ModelRegistry.qwen3_06b,
  ModelRegistry.whisperTinyEn,
  ModelRegistry.allMiniLmL6V2,
  ModelRegistry.sdV21Turbo,
];

function StorageCard() {
  const models = ALL_MODELS;
  const totalBytes = models.reduce((sum, m) => sum + m.sizeBytes, 0);
  const totalGb = totalBytes / (1024 * 1024 * 1024);
  const pct = Math.min(100, (totalGb / 4) * 100);

  return (
    <Card>
      <View style={styles.infoRow}>
        <Text style={styles.rowIcon}>💾</Text>
        <Text style={styles.rowLabel}>Models</Text>
        <View style={{ flex: 1 }} />
        <Text style={styles.rowValue}>~{totalGb.toFixed(1)} GB</Text>
      </View>
      <View style={styles.storageBarBg}>
        <View style={[styles.storageBarFill, { width: `${pct}%` }]} />
      </View>
      <Text style={styles.storageHint}>{totalGb.toFixed(1)} GB used</Text>
    </Card>
  );
}

function ModelsCard() {
  const models = ALL_MODELS;

  return (
    <Card>
      {models.map((model, i) => (
        <React.Fragment key={model.id}>
          {i > 0 && <Divider />}
          <ModelRow model={model} />
        </React.Fragment>
      ))}
    </Card>
  );
}

function ModelRow({ model }: { model: ModelInfo }) {
  const [isDownloaded, setIsDownloaded] = useState<boolean | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  useEffect(() => {
    (async () => {
      const mm = ModelManager.create();
      setIsDownloaded(await mm.isModelDownloaded(model.id));
    })();
  }, [model.id]);

  const sizeMb = model.sizeBytes / (1024 * 1024);
  const sizeLabel = sizeMb >= 1024 ? `~${(sizeMb / 1024).toFixed(1)} GB` : `~${Math.round(sizeMb)} MB`;

  const icon = model.id.includes('mmproj')
    ? '🧩'
    : model.id.includes('vlm') || model.id.includes('smol')
    ? '👁️'
    : model.id.includes('whisper')
    ? '🎙️'
    : model.id.includes('minilm') || model.id.includes('embedding')
    ? '🔢'
    : model.id.includes('sd-') || model.id.includes('stable')
    ? '🎨'
    : model.id.includes('qwen')
    ? '🔧'
    : '🤖';

  const handleDelete = async () => {
    setIsDeleting(true);
    try {
      const mm = ModelManager.create();
      await mm.deleteModel(model.id);
      setIsDownloaded(false);
    } catch {}
    setIsDeleting(false);
  };

  return (
    <View style={styles.modelRow}>
      <Text style={styles.modelIcon}>{icon}</Text>
      <View style={{ flex: 1, marginLeft: 12 }}>
        <Text style={styles.modelName}>{model.name}</Text>
        <Text style={styles.modelSize}>{sizeLabel}</Text>
      </View>
      {isDeleting ? (
        <ActivityIndicator size="small" color={AppTheme.accent} />
      ) : isDownloaded === true ? (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <Text style={{ color: AppTheme.success }}>✓</Text>
          <TouchableOpacity onPress={handleDelete}>
            <Text style={{ color: AppTheme.textTertiary }}>🗑️</Text>
          </TouchableOpacity>
        </View>
      ) : isDownloaded === false ? (
        <Text style={{ color: AppTheme.textTertiary }}>☁️</Text>
      ) : (
        <ActivityIndicator size="small" color={AppTheme.accent} />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: AppTheme.background },
  header: {
    fontSize: 18,
    fontWeight: '700',
    color: AppTheme.textPrimary,
    textAlign: 'center',
    paddingVertical: 14,
  },
  scroll: { flex: 1 },

  sectionTitle: {
    fontSize: 13,
    fontWeight: '600',
    color: AppTheme.accent,
    letterSpacing: 1.2,
    marginLeft: 20,
    marginTop: 24,
    marginBottom: 8,
  },

  card: {
    marginHorizontal: 16,
    backgroundColor: AppTheme.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: AppTheme.border,
    overflow: 'hidden',
  },

  divider: {
    height: 1,
    backgroundColor: AppTheme.border,
    marginHorizontal: 16,
  },

  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  rowIcon: { fontSize: 18, marginRight: 12 },
  rowLabel: { fontSize: 14, color: AppTheme.textPrimary },
  rowSub: { fontSize: 12, color: AppTheme.textTertiary, marginTop: 2 },
  rowValue: { fontSize: 14, color: AppTheme.textSecondary },

  sliderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 12,
  },
  sliderIcon: { fontSize: 18, marginRight: 12 },
  sliderLabel: { fontSize: 14, color: AppTheme.textPrimary, flex: 1 },
  sliderValue: { fontSize: 14, color: AppTheme.accent, fontWeight: '600' },

  sliderTrack: {
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.border,
    marginHorizontal: 16,
    marginTop: 8,
    position: 'relative',
  },
  sliderFill: {
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.accent,
  },
  sliderThumb: {
    position: 'absolute',
    top: -6,
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: AppTheme.accent,
    marginLeft: -8,
  },
  sliderHints: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 24,
    paddingTop: 4,
    paddingBottom: 12,
  },
  hintText: { fontSize: 11, color: AppTheme.textTertiary },

  storageBarBg: {
    height: 6,
    borderRadius: 3,
    backgroundColor: AppTheme.surfaceVariant,
    marginHorizontal: 16,
    marginTop: 8,
  },
  storageBarFill: {
    height: 6,
    borderRadius: 3,
    backgroundColor: AppTheme.accent,
  },
  storageHint: {
    fontSize: 11,
    color: AppTheme.textTertiary,
    marginLeft: 16,
    marginTop: 8,
    marginBottom: 12,
  },

  modelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  modelIcon: { fontSize: 18 },
  modelName: { fontSize: 14, color: AppTheme.textPrimary },
  modelSize: { fontSize: 12, color: AppTheme.textSecondary, marginTop: 2 },
});