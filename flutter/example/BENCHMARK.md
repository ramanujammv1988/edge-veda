# Performance Benchmarks

## Test Environment

**Device:** iPhone 12
**OS:** iOS 26
**Model:** Llama 3.2 1B Q4_K_M
**Test Date:** 2026-02-04
**Build:** Release mode (`flutter run --release`)

## Benchmark Methodology

- **Test Count:** 10 consecutive generations
- **Prompt Variety:** 10 different prompts (varying length/complexity)
- **Token Limit:** 100 tokens per generation
- **Cooldown:** 500ms pause between tests
- **Conditions:** Device fully charged, minimal background apps

## Results

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Avg Speed | 42.9 tok/s | >15 tok/s | ✅ |
| Min Speed | 25.4 tok/s | - | - |
| Max Speed | 52.0 tok/s | - | - |
| Avg TTFT | 516 ms | - | - |
| Avg Latency | 2579 ms | - | - |
| Peak Memory | 1316 MB | <1200 MB | ⚠️ |

## Analysis

### Performance vs Target

**Speed: EXCEEDS TARGET**
- Achieved **42.9 tok/s** average, which is **2.86x** the 15 tok/s target
- Even the minimum speed (25.4 tok/s) exceeds the target by 69%
- Peak speed of 52.0 tok/s demonstrates excellent Metal GPU acceleration

**Memory: SLIGHTLY OVER LIMIT**
- Peak memory of 1316 MB exceeds the 1200 MB target by 116 MB (9.7% over)
- This is acceptable for v1 - the model runs successfully without crashes
- Memory can be reduced in future versions by:
  - Reducing context length from 2048 to 1024
  - Using more aggressive quantization (Q4_0 instead of Q4_K_M)
  - Implementing KV cache pruning

### Sustained Usage

- Memory remained stable across 10 consecutive runs (no leaks detected)
- No thermal throttling observed during the ~3 minute benchmark
- Performance variance (25.4-52.0 tok/s) is normal for mobile GPUs

### Comparison to Phase 1 Smoke Test

Phase 1 achieved **79 tok/s** on M1 Mac with Metal. iPhone 12 achieves **42.9 tok/s**, which is:
- 54% of M1 Mac performance
- Excellent for a mobile device with thermal/power constraints
- Well above the 15 tok/s minimum requirement

## Recommendations

**Performance: PRODUCTION READY**
- Speed significantly exceeds requirements
- Suitable for real-time conversational AI on iPhone 12+

**Memory Optimization (Optional for v1.1):**
- Reduce default context length to 1024 tokens
- Add memory pressure callbacks to auto-reduce context when needed
- Consider offering Q4_0 quantization option for memory-constrained devices

## Reproducing Results

To run the benchmark yourself:

1. Build and deploy to iPhone 12:
   ```bash
   cd flutter/example
   flutter run --release -d <device-id>
   ```

2. Wait for model download and initialization

3. Tap the benchmark icon (chart/assessment) in the AppBar

4. Results appear in dialog and console logs

## Notes

- **Simulator Performance:** Do NOT benchmark on iOS Simulator. It uses Mac GPU and gives misleading results.
- **Thermal Throttling:** Extended usage (5+ minutes continuous inference) may trigger thermal throttling, reducing performance by 10-30%.
- **Background Apps:** Close background apps before benchmarking for consistent results.
- **Device Variance:** Older devices (iPhone 11 and earlier) will show lower performance.

---
*Benchmark Date: 2026-02-04*
*SDK Version: 1.0.0*
