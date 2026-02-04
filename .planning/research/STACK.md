# Technology Stack: Flutter iOS On-Device LLM Inference

**Project:** Edge Veda SDK - Flutter iOS
**Researched:** 2026-02-04
**Overall Confidence:** MEDIUM (WebSearch/WebFetch unavailable; based on training data with version verification needed)

## Executive Summary

This document provides technology recommendations for integrating llama.cpp with Flutter on iOS for on-device LLM inference. The stack leverages the existing C++ core scaffolding and Flutter FFI bindings already in place, focusing on the specific integration approach for iOS with Metal GPU acceleration.

**Key Recommendation:** Use llama.cpp as a git submodule compiled with Metal support, accessed via Dart FFI with the existing `ffi` package. The Flutter plugin should bundle a pre-compiled XCFramework for iOS deployment.

---

## Recommended Stack

### Core Inference Engine

| Technology | Version | Purpose | Confidence | Rationale |
|------------|---------|---------|------------|-----------|
| llama.cpp | b4695 or later | LLM inference engine | MEDIUM | Primary inference engine with excellent Metal support. Version b4695+ recommended for stable Metal implementation. **VERIFY: Check llama.cpp releases for latest stable tag.** |
| GGUF | v3 format | Model format | HIGH | Native llama.cpp format, supports quantization metadata. Llama 3.2 1B available in GGUF. |
| Metal | iOS 13.0+ | GPU acceleration | HIGH | Apple's GPU framework, required for >15 tok/sec target on iPhone. |

### Flutter Integration

| Technology | Version | Purpose | Confidence | Rationale |
|------------|---------|---------|------------|-----------|
| ffi | ^2.1.0 | Dart FFI bindings | HIGH | Already in pubspec.yaml. Standard for calling C code from Dart. |
| ffigen | ^11.0.0 | Generate FFI bindings | MEDIUM | In dev_dependencies. Consider manual bindings for control over async patterns. **VERIFY: Check if ffigen ^14.0.0 is available with better async support.** |
| path_provider | ^2.1.0 | File system access | HIGH | Already in pubspec.yaml. Required for model storage paths. |
| http | ^1.2.0 | Model download | HIGH | Already in pubspec.yaml. For downloading GGUF models. |
| crypto | ^3.0.3 | Checksum validation | HIGH | Already in pubspec.yaml. SHA256 validation for model integrity. |

### Build System

| Technology | Version | Purpose | Confidence | Rationale |
|------------|---------|---------|------------|-----------|
| CMake | 3.15+ | C++ build system | HIGH | Already configured in core/CMakeLists.txt. |
| Xcode | 15+ | iOS builds | HIGH | Required for Metal compilation and iOS deployment. |
| CocoaPods | Latest | iOS dependency management | HIGH | Flutter iOS plugins use CocoaPods by default. Podspec exists. |

### iOS Platform Requirements

| Requirement | Value | Rationale |
|-------------|-------|-----------|
| iOS Deployment Target | 13.0 | Metal Performance Shaders available, broad device support |
| Architectures | arm64 only | Exclude i386, armv7; all recent iPhones are 64-bit |
| Bitcode | Disabled | llama.cpp incompatible with bitcode; Apple deprecated anyway |
| Swift Version | 5.0+ | For plugin bridge code if needed |

---

## llama.cpp Integration Approach

### Submodule Strategy (Recommended)

**Confidence: HIGH** - This is the standard approach used by llama.cpp wrappers.

```
core/
  third_party/
    llama.cpp/          # Git submodule
      CMakeLists.txt
      ggml/
      src/
      include/
```

**Setup:**
```bash
cd core
git submodule add https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
git submodule update --init --recursive
```

### CMake Configuration for iOS Metal

**Confidence: MEDIUM** - Based on llama.cpp CMake patterns. **VERIFY exact flags with current llama.cpp.**

The existing `core/CMakeLists.txt` already has the structure. Key additions needed:

```cmake
# In core/CMakeLists.txt, modify the llama.cpp section:

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp/CMakeLists.txt")
    # Disable components we don't need
    set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

    # Enable Metal for iOS/macOS
    if(IOS OR MACOS)
        set(GGML_METAL ON CACHE BOOL "" FORCE)
        set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)  # Embed Metal shaders
    endif()

    # BLAS acceleration (Accelerate framework on Apple)
    if(APPLE)
        set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    endif()

    add_subdirectory(third_party/llama.cpp)
    set(LLAMA_CPP_AVAILABLE TRUE)
endif()
```

### iOS-Specific Build Flags

**Confidence: MEDIUM** - Standard iOS cross-compilation flags.

