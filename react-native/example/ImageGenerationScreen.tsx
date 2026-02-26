import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  ActivityIndicator,
  Image,
  FlatList,
} from 'react-native';
import { AppTheme } from './theme';
import EdgeVeda, {
  ModelManager,
  ModelRegistry,
  ImageGenerationConfig,
  ImageSampler,
  CancelToken,
  ImageResult,
} from 'edge-veda';

/**
 * Image Generation screen using Stable Diffusion v2.1 Turbo.
 *
 * Matches Flutter's image_screen.dart:
 * - Prompt + negative prompt inputs
 * - Collapsible advanced settings (steps, CFG scale, seed, size, sampler)
 * - Step progress bar with elapsed time
 * - Generated image display
 * - Horizontal gallery of past generations
 */

type ImageGenState = 'downloading' | 'loading' | 'ready' | 'generating' | 'error';

interface GeneratedImage {
  id: string;
  uri: string;
  prompt: string;
  width: number;
  height: number;
  generationTimeMs: number;
}

const SIZE_PRESETS = [
  { label: '256×256', width: 256, height: 256 },
  { label: '512×512', width: 512, height: 512 },
];

const SAMPLER_OPTIONS = [
  { label: 'Euler A', value: ImageSampler.EULER_A },
  { label: 'Euler', value: ImageSampler.EULER },
  { label: 'DPM++ 2M', value: ImageSampler.DPM_PP_2M },
  { label: 'LCM', value: ImageSampler.LCM },
];

