# Edge Veda Swift SDK

Native Swift SDK for on-device AI inference on iOS and macOS. No Flutter dependency required.

## Features

- Modern Swift API with async/await
- AsyncSequence-based streaming for token generation
- Metal GPU acceleration (built into the C++ core)
- Swift Package Manager distribution
- iOS 15+ and macOS 12+ support
- Thread-safe with Swift Concurrency

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/ramanujammv1988/edge-veda.git", from: "1.0.0")
]
```

Then add `"EdgeVeda"` to your target's dependencies.

## Quick Start

```swift
import EdgeVeda

// Initialize
let veda = try EdgeVeda(config: Config(modelPath: "model.gguf"))

// Streaming with AsyncSequence
for try await token in veda.generate("What is AI?") {
    print(token, terminator: "")
}

// Single-shot
let response = try await veda.generateComplete("What is AI?")
print(response.text)
print("\(response.tokensPerSecond ?? 0) tokens/sec")

// Embeddings
let embedding = try await veda.embed("Hello world")
print("Dimensions: \(embedding.dimensions)")

// Memory stats
let stats = try veda.memoryUsage
print("Memory: \(stats.currentBytes / 1024 / 1024) MB")
```

## Architecture

```
Swift API (EdgeVeda.swift)
    ↓ C interop
edge_veda.h (C API)
    ↓
C++ Core (llama.cpp + whisper.cpp)
    ↓
Metal GPU / CPU
```

## Platforms

- iOS 15+
- macOS 12+

## License

MIT
