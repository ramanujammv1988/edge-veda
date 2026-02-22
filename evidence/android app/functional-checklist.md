# Functional Checklist — Android Device Testing

**Tester**: Claude Code (automated) + manual verification
**Device Model**: OnePlus 6 (ONEPLUS A6000), Snapdragon 845 (SDM845), 8GB RAM
**Android Version**: 11 (API 30)
**Date**: 2026-02-22
**Branch**: feature/android-sdk-testing
**Commit**: 92ba146 + local fixes
**GPU**: Adreno 630, Vulkan 1.0.49 (below ggml-vulkan 1.2 requirement) — CPU-only

## Pre-conditions

- [x] Device connected via USB, USB debugging enabled
- [x] App installed and launched without crash
- [x] Model downloaded successfully (Llama 3.2 1B Q4_K_M, ~770MB)

## Core Functionality

- [x] **Text Inference**: Chat screen generates streaming text responses
  - TTFT: ~45-60s (CPU-only), streaming tokens at ~2-3 tok/s
  - Multi-turn conversations work (3+ turns tested)
  - Streaming timeout increased from 30s to 600s for CPU
  - Persona selection functional (Assistant, Expert, Creative, Analytical)
  - Cancel mid-stream via stop button works

- [x] **Vision**: Vision tab processes camera frame
  - SmolVLM2 500M Q8_0 model + Q8_0 mmproj loaded successfully
  - Manual capture mode on Android (CPU too slow for continuous scanning)
  - 320x240 frame described in 281s (~4.7 min): "A smartphone is placed on a floral-patterned bed. The phone is black"
  - YUV420→RGB conversion for Android camera format works correctly
  - "Describe What I See" button with elapsed timer UI

- [x] **STT**: Speech-to-text records and transcribes audio
  - Whisper Tiny EN model (~77MB) loaded successfully
  - 16kHz PCM audio capture via AudioRecord (Kotlin plugin)
  - 3s audio chunks transcribed in ~55-70s on CPU
  - Successfully transcribed: "Hello, let's see if you can work."
  - Processing indicator shows during chunk transcription
  - Session reuse pattern prevents native thread accumulation

- [x] **Image Generation**: Stable Diffusion generates an image (VERY SLOW on CPU)
  - SD v2.1 Turbo Q8_0 model (~2.3GB) downloaded successfully from gpustack repo
  - Model loads into memory (status "Loaded" shown, RSS ~2.6GB)
  - Generation successful at 256x256, 1 step: **1280.5 seconds (~21.3 minutes)**
  - Prompt "cat with hat" → generated recognizable image of a cat wearing a blue hat
  - Peak memory during generation: ~2.6GB RSS, 414-440% CPU utilization (all 8 cores)
  - Default size reduced from 512x512 to 256x256 for CPU-only devices
  - **Note**: Impractical for interactive use on CPU (~21 min/image) — GPU required for production
  - Download URL fix: old stabilityai URL was 404, fixed to gpustack/stable-diffusion-v2-1-turbo-GGUF
  - Screenshot saved: evidence/android app/image_gen_result.png

- [x] **Settings**: Backend display shows correct value
  - Shows "CPU" (correctly detects Vulkan 1.0 < required 1.2)
  - Version displays "2.1.2" (fixed from hardcoded 1.1.0)
  - Device info: OnePlus A6000, SDM845, 8GB RAM, no neural engine

## Vulkan GPU Verification

- [x] Vulkan 1.0.49 detected but below ggml-vulkan 1.2 requirement
- [x] Settings screen correctly shows "CPU" (not "Vulkan GPU") after fix
- [x] CPU inference runs without crash (all capabilities tested)
- N/A: `ggml_vulkan_init` not expected (Vulkan backend not compiled for Windows cross-compilation)

## Stability

- [x] App survives background/foreground cycle (tested multiple times)
- [x] No crash during extended session (2+ hours)
- [x] Multiple inference calls complete without error
  - Text: 5+ messages across multiple conversations
  - STT: 5+ recording sessions, multiple chunks transcribed
  - Vision: multiple capture attempts, successful description
