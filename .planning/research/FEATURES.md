# Features Research

## Hardware Acceleration
**Table Stakes:**
- Metal GPU acceleration on iOS (100% layer offload).
- Vulkan GPU acceleration on Android (modern devices).
- CPU fallback (essential for compatibility).

**Differentiators:**
- Auto-tuning `n_gpu_layers` based on available VRAM (prevents OOM).
- NNAPI fallback for older Android devices.
- Shader caching (avoids "jank" on first run).

## Native SDKs
**Table Stakes:**
- Initialization (load model).
- Text generation (streaming).
- Chat session management (history).

**Differentiators:**
- **Zero-Copy Audio**: Passing PCM data without duplication (critical for STT).
- **Lifecycle Awareness**: Auto-free resources when UI destroys.
- **React Native JSI**: Synchronous inference (no bridge overhead).

## Low Latency (TTFT)
**Table Stakes:**
- Pre-computed prompting (not applicable for dynamic chat).

**Differentiators:**
- **mmap loading**: Instant startup (OS manages paging).
- **KV-Cache Quantization**: Reduces memory bandwidth bottleneck.
- **Token streaming**: Instant feedback to user.
