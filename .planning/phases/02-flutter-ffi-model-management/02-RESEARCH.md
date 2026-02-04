# Phase 2: Flutter FFI + Model Management - Research

**Researched:** 2026-02-04
**Domain:** Flutter dart:ffi bindings, model download/caching, background isolate patterns
**Confidence:** HIGH (verified with official documentation and multiple sources)

## Summary

This phase implements the Flutter layer that connects to the Phase 1 C++ core, plus model download/management infrastructure. The critical challenges are: (1) FFI calls block the Dart main isolate, requiring background isolate patterns for all inference operations; (2) memory management across Dart/C++ boundary requires explicit ownership rules; (3) large model downloads need chunked streaming with progress tracking and checksum verification.

The existing codebase already has well-designed scaffolding (`bindings.dart`, `model_manager.dart`, `edge_veda_impl.dart`). The task is primarily to align FFI signatures with `edge_veda.h`, implement proper isolate-based async patterns, and harden the model download flow with proper error handling.

**Primary recommendation:** Use `Isolate.run()` for all FFI inference calls from day one. Never call blocking native functions from the main isolate. This is a non-negotiable architectural decision that prevents UI freezes and iOS watchdog kills.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ffi | ^2.1.5 | Dart FFI bindings and memory allocation | Official Dart package for C interop, provides malloc/calloc allocators and Utf8 encoding |
| path_provider | ^2.1.5 | Platform-specific file system paths | Official Flutter plugin, provides applicationSupportDirectory for model storage |
| http | ^1.6.0 | HTTP client for model downloads | Official Dart package, supports streaming responses for large file downloads |
| crypto | ^3.0.7 | SHA256 checksum computation | Official Dart package, supports chunked hashing for large files |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| path | ^1.9.0 | Cross-platform path manipulation | Already in pubspec, used for building model file paths |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| http | dio | More features (interceptors, retry) but heavier dependency; http sufficient for v1 |
| path_provider | Manual platform channels | More control but unnecessary complexity |
| compute() | Isolate.run() | compute() works on web, but we're mobile-only and Isolate.run() is cleaner |

**Installation:**
```bash
# Already in pubspec.yaml - no additional packages needed
flutter pub get
```

## Architecture Patterns

### Recommended Project Structure
```
flutter/lib/
  src/
    ffi/
      bindings.dart        # FFI function signatures (aligned to edge_veda.h)
      native_memory.dart   # Memory management helpers, RAII patterns
    model_manager.dart     # Download, cache, verify models
    edge_veda_impl.dart    # Main SDK class with isolate-based async
    types.dart             # Public types, exceptions
  edge_veda.dart           # Public API exports
```

### Pattern 1: Isolate.run() for Blocking FFI Calls
**What:** Offload all inference FFI calls to background isolates using `Isolate.run()`
**When to use:** Any FFI call that takes >16ms (frame budget)
**Why:** FFI calls are synchronous and block the calling thread. The main isolate handles UI - blocking it causes jank or iOS watchdog termination.

**Example:**
```dart
// Source: https://docs.flutter.dev/perf/isolates
Future<String> generate(String prompt) async {
  final modelPath = _config!.modelPath;
  final numThreads = _config!.numThreads;
  final contextLength = _config!.contextLength;
  final useGpu = _config!.useGpu;

  // Run blocking FFI call in background isolate
  final result = await Isolate.run<String>(() {
    // Re-open library in this isolate
    final bindings = EdgeVedaNativeBindings.instance;

    // Initialize context in this isolate
    final ctx = bindings.evInit(modelPath, numThreads, contextLength, useGpu);
    if (ctx == nullptr) {
      throw GenerationException('Failed to initialize context');
    }

    try {
      final output = bindings.evGenerate(ctx, prompt, params);
      return output;
    } finally {
      bindings.evFree(ctx);
    }
  });

  return result;
}
```

**Critical note:** DynamicLibrary and Pointers cannot be transferred between isolates. Each isolate must load the library and create its own context. For v1, this is acceptable. For v2, consider a long-lived worker isolate pattern.

### Pattern 2: Chunked Download with Progress Stream
**What:** Download large model files in chunks, emit progress updates
**When to use:** Downloading GGUF models (500MB-2GB)
**Why:** Memory-efficient, enables progress tracking, supports resume

