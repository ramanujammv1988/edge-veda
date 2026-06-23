# Edge Veda SDK — Capability × Platform × Device Matrix Review

**Reviewed:** 2026-03-02
**Matrix Version:** v1.0 (as stated in document)
**SDK Version:** v2.4.2 (pub.dev)
**Reviewer:** SDK Team

---

## Executive Summary

The matrix is a well-structured React component covering 8 capability categories, 3 platforms (macOS/iOS/Android), 3 device tiers each (FLOOR/MID/HIGH), with priority tagging (P0–P2) and interactive filters. However, **4 critical inaccuracies** will mislead testers into validating features that don't exist in the current build. These must be fixed before sharing with the QA team.

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 4 | Must fix before distribution |
| Important | 4 | Should fix for accuracy |
| Minor | 4 | Nice to fix |

---

## Critical Issues

### C1. TTS engine is wrong — "Kokoro-82M" does not exist

| Field | Matrix Claims | Codebase Reality |
|-------|-------------|------------------|
| Engine | Kokoro-82M | AVSpeechSynthesizer (iOS/macOS), **nothing on Android** |
| iOS support | Green all tiers | Correct — AVSpeechSynthesizer works on all iOS devices |
| Android support | Green all tiers | **Wrong** — zero Android TTS code exists |

**Evidence:**
- `grep -r Kokoro` → 0 matches across entire repo
- `grep -r TextToSpeech` (Android API) → 0 matches
- iOS implementation: `flutter/ios/Classes/EdgeVedaPlugin.m:213` → `AVSpeechSynthesizer`
- macOS implementation: `flutter/macos/Classes/EdgeVedaPlugin.swift:197` → `AVSpeechSynthesizer`

**Fix:** Rename to "Platform TTS (AVSpeechSynthesizer)". Mark all Android TTS rows as red (not implemented).

---

### C2. Vulkan shown as green — actually compiled out (OFF)

| Field | Matrix Claims | Codebase Reality |
|-------|-------------|------------------|
| `llm_gpu` Android | Green "Vulkan" all tiers | `EDGE_VEDA_ENABLE_VULKAN=OFF` |
| `hw_vulkan` Android | Green Mali/Exynos/Adreno | Scaffolded but compiled out |

**Evidence:**
- `core/CMakeLists.txt:29` → `option(EDGE_VEDA_ENABLE_VULKAN "..." OFF)` with comment: *"CPU-only, Vulkan deferred to Phase 7"*
- `scripts/build-android.sh:159` → `-DEDGE_VEDA_ENABLE_VULKAN=OFF`
- `flutter/android/build.gradle:63` → `-DEDGE_VEDA_ENABLE_VULKAN=OFF`
- `core/src/engine.cpp:234` → Vulkan path behind `#ifdef EDGE_VEDA_VULKAN_ENABLED` (never defined)
- `README.md:642` → `| Android (Vulkan) | -- | Planned |`
- GitHub PRs: Zero Vulkan PRs (open or merged)

**Note:** Vulkan infrastructure is scaffolded (`link_vulkan()` helper in `android.toolchain.cmake`, backend enum in `engine.cpp`), but the `EDGE_VEDA_VULKAN_ENABLED` define is never set in any build configuration.

**Fix:** Mark `llm_gpu` Android as red ("CPU fallback, Vulkan Phase 7"). Mark `hw_vulkan` as yellow ("scaffolded, not active").

---

### C3. NNAPI shown as partial/full — not functionally implemented

| Field | Matrix Claims | Codebase Reality |
|-------|-------------|------------------|
| `hw_nnapi` floor | Yellow "limited" | Compile define only |
| `hw_nnapi` mid | Yellow "partial" | Compile define only |
| `hw_nnapi` high | Green "full" | Compile define only |

**Evidence:**
- `core/cmake/android.toolchain.cmake:117` → `add_compile_definitions(USE_NNAPI=1)` for API 27+
- `core/cmake/android.toolchain.cmake:149` → `link_nnapi()` helper exists (just links `dl`)
- `grep -r ANeuralNetworks` → 0 matches — no actual NNAPI delegation calls in inference path
- No `NeuralNetworksDevice`, `NeuralNetworksCompilation`, or `NeuralNetworksExecution` calls anywhere

**Fix:** Mark all NNAPI rows as red ("scaffolded, no runtime delegation") or remove entirely.

---

### C4. Version shows "v1.0" — current SDK is v2.4.2

**Evidence:** `pubspec.yaml` version and pub.dev listing both show v2.4.2 (2026-02-26).

**Fix:** Update header to `v2.4.2`.

---

## Important Issues

