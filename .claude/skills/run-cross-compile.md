---
name: run-cross-compile
description: Cross-compile C++ core for specified target platform
allowed-tools: Bash, Read
---

# Cross-Compile for Target

Build the C++ core for the specified target platform.

## Usage
```
/run-cross-compile <target>
```

## Supported Targets

### `ios`
- Architectures: arm64, arm64-simulator, x86_64-simulator
- Toolchain: Xcode + CMake iOS toolchain
- Output: libedge_veda.a (static library)

### `android`
- Architectures: arm64-v8a, armeabi-v7a, x86_64
- Toolchain: Android NDK + CMake
- Output: libedge_veda.so (shared library)

### `macos`
- Architectures: arm64, x86_64
- Toolchain: Xcode + CMake
- Output: libedge_veda.dylib

### `wasm`
- Architecture: wasm32
- Toolchain: Emscripten
- Output: edge_veda.wasm + edge_veda.js

## Build Commands

```bash
# iOS
cmake -B build/ios -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
  -DPLATFORM=OS64
cmake --build build/ios --config Release

# Android
cmake -B build/android \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-26
cmake --build build/android

# WASM
emcmake cmake -B build/wasm
cmake --build build/wasm
```

## Report
After building, report:
1. Build success/failure
2. Binary size (compare against limits)
3. Any compiler warnings
4. Symbols exported
