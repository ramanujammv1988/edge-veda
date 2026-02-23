# Benchmarks

All numbers measured on physical devices with Metal GPU enabled. No cherry-picking — these are sustained, real-world measurements from automated soak tests and manual UAT sessions.

**Platforms tested:**
- **iOS:** iPhone (A16 Bionic, 6 GB RAM, iOS 26.2.1)
- **macOS:** MacBook Pro (M1 Max, 32 GB Unified Memory, macOS 26.2)

---

## Text Generation

| Metric | Value | Conditions |
|--------|-------|------------|
| **Throughput** | 42–43 tok/s | Llama 3.2 1B Q4_K_M, 2048 ctx, Metal GPU |
| **TTFT** | <500 ms | First token latency, warm model |
| **Memory (steady state)** | 400–550 MB | KV cache Q8_0 + flash attention |
| **Context window** | 2048 tokens | Configurable up to model limit |
| **Multi-turn stability** | No degradation | 10+ turns, auto-summarization at 70% context |

## Vision (Continuous Inference)

Sustained soak tests — not single-frame burst benchmarks.

### iOS (iPhone, A16 Bionic)

| Metric | Value | Conditions |
|--------|-------|------------|
| **Duration** | 12.6 min | Continuous camera scanning |
| **Frames processed** | 254 | Drop-newest backpressure on FrameQueue |
| **Throughput** | 37.2 frames/min | ~0.6 FPS sustained |
| **p50 latency** | 1,412 ms | End-to-end (encode + prompt eval + decode) |
| **p95 latency** | 2,283 ms | |
| **p99 latency** | 2,597 ms | |
| **Mean latency** | 1,505 ms | |
| **Crashes** | 0 | |
| **Model reloads** | 0 | Persistent VisionWorker isolate |
| **Model** | SmolVLM2-500M | 417 MB model + 190 MB mmproj |

### macOS (MacBook Pro, M1 Max)

| Metric | Value | Conditions |
|--------|-------|------------|
| **Duration** | 30 min | Continuous screen capture |
| **Frames processed** | 357 | Drop-newest backpressure on FrameQueue |
| **Throughput** | 18.1 frames/min | ~0.3 FPS sustained |
| **p50 latency** | 3,184 ms | End-to-end (CLIP encode + prompt eval + decode) |
| **p95 latency** | 4,286 ms | |
| **p99 latency** | 6,354 ms | |
| **Mean latency** | 3,316 ms | |
| **CLIP encode** | 2,957 ms avg | 89% of total latency (bottleneck) |
| **Text generation** | 360 ms avg | 210 ms p50 |
| **RSS (steady state)** | 6,497–6,625 MB | Stable, no memory growth |
| **Thermal** | Nominal | No throttling over 30 min |
| **Battery drain** | 30% over 30 min | 71% → 41% on battery |
| **Crashes** | 0 | |
| **Model reloads** | 0 | Persistent VisionWorker isolate |
| **Model** | Qwen2-VL 7B | 4.5 GB model + 892 MB mmproj (Q4_K_M) |

## Speech-to-Text

| Metric | Value | Conditions |
|--------|-------|------------|
| **Transcription latency (p50)** | ~670 ms | Per 3-second audio chunk |
| **First chunk latency** | ~2,200 ms | Includes Metal shader compilation |
| **Audio format** | 16 kHz mono | Downsampled from 48 kHz native |
| **Chunk size** | 3 seconds | 48,000 samples per chunk |
| **Streaming** | Real-time | Segments emitted as processed |
| **Model** | whisper-tiny.en | 77 MB (F16) |

## Retrieval-Augmented Generation (RAG)

Two-model architecture: dedicated embedder + generator. Hybrid search combines vector similarity with BM25 full-text search via Reciprocal Rank Fusion (RRF).

| Metric | Value | Conditions |
|--------|-------|------------|
| **Generation speed** | 42–43 tok/s | Llama 3.2 1B Q4_K_M |
| **Vector search** | <1 ms | HNSW index, cosine similarity |
| **BM25 text search** | <1 ms | FtsIndex, pure Dart |
| **Fusion** | Reciprocal Rank Fusion | k=60, normalized scores |
| **End-to-end retrieval** | 305–865 ms | Embed query + hybrid search + context injection |
| **Embedding model** | all-MiniLM-L6-v2 | 46 MB, 384 dimensions |
| **Index type** | HNSW + BM25 | Pure Dart, JSON-persistent |