```cmake
# iOS cross-compilation in core/CMakeLists.txt
if(IOS)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "")
    set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
    set(CMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE NO)  # Critical: llama.cpp doesn't support bitcode

    # arm64 only for iOS
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "")

    # Required frameworks
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(ACCELERATE_FRAMEWORK Accelerate REQUIRED)
endif()
```

---

## Flutter FFI Approach

### dart:ffi vs ffigen Decision

**Recommendation: Manual bindings with dart:ffi**

**Confidence: MEDIUM** - Based on the existing code patterns.

| Approach | Pros | Cons |
|----------|------|------|
| **ffigen (auto-generated)** | Less manual code, keeps in sync with header | Limited control over async, larger output, may include unused functions |
| **Manual dart:ffi** | Full control, cleaner API, better async patterns | Must maintain manually, sync issues possible |

The existing `bindings.dart` uses manual bindings, which is appropriate for this project because:
1. The C API is stable and well-defined
2. We need careful control over async patterns for streaming
3. We want a clean Dart API surface

### Async Pattern for Inference

**Critical:** LLM inference is blocking and takes seconds. Must not block Dart's UI thread.

**Confidence: HIGH** - Standard pattern for long-running FFI operations.

**Option 1: Isolate with dart:ffi (Recommended)**
```dart
// In edge_veda_impl.dart
Future<String> generate(String prompt) async {
  return await Isolate.run(() {
    // This runs in a separate isolate
    final result = _bindings.ev_generate(
      _context,
      prompt.toNativeUtf8(),
      ffi.nullptr,  // use defaults
      resultPtr,
    );
    // ... handle result
  });
}
```

**Option 2: Native Callbacks**
More complex, requires setting up native-to-Dart callbacks. Not recommended for v1.

### Streaming Implementation

**Confidence: MEDIUM** - This is the trickier part.

For streaming, use a polling approach with yields:

```dart
Stream<String> generateStream(String prompt) async* {
  final stream = _bindings.ev_generate_stream(_context, ...);

  while (_bindings.ev_stream_has_next(stream)) {
    // Poll in isolate to avoid blocking
    final token = await Isolate.run(() {
      return _bindings.ev_stream_next(stream, ffi.nullptr);
    });

    if (token != ffi.nullptr) {
      yield token.toDartString();
      _bindings.ev_free_string(token);
    }
  }

  _bindings.ev_stream_free(stream);
}
```

---

## iOS Deployment Considerations

### XCFramework Bundling

**Confidence: HIGH** - Standard approach for Flutter iOS plugins with native code.

The podspec already references `EdgeVedaCore.xcframework`. Build process:

```bash
# Build for iOS device
cmake -B build-ios-device \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
  -DPLATFORM=OS64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  core

cmake --build build-ios-device --config Release

# Build for iOS simulator (arm64 for Apple Silicon Macs)
cmake -B build-ios-sim \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
  -DPLATFORM=SIMULATORARM64 \
  core

cmake --build build-ios-sim --config Release

# Create XCFramework
xcodebuild -create-xcframework \
  -library build-ios-device/libedge_veda.a -headers core/include \
  -library build-ios-sim/libedge_veda.a -headers core/include \
  -output flutter/ios/Frameworks/EdgeVedaCore.xcframework
```

### Code Signing

**Confidence: HIGH** - Standard iOS requirements.

- Library is unsigned (`.a` or `.xcframework`)
- Signing happens during app build
- No special entitlements required for on-device inference
- App Store allows on-device ML (Apple encourages it)

### App Store Guidelines

**Confidence: MEDIUM** - Based on Apple's published guidelines, but always verify current state.

| Concern | Status | Notes |
|---------|--------|-------|
| On-device ML | Allowed | Apple promotes on-device ML for privacy |
| Model download at runtime | Allowed | Use On-Demand Resources or direct download |
| Binary size | Check | Apple has soft limits (~200MB warning, ~4GB hard limit) |
| Metal usage | Allowed | Standard GPU framework |
| Background processing | Limited | iOS backgrounding rules apply; inference should be foreground |

### Memory Management

**Confidence: HIGH** - Critical for iOS stability.

iOS memory limits (approximate):
- 4GB device (iPhone 11): ~1.5GB available to app
- 6GB device (iPhone 13 Pro): ~3GB available to app
- 8GB device (iPhone 15 Pro): ~5GB available to app

**Llama 3.2 1B memory requirements:**
- Q4_K_M quantization: ~700MB-900MB model
- Context (2048 tokens): ~100-200MB
- Total: ~1GB typical

The existing `memory_guard.cpp` handles this with:
- Real-time memory monitoring via `mach_task_info`
- Pressure callbacks at 90% threshold
- Auto-cleanup triggers

---

## Versions to Verify

