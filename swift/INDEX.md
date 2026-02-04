# EdgeVeda Swift SDK - Quick Reference Index

## 📍 Quick Navigation

### Getting Started
- [README.md](README.md) - Start here for installation and quick start
- [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) - Project overview and statistics
- [SCAFFOLD_COMPLETE.md](SCAFFOLD_COMPLETE.md) - What was built

### Documentation
- [API.md](API.md) - Complete API reference
- [INTEGRATION.md](INTEGRATION.md) - Integration guide for iOS/macOS
- [STRUCTURE.md](STRUCTURE.md) - Project structure details

### Code
- [Sources/EdgeVeda/EdgeVeda.swift](Sources/EdgeVeda/EdgeVeda.swift) - Main actor API
- [Sources/EdgeVeda/Config.swift](Sources/EdgeVeda/Config.swift) - Configurations
- [Sources/EdgeVeda/Types.swift](Sources/EdgeVeda/Types.swift) - Types and errors
- [Sources/EdgeVeda/Internal/FFIBridge.swift](Sources/EdgeVeda/Internal/FFIBridge.swift) - C interop

### Examples
- [Examples/SimpleExample.swift](Examples/SimpleExample.swift) - Basic usage
- [Examples/StreamingExample.swift](Examples/StreamingExample.swift) - Streaming demo
- [Examples/ConfigExample.swift](Examples/ConfigExample.swift) - Config comparison

### Tools
- [validate.sh](validate.sh) - Run validation checks

---

## 🔍 Find By Topic