## Function Calling

| Metric | Value | Conditions |
|--------|-------|------------|
| **Tool chain rounds** | Up to 3 | Configurable maxToolRounds |
| **Grammar enforcement** | GBNF sampler | Constrains output to valid JSON |
| **Model** | Qwen3-0.6B Q4_K_M | 524 MB, Hermes-style tool format |

## Memory

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **KV cache** | ~64 MB (F16) | ~32 MB (Q8_0) | 50% reduction |
| **getMemoryStats()** | +600 MB spike | 0 MB overhead | Eliminated double-load |
| **Steady-state (chat)** | ~1,200 MB peak | 400–550 MB | ~55% reduction |
| **Quality impact** | — | None observed | Q8_0 negligible degradation |

## Model Sizes

### Mobile (iOS)

| Model | Size | Quantization | Use Case |
|-------|------|--------------|----------|
| Llama 3.2 1B Instruct | 668 MB | Q4_K_M | General chat |
| Qwen3-0.6B | 524 MB | Q4_K_M | Tool calling |
| SmolVLM2-500M | 417 + 190 MB | Q8_0 + F16 | Vision |
| all-MiniLM-L6-v2 | 46 MB | F16 | Embeddings |
| whisper-tiny.en | 77 MB | F16 | Speech-to-text |

### Desktop (macOS)

| Model | Size | Quantization | Use Case |
|-------|------|--------------|----------|
| Llama 3.2 1B Instruct | 668 MB | Q4_K_M | General chat |
| Qwen3-0.6B | 524 MB | Q4_K_M | Tool calling |
| Qwen2-VL 7B | 4.5 GB + 892 MB | Q4_K_M + F16 | Vision |
| all-MiniLM-L6-v2 | 46 MB | F16 | Embeddings |
| whisper-tiny.en | 77 MB | F16 | Speech-to-text |

## SDK & Binary Size

| Component | Size | Platform |
|-----------|------|----------|
| XCFramework (per arch) | ~8.1 MB | iOS |
| Static library (arm64) | ~8.3 MB | macOS |
| Flutter package | ~1.4 MB | All |
| C API surface | 48 functions | All |

## Runtime Supervision

Validated under sustained thermal pressure:

| Metric | Value |
|--------|-------|
| Thermal adaptation | 4-level QoS (full → reduced → minimal → paused) |
| Recovery cooldown | 60s per level (3 min full recovery) |
| Budget enforcement cycle | 2 seconds |
| Soak test thermal peak | Critical (state 3) — recovered without crash |
| Battery drain tracking | Rolling 10-min window |
| Jetsam kills during testing | 0 |

---

## Test Conditions

### iOS

- **Device:** iPhone (A16 Bionic), 6 GB RAM
- **OS:** iOS 26.2.1
- **GPU:** Apple Metal
- **SDK:** Flutter 3.38.9, Dart 3.10.8
- **Build:** Release mode, LTO enabled, 16KB page alignment
- **llama.cpp:** b7952
- **whisper.cpp:** v1.8.3

### macOS

- **Device:** MacBook Pro (M1 Max), 32 GB Unified Memory
- **OS:** macOS 26.2
- **GPU:** Apple Metal (M1 Max, 32-core GPU)
- **SDK:** Flutter 3.41.2, Dart 3.10.8
- **Build:** Debug mode, static library force-loaded
- **llama.cpp:** b7952
- **whisper.cpp:** v1.8.3

## Reproduce

### iOS

```bash
# Build XCFramework
./scripts/build-ios.sh --clean --release

# Run demo app on device
cd flutter/example && flutter run --release
```

### macOS

```bash
# Build static library
./scripts/build-macos.sh --clean --release

# Run demo app
cd flutter/example && flutter run -d macos
```

### Analyze soak tests

Vision soak test traces can be analyzed with:

```bash
python3 tools/analyze_trace.py soak_trace_latest.jsonl
```

Generates p50/p95/p99 stats, throughput charts, thermal overlays, and memory slope analysis.
