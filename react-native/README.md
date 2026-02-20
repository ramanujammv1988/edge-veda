# Edge Veda SDK for React Native (v1.2.0)

On-device LLM inference for React Native — with chat sessions, vision, runtime supervision, model management, camera utilities, and observability.

## Features

- **TurboModule Support**: Built with React Native's New Architecture for maximum performance
- **On-Device Inference**: Run LLMs locally without internet connection
- **Chat Sessions**: Multi-turn conversation management with template support
- **Vision Inference**: Process images and camera frames through vision models
- **Runtime Supervision**: Budget, latency, thermal, battery, resource monitoring, scheduling, and telemetry
- **Model Management**: Download, cache, and manage models with ModelManager and ModelRegistry
- **Camera Utilities**: Capture and preprocess camera frames for vision pipelines
- **Observability**: Performance tracing and native error codes
- **Streaming Generation**: Real-time token streaming with callbacks
- **Cross-Platform**: iOS and Android with native C++ core
- **TypeScript**: Full type safety with comprehensive type definitions

## Installation

```bash
npm install @edgeveda/react-native
# or
yarn add @edgeveda/react-native
```

### iOS

```bash
cd ios && pod install
```

### Android

No additional setup required — autolinking handles everything.

## Requirements

- React Native >= 0.68.0
- iOS >= 13.0
- Android minSdkVersion >= 21
- Expo SDK >= 49 (development builds only, not Expo Go)

## Quick Start

```typescript
import EdgeVeda from '@edgeveda/react-native';

await EdgeVeda.init('/path/to/model.gguf', {
  maxTokens: 512,
  temperature: 0.7,
  useGpu: true,
});

const response = await EdgeVeda.generate('What is the capital of France?');
console.log(response);

await EdgeVeda.unloadModel();
```

### Streaming

```typescript
await EdgeVeda.generateStream(
  'Write a short story',
  (token, isComplete) => {
    if (!isComplete) process.stdout.write(token);
    else console.log('\nDone!');
  },
  { temperature: 0.9, maxTokens: 2048 }
);
```

## Chat Sessions

Multi-turn conversation management with automatic prompt formatting.

```typescript
import { ChatSession, ChatTemplate } from '@edgeveda/react-native';

const template = new ChatTemplate('llama3');
const session = new ChatSession(edgeVeda, template, {
  systemPrompt: 'You are a helpful assistant.',
});

const reply1 = await session.send('What is React Native?');
console.log(reply1);

const reply2 = await session.send('How does it differ from Flutter?');
console.log(reply2); // context-aware follow-up

session.clearHistory();
```

## Vision Inference

Process images and camera frames through vision-capable models.

```typescript
import { VisionWorker, FrameQueue } from '@edgeveda/react-native';

const vision = new VisionWorker(edgeVeda, {
  maxFrames: 30,
  resolution: { width: 224, height: 224 },
});
const queue = new FrameQueue(30);

queue.enqueue(frameData);

const result = await vision.processFrame(queue.dequeue());
console.log(result.description);
```

## Runtime Supervision

### Budget

Control token and time limits for generation.

```typescript
import { Budget } from '@edgeveda/react-native';

const budget = new Budget({ maxTokens: 500, maxTimeMs: 10000, maxMemoryBytes: 512 * 1024 * 1024 });
budget.startTracking();

if (budget.isExhausted()) console.log('Budget exceeded');
console.log(budget.snapshot());
```

### Latency Tracker

Track token generation latency with percentile statistics.

```typescript
import { LatencyTracker } from '@edgeveda/react-native';

const tracker = new LatencyTracker({ windowSize: 100 });
tracker.recordLatency(12.5);
tracker.recordLatency(15.3);

const stats = tracker.getStats();
console.log(`p50=${stats.p50}ms, p99=${stats.p99}ms, avg=${stats.avg}ms`);
```

### Resource Monitor

Monitor memory and system resource consumption.

```typescript
import { ResourceMonitor } from '@edgeveda/react-native';

const monitor = new ResourceMonitor({ pollingIntervalMs: 1000 });
monitor.start();
monitor.onThreshold('memory', 0.85, () => console.warn('High memory'));

const snapshot = monitor.snapshot();
console.log(`Memory: ${snapshot.memoryUsagePercent}%`);
monitor.stop();
```

### Thermal Monitor

Track device thermal state.

```typescript
import { ThermalMonitor } from '@edgeveda/react-native';

const thermal = new ThermalMonitor();
thermal.start();
thermal.onStateChange((state) => console.log(`Thermal: ${state}`));
// States: nominal, fair, serious, critical
thermal.stop();
```

### Battery Drain Tracker

Monitor battery impact during inference.

```typescript
import { BatteryDrainTracker } from '@edgeveda/react-native';

const battery = new BatteryDrainTracker();
await battery.start();

const drain = battery.snapshot();
console.log(`Drain rate: ${drain.drainRatePerHour}%/hr, level: ${drain.level}%`);
battery.stop();
```

### Scheduler

Schedule and prioritize inference tasks.

```typescript
import { Scheduler } from '@edgeveda/react-native';

const scheduler = new Scheduler({ maxConcurrent: 2, defaultPriority: 'normal' });

const handle = scheduler.enqueue({ prompt: 'Task 1', priority: 'high' });
const result = await handle.result;
```

### Runtime Policy

Combine budget, thermal, and resource constraints into adaptive policies.