### Initialization & Setup
- **Basic init**: [README.md#quick-start](README.md) → EdgeVeda.swift
- **Configuration**: Config.swift → [API.md#edgevedaconfig](API.md)
- **iOS setup**: [INTEGRATION.md#ios-integration](INTEGRATION.md)
- **macOS setup**: [INTEGRATION.md#macos-integration](INTEGRATION.md)

### Text Generation
- **Simple generation**: [API.md#generate](API.md) → EdgeVeda.swift
- **Streaming**: [API.md#generatestream](API.md) → EdgeVeda.swift
- **Options**: [API.md#generateoptions](API.md) → Config.swift

### Configuration
- **Presets**: Config.swift → [README.md#configuration](README.md)
- **Custom config**: [API.md#edgevedaconfig](API.md)
- **Backend selection**: [README.md#backend-selection](README.md)

### Error Handling
- **Error types**: Types.swift → [API.md#edgevedaerror](API.md)
- **Error handling patterns**: [README.md#error-handling](README.md)
- **Recovery**: [API.md#edgevedaerror](API.md)

### Advanced Features
- **Memory monitoring**: EdgeVeda.swift → [API.md#memoryusage](API.md)
- **Device info**: Types.swift → [API.md#deviceinfo](API.md)
- **Context management**: EdgeVeda.swift → [API.md#resetcontext](API.md)

### FFI & C Interop
- **C header**: [Sources/CEdgeVeda/include/edge_veda.h](Sources/CEdgeVeda/include/edge_veda.h)
- **FFI bridge**: FFIBridge.swift
- **Integration**: [INTEGRATION.md#c-library-integration](INTEGRATION.md)

### Testing
- **Test suite**: [Tests/EdgeVedaTests/EdgeVedaTests.swift](Tests/EdgeVedaTests/EdgeVedaTests.swift)
- **Running tests**: [README.md#building](README.md)

---

## 📖 Documentation Quick Links

### API Reference

| Component | Description | Link |
|-----------|-------------|------|
| **EdgeVeda** | Main actor API | [API.md#edgeveda-actor](API.md) |
| **EdgeVedaConfig** | Model configuration | [API.md#edgevedaconfig](API.md) |
| **GenerateOptions** | Generation parameters | [API.md#generateoptions](API.md) |
| **Backend** | Backend enum | [API.md#backend](API.md) |
| **EdgeVedaError** | Error types | [API.md#edgevedaerror](API.md) |
| **Types** | Data structures | [API.md#types](API.md) |

### Guides

| Guide | Purpose | Link |
|-------|---------|------|
| **Quick Start** | Get running fast | [README.md](README.md) |
| **iOS Integration** | iOS app setup | [INTEGRATION.md#ios-integration](INTEGRATION.md) |
| **macOS Integration** | macOS app setup | [INTEGRATION.md#macos-integration](INTEGRATION.md) |
| **Performance** | Optimization tips | [README.md#performance-tips](README.md) |
| **Troubleshooting** | Common issues | [INTEGRATION.md#troubleshooting](INTEGRATION.md) |

---

## 🎯 Common Tasks

### Initialize EdgeVeda

```swift
// See: EdgeVeda.swift, README.md
let edgeVeda = try await EdgeVeda(
    modelPath: "/path/to/model.gguf",
    config: .default
)
```

### Generate Text

```swift
// See: EdgeVeda.swift, API.md#generate
let response = try await edgeVeda.generate("Hello!")
```

### Stream Generation

```swift
// See: EdgeVeda.swift, API.md#generatestream
for try await token in edgeVeda.generateStream("Story") {
    print(token, terminator: "")
}
```

### Handle Errors

```swift
// See: Types.swift, API.md#edgevedaerror
do {
    let edgeVeda = try await EdgeVeda(modelPath: path, config: .metal)
} catch EdgeVedaError.modelNotFound(let path) {
    print("Model not found: \(path)")
} catch EdgeVedaError.outOfMemory {
    // Use lowMemory config
}
```

### Monitor Memory

```swift
// See: EdgeVeda.swift, API.md#memoryusage
let memoryMB = await edgeVeda.memoryUsage / 1_024_000
```

### Custom Configuration

```swift
// See: Config.swift, API.md#edgevedaconfig
let config = EdgeVedaConfig(
    backend: .metal,
    threads: 4,
    contextSize: 4096
)
```

---

## 📂 File Reference

### Core Library (Sources/EdgeVeda/)

| File | Lines | Purpose |
|------|-------|---------|
| **EdgeVeda.swift** | 140 | Main public API (actor) |
| **Config.swift** | 180 | Configurations and presets |
| **Types.swift** | 220 | Error types and structures |
| **Internal/FFIBridge.swift** | 240 | C FFI bridge layer |

### C Interop (Sources/CEdgeVeda/)

| File | Lines | Purpose |
|------|-------|---------|
| **include/edge_veda.h** | 120 | C header declarations |

### Tests (Tests/EdgeVedaTests/)

| File | Lines | Purpose |
|------|-------|---------|
| **EdgeVedaTests.swift** | 400+ | Comprehensive test suite |

### Examples (Examples/)

| File | Purpose |
|------|---------|
| **SimpleExample.swift** | Basic usage demo |
| **StreamingExample.swift** | Streaming with metrics |
| **ConfigExample.swift** | Config comparison |

### Documentation (Root)

| File | Purpose |
|------|---------|
| **README.md** | Getting started guide |
| **API.md** | Complete API reference |
| **INTEGRATION.md** | Integration guide |
| **STRUCTURE.md** | Project structure |
| **SCAFFOLD_COMPLETE.md** | Build completion report |
| **PROJECT_SUMMARY.md** | Project overview |
| **INDEX.md** | This file |

---

## 🔧 Build & Development

### Commands

```bash
# Validate structure
./validate.sh

# Build
swift build

# Test
swift test

# Clean
swift package clean

# Generate Xcode project
swift package generate-xcodeproj
```

### Files

- [Package.swift](Package.swift) - SPM manifest
- [validate.sh](validate.sh) - Validation script
- [.gitignore](.gitignore) - Git ignore rules

---

## 🎓 Learning Path

### Beginner

1. Read [README.md](README.md) - Quick start
2. Try [Examples/SimpleExample.swift](Examples/SimpleExample.swift)
3. Experiment with [Config.swift](Sources/EdgeVeda/Config.swift) presets

### Intermediate

4. Read [API.md](API.md) - Full API
5. Try [Examples/StreamingExample.swift](Examples/StreamingExample.swift)
6. Explore [Types.swift](Sources/EdgeVeda/Types.swift) - Error handling

### Advanced

7. Read [INTEGRATION.md](INTEGRATION.md) - Deep integration
8. Study [FFIBridge.swift](Sources/EdgeVeda/Internal/FFIBridge.swift) - FFI layer
9. Review [edge_veda.h](Sources/CEdgeVeda/include/edge_veda.h) - C interface

---

## 🎨 Code Patterns

### Actor Pattern (EdgeVeda.swift)
- Thread-safe access
- Async/await methods
- Automatic serialization

### Configuration Pattern (Config.swift)
- Sendable structs
- Preset factories
- Builder pattern

### Error Pattern (Types.swift)
- Typed errors
- Localized descriptions
- Recovery suggestions

### FFI Pattern (FFIBridge.swift)
- Unsafe operations isolated
- Memory management
- C string conversions

---

## 🔗 External Resources

- **Swift Evolution**: Concurrency, actors, async/await
- **Swift Package Manager**: Documentation
- **llama.cpp**: C/C++ backend
- **GGUF Format**: Model file format

---

## ✅ Checklist

### For Users

- [ ] Read README.md
- [ ] Run validate.sh
- [ ] Try SimpleExample.swift
- [ ] Configure for your needs
- [ ] Handle errors properly

### For Contributors

- [ ] Read STRUCTURE.md
- [ ] Understand FFI layer
- [ ] Follow Swift best practices
- [ ] Add tests for changes
- [ ] Update documentation

---

## 📞 Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Documentation**: All .md files
- **Examples**: Examples/ directory

---

**Last Updated**: 2026-02-04
**Version**: 1.0.0 (Scaffold)
**Status**: ✅ Complete
