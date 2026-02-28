# Roadmap

## Phase 1: Foundation (Build System & Scripts) ✓
**Goal:** Establish Android native build chain in the core C++.
**Status:** Complete (2026-02-28) — Verified 7/7 must-haves
**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md -- Polish build-android.sh and add JNI bridge to CMakeLists.txt
- [x] 01-02-PLAN.md -- Align JNI bridge with Kotlin declarations and clean up build.gradle

## Phase 2: Native Android Layer (JNI & Kotlin) ✓
**Goal:** Create the bridge connecting Java/Kotlin Android services to C++ methods.
**Status:** Complete (2026-02-28)
**Plans:** 2 plans

Plans:
- [x] 02-01-PLAN.md -- Expand JNI bridge with whisper STT functions
- [x] 02-02-PLAN.md -- Add telemetry MethodChannel and update build verification

## Phase 3: Flutter Plugin Integration (Dart)
**Goal:** Expose the Android interfaces cleanly back towards Flutter Dart isolates.
- Update `pubspec.yaml` to declare Android platform support
- Wire up Dart FFI for Android (`DynamicLibrary.open` for `.so` files) in `flutter/lib/src/`

## Phase 4: Verification Loop
**Goal:** Prove the stack operates accurately in emulator / physical hardware testing.
- Test initialization parameters (VRAM, memory guards) in emulator CPU backend context.