**Example:**
```dart
// Source: https://pub.dev/packages/http
Stream<DownloadProgress> downloadModel(String url, String destPath) async* {
  final request = http.Request('GET', Uri.parse(url));
  final client = http.Client();

  try {
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw DownloadException('HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var downloadedBytes = 0;

    final file = File(destPath);
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;

      yield DownloadProgress(
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
      );
    }

    await sink.flush();
    await sink.close();
  } finally {
    client.close();
  }
}
```

### Pattern 3: RAII-Style Memory Management for FFI
**What:** Wrap native string operations in try-finally blocks ensuring cleanup
**When to use:** All FFI calls that allocate native memory
**Why:** Dart has GC but C doesn't - manual memory management required to prevent leaks

**Example:**
```dart
// Source: https://pub.dev/packages/ffi, https://github.com/dart-lang/sdk/issues/50457
extension StringNativeScope on String {
  /// Execute function with native string, automatically free after
  R useNative<R>(R Function(Pointer<Utf8>) fn) {
    final ptr = toNativeUtf8();
    try {
      return fn(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
}

// Usage
final result = prompt.useNative((promptPtr) {
  return _bindings.evGenerate(ctx, promptPtr, params);
});
```

### Pattern 4: Memory Pressure Callback via NativeCallable
**What:** Register Dart callback with C++ memory pressure monitoring
**When to use:** Propagating iOS memory warnings from C++ to Flutter
**Why:** C++ receives OS memory warnings; Dart layer needs to respond

**Example:**
```dart
// Source: https://api.flutter.dev/flutter/dart-ffi/NativeCallable-class.html
typedef MemoryPressureCallback = Void Function(Pointer<Void>, Size, Size);

class EdgeVeda {
  NativeCallable<MemoryPressureCallback>? _memoryCallback;

  void _setupMemoryPressureCallback(Pointer<ev_context> ctx) {
    _memoryCallback = NativeCallable<MemoryPressureCallback>.listener(
      (userData, current, limit) {
        // This runs on Dart's event loop, not the native thread
        _handleMemoryPressure(current, limit);
      },
    );

    _bindings.evSetMemoryPressureCallback(
      ctx,
      _memoryCallback!.nativeFunction,
      nullptr, // user_data
    );
  }

  void _handleMemoryPressure(int current, int limit) {
    // Notify listeners, potentially cancel generation
    _memoryPressureController.add(MemoryPressureEvent(current, limit));
  }

  void dispose() {
    _memoryCallback?.close(); // CRITICAL: must close to prevent leak
    // ... other cleanup
  }
}
```

### Anti-Patterns to Avoid
- **Calling FFI from main isolate:** Will freeze UI. Always use `Isolate.run()`.
- **Sharing Pointer between isolates:** Undefined behavior. Re-load library per isolate.
- **Forgetting to free native strings:** Memory leak. Use try-finally or RAII wrappers.
- **Not closing NativeCallable:** Keeps isolate alive, memory leak. Always call `.close()`.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UTF-8 string encoding | Manual byte arrays | `toNativeUtf8()` from ffi package | Handles null termination, multi-byte chars correctly |
| Memory allocation | `Pointer.allocate()` | `calloc<T>()` from ffi package | Zero-initializes, proper alignment |
| File paths on iOS | Hardcoded paths | `getApplicationSupportDirectory()` | Sandbox-safe, works across app reinstalls |
| SHA256 streaming | Reading whole file into memory | `sha256.bind(stream)` from crypto | Memory-efficient for large files |
| Download progress | Polling content-length | `response.stream` with `await for` | Built-in, handles chunked transfer |

**Key insight:** The ffi and crypto packages have solved the hard problems. Using raw dart:ffi primitives leads to subtle bugs around memory alignment, string encoding, and resource cleanup.

## Common Pitfalls

### Pitfall 1: FFI Blocks Main Isolate (CRITICAL)
**What goes wrong:** Developer calls `_bindings.evGenerate()` directly, UI freezes for 5-30 seconds during inference.
**Why it happens:** dart:ffi is synchronous by design. Blocking FFI call blocks the entire isolate.
**How to avoid:** Use `Isolate.run()` for ALL inference calls. No exceptions.
**Warning signs:** Purple "main thread blocked" warning in Xcode, ANR dialog on device.

### Pitfall 2: Model Path Sandbox Violation (CRITICAL)
**What goes wrong:** Model path hardcoded or uses wrong directory, works on simulator but fails on device.
**Why it happens:** iOS sandbox paths change between app installs. Documents directory backs up to iCloud.
**How to avoid:** Always use `getApplicationSupportDirectory()` for models. Set `excludeFromBackup` attribute.
**Warning signs:** "File not found" after app reinstall, iCloud backup complaints.

