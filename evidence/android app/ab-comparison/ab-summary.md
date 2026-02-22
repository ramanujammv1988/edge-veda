# A/B Comparison: Veda Managed vs Raw llama.cpp

**Device**: OnePlus 6 (ONEPLUS A6000), Snapdragon 845 (SDM845), 8GB RAM
**Model**: Llama 3.2 1B Q4_K_M (~770MB)
**Date**: 2026-02-22
**Backend**: CPU-only (Vulkan 1.0.49 < ggml-vulkan 1.2 required)

## Note

Raw llama-cli was not deployed to the device. Only Veda Managed (via the example app) was tested. A/B overhead comparison requires a standalone llama.cpp build for Android, which was out of scope for this testing cycle.

## Veda Managed Results (via app)

| Run | TTFT (ms) | tok/s | Notes |
|-----|-----------|-------|-------|
| 1 | ~60,000 | ~2 | First load, cold start |
| 2 | ~50,000 | ~2.5 | Warm, model cached in memory |
| 3 | ~45,000 | ~3 | Multi-turn, context warm |
| 4 | ~55,000 | ~2 | After background/foreground cycle |
| 5 | ~50,000 | ~2.5 | Sustained session |

**Mean TTFT**: ~52,000ms (~52s)
**Mean tok/s**: ~2.4 tok/s

## Capability Performance Summary

| Capability | Model | Inference Time | Status |
|-----------|-------|---------------|--------|
| Text Gen | Llama 3.2 1B Q4_K_M | TTFT ~52s, ~2.4 tok/s | Working |
| Vision | SmolVLM2 500M Q8_0 | ~281s per 320x240 frame | Working (manual capture) |
| STT | Whisper Tiny EN | ~55-70s per 3s chunk | Working |
| Image Gen | SD v2.1 Turbo Q8_0 | 1280.5s per 256x256 image (1 step) | Working (very slow on CPU) |

## Notes

- All inference is CPU-only — no GPU/NPU acceleration available
- Vulkan 1.0.49 detected but ggml-vulkan requires 1.2+, so Vulkan backend not used
- Heavy GC activity during inference (10-30MB freed per cycle)
- Device temperature rises during sustained inference but no throttling observed
- 8GB RAM is sufficient for all capabilities including SD image generation (peak RSS ~2.6GB)
- SD image gen works but is impractical for interactive use (~21 min/image on CPU)
- Background/foreground transitions handled cleanly (no crash)
