# Edge Veda Android SDK

Native Kotlin SDK for on-device AI inference on Android. No Flutter dependency required.

## Features

- Idiomatic Kotlin API with coroutines (`suspend` functions)
- Kotlin Flow-based streaming for token generation
- JNI bridge to the Edge Veda C++ core (llama.cpp)
- GPU acceleration via Vulkan on supported devices
- Model download and caching
- Memory-aware inference with Android `ActivityManager` integration

## Installation

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.edgeveda:edge-veda-android:1.0.0")
}
```

## Quick Start

```kotlin
// Initialize
val edgeVeda = EdgeVeda.builder(context)
    .setModel("path/to/model.gguf")
    .setMaxTokens(512)
    .build()

// Single-shot generation
val response = edgeVeda.generate("What is AI?")
println(response.text)
println("${response.tokensPerSecond} tokens/sec")

// Streaming with Flow
edgeVeda.generateStream("Explain quantum computing")
    .collect { token -> print(token) }

// Embeddings
val embedding = edgeVeda.embed("Hello world")
println("Dimensions: ${embedding.dimensions}")

// Memory stats
val stats = edgeVeda.getMemoryUsage()
println("Memory: ${stats.currentBytes / 1024 / 1024} MB")

// Cleanup
edgeVeda.close()
```

## Architecture

```
Kotlin API (EdgeVeda.kt)
    ↓ suspend/Flow
JNI Bridge (edge_veda_jni.cpp)
    ↓ ev_* C functions
C++ Core (llama.cpp + whisper.cpp)
    ↓
GPU (Vulkan) / CPU
```

## Supported ABIs

- `arm64-v8a` (ARM64)
- `armeabi-v7a` (ARM32)
- `x86_64` (Emulator)

## Min SDK

Android API 24 (Android 7.0)

## License

MIT
