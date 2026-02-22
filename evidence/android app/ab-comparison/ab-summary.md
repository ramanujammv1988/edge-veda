# Android Performance Metrics — On-Device AI Inference

**Device**: OnePlus 6 (ONEPLUS A6000), Snapdragon 845 (SDM845), 8GB RAM
**Android**: 11 (API 30)
**SDK Version**: 2.4.0
**Date**: 2026-02-22
**Backend**: CPU-only (Vulkan 1.0.49 < ggml-vulkan 1.2 required)

## Text Generation

**Model**: Llama 3.2 1B Q4_K_M (~770MB)

| Run | TTFT (ms) | tok/s | Notes |
|-----|-----------|-------|-------|
| 1 | ~60,000 | ~2 | First load, cold start |
| 2 | ~50,000 | ~2.5 | Warm, model cached in memory |
| 3 | ~45,000 | ~3 | Multi-turn, context warm |
| 4 | ~55,000 | ~2 | After background/foreground cycle |
| 5 | ~50,000 | ~2.5 | Sustained session |

**Mean TTFT**: ~52,000ms (~52s)
**Mean tok/s**: ~2.4 tok/s

## All Capabilities Performance

| Capability | Model | Inference Time | Status |
|-----------|-------|---------------|--------|
| Text Gen | Llama 3.2 1B Q4_K_M | TTFT ~52s, ~2.4 tok/s | Working |
| Vision | SmolVLM2 500M Q8_0 | ~281s per 320x240 frame | Working (manual capture) |
| STT | Whisper Tiny EN | ~55-70s per 3s chunk | Working |
| Image Gen | SD v2.1 Turbo Q8_0 | 1280.5s per 256x256 image (1 step) | Working (very slow on CPU) |

## Soak Test (20-min sustained vision inference)

| Metric | Value |
|--------|-------|
| Duration | 20 minutes |
| Frames processed | 2 |
| Avg latency | 217,250ms |
| Last latency | 95,549ms |
| Memory (start) | 1,019 MB RSS |
| Memory (end) | 1,042 MB RSS |
| Memory leak | None detected |
| Battery drain | 4% (100% → 96%) |
| Thermal | Serious (no throttling crash) |
| Budget violations | 0 |

## Resource Usage

| Metric | Value |
|--------|-------|
| Peak RSS (text) | ~1,042 MB |
| Peak RSS (SD image gen) | ~2,600 MB |
| CPU utilization (inference) | 400-440% (all 8 cores) |
| GC activity | 10-30 MB freed per cycle |

## Notes

- All inference is CPU-only — no GPU/NPU acceleration available
- Vulkan 1.0.49 detected but ggml-vulkan requires 1.2+, so Vulkan backend not used
- Device temperature rises during sustained inference but no throttling observed
- 8GB RAM is sufficient for all capabilities including SD image generation (peak RSS ~2.6GB)
- SD image gen works but is impractical for interactive use (~21 min/image on CPU)
- Background/foreground transitions handled cleanly (no crash)
- A/B comparison vs raw llama.cpp not performed (out of scope for this cycle)
