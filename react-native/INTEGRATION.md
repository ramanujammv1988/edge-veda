# Edge Veda React Native SDK - Integration Guide

## Architecture Overview

The Edge Veda React Native SDK uses the New Architecture (TurboModules) for optimal performance. The architecture consists of three layers:

### 1. JavaScript Layer (`src/`)

- **index.tsx**: Main entry point, exports all public APIs
- **EdgeVeda.ts**: High-level JavaScript wrapper with event handling
- **NativeEdgeVeda.ts**: TurboModule specification (interface between JS and native)
- **types.ts**: TypeScript type definitions

### 2. iOS Native Layer (`ios/`)

- **EdgeVeda.mm**: Objective-C bridge that exposes Swift code to React Native
- **EdgeVeda.swift**: Swift implementation of the TurboModule
- Integrates with Edge Veda Core iOS SDK (to be implemented)

### 3. Android Native Layer (`android/`)

- **EdgeVedaModule.kt**: Kotlin TurboModule implementation
- **EdgeVedaPackage.kt**: Package registration for React Native
- Integrates with Edge Veda Core Android SDK (to be implemented)

## TurboModule Flow

```
JavaScript Call
    ↓
NativeEdgeVeda (TurboModule Spec)
    ↓
Native Implementation (iOS/Android)
    ↓
Edge Veda Core SDK
    ↓
Native Response
    ↓
JavaScript Promise/Callback
```

## Integration Steps

### Step 1: Integrate Core SDKs

#### iOS (Swift/Objective-C++)
1. Add Edge Veda Core iOS framework to `edge-veda.podspec`
2. Import and use in `EdgeVeda.swift`
3. Replace TODO comments with actual Core SDK calls

```swift
import EdgeVedaCore

private var edgeVedaCore: EdgeVedaCore?

// In initialize method:
self.edgeVedaCore = try EdgeVedaCore(modelPath: modelPath, config: configDict)
```

#### Android (Kotlin)
1. Add Edge Veda Core Android library to `android/build.gradle`
2. Import and use in `EdgeVedaModule.kt`
3. Replace TODO comments with actual Core SDK calls

```kotlin
import com.edgeveda.core.EdgeVedaCore

private var edgeVedaCore: EdgeVedaCore? = null

// In initialize method:
edgeVedaCore = EdgeVedaCore(modelPath, configJson)
```

### Step 2: Implement Event Streaming

The SDK already has event infrastructure in place. Connect native events to Core SDK:

#### iOS
```swift
// In generateStream method:
try self.edgeVedaCore?.generateStream(prompt: prompt, options: optionsDict) { token in
    if self.activeGenerations[requestId] == true {
        self.sendEvent(withName: "EdgeVeda_TokenGenerated",
                     body: ["requestId": requestId, "token": token])
    }
}
```

#### Android
```kotlin
// In generateStream method:
edgeVedaCore?.generateStream(prompt, optionsJson) { token ->
    if (activeGenerations.containsKey(requestId)) {
        sendTokenEvent(requestId, token)
    }
}
```

### Step 3: Implement Memory Management

Connect native memory APIs to JavaScript:

#### iOS
```swift
func getMemoryUsage(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
    guard let stats = edgeVedaCore?.getMemoryStats() else {
        reject("STATS_ERROR", "Failed to get memory stats", nil)
        return
    }

    let usage: [String: Any] = [
        "totalBytes": stats.total,
        "modelBytes": stats.model,
        "kvCacheBytes": stats.kvCache,
        "availableBytes": stats.available
    ]

    if let jsonString = try? JSONSerialization.data(withJSONObject: usage)
        .toString() {
        resolve(jsonString)
    }
}
```

#### Android
```kotlin
@ReactMethod(isBlockingSynchronousMethod = true)
fun getMemoryUsage(): String {
    val stats = edgeVedaCore?.getMemoryStats() ?: return "{}"

    val usage = JSONObject().apply {
        put("totalBytes", stats.total)
        put("modelBytes", stats.model)
        put("kvCacheBytes", stats.kvCache)
        put("availableBytes", stats.available)
    }

    return usage.toString()
}
```

### Step 4: Error Handling

Map native errors to JavaScript error codes:

```typescript
// In EdgeVeda.ts
catch (error) {
    if (error.code === 'OOM') {
        throw new EdgeVedaError(
            EdgeVedaErrorCode.OUT_OF_MEMORY,
            'Out of memory',
            error.message
        );
    }
    // Map other errors...
}
```

