---
name: benchmark-inference
description: Run inference benchmarks and report performance metrics
allowed-tools: Bash, Read, Write
---

# Benchmark Inference Performance

Run comprehensive benchmarks for the Edge Veda inference engine.

## Usage
```
/benchmark-inference <model> [platform]
```

## Metrics to Measure

### 1. Time to First Token (TTFT)
- Measure from prompt submission to first token output
- Target: <500ms on iPhone 13+

### 2. Tokens Per Second (Throughput)
- Sustained generation speed
- Target: >15 tok/s on mid-range devices

### 3. Peak Memory Usage
- Maximum RAM during inference
- Target: <1.5GB on 4GB devices

### 4. Model Load Time
- Time from init() to ready state
- Target: <3s for 1B models

### 5. Time to First Audio (TTS only)
- Target: <100ms

## Benchmark Script

```cpp
// benchmark.cpp
#include "edge_veda.h"
#include <chrono>

void benchmark(const char* model_path, const char* prompt) {
    auto start = std::chrono::high_resolution_clock::now();

    ev_config config = ev_default_config();
    ev_context* ctx = ev_init(model_path, &config);

    auto load_time = std::chrono::high_resolution_clock::now();
    printf("Load time: %lldms\n", duration_ms(start, load_time));

    ev_stream* stream = ev_generate_stream(ctx, prompt);

    bool first_token = true;
    int token_count = 0;

    while (char* token = ev_stream_next(stream)) {
        if (first_token) {
            auto ttft = std::chrono::high_resolution_clock::now();
            printf("TTFT: %lldms\n", duration_ms(load_time, ttft));
            first_token = false;
        }
        token_count++;
        free(token);
    }

    auto end = std::chrono::high_resolution_clock::now();
    double duration_s = duration_ms(load_time, end) / 1000.0;
    printf("Throughput: %.1f tok/s\n", token_count / duration_s);
    printf("Peak memory: %zu MB\n", ev_get_memory_usage(ctx) / (1024*1024));

    ev_free(ctx);
}
```

## Output Format

```
=== Edge Veda Benchmark ===
Model: llama-3.2-1b-q4
Platform: iOS (iPhone 14 Pro)
Backend: Metal

Load Time:     2.3s    [PASS] (<3s)
TTFT:          387ms   [PASS] (<500ms)
Throughput:    18.2 t/s [PASS] (>15 t/s)
Peak Memory:   1.2GB   [PASS] (<1.5GB)
```
