import React, { useState, useEffect, useRef } from 'react';
import { View, Text, StyleSheet, ActivityIndicator, Animated, Easing } from 'react-native';
import { Camera, useCameraDevices, useFrameProcessor } from 'react-native-vision-camera';
import { AppTheme } from './theme';
import EdgeVeda, { VisionWorker, FrameQueue, ModelManager, ModelRegistry } from 'edge-veda';

/**
 * Vision screen with continuous camera scanning and description overlay.
 *
 * Matches Flutter's VisionScreen: full-screen camera preview,
 * AR-style description overlay at bottom with pulsing dot,
 * and model download overlay on first launch.
 */
export function VisionScreen(): React.JSX.Element {
  const [isVisionReady, setIsVisionReady] = useState(false);
  const [isDownloading, setIsDownloading] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [statusMessage, setStatusMessage] = useState('Preparing vision...');
  const [description, setDescription] = useState<string | null>(null);
  const [hasPermission, setHasPermission] = useState(false);

  const visionWorkerRef = useRef(new VisionWorker());
  const frameQueueRef = useRef(new FrameQueue());
  const devices = useCameraDevices();
  const device = devices.back;

  // Request camera permission
  useEffect(() => {
    (async () => {
      const status = await Camera.requestCameraPermission();
      setHasPermission(status === 'authorized');
    })();
  }, []);

  // Initialize vision pipeline
  useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        const mm = ModelManager.create();
        const model = ModelRegistry.smolvlm2_500m;
        const mmproj = ModelRegistry.smolvlm2_500m_mmproj;

        const modelDownloaded = await mm.isModelDownloaded(model.id);
        const mmprojDownloaded = await mm.isModelDownloaded(mmproj.id);

        let modelPath: string;
        let mmprojPath: string;

        if (!modelDownloaded || !mmprojDownloaded) {
          setIsDownloading(true);
          setStatusMessage('Downloading vision model...');

          modelPath = modelDownloaded
            ? (await mm.getModelPath(model.id))!
            : await mm.downloadModel(model, (p) => {
                setDownloadProgress(p.progress);
                setStatusMessage(`Downloading: ${p.progressPercent}%`);
              });

          mmprojPath = mmprojDownloaded
            ? (await mm.getModelPath(mmproj.id))!
            : await mm.downloadModel(mmproj, (p) => {
                setDownloadProgress(p.progress);
              });

          setIsDownloading(false);
        } else {
          modelPath = (await mm.getModelPath(model.id))!;
          mmprojPath = (await mm.getModelPath(mmproj.id))!;
        }

        if (cancelled) return;

        setStatusMessage('Loading vision model...');
        await visionWorkerRef.current.initialize({
          modelPath,
          mmprojPath,
          threads: 4,
          contextSize: 4096,
        });

        setIsVisionReady(true);
        setStatusMessage('Vision ready');
      } catch (e: any) {
        setStatusMessage(`Error: ${e.message}`);
        setIsDownloading(false);
      }
    })();

    return () => {
      cancelled = true;
      visionWorkerRef.current.cleanup();
    };
  }, []);

  // Frame processor (processes frames from camera)
  const frameProcessor = useFrameProcessor((frame) => {
    'worklet';
    if (!isVisionReady || isProcessing) return;

    const rgb = frame.toArrayBuffer();
    const width = frame.width;
    const height = frame.height;

    frameQueueRef.current.enqueue(rgb, width, height);
  }, [isVisionReady, isProcessing]);

  // Process frames from queue
  useEffect(() => {
    if (!isVisionReady) return;

    const interval = setInterval(async () => {
      const frame = frameQueueRef.current.dequeue();
      if (!frame || isProcessing) return;

      setIsProcessing(true);
      try {
        const result = await visionWorkerRef.current.describeFrame(
          frame.rgb,
          frame.width,
          frame.height,
          'Describe what you see in this image in one sentence.',
          { maxTokens: 100 },
        );
        setDescription(result.description);
      } catch (e) {
        // Silently continue
      }
      frameQueueRef.current.markDone();
      setIsProcessing(false);
    }, 500);

    return () => clearInterval(interval);
  }, [isVisionReady, isProcessing]);

  return (
    <View style={styles.container}>
      {/* Camera preview */}
      {isVisionReady && device && hasPermission && (
        <Camera
          style={StyleSheet.absoluteFill}
          device={device}
          isActive={true}
          frameProcessor={frameProcessor}
          frameProcessorFps={2}
        />
      )}

      {/* Description overlay at bottom (AR-style) */}
      {description && (
        <View style={styles.descriptionContainer}>
          <View style={styles.descriptionCard}>
            {isProcessing && <PulsingDot />}
            <Text style={styles.descriptionText}>{description}</Text>
          </View>
        </View>
      )}

      {/* Loading/download overlay */}
      {(isDownloading || !isVisionReady) && (
        <View style={styles.overlay}>
          {isDownloading ? (
            <>
              <Text style={styles.overlayIcon}>☁️</Text>
              <View style={styles.progressBarBg}>
                <View
                  style={[
                    styles.progressBarFill,
                    { width: `${Math.max(0, downloadProgress * 100)}%` },
                  ]}
                />
              </View>
            </>
          ) : (
            <ActivityIndicator size="large" color={AppTheme.textSecondary} />
          )}
          <Text style={styles.overlayText}>{statusMessage}</Text>
        </View>
      )}

      {/* No permission */}
      {!hasPermission && isVisionReady && (
        <View style={styles.overlay}>
          <Text style={styles.overlayIcon}>📷</Text>
          <Text style={styles.overlayText}>Camera permission required</Text>
        </View>
      )}
    </View>
  );
}

function PulsingDot(): React.JSX.Element {
  const opacity = useRef(new Animated.Value(0.3)).current;

  useEffect(() => {
    const pulse = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, {
          toValue: 1,
          duration: 1000,
          easing: Easing.inOut(Easing.ease),
          useNativeDriver: true,
        }),
        Animated.timing(opacity, {
          toValue: 0.3,
          duration: 1000,
          easing: Easing.inOut(Easing.ease),
          useNativeDriver: true,
        }),
      ]),
    );
    pulse.start();
    return () => pulse.stop();
  }, [opacity]);

  return (
    <Animated.View
      style={[styles.pulsingDot, { opacity }]}
    />
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: AppTheme.background },

  descriptionContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 16,
  },
  descriptionCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: `${AppTheme.surface}E6`,
    borderRadius: 16,
    padding: 16,
  },
  descriptionText: {
    flex: 1,
    color: AppTheme.textPrimary,
    fontSize: 16,
    lineHeight: 22,
  },

  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: `${AppTheme.background}DE`,
    alignItems: 'center',
    justifyContent: 'center',
  },
  overlayIcon: { fontSize: 48, marginBottom: 24 },
  overlayText: { color: AppTheme.textPrimary, fontSize: 16, marginTop: 16 },

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

  pulsingDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: AppTheme.accent,
    marginRight: 12,
  },
});