```dart
// CORRECT: Use applicationSupportDirectory
final dir = await getApplicationSupportDirectory();
final modelPath = path.join(dir.path, 'models', 'model.gguf');

// Set exclude from backup (iOS-specific, requires MethodChannel to AppDelegate)
// Or document that users should implement this in their app
```

### Pitfall 3: FFI Memory Leaks (CRITICAL)
**What goes wrong:** `toNativeUtf8()` allocates memory but `calloc.free()` never called. Memory grows with each call.
**Why it happens:** Dart GC doesn't manage native memory. Easy to forget cleanup in error paths.
**How to avoid:**
1. Ownership rule: Dart allocates -> Dart frees (calloc.free). C++ allocates -> C++ frees (ev_free_string).
2. Always use try-finally blocks.
3. Use the RAII pattern (StringNativeScope extension).
**Warning signs:** Memory grows linearly with number of generations in Instruments.

### Pitfall 4: DynamicLibrary Cannot Transfer Between Isolates
**What goes wrong:** Try to pass context pointer or bindings to `Isolate.run()`, get "Illegal argument in isolate message" error.
**Why it happens:** Isolates have separate memory heaps. Pointers are memory addresses, meaningless in another heap.
**How to avoid:** Re-load DynamicLibrary in each isolate. Pass primitive data (strings, numbers) only.
**Warning signs:** Runtime error on isolate spawn.

```dart
// WRONG: Cannot pass bindings or context pointer
await Isolate.run(() {
  _bindings.evGenerate(_ctx, prompt); // ERROR: _bindings and _ctx can't transfer
});

// CORRECT: Re-create in isolate
await Isolate.run(() {
  final bindings = EdgeVedaNativeBindings.instance; // Loads library in this isolate
  final ctx = bindings.evInit(...); // Create context in this isolate
  try {
    return bindings.evGenerate(ctx, ...);
  } finally {
    bindings.evFree(ctx);
  }
});
```

### Pitfall 5: Download Progress Jumps or Stalls
**What goes wrong:** Progress bar jumps from 0% to 100%, or stalls at arbitrary percentage.
**Why it happens:** Using `http.get()` instead of `client.send(request)` with streaming. Or server doesn't send Content-Length.
**How to avoid:**
1. Use `StreamedRequest` and `StreamedResponse` for downloads.
2. Handle missing `contentLength` gracefully (show bytes instead of percentage).
3. Emit progress on each chunk, not on completion.
**Warning signs:** Users think download failed when it's still progressing.

### Pitfall 6: Checksum Computed on Incomplete File
**What goes wrong:** Download interrupted, checksum computed on partial file, verification "passes" incorrectly.
**Why it happens:** Download to final path, compute checksum, rename. Crash between steps.
**How to avoid:** Download to `.tmp` file, verify checksum, then rename to final path atomically.
**Warning signs:** Model loads with garbage output, or crashes during inference.

## Code Examples

Verified patterns from official sources:

### Initialize SDK with Background Isolate
```dart
// Recommended pattern for Phase 2 implementation
class EdgeVeda {
  EdgeVedaConfig? _config;
  bool _isInitialized = false;

  Future<void> init(EdgeVedaConfig config) async {
    if (_isInitialized) {
      throw InitializationException('Already initialized. Call dispose() first.');
    }

    _config = config;

    // Validate model file exists
    final file = File(config.modelPath);
    if (!await file.exists()) {
      throw ModelLoadException('Model file not found: ${config.modelPath}');
    }

    // Test initialization in background isolate
    await Isolate.run<void>(() {
      final bindings = EdgeVedaNativeBindings.instance;
      final configPtr = _createConfigStruct(config);
      final errorPtr = calloc<Int32>();

      try {
        final ctx = bindings.evInit(configPtr, errorPtr);
        if (ctx == nullptr) {
          final errorCode = errorPtr.value;
          throw InitializationException(
            'Native init failed',
            details: 'Error code: $errorCode',
          );
        }
        bindings.evFree(ctx);
      } finally {
        calloc.free(configPtr);
        calloc.free(errorPtr);
      }
    });

    _isInitialized = true;
  }
}
```

