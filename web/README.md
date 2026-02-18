# Edge Veda Web SDK (v1.2.0)

Browser-based Large Language Model inference using WebGPU and WebAssembly — with chat sessions, vision, runtime supervision, model registry, camera utilities, and observability.

## Features

- **WebGPU Acceleration**: Automatic GPU detection and usage for high-performance inference
- **WASM Fallback**: CPU-based inference when WebGPU is unavailable
- **Chat Sessions**: Multi-turn conversation management with template support
- **Vision Inference**: Process images/video frames through vision models
- **Runtime Supervision**: Budget, latency, thermal, battery, resource monitoring, scheduling, and telemetry
- **Model Registry**: Discover and manage available models with metadata
- **Camera Utilities**: Capture and preprocess camera frames for vision pipelines
- **Observability**: Performance tracing and native error codes
- **Model Caching**: Automatic model caching in IndexedDB for faster subsequent loads
- **Streaming Support**: Real-time token streaming for responsive UX
- **Web Worker Architecture**: Non-blocking inference using Web Workers
- **TypeScript**: Full type safety and excellent IDE support

## Installation

```bash
npm install @edgeveda/web
```

## Quick Start

```typescript
import { EdgeVeda } from '@edgeveda/web';

const ai = new EdgeVeda({ modelId: 'llama-3.2-1b', device: 'auto' });
await ai.init();

const result = await ai.generate({ prompt: 'Hello!', maxTokens: 100 });
console.log(result.text);

await ai.terminate();
```

### Streaming

```typescript
for await (const chunk of ai.generateStream({ prompt: 'Write a poem:', maxTokens: 200 })) {
  process.stdout.write(chunk.token);
}
```

## Chat Sessions

Multi-turn conversation management with automatic prompt formatting.

```typescript
import { ChatSession, ChatTemplate } from '@edgeveda/web';

const template = new ChatTemplate('llama3');
const session = new ChatSession(ai, template, { systemPrompt: 'You are helpful.' });

const reply1 = await session.send('What is TypeScript?');
console.log(reply1);

const reply2 = await session.send('How does it differ from JavaScript?');
console.log(reply2); // context-aware follow-up

session.clearHistory();
```

## Vision Inference

Process images and video frames through vision-capable models.

```typescript
import { VisionWorker, FrameQueue } from '@edgeveda/web';

const vision = new VisionWorker(ai, { maxFrames: 30, resolution: { width: 224, height: 224 } });
const queue = new FrameQueue(30);

// Enqueue a frame (ImageData, Blob, or URL)
queue.enqueue(imageData);

// Process frames
const result = await vision.processFrame(queue.dequeue());
console.log(result.description);
```

## Runtime Supervision

### Budget

Control token and time limits for generation.

```typescript
import { Budget } from '@edgeveda/web';

const budget = new Budget({ maxTokens: 500, maxTimeMs: 10000, maxMemoryBytes: 512 * 1024 * 1024 });
budget.startTracking();

if (budget.isExhausted()) console.log('Budget exceeded');
console.log(budget.snapshot());
```

### Latency Tracker

Track token generation latency with percentile statistics.

```typescript
import { LatencyTracker } from '@edgeveda/web';

const tracker = new LatencyTracker({ windowSize: 100 });
tracker.recordLatency(12.5);
tracker.recordLatency(15.3);

const stats = tracker.getStats();
console.log(`p50=${stats.p50}ms, p99=${stats.p99}ms, avg=${stats.avg}ms`);
```

### Resource Monitor

Monitor memory and system resource consumption.

```typescript
import { ResourceMonitor } from '@edgeveda/web';

const monitor = new ResourceMonitor({ pollingIntervalMs: 1000 });
monitor.start();
monitor.onThreshold('memory', 0.85, () => console.warn('High memory'));

const snapshot = monitor.snapshot();
console.log(`Memory: ${snapshot.memoryUsagePercent}%`);
monitor.stop();
```

### Thermal Monitor

