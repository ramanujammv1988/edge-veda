# EdgeVeda Swift SDK Integration Guide

This guide covers integrating the EdgeVeda Swift SDK into your iOS/macOS applications.

## Table of Contents

1. [Installation](#installation)
2. [C Library Integration](#c-library-integration)
3. [Basic Setup](#basic-setup)
4. [iOS Integration](#ios-integration)
5. [macOS Integration](#macos-integration)
6. [Build Configuration](#build-configuration)
7. [Troubleshooting](#troubleshooting)

## Installation

### Swift Package Manager (Recommended)

#### Xcode
1. File > Add Package Dependencies
2. Enter repository URL
3. Select version/branch
4. Add to target

#### Package.swift
```swift
dependencies: [
    .package(url: "https://github.com/yourusername/edge-veda-swift", from: "1.0.0")
]
```

## C Library Integration

The Swift SDK requires the EdgeVeda C library. You have two options:

### Option 1: Pre-built XCFramework (Recommended)

1. Download the latest `EdgeVeda.xcframework` from releases
2. Add to your Xcode project:
   - Drag into project navigator
   - Select "Copy items if needed"
   - Add to target's "Frameworks, Libraries, and Embedded Content"

### Option 2: Build from Source

```bash
# Clone and build the C library
git clone https://github.com/yourusername/edge-veda
cd edge-veda/c
mkdir build && cd build

# For iOS
cmake -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  ..

# For macOS
cmake -G Xcode \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  ..

cmake --build . --config Release
```

### Linking the C Library

Update `Package.swift` to link against the built library:

```swift
targets: [
    .target(
        name: "CEdgeVeda",
        dependencies: [],
        path: "Sources/CEdgeVeda",
        publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("include")
        ],
        linkerSettings: [
            .linkedLibrary("edge_veda"),
            .linkedLibrary("c++")
        ]
    )
]
```

## Basic Setup

### Import and Initialize

```swift
import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
class LLMService {
    private var edgeVeda: EdgeVeda?

    func initialize() async throws {
        // Get model path from bundle
        guard let modelPath = Bundle.main.path(
            forResource: "model",
            ofType: "gguf"
        ) else {
            throw NSError(domain: "ModelNotFound", code: 404)
        }

        // Initialize with Metal on Apple Silicon
        edgeVeda = try await EdgeVeda(
            modelPath: modelPath,
            config: .metal
        )
    }

    func generate(_ prompt: String) async throws -> String {
        guard let edgeVeda = edgeVeda else {
            throw NSError(domain: "ModelNotLoaded", code: 500)
        }

        return try await edgeVeda.generate(prompt)
    }

    deinit {
        // EdgeVeda actor handles cleanup automatically
    }
}
```

## iOS Integration

### App Structure

```swift
import SwiftUI
import EdgeVeda

@main
struct MyApp: App {
    @StateObject private var llmService = LLMService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(llmService)
                .task {
                    await llmService.loadModel()
                }
        }
    }
}

@MainActor
class LLMService: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?

    private var edgeVeda: EdgeVeda?

    func loadModel() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let modelPath = Bundle.main.path(
                forResource: "model",
                ofType: "gguf"
            ) else {
                error = "Model file not found in bundle"
                return
            }

            edgeVeda = try await EdgeVeda(
                modelPath: modelPath,
                config: .default
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func generate(_ prompt: String) async -> String? {
        guard let edgeVeda = edgeVeda else { return nil }

        do {
            return try await edgeVeda.generate(prompt)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
```

### SwiftUI View with Streaming

```swift
struct ChatView: View {
    @EnvironmentObject var llmService: LLMService
    @State private var prompt = ""
    @State private var response = ""
    @State private var isGenerating = false

    var body: some View {
        VStack {
            ScrollView {
                Text(response)
                    .padding()
            }

            HStack {
                TextField("Enter prompt", text: $prompt)
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    Task {
                        await generate()
                    }
                }
                .disabled(isGenerating || prompt.isEmpty)
            }
            .padding()
        }
    }

    private func generate() async {
        isGenerating = true
        response = ""

        guard let edgeVeda = llmService.edgeVeda else {
            return
        }

        for try await token in edgeVeda.generateStream(prompt) {
            await MainActor.run {
                response += token
            }
        }

        isGenerating = false
    }
}
```

### Including Model in App Bundle

1. Add model file to Xcode project
2. Ensure it's added to target's "Copy Bundle Resources"
3. Access via `Bundle.main`:

```swift
func getModelPath() -> String? {
    // Option 1: From main bundle
    Bundle.main.path(forResource: "model", ofType: "gguf")

    // Option 2: From documents directory (for downloaded models)
    let documentsPath = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first
    return documentsPath?.appendingPathComponent("model.gguf").path
}
```

## macOS Integration

### AppKit Application

```swift
import Cocoa
import EdgeVeda

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var edgeVeda: EdgeVeda?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await loadModel()
        }
    }

    private func loadModel() async {
        do {
            let modelPath = "/path/to/model.gguf"
            edgeVeda = try await EdgeVeda(
                modelPath: modelPath,
                config: .highPerformance
            )
        } catch {
            NSLog("Failed to load model: \(error)")
        }
    }
}
```

### Command-Line Tool

```swift
import Foundation
import EdgeVeda

@main
struct CLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("Usage: cli <model_path> <prompt>")
            return
        }

        let modelPath = args[1]
        let prompt = args[2]

        do {
            let edgeVeda = try await EdgeVeda(
                modelPath: modelPath,
                config: .cpu
            )

            let response = try await edgeVeda.generate(prompt)
            print(response)

            await edgeVeda.unloadModel()
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}
```

## Build Configuration

### Xcode Build Settings

#### For iOS:
- Deployment Target: iOS 15.0+
- Supported Platforms: iOS, iOS Simulator
- Architectures: arm64, arm64-simulator

#### For macOS:
- Deployment Target: macOS 12.0+
- Supported Platforms: macOS
- Architectures: arm64, x86_64

### Swift Compiler Flags

Add to build settings:
```
-enable-upcoming-feature StrictConcurrency
```

### Linker Flags

If using static library:
```
-lc++
-ledge_veda
```

### Info.plist Entries

For file access:
```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

## Performance Optimization

### Memory Management

```swift
// Use low memory config for older devices
let config: EdgeVedaConfig = {
    let totalMemory = ProcessInfo.processInfo.physicalMemory
    if totalMemory < 4_000_000_000 { // < 4GB
        return .lowMemory
    } else {
        return .highPerformance
    }
}()
```

### Background Processing

```swift
func generateInBackground(_ prompt: String) async -> String? {
    await Task.detached(priority: .userInitiated) {
        guard let edgeVeda = await self.edgeVeda else {
            return nil
        }
        return try? await edgeVeda.generate(prompt)
    }.value
}
```

### Batch Processing

```swift
func processBatch(_ prompts: [String]) async -> [String] {
    var results: [String] = []

    for prompt in prompts {
        if let response = try? await edgeVeda?.generate(prompt) {
            results.append(response)
        }

        // Reset context between prompts
        try? await edgeVeda?.resetContext()
    }

    return results
}
```

## Troubleshooting

### Common Issues

#### 1. "Model file not found"
- Verify model is in app bundle or documents directory
- Check file path is absolute
- Ensure model file wasn't stripped during build

#### 2. "Out of memory"
- Use `EdgeVedaConfig.lowMemory`
- Reduce `contextSize` or `batchSize`
- Use quantized models (Q4_0, Q4_1)

#### 3. "Metal not supported"
- Only available on Apple Silicon
- Fallback to `.cpu` backend on Intel Macs
- Use `.auto` to automatically select

#### 4. "Undefined symbols for architecture"
- Ensure C library is properly linked
- Check architecture matches target
- Verify library search paths

### Debugging

Enable verbose logging:
```swift
let config = EdgeVedaConfig(
    backend: .auto,
    verbose: true
)
```

Check memory usage:
```swift
let memoryUsage = await edgeVeda.memoryUsage
print("Memory: \(memoryUsage / 1_024_000) MB")
```

### Platform-Specific Issues

#### iOS
- Simulators may have Metal limitations
- Background app refresh affects inference
- Memory warnings require cleanup

#### macOS
- Intel Macs: Use CPU backend
- Apple Silicon: Metal provides 2-5x speedup
- File permissions for model access

## Best Practices

1. **Initialize Early**: Load model during app launch
2. **Handle Errors**: Always catch and handle `EdgeVedaError`
3. **Memory Aware**: Monitor and respond to memory warnings
4. **Thread Safety**: EdgeVeda is an Actor - await all calls
5. **Cleanup**: Call `unloadModel()` when done
6. **Testing**: Test on both device and simulator
7. **Backend Selection**: Use `.auto` for best compatibility

## Resources

- [API Documentation](https://edgeveda.dev/docs/swift/api)
- [Example Apps](./Examples/)
- [Issue Tracker](https://github.com/yourusername/edge-veda-swift/issues)
- [Discussions](https://github.com/yourusername/edge-veda-swift/discussions)