export function ImageGenerationScreen(): React.JSX.Element {
  const [state, setState] = useState<ImageGenState>('downloading');
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [statusMessage, setStatusMessage] = useState('Checking for model…');
  const [prompt, setPrompt] = useState('');
  const [negativePrompt, setNegativePrompt] = useState('');
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [steps, setSteps] = useState(20);
  const [cfgScale, setCfgScale] = useState(7.0);
  const [seed, setSeed] = useState(-1);
  const [sizeIndex, setSizeIndex] = useState(1); // 512×512 default
  const [samplerIndex, setSamplerIndex] = useState(0); // Euler A default
  const [currentStep, setCurrentStep] = useState(0);
  const [totalSteps, setTotalSteps] = useState(20);
  const [elapsedSec, setElapsedSec] = useState(0);
  const [gallery, setGallery] = useState<GeneratedImage[]>([]);
  const [selectedImageId, setSelectedImageId] = useState<string | null>(null);

  const cancelTokenRef = useRef<CancelToken | null>(null);
  const isInitialized = useRef(false);

  // Lazy-initialize on first render
  React.useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const mm = ModelManager.create();
        const model = ModelRegistry.sdV21Turbo;

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
        setState('loading');
        setStatusMessage('Loading model…');

        await EdgeVeda.initImageGeneration(modelPath);
        isInitialized.current = true;

        setState('ready');
        setStatusMessage('Ready');
      } catch (e: any) {
        setState('error');
        setStatusMessage(`Error: ${e.message}`);
      }
    })();

    return () => {
      cancelled = true;
      EdgeVeda.freeImageGeneration().catch(() => {});
    };
  }, []);

  const generate = async () => {
    if (!prompt.trim() || state !== 'ready') return;

    setState('generating');
    setCurrentStep(0);
    setTotalSteps(steps);
    setElapsedSec(0);

    const cancelToken = new CancelToken();
    cancelTokenRef.current = cancelToken;

    const size = SIZE_PRESETS[sizeIndex]!;
    const sampler = SAMPLER_OPTIONS[samplerIndex]!;

    const config: ImageGenerationConfig = {
      negativePrompt,
      width: size.width,
      height: size.height,
      steps,
      cfgScale,
      seed,
      sampler: sampler.value,
    };

    try {
      const result: ImageResult = await EdgeVeda.generateImage(
        prompt.trim(),
        config,
        (progress) => {
          setCurrentStep(progress.step);
          setTotalSteps(progress.totalSteps);
          setElapsedSec(Math.round(progress.elapsedSeconds));
        },
        cancelToken,
      );

      // Convert RGBA pixelData to base64 data URI
      const uri = _pixelDataToUri(result.pixelData, result.width, result.height);

      const img: GeneratedImage = {
        id: String(Date.now()),
        uri,
        prompt: prompt.trim(),
        width: result.width,
        height: result.height,
        generationTimeMs: result.generationTimeMs,
      };

      setGallery((prev) => [img, ...prev]);
      setSelectedImageId(img.id);
      setState('ready');
      setStatusMessage(`Done — ${(result.generationTimeMs / 1000).toFixed(1)}s`);
    } catch (e: any) {
      if (!cancelToken.isCancelled) {
        setStatusMessage(`Error: ${e.message}`);
      } else {
        setStatusMessage('Cancelled');
      }
      setState('ready');
    }

    cancelTokenRef.current = null;
  };

  const cancelGeneration = () => {
    cancelTokenRef.current?.cancel();
    setState('ready');
    setStatusMessage('Cancelled');
  };

  const selectedImage = gallery.find((g) => g.id === selectedImageId) ?? gallery[0] ?? null;
  const progressPct = totalSteps > 0 ? (currentStep / totalSteps) * 100 : 0;

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Image Generation</Text>
        <View style={styles.headerRight}>
          {state === 'generating' && (
            <Text style={styles.stepLabel}>{currentStep}/{totalSteps}</Text>
          )}
        </View>
      </View>

      {/* Status + progress */}
      <View style={styles.statusBar}>
        {(state === 'downloading' || state === 'loading' || state === 'generating') && (
          <ActivityIndicator size="small" color={AppTheme.accent} style={{ marginRight: 8 }} />
        )}
        <Text style={styles.statusText} numberOfLines={1}>{statusMessage}</Text>
        {state === 'generating' && (
          <Text style={styles.elapsedText}>{elapsedSec}s</Text>
        )}
      </View>

      {/* Step progress bar */}
      {state === 'generating' && (
        <View style={styles.progressBarBg}>
          <View style={[styles.progressBarFill, { width: `${progressPct}%` }]} />
        </View>
      )}

      {/* Download progress bar */}
      {state === 'downloading' && (
        <View style={styles.progressBarBg}>
          <View style={[styles.progressBarFill, { width: `${Math.max(2, downloadProgress * 100)}%` }]} />
        </View>
      )}

      <ScrollView style={styles.scroll} contentContainerStyle={{ paddingBottom: 32 }}>
        {/* Generated image */}
        {selectedImage ? (
          <View style={styles.imageContainer}>
            <Image
              source={{ uri: selectedImage.uri }}
              style={[styles.generatedImage, { aspectRatio: selectedImage.width / selectedImage.height }]}
              resizeMode="contain"
            />
            <Text style={styles.imageCaption} numberOfLines={2}>{selectedImage.prompt}</Text>
            <Text style={styles.imageTime}>{(selectedImage.generationTimeMs / 1000).toFixed(1)}s</Text>
          </View>
        ) : state !== 'downloading' && state !== 'loading' ? (
          <View style={styles.imagePlaceholder}>
            <Text style={styles.placeholderIcon}>🎨</Text>
            <Text style={styles.placeholderText}>Your image will appear here</Text>
          </View>
        ) : null}

        {/* Gallery strip */}
        {gallery.length > 1 && (
          <FlatList
            data={gallery}
            horizontal
            keyExtractor={(g) => g.id}
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.galleryStrip}
            renderItem={({ item }) => (
              <TouchableOpacity
                onPress={() => setSelectedImageId(item.id)}
                style={[styles.galleryThumb, item.id === selectedImageId && styles.galleryThumbActive]}
              >
                <Image source={{ uri: item.uri }} style={styles.galleryThumbImage} />
              </TouchableOpacity>
            )}
          />
        )}

        {/* Prompt inputs */}
        <View style={styles.inputSection}>
          <TextInput
            style={styles.promptInput}
            value={prompt}
            onChangeText={setPrompt}
            placeholder="Describe your image…"
            placeholderTextColor={AppTheme.textTertiary}
            multiline
            maxLength={300}
            editable={state === 'ready'}
          />
          <TextInput
            style={[styles.promptInput, styles.negativeInput]}
            value={negativePrompt}
            onChangeText={setNegativePrompt}
            placeholder="Negative prompt (optional)"
            placeholderTextColor={AppTheme.textTertiary}
            multiline
            maxLength={200}
            editable={state === 'ready'}
          />
        </View>

        {/* Advanced settings toggle */}
        <TouchableOpacity
          style={styles.advancedToggle}
          onPress={() => setShowAdvanced(!showAdvanced)}
        >
          <Text style={styles.advancedToggleText}>
            {showAdvanced ? '▲' : '▼'} Advanced Settings
          </Text>
        </TouchableOpacity>

        {showAdvanced && (
          <View style={styles.advancedPanel}>
            {/* Steps slider */}
            <SettingRow label="Steps" value={String(steps)}>
              <SimpleSlider value={steps} min={1} max={50} step={1} onChange={setSteps} disabled={state !== 'ready'} />
            </SettingRow>

            {/* CFG scale */}
            <SettingRow label="Guidance" value={cfgScale.toFixed(1)}>
              <SimpleSlider value={cfgScale} min={1} max={20} step={0.5} onChange={setCfgScale} disabled={state !== 'ready'} />
            </SettingRow>

            {/* Size picker */}
            <View style={styles.pickerRow}>
              <Text style={styles.pickerLabel}>Size</Text>
              <View style={styles.pickerOptions}>
                {SIZE_PRESETS.map((s, i) => (
                  <TouchableOpacity
                    key={s.label}
                    style={[styles.pickerOption, i === sizeIndex && styles.pickerOptionActive]}
                    onPress={() => setSizeIndex(i)}
                  >
                    <Text style={[styles.pickerOptionText, i === sizeIndex && styles.pickerOptionTextActive]}>
                      {s.label}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>

            {/* Sampler picker */}
            <View style={styles.pickerRow}>
              <Text style={styles.pickerLabel}>Sampler</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                <View style={styles.pickerOptions}>
                  {SAMPLER_OPTIONS.map((s, i) => (
                    <TouchableOpacity
                      key={s.label}
                      style={[styles.pickerOption, i === samplerIndex && styles.pickerOptionActive]}
                      onPress={() => setSamplerIndex(i)}
                    >
                      <Text style={[styles.pickerOptionText, i === samplerIndex && styles.pickerOptionTextActive]}>
                        {s.label}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </ScrollView>
            </View>
          </View>
        )}
      </ScrollView>

      {/* Generate / Cancel button */}
      <View style={styles.generateArea}>
        <TouchableOpacity
          style={[
            styles.generateBtn,
            state === 'generating' && styles.cancelBtn,
            state !== 'ready' && state !== 'generating' && styles.generateBtnDisabled,
          ]}
          onPress={state === 'generating' ? cancelGeneration : generate}
          disabled={state !== 'ready' && state !== 'generating'}
          activeOpacity={0.8}
        >
          <Text style={styles.generateBtnText}>
            {state === 'generating' ? '■  Cancel' : '✨  Generate'}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function SettingRow({
  label,
  value,
  children,
}: {
  label: string;
  value: string;
  children: React.ReactNode;
}) {
  return (
    <View style={styles.settingRow}>
      <View style={styles.settingLabelRow}>
        <Text style={styles.settingLabel}>{label}</Text>
        <Text style={styles.settingValue}>{value}</Text>
      </View>
      {children}
    </View>
  );
}

function SimpleSlider({
  value,
  min,
  max,
  step,
  onChange,
  disabled,
}: {
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
  disabled?: boolean;
}) {
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <View style={styles.sliderTrack}>
      <View style={[styles.sliderFill, { width: `${pct}%` }]} />
      {/* In a real app, use a proper Slider component here */}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Convert raw RGBA pixel data to a base64 data URI.
 * In a real app, use a native image encoder for proper PNG output.
 * Here we produce a minimal BMP-like raw data URI for demonstration.
 */
function _pixelDataToUri(pixelData: Uint8Array, _width: number, _height: number): string {
  // Convert to base64
  let binary = '';
  for (let i = 0; i < pixelData.length; i++) {
    binary += String.fromCharCode(pixelData[i]!);
  }
  const base64 = btoa(binary);
  // For demo purposes — real apps would encode as PNG
  return `data:image/rgba;base64,${base64}`;
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: AppTheme.background },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  headerTitle: { fontSize: 18, fontWeight: '700', color: AppTheme.textPrimary, flex: 1 },
  headerRight: { flexDirection: 'row', alignItems: 'center' },
  stepLabel: { fontSize: 13, color: AppTheme.accent, fontWeight: '600' },

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
  elapsedText: { fontSize: 12, color: AppTheme.textTertiary },

  progressBarBg: { height: 3, backgroundColor: AppTheme.surfaceVariant },
  progressBarFill: { height: 3, backgroundColor: AppTheme.accent },

  scroll: { flex: 1 },

  imageContainer: {
    alignItems: 'center',
    padding: 16,
  },
  generatedImage: {
    width: '100%',
    borderRadius: 12,
    backgroundColor: AppTheme.surfaceVariant,
  },
  imageCaption: {
    fontSize: 13,
    color: AppTheme.textSecondary,
    textAlign: 'center',
    marginTop: 8,
    paddingHorizontal: 16,
  },
  imageTime: {
    fontSize: 11,
    color: AppTheme.textTertiary,
    marginTop: 4,
  },

  imagePlaceholder: {
    height: 220,
    alignItems: 'center',
    justifyContent: 'center',
    margin: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: AppTheme.border,
    borderStyle: 'dashed',
  },
  placeholderIcon: { fontSize: 48, marginBottom: 12 },
  placeholderText: { fontSize: 14, color: AppTheme.textTertiary },

  galleryStrip: { paddingHorizontal: 12, paddingBottom: 8 },
  galleryThumb: {
    width: 56,
    height: 56,
    borderRadius: 8,
    marginRight: 8,
    borderWidth: 2,
    borderColor: 'transparent',
    overflow: 'hidden',
  },
  galleryThumbActive: { borderColor: AppTheme.accent },
  galleryThumbImage: { width: '100%', height: '100%' },

  inputSection: { paddingHorizontal: 16, gap: 10 },
  promptInput: {
    backgroundColor: AppTheme.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: AppTheme.border,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: AppTheme.textPrimary,
    fontSize: 15,
    minHeight: 60,
    maxHeight: 120,
  },
  negativeInput: { minHeight: 44, maxHeight: 80 },

  advancedToggle: {
    alignSelf: 'center',
    paddingVertical: 10,
    paddingHorizontal: 16,
    marginTop: 8,
  },
  advancedToggleText: { fontSize: 13, color: AppTheme.accent, fontWeight: '600' },

  advancedPanel: {
    marginHorizontal: 16,
    backgroundColor: AppTheme.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: AppTheme.border,
    padding: 16,
    gap: 16,
  },

  settingRow: { gap: 8 },
  settingLabelRow: { flexDirection: 'row', justifyContent: 'space-between' },
  settingLabel: { fontSize: 13, color: AppTheme.textPrimary },
  settingValue: { fontSize: 13, color: AppTheme.accent, fontWeight: '600' },

  sliderTrack: {
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.border,
  },
  sliderFill: {
    height: 4,
    borderRadius: 2,
    backgroundColor: AppTheme.accent,
  },

  pickerRow: { gap: 8 },
  pickerLabel: { fontSize: 13, color: AppTheme.textPrimary },
  pickerOptions: { flexDirection: 'row', gap: 8 },
  pickerOption: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    backgroundColor: AppTheme.surfaceVariant,
    borderWidth: 1,
    borderColor: AppTheme.border,
  },
  pickerOptionActive: {
    backgroundColor: `${AppTheme.accent}33`,
    borderColor: AppTheme.accent,
  },
  pickerOptionText: { fontSize: 12, color: AppTheme.textSecondary },
  pickerOptionTextActive: { color: AppTheme.accent, fontWeight: '600' },

  generateArea: {
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: AppTheme.border,
  },
  generateBtn: {
    backgroundColor: AppTheme.accent,
    borderRadius: 28,
    paddingVertical: 16,
    alignItems: 'center',
  },
  cancelBtn: { backgroundColor: AppTheme.danger },
  generateBtnDisabled: { backgroundColor: AppTheme.surfaceVariant },
  generateBtnText: { fontSize: 16, fontWeight: '700', color: AppTheme.background },
});
