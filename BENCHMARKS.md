# Benchmarks

All numbers measured on a physical iPhone (A16 Bionic, 6GB RAM, iOS 26.2.1) with Metal GPU enabled. No cherry-picking — these are sustained, real-world measurements from automated soak tests and manual UAT sessions.

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

Sustained soak test — not a single-frame burst benchmark.

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

Two-model architecture: dedicated embedder + generator.

| Metric | Value | Conditions |
|--------|-------|------------|
| **Generation speed** | 42–43 tok/s | Llama 3.2 1B Q4_K_M |
| **Vector search** | <1 ms | HNSW index, cosine similarity |
| **End-to-end retrieval** | 305–865 ms | Embed query + search + context injection |
| **Embedding model** | all-MiniLM-L6-v2 | 46 MB, 384 dimensions |
| **Index type** | HNSW | Pure Dart, JSON-persistent |

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

| Model | Size | Quantization | Use Case |
|-------|------|--------------|----------|
| Llama 3.2 1B Instruct | 668 MB | Q4_K_M | General chat |
| Qwen3-0.6B | 524 MB | Q4_K_M | Tool calling |
| SmolVLM2-500M | 417 + 190 MB | Q8_0 + F16 | Vision |
| all-MiniLM-L6-v2 | 46 MB | F16 | Embeddings |
| whisper-tiny.en | 77 MB | F16 | Speech-to-text |

## SDK & Binary Size

| Component | Size |
|-----------|------|
| XCFramework (per arch) | ~8.1 MB |
| Flutter package | ~1.4 MB |
| C API surface | 40 functions |

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

- **Device:** iPhone (A16 Bionic), 6 GB RAM
- **OS:** iOS 26.2.1
- **GPU:** Apple Metal
- **SDK:** Flutter 3.38.9, Dart 3.10.8
- **Build:** Release mode, LTO enabled, 16KB page alignment
- **llama.cpp:** b7952
- **whisper.cpp:** v1.8.3

## Reproduce

```bash
# Build XCFramework
./scripts/build-ios.sh --clean --release

# Run demo app on device
cd flutter/example && flutter run --release
```

Vision soak test traces can be analyzed with:

```bash
python3 tools/analyze_trace.py soak_trace_latest.jsonl
```

Generates p50/p95/p99 stats, throughput charts, thermal overlays, and memory slope analysis.