**CRITICAL:** These versions are based on training data (cutoff: January 2025). Verify before implementation.

| Component | Stated Version | Verification Method |
|-----------|---------------|---------------------|
| llama.cpp | b4695+ | Check https://github.com/ggml-org/llama.cpp/releases |
| ffi package | ^2.1.0 | Check https://pub.dev/packages/ffi |
| ffigen | ^11.0.0 | Check https://pub.dev/packages/ffigen |
| Flutter | 3.16.0+ | Already in pubspec.yaml, but verify latest stable |
| Xcode | 15+ | Check Apple Developer requirements |

---

## Alternatives Considered

### Inference Engine Alternatives

| Option | Rejected Because |
|--------|------------------|
| **ONNX Runtime** | Heavier binary, less optimized for LLMs, no native GGUF support |
| **TensorFlow Lite** | Not designed for generative LLMs, conversion complexity |
| **MLX** | Apple Silicon Mac only, not iOS |
| **Custom implementation** | Unnecessary when llama.cpp exists and is battle-tested |

### FFI Alternatives

| Option | Rejected Because |
|--------|------------------|
| **Method channels** | Too slow for high-frequency token streaming |
| **Platform channels** | Extra indirection, adds Swift/ObjC layer |
| **WASM** | Not for native mobile; reserved for web target |

### Build System Alternatives

| Option | Rejected Because |
|--------|------------------|
| **Bazel** | Overkill for this project, CMake already set up |
| **Meson** | Less iOS toolchain support than CMake |
| **Manual Xcode project** | Hard to maintain, CMake generates Xcode projects |

---

## What NOT to Use

| Anti-Pattern | Why to Avoid |
|--------------|--------------|
| **Bitcode enabled** | llama.cpp assembly optimizations incompatible; Apple deprecated bitcode anyway |
| **i386/armv7 architectures** | No recent iOS devices use these; wastes build time |
| **Synchronous FFI on main thread** | Will freeze UI during inference (seconds) |
| **Large context sizes (>4096)** | Memory explosion on mobile; 2048 is safe default |
| **mlock on iOS** | iOS doesn't support locking memory; will silently fail |
| **Background inference** | iOS will terminate app; foreground only for v1 |

---

## Installation Summary

```bash
# Core dependencies (already in pubspec.yaml)
# No additional packages needed for v1

# Build tools required:
# - Xcode 15+
# - CMake 3.15+
# - CocoaPods (comes with Flutter)

# Development setup:
cd core
git submodule add https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
git submodule update --init --recursive
```

---

## Confidence Assessment Summary

| Area | Confidence | Reason |
|------|------------|--------|
| llama.cpp as engine | HIGH | Industry standard for on-device LLM, excellent Metal support |
| Git submodule approach | HIGH | Standard pattern, used by many llama.cpp wrappers |
| dart:ffi for FFI | HIGH | Already in use, appropriate for this use case |
| CMake build flags | MEDIUM | Based on llama.cpp patterns; exact flags need verification |
| Specific versions | LOW | Training data is potentially stale; verify all versions |
| iOS memory limits | MEDIUM | Approximate; varies by iOS version and device state |
| App Store acceptance | MEDIUM | Policy can change; Apple generally supports on-device ML |

---

## Sources

**Note:** WebSearch and WebFetch were unavailable during research. The following sources should be consulted for verification:

- llama.cpp repository: https://github.com/ggml-org/llama.cpp
- llama.cpp releases: https://github.com/ggml-org/llama.cpp/releases
- Dart ffi package: https://pub.dev/packages/ffi
- Dart ffigen package: https://pub.dev/packages/ffigen
- Apple Metal documentation: https://developer.apple.com/metal/
- Flutter FFI documentation: https://docs.flutter.dev/development/platform-integration/c-interop
- Apple App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

---

## Roadmap Implications

Based on this stack research:

1. **Phase 1: llama.cpp Integration**
   - Add llama.cpp as submodule
   - Update CMakeLists.txt with Metal flags
   - Build XCFramework for iOS
   - **Risk:** CMake configuration may need iteration

2. **Phase 2: FFI Implementation**
   - Complete FFI bindings in bindings.dart
   - Implement Isolate-based async patterns
   - Wire up streaming
   - **Risk:** Async patterns need careful testing

3. **Phase 3: Model Management**
   - Download GGUF model on first use
   - Checksum validation
   - Storage in app documents
   - **Risk:** Model size (~700MB) affects download time

4. **Phase 4: Memory Safety**
   - Integrate memory_guard with llama.cpp
   - Test on 4GB devices
   - **Risk:** Edge cases under memory pressure

**Recommended order:** 1 -> 2 -> 3 -> 4 (dependencies cascade)