### Download Model with Progress and Checksum
```dart
// Source: Pattern verified against http ^1.6.0 and crypto ^3.0.7 documentation
Future<String> downloadModel(ModelInfo model) async {
  final modelPath = await getModelPath(model.id);
  final tempPath = '$modelPath.tmp';
  final file = File(modelPath);
  final tempFile = File(tempPath);

  // Check cache first
  if (await file.exists()) {
    if (model.checksum != null) {
      final isValid = await _verifyChecksum(modelPath, model.checksum!);
      if (isValid) return modelPath;
      await file.delete(); // Invalid, re-download
    } else {
      return modelPath; // No checksum, assume valid
    }
  }

  final request = http.Request('GET', Uri.parse(model.downloadUrl));
  final client = http.Client();

  try {
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw DownloadException(
        'Download failed',
        details: 'HTTP ${response.statusCode}',
      );
    }

    final totalBytes = response.contentLength ?? model.sizeBytes;
    var downloadedBytes = 0;
    final sink = tempFile.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;

      _progressController.add(DownloadProgress(
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
      ));
    }

    await sink.flush();
    await sink.close();

    // Verify checksum BEFORE renaming
    if (model.checksum != null) {
      final isValid = await _verifyChecksum(tempPath, model.checksum!);
      if (!isValid) {
        await tempFile.delete();
        throw ChecksumException(
          'Checksum verification failed',
          details: 'Expected: ${model.checksum}',
        );
      }
    }

    // Atomic rename
    await tempFile.rename(modelPath);
    return modelPath;

  } catch (e) {
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    rethrow;
  } finally {
    client.close();
  }
}

Future<bool> _verifyChecksum(String filePath, String expected) async {
  // Source: crypto ^3.0.7 chunked hashing
  final file = File(filePath);
  final stream = file.openRead();
  final digest = await sha256.bind(stream).first;
  return digest.toString().toLowerCase() == expected.toLowerCase();
}
```

