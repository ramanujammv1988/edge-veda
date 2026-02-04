# Technology Stack

## Languages

| Language | Version | Location | Purpose |
|----------|---------|----------|---------|
| C++ | C++17 | `core/` | Inference engine core |
| TypeScript | 5.3+ | `web/`, `react-native/` | Web SDK, React Native SDK |
| Dart | 3.0+ | `flutter/` | Flutter SDK |
| Swift | 5.9+ | `swift/` | iOS/macOS SDK |
| Kotlin | 1.9.22 | `kotlin/` | Android SDK |

## Runtimes

| Runtime | Version | Platform |
|---------|---------|----------|
| Node.js | 18.0.0+ | Web SDK development |
| Flutter | 3.16.0+ | Flutter plugin |
| JVM | 17+ | Android SDK (Kotlin) |
| iOS | 15.0+ | Swift SDK |
| macOS | 12.0+ | Swift SDK |
| Android | API 26+ | Kotlin SDK |

## Frameworks

### Core Inference
- **llama.cpp** - LLM inference (integrated via CMake submodule at `third_party/llama.cpp`)
- **whisper.cpp** - STT support (planned)
- **Kokoro-82M** - TTS support (planned)

### Hardware Acceleration
| Backend | Platform | Framework |
|---------|----------|-----------|
| Metal | iOS/macOS | Apple Metal framework |
| Vulkan | Android | Vulkan SDK |
| WebGPU | Web | Browser WebGPU API |
| CPU | All | Fallback (always available) |

### SDK Frameworks
- **Flutter FFI** - `ffi: ^2.1.0`, `ffigen: ^11.0.0`
- **React Native TurboModules** - New Architecture support with codegen
- **Swift Package Manager** - Pure SPM package with C interop
- **Kotlin Coroutines** - `kotlinx-coroutines-core: 1.7.3`

## Key Dependencies

### Web SDK (`web/package.json`)
```json
"devDependencies": {
  "@rollup/plugin-typescript": "^11.1.6",
  "@rollup/plugin-node-resolve": "^15.2.3",
  "@rollup/plugin-commonjs": "^25.0.7",
  "@rollup/plugin-terser": "^0.4.4",
  "rollup": "^4.9.6",
  "typescript": "^5.3.3"
}
```

### React Native (`react-native/package.json`)
```json
"peerDependencies": {
  "react": "*",
  "react-native": ">=0.73.0"
},
"devDependencies": {
  "react-native-builder-bob": "^0.23.2",
  "@react-native-community/eslint-config": "^3.2.0"
}
```

### Android (`kotlin/build.gradle.kts`)
```kotlin
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
implementation("androidx.core:core-ktx:1.12.0")
testImplementation("io.mockk:mockk:1.13.8")
```

### Flutter (`flutter/pubspec.yaml`)
```yaml
dependencies:
  ffi: ^2.1.0
  path_provider: ^2.1.0
  http: ^1.2.0
  crypto: ^3.0.3
dev_dependencies:
  ffigen: ^11.0.0
  flutter_lints: ^3.0.0
```

## Build Tools

| Tool | Version | Purpose |
|------|---------|---------|
| CMake | 3.15+ (3.22.1 for Android) | Core C++ build system |
| Ninja | Latest | CMake generator |
| Rollup | 4.9.6 | Web SDK bundling |
| Gradle | 8.x | Android/Kotlin builds |
| Xcode | 15+ | iOS/macOS builds |
| Emscripten | Latest | WASM compilation |
| react-native-builder-bob | 0.23.2 | RN module builds |

## Configuration Files

| File | Purpose |
|------|---------|
| `core/CMakeLists.txt` | Core C++ build configuration |
| `core/cmake/ios.toolchain.cmake` | iOS cross-compilation |
| `core/cmake/android.toolchain.cmake` | Android cross-compilation |
| `web/rollup.config.js` | Web SDK bundling |
| `web/tsconfig.json` | TypeScript configuration |
| `kotlin/build.gradle.kts` | Android SDK build |
| `swift/Package.swift` | Swift Package definition |
| `flutter/pubspec.yaml` | Flutter plugin definition |
| `Makefile` | Cross-platform build orchestration |

## Environment Requirements

| Variable | Required For | Description |
|----------|--------------|-------------|
| `ANDROID_NDK_HOME` | Android builds | Path to Android NDK r25+ |
| `EMSDK` | WASM builds | Path to Emscripten SDK |