### I1. Android LLM GPU row contradicts build config

The `llm_gpu` row shows green "Vulkan" for all Android tiers. Since Vulkan is OFF, Android LLM inference is CPU-only via `EV_BACKEND_CPU` (`core/src/engine.cpp:240`).

**Fix:** Change Android `llm_gpu` to yellow "CPU fallback" or red "Vulkan not enabled".

---

### I2. Android test devices don't match actual test hardware

| Matrix Tier | Matrix Device | Our Actual Test Device |
|-------------|--------------|----------------------|
| FLOOR | Pixel 6a (Tensor G1, 6GB) | — |
| MID | Galaxy A54 (Exynos 1380, 8GB) | — |
| HIGH | Galaxy S23 (SD 8 Gen 2, 8GB) | — |
| Not listed | — | **OnePlus A6000 (SD845, 6GB)** |

Our only soak-tested Android device (OnePlus A6000, Snapdragon 845) is older than any device in the matrix. The SD845 soak test (`tools/experiments.json`) showed 100% thermal-serious state and 7.44%/10min battery drain.

**Fix:** Either add SD845 as a "LEGACY" tier, or replace FLOOR with OnePlus 6 to match actual test data. At minimum, note that listed devices are *target* devices, not yet tested.

---

### I3. iOS device tier could use refresh for 2026

- FLOOR: iPhone 12 (A14, 4GB) — reasonable but aging
- HIGH: iPhone 15 Pro (A17 Pro) — should this be iPhone 16 Pro given it's 2026?

**Fix:** Consider bumping HIGH to iPhone 16 Pro or adding it as an alternate.

---

### I4. Battery drain shown as green for all Android tiers

Matrix `perf_battery` shows green checkmarks for all Android tiers. Our only empirical data (SD845 soak test) measured **7.44%/10min** — which **failed** the 5%/10min threshold.

**Evidence:** `tools/experiments.json` → `H5_battery: FAIL, 7.44%/10min`

**Fix:** Mark Android FLOOR battery as yellow at minimum. No empirical data exists for MID/HIGH — mark as untested.

---

## Minor Issues

### M1. STT realtime Android FLOOR — understated risk

Matrix shows yellow "VAD tuning" for Android FLOOR real-time STT. Our SD845 soak data shows ~64s per inference frame (`tools/experiments.json` → `p50: 64714ms`). "VAD tuning" undersells the problem.

**Fix:** Change to yellow "CPU-bound, high latency" or "~60s/frame on SD845".

---

### M2. iOS background behavior correctly flagged

`perf_background` shows yellow for all iOS tiers ("iOS kills BG"). This is accurate — iOS aggressively terminates background processes during inference. Good call, no change needed.

---

### M3. Thermal data contradicts matrix for Android

Matrix `perf_thermal` shows yellow for Android FLOOR ("Tensor warm") and MID ("Exynos warm"), green for HIGH. Our SD845 test hit **100% thermal-serious** (`tools/experiments.json` → `H4_thermal: FAIL, serious_pct: 100%`).

**Fix:** Mark Android FLOOR/MID thermal as yellow/red based on actual soak data.

---

### M4. Category filter may be missing from UI

The React component has platform and priority filter buttons visible, but the category filter logic (`activeCategory`) exists in state without clear UI toggle buttons in the rendered JSX. Verify it renders correctly when the component is live.

---

## Corrected Status Matrix (Critical Items Only)

### TTS (corrected)

| Item | macOS | iOS | Android |
|------|-------|-----|---------|
| Platform TTS | AVSpeechSynthesizer | AVSpeechSynthesizer | **Not implemented** |
| Pitch/rate adjust | AVSpeechSynthesizer | AVSpeechSynthesizer | **Not implemented** |

### Hardware Acceleration (corrected)

| Item | macOS | iOS | Android |
|------|-------|-----|---------|
| Metal GPU | Green | Green | N/A |
| Vulkan GPU | N/A | N/A | **Red** (OFF, Phase 7) |
| NNAPI | N/A | N/A | **Red** (scaffolded, no runtime) |
| CPU fallback | Green | Green | Green (only active Android backend) |

### LLM GPU (corrected)

| Item | macOS | iOS | Android |
|------|-------|-----|---------|
| GPU accelerated | Green (Metal) | Green (Metal) | **Red** (Vulkan OFF, CPU-only) |

---

## Recommendation

Fix the 4 critical items before distributing this matrix to testers. A tester following this document as-is would waste time trying to validate Vulkan GPU paths, looking for a Kokoro TTS model, and testing Android TTS — none of which exist in the current build.

After corrections, this is a solid test planning artifact that covers the right capabilities and device tiers.