## Event System

The SDK uses React Native's event emitter for streaming and progress updates:

### JavaScript Side
```typescript
// Already implemented in EdgeVeda.ts
this.eventEmitter.addListener('EdgeVeda_TokenGenerated', ({ requestId, token }) => {
    const callback = this.activeGenerations.get(requestId);
    if (callback) callback(token, false);
});
```

### Native Side (iOS)
```swift
// Send events to JavaScript
self.sendEvent(withName: "EdgeVeda_TokenGenerated",
               body: ["requestId": requestId, "token": token])
```

### Native Side (Android)
```kotlin
// Send events to JavaScript
sendEvent(EVENT_TOKEN_GENERATED, Arguments.createMap().apply {
    putString("requestId", requestId)
    putString("token", token)
})
```

## Available Events

1. **EdgeVeda_TokenGenerated**: Emitted for each generated token during streaming
2. **EdgeVeda_GenerationComplete**: Emitted when generation finishes
3. **EdgeVeda_GenerationError**: Emitted when generation encounters an error
4. **EdgeVeda_ModelLoadProgress**: Emitted during model loading with progress updates

## Testing Strategy

### Unit Tests
- Test JavaScript wrapper logic
- Mock native module
- Test error handling

### Integration Tests
- Test TurboModule interface
- Test event emitter
- Test memory management

### E2E Tests
- Test with actual model file
- Test streaming generation
- Test memory pressure scenarios

## Performance Considerations

1. **Thread Management**
   - Use background threads for inference
   - Main thread only for UI updates
   - iOS: Use DispatchQueue.global(qos: .userInitiated)
   - Android: Use Dispatchers.Default

2. **Memory Management**
   - Monitor memory usage continuously
   - Implement automatic model unloading on low memory
   - Use memory warnings from OS

3. **GPU Acceleration**
   - iOS: Use Metal Performance Shaders
   - Android: Use Vulkan or GPU delegate

4. **Batching**
   - Batch token emissions to reduce JS bridge overhead
   - Configurable batch size in config

## Codegen (New Architecture)

The SDK uses React Native Codegen for TurboModule generation:

```json
// In package.json
"codegenConfig": {
  "name": "RNEdgeVedaSpec",
  "type": "modules",
  "jsSrcsDir": "src",
  "android": {
    "javaPackageName": "com.edgeveda"
  }
}
```

This generates:
- iOS: C++ headers in build directory
- Android: Java interfaces in build directory

## Building and Publishing

### Development Build
```bash
npm run prepare
# or
yarn prepare
```

### Publishing to npm
```bash
npm version patch  # or minor/major
npm publish --access public
```

### CocoaPods (iOS)
```bash
pod lib lint edge-veda.podspec
pod trunk push edge-veda.podspec
```

### Maven (Android)
Configure in `android/build.gradle` for Maven Central publishing.

## Next Steps

1. Implement Core SDK integration (replace TODOs)
2. Add comprehensive error handling
3. Implement progress callbacks
4. Add unit and integration tests
5. Create example app
6. Write API documentation
7. Performance benchmarking
8. Add CI/CD pipeline

## File Checklist

✅ package.json - Package configuration with TurboModule support
✅ src/index.tsx - Main exports
✅ src/types.ts - TypeScript type definitions
✅ src/NativeEdgeVeda.ts - TurboModule spec
✅ src/EdgeVeda.ts - JavaScript wrapper with event handling
✅ ios/EdgeVeda.mm - Objective-C bridge
✅ ios/EdgeVeda.swift - Swift implementation
✅ android/src/main/java/com/edgeveda/EdgeVedaModule.kt - Kotlin module
✅ android/src/main/java/com/edgeveda/EdgeVedaPackage.kt - Package registration
✅ android/build.gradle - Android build configuration
✅ edge-veda.podspec - CocoaPods specification
✅ tsconfig.json - TypeScript configuration
✅ README.md - User documentation

## Resources

- [React Native New Architecture](https://reactnative.dev/docs/the-new-architecture/landing-page)
- [TurboModules Guide](https://reactnative.dev/docs/the-new-architecture/pillars-turbomodules)
- [Codegen](https://reactnative.dev/docs/the-new-architecture/pillars-codegen)