```typescript
import { RuntimePolicy } from '@edgeveda/react-native';

const policy = new RuntimePolicy({
  maxTokens: 1000,
  thermalThrottleState: 'serious',
  memoryThresholdPercent: 90,
  action: 'throttle', // 'throttle' | 'cancel' | 'warn'
});

policy.evaluate(currentContext); // returns recommended action
```

### Telemetry

Collect and export SDK usage metrics.

```typescript
import { Telemetry } from '@edgeveda/react-native';

const telemetry = new Telemetry({ enabled: true, batchSize: 50 });
telemetry.record('inference_start', { model: 'llama-3.2-1b', tokens: 100 });
telemetry.record('inference_end', { durationMs: 450, tokensPerSec: 22.1 });

const events = telemetry.flush();
```

## Model Management

### ModelManager

Download, cache, and lifecycle-manage models.

```typescript
import { ModelManager } from '@edgeveda/react-native';

const manager = new ModelManager({ cacheDir: '/path/to/cache' });

await manager.download('llama-3.2-1b', {
  onProgress: (p) => console.log(`${p.percent}%`),
});

const modelPath = manager.getModelPath('llama-3.2-1b');
const cached = manager.listCachedModels();
await manager.deleteModel('llama-3.2-1b');
```

### ModelRegistry

Discover available models and their metadata.

```typescript
import { ModelRegistry } from '@edgeveda/react-native';

const registry = new ModelRegistry();
await registry.refresh();

const models = registry.listModels();
models.forEach(m => console.log(`${m.id}: ${m.name} (${m.sizeBytes} bytes)`));

const model = registry.getModel('llama-3.2-1b');
console.log(model.quantization, model.contextLength);
```

## Camera Utilities

Capture and preprocess camera frames for vision pipelines.

```typescript
import { CameraUtils } from '@edgeveda/react-native';

const camera = new CameraUtils({ facing: 'back', width: 640, height: 480 });
await camera.start();

const frame = await camera.captureFrame();
const resized = camera.resize(frame, 224, 224);
const normalized = camera.normalize(resized);

camera.stop();
```

## Observability

### PerfTrace

Capture detailed performance traces for inference runs.

```typescript
import { PerfTrace } from '@edgeveda/react-native';

const trace = new PerfTrace('inference-run-1');
trace.begin('tokenize');
// ... tokenization ...
trace.end('tokenize');

trace.begin('generate');
// ... generation ...
trace.end('generate');

const report = trace.report();
console.log(report.spans); // [{name, startMs, endMs, durationMs}, ...]
console.log(`Total: ${report.totalDurationMs}ms`);
```

### NativeErrorCode

Structured error codes from the native C core.

```typescript
import { NativeErrorCode, isRecoverable } from '@edgeveda/react-native';

try {
  await EdgeVeda.generate('test');
} catch (e) {
  const code = NativeErrorCode.fromError(e);
  console.log(`Error ${code.code}: ${code.message} (domain: ${code.domain})`);
  console.log(`Recoverable: ${isRecoverable(code)}`);
}
```

## Architecture

| Component | File | Description |
|-----------|------|-------------|
| EdgeVeda | `EdgeVeda.ts` | Main SDK entry point |
| NativeEdgeVeda | `NativeEdgeVeda.ts` | TurboModule native bridge |
| Types | `types.ts` | Core type definitions |
| ChatSession | `ChatSession.ts` | Multi-turn conversation manager |
| ChatTemplate | `ChatTemplate.ts` | Prompt template formatting |
| ChatTypes | `ChatTypes.ts` | Chat type definitions |
| VisionWorker | `VisionWorker.ts` | Vision inference pipeline |
| FrameQueue | `FrameQueue.ts` | Frame buffer for vision |
| Budget | `Budget.ts` | Token/time budget enforcement |
| LatencyTracker | `LatencyTracker.ts` | Latency percentile tracking |
| ResourceMonitor | `ResourceMonitor.ts` | Memory/resource monitoring |
| ThermalMonitor | `ThermalMonitor.ts` | Thermal state tracking |
| BatteryDrainTracker | `BatteryDrainTracker.ts` | Battery drain monitoring |
| Scheduler | `Scheduler.ts` | Task scheduling and prioritization |
| RuntimePolicy | `RuntimePolicy.ts` | Adaptive runtime policies |
| Telemetry | `Telemetry.ts` | Usage metrics collection |
| ModelManager | `ModelManager.ts` | Model download and caching |
| ModelRegistry | `ModelRegistry.ts` | Model discovery and metadata |
| CameraUtils | `CameraUtils.ts` | Camera capture and preprocessing |
| PerfTrace | `PerfTrace.ts` | Performance tracing |
| NativeErrorCode | `NativeErrorCode.ts` | Structured native error codes |

## Architecture Support

| Feature | Old Architecture | New Architecture |
|---------|-----------------|------------------|
| Module Type | ReactContextBaseJavaModule | TurboModule |
| Method Calls | Asynchronous | Synchronous |
| Performance | Good | Excellent |
| JSI Support | No | Yes |
| React Native | 0.68-0.72 | 0.73+ |

Architecture detection is automatic — no configuration needed.

## Performance Tips

1. **Use GPU acceleration** — set `useGpu: true` (Metal on iOS, Vulkan on Android)
2. **Use streaming** for long-form generation to improve perceived latency
3. **Monitor memory** with ResourceMonitor and unload models when not in use
4. **Use RuntimePolicy** to automatically throttle under thermal/memory pressure
5. **Choose appropriate quantization** — Q4 models are fastest, F16 most accurate

## Model Support

GGUF format with quantization levels: Q4_0, Q4_1, Q5_0, Q5_1, Q8_0, F16.

## License

Apache-2.0