### FFI Bindings Aligned to edge_veda.h
```dart
// Bindings must match edge_veda.h signatures exactly
class EdgeVedaNativeBindings {
  late final ffi.DynamicLibrary _dylib;

  // ev_context ev_init(const ev_config* config, ev_error_t* error)
  late final evInit = _dylib.lookupFunction<
    Pointer<ev_context_impl> Function(Pointer<ev_config>, Pointer<Int32>),
    Pointer<ev_context_impl> Function(Pointer<ev_config>, Pointer<Int32>)
  >('ev_init');

  // void ev_free(ev_context ctx)
  late final evFree = _dylib.lookupFunction<
    Void Function(Pointer<ev_context_impl>),
    void Function(Pointer<ev_context_impl>)
  >('ev_free');

  // ev_error_t ev_generate(ev_context ctx, const char* prompt,
  //                        const ev_generation_params* params, char** output)
  late final evGenerate = _dylib.lookupFunction<
    Int32 Function(
      Pointer<ev_context_impl>,
      Pointer<Utf8>,
      Pointer<ev_generation_params>,
      Pointer<Pointer<Utf8>>
    ),
    int Function(
      Pointer<ev_context_impl>,
      Pointer<Utf8>,
      Pointer<ev_generation_params>,
      Pointer<Pointer<Utf8>>
    )
  >('ev_generate');

  // void ev_free_string(char* str)
  late final evFreeString = _dylib.lookupFunction<
    Void Function(Pointer<Utf8>),
    void Function(Pointer<Utf8>)
  >('ev_free_string');

  // ev_error_t ev_set_memory_pressure_callback(
  //   ev_context ctx, ev_memory_pressure_callback callback, void* user_data)
  late final evSetMemoryPressureCallback = _dylib.lookupFunction<
    Int32 Function(
      Pointer<ev_context_impl>,
      Pointer<NativeFunction<Void Function(Pointer<Void>, Size, Size)>>,
      Pointer<Void>
    ),
    int Function(
      Pointer<ev_context_impl>,
      Pointer<NativeFunction<Void Function(Pointer<Void>, Size, Size)>>,
      Pointer<Void>
    )
  >('ev_set_memory_pressure_callback');
}

// FFI struct definitions matching edge_veda.h
final class ev_context_impl extends Opaque {}

final class ev_config extends Struct {
  external Pointer<Utf8> model_path;
  @Int32() external int backend;
  @Int32() external int num_threads;
  @Int32() external int context_size;
  @Int32() external int batch_size;
  @Size() external int memory_limit_bytes;
  @Bool() external bool auto_unload_on_memory_pressure;
  @Int32() external int gpu_layers;
  @Bool() external bool use_mmap;
  @Bool() external bool use_mlock;
  @Int32() external int seed;
  external Pointer<Void> reserved;
}

final class ev_generation_params extends Struct {
  @Int32() external int max_tokens;
  @Float() external double temperature;
  @Float() external double top_p;
  @Int32() external int top_k;
  @Float() external double repeat_penalty;
  @Float() external double frequency_penalty;
  @Float() external double presence_penalty;
  external Pointer<Pointer<Utf8>> stop_sequences;
  @Int32() external int num_stop_sequences;
  external Pointer<Void> reserved;
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Platform Channels for native code | FFI direct calls | Flutter 2.0+ (2021) | 10-100x faster for high-frequency calls |
| Manual isolate setup with ports | `Isolate.run()` | Dart 2.19 (2023) | Simplified async FFI pattern |
| `compute()` for background work | `Isolate.run()` preferred | Dart 3.0 (2023) | Cleaner API, same functionality |
| Thread merge disabled | Threads merged by default (iOS/Android) | Flutter 3.29+ (2025) | FFI even faster, but main thread blocking still bad |

**Deprecated/outdated:**
- `Isolate.spawn()` without `Isolate.run()` wrapper: Still works but `Isolate.run()` is simpler for one-shot operations
- ffigen for simple APIs: Manual bindings give more control; use ffigen for complex APIs with many functions

## Open Questions

Things that couldn't be fully resolved:

1. **iOS Backup Exclusion from Dart**
   - What we know: iOS requires calling `NSURLIsExcludedFromBackupKey` to exclude files from iCloud backup
   - What's unclear: No pure Dart API exists; requires MethodChannel to native iOS code
   - Recommendation: Document that app developers should call native exclusion API in AppDelegate, or implement helper MethodChannel in Phase 3

2. **Long-lived Worker Isolate vs Per-Request Isolate**
   - What we know: Per-request isolate is simpler but re-loads library each time. Worker isolate can reuse context.
   - What's unclear: Performance impact of library reload (likely negligible since it's the same binary)
   - Recommendation: Start with per-request `Isolate.run()` for v1. If profiling shows overhead, implement worker isolate in v2.

3. **Flutter 3.29+ Thread Merge Impact**
   - What we know: Main UI thread merged with platform thread on iOS/Android as of Flutter 3.29+
   - What's unclear: Whether this changes the FFI blocking recommendation (likely no - still shouldn't block main thread)
   - Recommendation: Continue using `Isolate.run()` regardless. Thread merge improves latency but doesn't make blocking safe.

## Sources

### Primary (HIGH confidence)
- [Flutter Official: Concurrency and isolates](https://docs.flutter.dev/perf/isolates) - Isolate.run() patterns, when to use isolates
- [Dart Official: Concurrency](https://dart.dev/language/concurrency) - Isolate fundamentals
- [pub.dev/packages/ffi v2.1.5](https://pub.dev/packages/ffi) - Memory allocation, UTF8 encoding
- [pub.dev/packages/path_provider v2.1.5](https://pub.dev/packages/path_provider) - iOS directory paths
- [pub.dev/packages/http v1.6.0](https://pub.dev/packages/http) - Streaming downloads
- [pub.dev/packages/crypto v3.0.7](https://pub.dev/packages/crypto) - SHA256 chunked hashing
- [Flutter API: NativeCallable](https://api.flutter.dev/flutter/dart-ffi/NativeCallable-class.html) - Native callbacks to Dart
- Existing codebase: `/Users/ram/Documents/explore/edge/core/include/edge_veda.h` - C API signatures

### Secondary (MEDIUM confidence)
- [GitHub flutter/flutter #169431](https://github.com/flutter/flutter/issues/169431) - FFI and isolates challenges
- [GitHub dart-lang/sdk #50457](https://github.com/dart-lang/sdk/issues/50457) - Pointer transfer between isolates
- [Medium: Memory Management in Dart FFI](https://medium.com/@andycall/memory-management-in-dart-ffi-24577067ba43) - Ownership patterns
- [Apple Developer: isExcludedFromBackupKey](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey) - iOS backup exclusion

### Tertiary (LOW confidence)
- Community blog posts on FFI patterns - verified against official docs before inclusion

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official packages, verified versions via pub.dev
- Architecture patterns: HIGH - Verified against Flutter official docs and API reference
- Pitfalls: HIGH - Cross-referenced existing PITFALLS.md with official documentation
- Code examples: MEDIUM - Based on documentation patterns, needs implementation validation

**Research date:** 2026-02-04
**Valid until:** 2026-03-06 (30 days - Flutter FFI is stable, patterns won't change quickly)