Track device thermal state (maps to browser/device thermal APIs).

```typescript
import { ThermalMonitor } from '@edgeveda/web';

const thermal = new ThermalMonitor();
thermal.start();
thermal.onStateChange((state) => console.log(`Thermal: ${state}`));
// States: nominal, fair, serious, critical
thermal.stop();
```

### Battery Drain Tracker

Monitor battery impact during inference.

```typescript
import { BatteryDrainTracker } from '@edgeveda/web';

const battery = new BatteryDrainTracker();
await battery.start();

const drain = battery.snapshot();
console.log(`Drain rate: ${drain.drainRatePerHour}%/hr, level: ${drain.level}%`);
battery.stop();
```

### Scheduler

Schedule and prioritize inference tasks.

```typescript
import { Scheduler } from '@edgeveda/web';

const scheduler = new Scheduler({ maxConcurrent: 2, defaultPriority: 'normal' });

const handle = scheduler.enqueue({ prompt: 'Task 1', priority: 'high' });
const result = await handle.result;
```

### Runtime Policy

Combine budget, thermal, and resource constraints into adaptive policies.

```typescript
import { RuntimePolicy } from '@edgeveda/web';

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
import { Telemetry } from '@edgeveda/web';

const telemetry = new Telemetry({ enabled: true, batchSize: 50 });
telemetry.record('inference_start', { model: 'llama-3.2-1b', tokens: 100 });
telemetry.record('inference_end', { durationMs: 450, tokensPerSec: 22.1 });

const events = telemetry.flush();
```

## Model Registry

Discover available models and their metadata.

```typescript
import { ModelRegistry } from '@edgeveda/web';

const registry = new ModelRegistry();
await registry.refresh();

const models = registry.listModels();
models.forEach(m => console.log(`${m.id}: ${m.name} (${m.sizeBytes} bytes)`));

const model = registry.getModel('llama-3.2-1b');
console.log(model.quantization, model.contextLength);
```

## Cache Management

```typescript
import { listCachedModels, getCacheSize, deleteCachedModel, clearCache } from '@edgeveda/web';

const models = await listCachedModels();
const size = await getCacheSize();
await deleteCachedModel('llama-3.2-1b');
await clearCache();
```

## Camera Utilities

Capture and preprocess camera frames for vision pipelines.

```typescript
import { CameraUtils } from '@edgeveda/web';

const camera = new CameraUtils({ facingMode: 'environment', width: 640, height: 480 });
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
import { PerfTrace } from '@edgeveda/web';

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

Structured error codes from the C/WASM core.

```typescript
import { NativeErrorCode, isRecoverable } from '@edgeveda/web';

try {
  await ai.generate({ prompt: 'test' });
} catch (e) {
  const code = NativeErrorCode.fromError(e);
  console.log(`Error ${code.code}: ${code.message} (domain: ${code.domain})`);
  console.log(`Recoverable: ${isRecoverable(code)}`);
}
```

## Architecture

| Component | File | Description |
|-----------|------|-------------|
| EdgeVeda | `index.ts` | Main SDK entry point |
| Types | `types.ts` | Core type definitions |
| Worker | `worker.ts` | Web Worker inference engine |
| WasmLoader | `wasm-loader.ts` | WASM module loader |
| ModelCache | `model-cache.ts` | IndexedDB model caching |
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
| ModelRegistry | `ModelRegistry.ts` | Model discovery and metadata |
| CameraUtils | `CameraUtils.ts` | Camera capture and preprocessing |
| PerfTrace | `PerfTrace.ts` | Performance tracing |
| NativeErrorCode | `NativeErrorCode.ts` | Structured native error codes |

## Browser Requirements

### WebGPU Mode (Recommended)
- Chrome 113+ / Edge 113+ / Safari 18+ / Firefox (experimental)

### WASM Mode (Fallback)
- Any modern browser with WebAssembly support
- SharedArrayBuffer support for multi-threading (requires COOP/COEP headers)

## License

MIT