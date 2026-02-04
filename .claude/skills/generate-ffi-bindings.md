---
name: generate-ffi-bindings
description: Generate FFI bindings from C header for specified language
allowed-tools: Read, Write, Bash
---

# Generate FFI Bindings

Generate language-specific bindings from `core/include/edge_veda.h`.

## Usage
```
/generate-ffi-bindings <target>
```

## Supported Targets

### `dart` - Dart FFI Bindings
Uses `package:ffigen` to generate bindings.

```yaml
# ffigen.yaml
name: EdgeVedaBindings
description: FFI bindings for Edge Veda C API
output: 'lib/src/ffi/bindings.dart'
headers:
  entry-points:
    - 'core/include/edge_veda.h'
```

Output: `flutter/lib/src/ffi/bindings.dart`

### `swift` - Swift C Interop
Creates bridging header and Swift wrapper.

```swift
// EdgeVeda-Bridging-Header.h
#import "edge_veda.h"

// EdgeVedaCore.swift
import Foundation

@_silgen_name("ev_init")
func ev_init(_ path: UnsafePointer<CChar>, _ config: UnsafeMutablePointer<ev_config>) -> OpaquePointer?
```

Output: `swift/Sources/EdgeVeda/EdgeVedaCore.swift`

### `kotlin` - JNI Bindings
Generates JNI wrapper with proper memory management.

```kotlin
// EdgeVedaJNI.kt
package com.edgeveda

object EdgeVedaJNI {
    init {
        System.loadLibrary("edge_veda")
    }

    external fun evInit(modelPath: String, config: Long): Long
    external fun evGenerateStream(ctx: Long, prompt: String): Long
    external fun evStreamNext(stream: Long): String?
    external fun evFree(ctx: Long)
}
```

Output: `kotlin/src/main/kotlin/EdgeVedaJNI.kt`

### `typescript` - WASM Bindings
Generates TypeScript types for Emscripten module.

```typescript
// types.ts
export interface EdgeVedaModule extends EmscriptenModule {
  _ev_init(modelPath: number, config: number): number;
  _ev_generate_stream(ctx: number, prompt: number): number;
  _ev_stream_next(stream: number): number;
  _ev_free(ctx: number): void;

  // Helper functions
  allocateUTF8(str: string): number;
  UTF8ToString(ptr: number): string;
}
```

Output: `web/src/types.ts`

## Process

1. Parse `core/include/edge_veda.h`
2. Extract function signatures, structs, enums
3. Generate idiomatic bindings for target language
4. Add memory management helpers
5. Include documentation comments