- [x] Soak test runs without crash (20 min managed vision benchmark)
  - 2 frames processed, avg latency 217,250ms, last latency 95,549ms
  - Memory RSS stable at ~1019-1042 MB (no leaks)
  - Thermal: Serious (sustained CPU load), no throttling-induced crash
  - Battery drain: 4% over 20 minutes (100% → 96%)
  - QoS adapted to "minimal" due to thermal pressure
  - 0 actionable budget violations
  - Screenshot: evidence/android app/soak_test_complete.png

## Performance Observations

- **Backend**: CPU-only (Vulkan 1.0.49 < 1.2 required)
- **Text inference**: TTFT ~45-60s, ~2-3 tok/s (Llama 3.2 1B Q4_K_M)
- **STT inference**: ~55-70s per 3s audio chunk (Whisper Tiny EN)
- **Vision inference**: ~281s per 320x240 frame (SmolVLM2 500M Q8_0)
- **Image gen inference**: 1280.5s (~21.3 min) per 256x256 image, 1 step (SD v2.1 Turbo Q8_0)
- **Memory**: Heavy GC activity during inference (10-30MB freed per cycle)
- **Peak RSS**: ~2.6GB during SD image generation
- **Thermal**: Device gets warm during extended inference but no throttling observed

## Fixes Applied During Testing

1. **Version display**: 1.1.0 → 2.1.2 (settings_screen.dart)
2. **Backend display**: Changed from any-Vulkan to Vulkan 1.2+ check (EdgeVedaPlugin.kt)
3. **SD model URL**: Fixed 404 URL to gpustack repo (model_manager.dart)
4. **Whisper timeout**: 30s → 120s for CPU (whisper_worker.dart)
5. **Vision timeout**: 30s → 600s for CPU (vision_worker.dart)
6. **Text streaming timeout**: 120s → 600s for CPU (worker_isolate.dart)
7. **STT session reuse**: Prevents native thread accumulation (stt_screen.dart)
8. **Vision manual capture**: Replaces continuous scanning on CPU (vision_screen.dart)
9. **Vision Q8_0 mmproj**: Faster than F16 on CPU (model_manager.dart)
10. **STT processing indicator**: Shows chunk processing state (whisper_session.dart)
11. **Image default size**: 512x512 → 256x256 for CPU-only devices (image_screen.dart)

## Models on Device

| Model | File | Size | Capability |
|-------|------|------|------------|
| Llama 3.2 1B Q4_K_M | llama-3.2-1b-instruct-q4.gguf | 770MB | Text generation |
| SmolVLM2 500M Q8_0 | smolvlm2-500m-video-instruct-q8.gguf | 417MB | Vision (VLM) |
| SmolVLM2 mmproj F16 | smolvlm2-500m-mmproj-f16.gguf | 190MB | Vision projector |
| SmolVLM2 mmproj Q8_0 | smolvlm2-500m-mmproj-q8.gguf | 104MB | Vision projector (CPU-optimized) |
| Whisper Tiny EN | whisper-tiny-en.bin | 74MB | Speech-to-text |
| SD v2.1 Turbo Q8_0 | sd-v2-1-turbo-q8.gguf | 2.1GB | Image generation |
| **Total** | | **~3.6GB** | |

## Code Quality

- **Flutter tests**: 23/23 passed (0 failures)
- **Dart analyze**: 0 errors, 2 warnings (unused field, unused element), 103 infos (print statements, const suggestions)
- **Build**: Debug APK builds successfully with CMake native library

## Screenshots

- `screen.png` through `screen9.png`: Various app screens during testing
- `screen-imagegen-oom.png`: Earlier failed SD generation attempt
- `image_gen_result.png`: Successful "cat with hat" image generation

## Session Duration

- **Start time**: 2026-02-21 09:30 (first session)
- **End time**: 2026-02-22 04:00+ (current session)
- **Total duration**: ~18+ hours across 4 sessions

## Signature

**Tested by** (automated): Claude Code with adb automation
**Verified by** (human): User on-device interaction
**Date**: 2026-02-22
