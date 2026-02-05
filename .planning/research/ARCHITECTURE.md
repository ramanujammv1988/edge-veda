# Architecture Patterns: Flutter FFI + llama.cpp + Metal on iOS

**Domain:** On-device LLM inference SDK for Flutter iOS
**Researched:** 2026-02-04
**Confidence:** MEDIUM (based on training data, llama.cpp API stability generally good)

## Executive Summary

The architecture wires Flutter Dart code through FFI to a C++ core that wraps llama.cpp for iOS inference with Metal GPU acceleration. The key challenge is managing the threading model correctly: Dart's main isolate cannot block during inference, but llama.cpp's generation is fundamentally synchronous. This document defines component boundaries, data flow, threading model, memory lifecycle, and build order.

## Recommended Architecture

```
+------------------+     +-------------------+     +------------------+
|   Flutter App    |     |   Dart FFI Layer  |     |   C++ Core       |
|                  |     |                   |     |   (edge_veda)    |
|  EdgeVeda.       | --> | NativeBindings    | --> |                  |
|  generate()      |     | (bindings.dart)   |     |  ev_init()       |
|                  |     |                   |     |  ev_generate()   |
|  async/await     |     | Pointer<Context>  |     |  ev_stream_*()   |
+------------------+     +-------------------+     +------------------+
                                                          |
                                                          v
+------------------+     +-------------------+     +------------------+
|   iOS Runtime    |     |   llama.cpp       |     |   Metal Backend  |
|                  |     |                   |     |                  |
|  CocoaPods       | <-- | llama_model       | --> | GPU Inference    |
|  XCFramework     |     | llama_context     |     | Metal shaders    |
|                  |     | llama_batch       |     | ggml-metal.m     |
+------------------+     +-------------------+     +------------------+
```

## Component Boundaries

| Component | Responsibility | Owns | Communicates With |
|-----------|---------------|------|-------------------|
| `EdgeVeda` (Dart) | Public API, async wrapping, error handling | Stream controllers, user-facing config | `EdgeVedaNativeBindings` |
| `EdgeVedaNativeBindings` (Dart) | FFI function lookups, pointer management | `DynamicLibrary`, function pointers | C API via FFI |
| `ev_context_impl` (C++) | Wrapper around llama.cpp, config management | `llama_model*`, `llama_context*`, mutex | llama.cpp API |
| `ev_stream_impl` (C++) | Streaming state machine, token buffer | Current generation state, partial tokens | `ev_context_impl` |
| `memory_guard` (C++) | Process memory monitoring | Monitor thread, callbacks | OS APIs (`mach_task_info`) |
| llama.cpp | Model loading, tokenization, inference | Model weights, KV cache | Metal backend |
| Metal backend | GPU compute shaders | Metal command queues, buffers | iOS Metal framework |

## Data Flow: Prompt to Response

### Synchronous Generation Flow

```
1. Dart: EdgeVeda.generate(prompt)
   |
   v
2. Dart: Convert String to Pointer<Utf8>
   |
   v
3. FFI: Call ev_generate(ctx, prompt_ptr, params, &output_ptr)
   |
   v
4. C++: Acquire mutex lock on context
   |
   v
5. C++: llama_tokenize(model, prompt) -> std::vector<llama_token>
   |
   v
6. C++: llama_decode(ctx, batch) [for each batch of tokens]
   |     - Metal GPU executes matrix operations
   |     - KV cache updated
   |
   v
7. C++: Loop until max_tokens or EOS:
   |     a. llama_get_logits_ith(ctx, -1)
   |     b. llama_sample_* (temperature, top_p, top_k)
   |     c. llama_decode(ctx, single_token_batch)
   |     d. Append token to output
   |
   v
8. C++: Detokenize output tokens -> char* output
   |
   v
9. C++: Release mutex, return output pointer
   |
   v
10. FFI: Return Pointer<Utf8>
    |
    v
11. Dart: Convert to String, free native memory
    |
    v
12. Dart: Return GenerateResponse to caller
```

### Streaming Generation Flow

```
1. Dart: EdgeVeda.generateStream(prompt)
   |
   v
2. Dart: Create StreamController<TokenChunk>
   |
   v
3. Dart: Call ev_generate_stream(ctx, prompt, params, &error)
   |     Returns: ev_stream handle
   |
   v
4. Dart: Loop (in microtask/timer):
   |     a. ev_stream_next(stream, &error) -> token or NULL
   |     b. If token: streamController.add(TokenChunk)
   |     c. If NULL: close stream
   |     d. await Future.delayed(1ms) [yield to event loop]
   |
   v
5. C++: ev_stream_next():
   |     a. Generate one token (same as step 7 above)
   |     b. Store token in stream state
   |     c. Return token pointer
   |
   v
6. Dart: On stream cancel -> ev_stream_cancel()
```

## Threading Model

### Critical Constraint: Dart Main Isolate

**Problem:** Dart's FFI calls block the main isolate. Long-running inference (100ms-10s) will freeze the UI.

**Solution Options (ranked by recommendation):**

#### Option 1: Background Isolate with SendPort (RECOMMENDED)

```dart
// In edge_veda_impl.dart
Future<GenerateResponse> generate(String prompt, ...) async {
  // Spawn isolate for blocking FFI call
  final receivePort = ReceivePort();
  await Isolate.spawn(
    _inferenceIsolate,
    _InferenceRequest(
      modelPath: _config!.modelPath,
      prompt: prompt,
      options: options,
      sendPort: receivePort.sendPort,
    ),
  );

  final response = await receivePort.first as GenerateResponse;
  return response;
}

// Top-level function (required for Isolate.spawn)
void _inferenceIsolate(_InferenceRequest request) {
  // Load bindings in this isolate
  final bindings = EdgeVedaNativeBindings.instance;

  // Do blocking FFI call - this is fine, we're not on main isolate
  final result = bindings.edgeVedaGenerate(...);

  request.sendPort.send(result);
}
```

**Pros:** Clean isolation, no UI blocking, standard Dart pattern
**Cons:** Context cannot be shared across isolates (must re-init or use different approach)

#### Option 2: Native Thread with Callback (Alternative)

```cpp
// In engine.cpp - add callback-based API
typedef void (*ev_generate_callback)(void* user_data, const char* token, bool is_final);

ev_error_t ev_generate_async(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    ev_generate_callback callback,
    void* user_data
);
```

```dart
// Dart NativeCallable for callback
final callback = NativeCallable<
    Void Function(Pointer<Void>, Pointer<Utf8>, Bool)
>.listener((userData, token, isFinal) {
  // This runs on Dart's event loop
  _streamController.add(TokenChunk(token: token.toDartString(), ...));
});
```

**Pros:** Context stays in one thread, efficient
**Cons:** More complex FFI, callback management, Dart 3.1+ required

#### Option 3: Polling with Short Timeouts (Simplest, Limited)

Keep current approach but with very short timeouts:
- Only works for fast operations (<50ms)
- NOT suitable for full generation
- OK for: `ev_stream_next()` which generates single token

### Thread Ownership Rules

| Thread | Owns | Can Access |
|--------|------|------------|
| Dart Main Isolate | StreamControllers, UI state | Read-only config after init |
| Dart Inference Isolate | FFI bindings instance | Context pointer (if using isolate) |
| C++ Main Thread | `ev_context_impl`, mutex | All C++ state |
| C++ Memory Monitor | Monitor thread | Atomic counters only |
| Metal Dispatch Queue | GPU command buffers | Read model weights |

### Mutex Strategy

```cpp
// In ev_context_impl
std::mutex mutex;  // Guards: model, ctx, last_error, generation state

// All public API functions acquire lock:
ev_error_t ev_generate(...) {
    std::lock_guard<std::mutex> lock(ctx->mutex);
    // ... safe to access ctx->model, ctx->ctx
}

// Streaming: lock held only during token generation, not between calls
char* ev_stream_next(ev_stream stream, ev_error_t* error) {
    std::lock_guard<std::mutex> stream_lock(stream->mutex);
    std::lock_guard<std::mutex> ctx_lock(stream->ctx->mutex);
    // Generate one token
    // Release locks
    return token;
}
```

## Memory Management

### Ownership Rules

| Resource | Owner | Lifecycle | Cleanup |
|----------|-------|-----------|---------|
| `llama_model*` | `ev_context_impl` | Init to Free | `llama_free_model()` in `ev_free()` |
| `llama_context*` | `ev_context_impl` | Init to Free | `llama_free()` in `ev_free()` |
| KV Cache | llama.cpp context | Automatic | Cleared on `ev_reset()` |
| Output strings | Caller | Until `ev_free_string()` | `ev_free_string()` |
| Stream handles | Caller | Until `ev_stream_free()` | `ev_stream_free()` |
| Metal buffers | Metal/llama.cpp | Automatic | On context free |
| Dart Pointers | Dart code | Manual | `malloc.free()` or `ev_free_string()` |

### Memory Budget (4GB device, 1B model)

```
Total Device RAM:     4,096 MB
iOS System Reserved:  ~1,500 MB
App Baseline:           ~100 MB
---------------------------------
Available for SDK:    ~2,400 MB

Model Weights (Q4_K_M): ~600 MB
KV Cache (2048 ctx):    ~150 MB
Working Memory:         ~100 MB
---------------------------------
SDK Usage:              ~850 MB

Safety Margin:        ~1,550 MB (OK)
```

### Memory Pressure Response

```cpp
// When memory_guard callback fires at 90% limit:
void handle_memory_pressure(void* user_data, size_t current, size_t limit) {
    ev_context ctx = static_cast<ev_context>(user_data);

    // Option 1: Clear KV cache (loses conversation history)
    llama_kv_cache_clear(ctx->llama_ctx);

    // Option 2: Reduce context size
    // (requires context recreation - expensive)

    // Option 3: Notify Dart to stop streaming
    // (via error return or callback)
}
```

## llama.cpp Integration Points

### Required llama.cpp Structures

```cpp
// In ev_context_impl, add:
#ifdef EDGE_VEDA_LLAMA_ENABLED
    llama_model* model = nullptr;
    llama_context* llama_ctx = nullptr;

    // For batch processing
    llama_batch batch;

    // Sampler chain for generation
    llama_sampler* sampler = nullptr;
#endif
```

### Integration in ev_init()

```cpp
ev_context ev_init(const ev_config* config, ev_error_t* error) {
    // ... existing validation ...

#ifdef EDGE_VEDA_LLAMA_ENABLED
    // Initialize llama.cpp backend (once per process)
    static bool backend_initialized = false;
    if (!backend_initialized) {
        llama_backend_init();
        backend_initialized = true;
    }

    // Load model
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = (config->gpu_layers == -1)
        ? 999  // All layers to GPU
        : config->gpu_layers;
    model_params.use_mmap = config->use_mmap;
    model_params.use_mlock = config->use_mlock;

    ctx->model = llama_load_model_from_file(
        config->model_path,
        model_params
    );
    if (!ctx->model) {
        err = EV_ERROR_MODEL_LOAD_FAILED;
        // ... cleanup ...
    }

    // Create context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = config->context_size;
    ctx_params.n_batch = config->batch_size;
    ctx_params.n_threads = (config->num_threads == 0)
        ? std::thread::hardware_concurrency()
        : config->num_threads;
    ctx_params.n_threads_batch = ctx_params.n_threads;
    ctx_params.seed = (config->seed == -1)
        ? (uint32_t)time(nullptr)
        : config->seed;

    ctx->llama_ctx = llama_new_context_with_model(ctx->model, ctx_params);
    if (!ctx->llama_ctx) {
        err = EV_ERROR_BACKEND_INIT_FAILED;
        // ... cleanup ...
    }

    // Initialize batch
    ctx->batch = llama_batch_init(config->batch_size, 0, 1);

    // Create sampler chain
    ctx->sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    // Add samplers in ev_generate based on params

    ctx->model_loaded = true;
#endif

    return ctx;
}
```

### Integration in ev_generate()

```cpp
ev_error_t ev_generate(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    char** output
) {
#ifdef EDGE_VEDA_LLAMA_ENABLED
    std::lock_guard<std::mutex> lock(ctx->mutex);

    // 1. Tokenize prompt
    const int max_tokens = llama_n_ctx(ctx->llama_ctx);
    std::vector<llama_token> tokens(max_tokens);
    int n_tokens = llama_tokenize(
        ctx->model,
        prompt,
        strlen(prompt),
        tokens.data(),
        max_tokens,
        true,   // add_special (BOS)
        false   // parse_special
    );
    if (n_tokens < 0) {
        ctx->last_error = "Tokenization failed";
        return EV_ERROR_INFERENCE_FAILED;
    }
    tokens.resize(n_tokens);

    // 2. Clear KV cache for fresh generation
    llama_kv_cache_clear(ctx->llama_ctx);

    // 3. Evaluate prompt tokens in batches
    for (size_t i = 0; i < tokens.size(); i += ctx->config.batch_size) {
        size_t batch_size = std::min(
            (size_t)ctx->config.batch_size,
            tokens.size() - i
        );

        llama_batch_clear(ctx->batch);
        for (size_t j = 0; j < batch_size; j++) {
            llama_batch_add(
                ctx->batch,
                tokens[i + j],
                i + j,           // position
                { 0 },           // sequence IDs
                (i + j == tokens.size() - 1)  // last token needs logits
            );
        }

        if (llama_decode(ctx->llama_ctx, ctx->batch) != 0) {
            ctx->last_error = "Decode failed during prompt evaluation";
            return EV_ERROR_INFERENCE_FAILED;
        }
    }

    // 4. Setup sampler chain
    llama_sampler_chain_reset(ctx->sampler);
    // Add samplers based on params
    auto chain = ctx->sampler;
    llama_sampler_chain_add(chain,
        llama_sampler_init_temp(params->temperature));
    llama_sampler_chain_add(chain,
        llama_sampler_init_top_k(params->top_k));
    llama_sampler_chain_add(chain,
        llama_sampler_init_top_p(params->top_p, 1));
    llama_sampler_chain_add(chain,
        llama_sampler_init_dist(ctx->config.seed));

    // 5. Generate tokens
    std::string result;
    int n_generated = 0;
    llama_token eos_token = llama_token_eos(ctx->model);

    while (n_generated < params->max_tokens) {
        // Sample next token
        llama_token new_token = llama_sampler_sample(
            ctx->sampler,
            ctx->llama_ctx,
            -1  // last logits
        );

        // Check for EOS
        if (new_token == eos_token) {
            break;
        }

        // Decode token to text
        char buf[128];
        int len = llama_token_to_piece(
            ctx->model,
            new_token,
            buf,
            sizeof(buf),
            0,      // no special tokens
            true    // render special
        );
        if (len > 0) {
            result.append(buf, len);
        }

        // Prepare next decode
        llama_batch_clear(ctx->batch);
        llama_batch_add(
            ctx->batch,
            new_token,
            tokens.size() + n_generated,
            { 0 },
            true
        );

        if (llama_decode(ctx->llama_ctx, ctx->batch) != 0) {
            ctx->last_error = "Decode failed during generation";
            return EV_ERROR_INFERENCE_FAILED;
        }

        n_generated++;

        // Accept token in sampler
        llama_sampler_accept(ctx->sampler, new_token);
    }

    // 6. Return result
    *output = strdup(result.c_str());
    if (!*output) {
        return EV_ERROR_OUT_OF_MEMORY;
    }

    return EV_SUCCESS;
#else
    return EV_ERROR_NOT_IMPLEMENTED;
#endif
}
```

## Build Order (Dependency Chain)

Build phases must respect these dependencies:

```
Phase 1: llama.cpp submodule
    |
    +-- Add as git submodule in core/third_party/llama.cpp
    |
    v
Phase 2: CMake integration
    |
    +-- Verify llama.cpp builds with Metal enabled
    +-- Define EDGE_VEDA_LLAMA_ENABLED
    +-- Link llama static library
    |
    v
Phase 3: C++ core implementation
    |
    +-- ev_init() with llama_load_model_from_file
    +-- ev_generate() with tokenize + decode loop
    +-- ev_free() with proper cleanup
    |
    v
Phase 4: iOS Framework build
    |
    +-- Build XCFramework (device + simulator)
    +-- Embed in Flutter plugin via CocoaPods
    |
    v
Phase 5: FFI binding verification
    |
    +-- Verify function signatures match
    +-- Test pointer round-trip
    |
    v
Phase 6: Dart async wrapper
    |
    +-- Implement isolate-based generation
    +-- Or: implement streaming with polling
    |
    v
Phase 7: Integration test
    |
    +-- Load model, generate text, verify output
```

## Patterns to Follow

### Pattern 1: Opaque Handle with Factory

**What:** Hide implementation behind opaque pointer, create via factory function
**Why:** Allows internal changes without breaking API, prevents direct struct access

```c
// Public API
typedef struct ev_context_impl* ev_context;
ev_context ev_init(const ev_config* config, ev_error_t* error);
void ev_free(ev_context ctx);
```

### Pattern 2: Error-Last Pattern

**What:** Return error via last parameter, return value is the result
**Why:** Consistent with llama.cpp style, easy to check in Dart

```c
ev_stream ev_generate_stream(
    ev_context ctx,
    const char* prompt,
    const ev_generation_params* params,
    ev_error_t* error  // OUT: error code
);
// Returns stream on success, NULL on failure
```

### Pattern 3: Batch Processing for Prompt

**What:** Process prompt tokens in batches before generation
**Why:** Metal GPU utilization, avoids timeout on long prompts

```cpp
// Good: batch processing
for (size_t i = 0; i < tokens.size(); i += batch_size) {
    llama_decode(ctx, batch);  // GPU parallel
}

// Bad: token-by-token
for (auto token : tokens) {
    llama_decode(ctx, single_token);  // Slow, bad GPU utilization
}
```

### Pattern 4: Sampler Chain for Generation

**What:** Use llama.cpp's sampler chain API for token selection
**Why:** Composable, handles temperature/top_p/top_k correctly

```cpp
llama_sampler* chain = llama_sampler_chain_init(...);
llama_sampler_chain_add(chain, llama_sampler_init_temp(temp));
llama_sampler_chain_add(chain, llama_sampler_init_top_k(k));
llama_sampler_chain_add(chain, llama_sampler_init_top_p(p, min_keep));
llama_sampler_chain_add(chain, llama_sampler_init_dist(seed));

llama_token token = llama_sampler_sample(chain, ctx, -1);
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Blocking Main Isolate

**What:** Calling long-running FFI functions directly from main isolate
**Why bad:** Freezes UI, causes jank, may trigger iOS watchdog
**Instead:** Use Isolate.spawn() or implement callback-based async

### Anti-Pattern 2: Shared Context Across Isolates

**What:** Passing context pointer between Dart isolates
**Why bad:** Thread-safety nightmare, undefined behavior
**Instead:** One context per isolate, or serialize/deserialize state

### Anti-Pattern 3: Manual Token Looping in Dart

**What:** Calling into C++ for each token from Dart
**Why bad:** FFI overhead per token (~1ms), kills throughput
**Instead:** Generate batch of tokens in C++, return together (or use stream with internal loop)

### Anti-Pattern 4: Ignoring Memory Pressure

**What:** Loading model without checking available memory
**Why bad:** iOS will kill app if memory exceeds ~1.5GB on 4GB devices
**Instead:** Check memory before load, set memory limit, respond to pressure callbacks

## Scalability Considerations

| Concern | Current (v1) | At Scale (v2+) |
|---------|--------------|----------------|
| Context length | 2048 tokens | 4096-8192 with GQA models |
| Model size | 1B (~600MB) | 3B-7B, need memory mapping |
| Concurrent requests | Single-threaded | Queue-based, multiple contexts |
| Streaming latency | Polling | Native callbacks or isolate channels |

## FFI Binding Alignment Check

Current `bindings.dart` has signature mismatches with `edge_veda.h`. Required updates:

| Function | bindings.dart | edge_veda.h | Action |
|----------|---------------|-------------|--------|
| `ev_init` | Different params | Takes `ev_config*` | Update Dart binding |
| `ev_generate` | Different params | Takes `ev_generation_params*` | Update Dart binding |
| `ev_generate_stream` | Different params | Returns `ev_stream` | Update Dart binding |

**Note:** The existing bindings use a simplified API. Either:
1. Update C++ to match Dart signatures (easier short-term)
2. Update Dart to match C++ signatures (cleaner long-term)

Recommendation: Update Dart to match the well-designed `edge_veda.h` API.

## Sources and Confidence

| Finding | Confidence | Basis |
|---------|------------|-------|
| llama.cpp API structure | MEDIUM | Training data (API relatively stable, but verify version) |
| Flutter FFI isolate pattern | MEDIUM | Training data, common Dart pattern |
| Metal integration via llama.cpp | MEDIUM | Training data, llama.cpp has built-in Metal support |
| Memory limits on iOS | HIGH | iOS documentation is consistent |
| Sampler chain API | LOW | Training data may be stale, verify in llama.cpp docs |

**Validation needed:**
- llama.cpp current API (sampler chain vs older sampling functions)
- Exact XCFramework build process for Flutter plugin
- Dart isolate FFI behavior with native libraries

---

*This architecture document informs phase structure. Key insight: threading model is the critical path - solving isolate/async before attempting full integration.*

---

# Architecture Extension: v1.1 Android + Streaming

**Extension Date:** 2026-02-04
**Focus:** Android NDK integration and streaming callbacks for Flutter FFI
**Confidence:** HIGH (based on existing codebase analysis + official documentation)

---

## v1.1 Extension Overview

This section extends the v1.0 architecture to add:
1. **Android NDK build** - Vulkan backend for GPU acceleration
2. **Streaming implementation** - Long-lived worker isolate pattern

## Current v1.0 State Analysis

### What's Already Built

| Component | Status | Location |
|-----------|--------|----------|
| C++ Core | Complete | `core/src/engine.cpp` - 830 lines, ev_* API implemented |
| Streaming C API | Defined, not implemented | ev_stream_* functions return EV_ERROR_NOT_IMPLEMENTED |
| iOS Build | Complete | `scripts/build-ios.sh` - XCFramework generation |
| Flutter FFI | Complete | `flutter/lib/src/ffi/bindings.dart` - all bindings |
| Dart SDK | Complete | `flutter/lib/src/edge_veda_impl.dart` - Isolate.run() pattern |
| Android Gradle | Scaffolded | `flutter/android/build.gradle` - CMake config present |

### Current Isolate Pattern (v1.0)

```dart
// edge_veda_impl.dart - Current implementation
Future<GenerateResponse> generate(String prompt, ...) async {
  // One-shot isolate - dies after returning
  return Isolate.run<String>(() {
    final bindings = EdgeVedaNativeBindings.instance;
    // Create context, generate, free context
    // Return primitive String (no pointers cross boundary)
  });
}
```

**Limitation:** Cannot maintain long-lived context for streaming.

---

## Android Integration Architecture

### Build System Changes

The existing `flutter/android/build.gradle` has CMake configuration:

```groovy
externalNativeBuild {
    cmake {
        path "../../core/CMakeLists.txt"
        cppFlags "-std=c++17 -frtti -fexceptions"
        arguments "-DANDROID_STL=c++_shared",
                  "-DANDROID_PLATFORM=android-24",
                  "-DGGML_VULKAN=ON"
    }
}
```

### Required Changes

| Component | Current State | Required Change |
|-----------|---------------|-----------------|
| build-android.sh | Does not exist | Create (mirror build-ios.sh) |
| CMakeLists.txt | Android detection present | Verify Vulkan linking |
| jniLibs output | Empty | Build outputs .so files |
| Vulkan shaders | Not built | Cross-compile vulkan-shaders-gen |

### Android Build Script Structure

```bash
# scripts/build-android.sh (new)

# Key differences from build-ios.sh:
# 1. Uses ANDROID_NDK toolchain instead of ios.toolchain.cmake
# 2. Builds .so files instead of .a/.framework
# 3. Multiple architectures (arm64-v8a, armeabi-v7a)
# 4. No bitcode stripping needed

cmake \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DGGML_VULKAN=ON \
  -DEDGE_VEDA_BUILD_SHARED=ON \
  -B build-android

cmake --build build-android

# Output: build-android/libedge_veda.so
```

### Vulkan Build Considerations

Per [llama.cpp documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md):

1. **vulkan-shaders-gen must be built for host first**
2. **Android NDK Vulkan headers may need updating**
3. **Known issues:** Adreno GPU may crash, Mali GPU may be slower than CPU

**Recommendation:** Build with both Vulkan and CPU, implement runtime fallback.

### Output Directory Structure

```
flutter/
  android/
    src/main/
      jniLibs/
        arm64-v8a/
          libedge_veda.so
          libc++_shared.so
        armeabi-v7a/
          libedge_veda.so
          libc++_shared.so
```

---

## Streaming Architecture

### The Streaming Problem

Current `Isolate.run()` pattern:
- Creates fresh isolate per call
- Reloads DynamicLibrary each time
- Creates new ev_context, runs generate, frees context
- Cannot maintain state between calls

Streaming requires:
- Long-lived native context
- Persistent isolate sending multiple messages
- Token-by-token delivery

### C++ Streaming Implementation

The C API exists in `edge_veda.h` (lines 262-318):

```c
ev_stream ev_generate_stream(ev_context ctx, const char* prompt, ...);
char* ev_stream_next(ev_stream stream, ev_error_t* error);
bool ev_stream_has_next(ev_stream stream);
void ev_stream_cancel(ev_stream stream);
void ev_stream_free(ev_stream stream);
```

Implementation in `engine.cpp` is marked TODO. Required implementation:

```cpp
// ev_generate_stream - Initialize streaming state
ev_stream ev_generate_stream(...) {
    ev_stream stream = new ev_stream_impl(ctx, prompt, params);

    // 1. Tokenize prompt
    stream->tokens = tokenize_prompt(ctx->model, prompt, true);

    // 2. Clear KV cache
    llama_kv_cache_clear(ctx->llama_ctx);

    // 3. Evaluate prompt batch
    llama_batch batch = llama_batch_get_one(stream->tokens.data(), stream->tokens.size());
    llama_decode(ctx->llama_ctx, batch);

    // 4. Create sampler
    stream->sampler = create_sampler(params);

    return stream;
}

// ev_stream_next - Generate one token
char* ev_stream_next(ev_stream stream, ev_error_t* error) {
    if (stream->ended) {
        *error = EV_ERROR_STREAM_ENDED;
        return nullptr;
    }

    // 1. Sample token
    llama_token new_token = llama_sampler_sample(
        stream->sampler, stream->ctx->llama_ctx, -1);

    // 2. Check EOS
    if (llama_vocab_is_eog(vocab, new_token)) {
        stream->ended = true;
        *error = EV_ERROR_STREAM_ENDED;
        return nullptr;
    }

    // 3. Convert to text
    char buf[128];
    llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);

    // 4. Advance decode state
    llama_batch batch = llama_batch_get_one(&new_token, 1);
    llama_decode(stream->ctx->llama_ctx, batch);

    *error = EV_SUCCESS;
    return strdup(buf);
}
```

### Dart Long-Lived Worker Pattern

Replace `Isolate.run()` with persistent worker isolate:

```dart
class EdgeVeda {
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;

  Future<void> init(EdgeVedaConfig config) async {
    // Spawn persistent worker
    _mainReceivePort = ReceivePort();
    _workerIsolate = await Isolate.spawn(
      _workerEntry,
      _mainReceivePort!.sendPort,
    );

    // Get worker's SendPort
    final completer = Completer<SendPort>();
    _mainReceivePort!.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      }
    });
    _workerSendPort = await completer.future;

    // Initialize native context in worker
    _workerSendPort!.send(_InitMessage(config));
  }

  Stream<String> generateStream(String prompt) {
    final controller = StreamController<String>();

    _mainReceivePort!.listen((message) {
      if (message is _TokenChunk) {
        controller.add(message.token);
      } else if (message is _StreamDone) {
        controller.close();
      }
    });

    _workerSendPort!.send(_StreamMessage(prompt));
    return controller.stream;
  }
}

// Worker isolate entry point
void _workerEntry(SendPort mainSendPort) {
  final workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  final bindings = EdgeVedaNativeBindings.instance;
  Pointer<EvContextImpl>? ctx;
  Pointer<EvStreamImpl>? stream;

  workerReceivePort.listen((message) {
    if (message is _InitMessage) {
      ctx = bindings.evInit(...);
      mainSendPort.send(_InitResult(success: ctx != nullptr));
    } else if (message is _StreamMessage) {
      stream = bindings.evGenerateStream(ctx, message.prompt, ...);

      // Poll tokens
      while (bindings.evStreamHasNext(stream)) {
        final token = bindings.evStreamNext(stream, errorPtr);
        if (token != nullptr) {
          mainSendPort.send(_TokenChunk(token.toDartString()));
          bindings.evFreeString(token);
        }
      }
      mainSendPort.send(_StreamDone());
      bindings.evStreamFree(stream);
    }
  });
}
```

### Data Flow: Streaming

```
[Main Isolate]                    [Worker Isolate (persistent)]
     |                                    |
  init() ----(SendPort)----------------->+
                                         | ev_init()
     +<----(SendPort)-- InitResult ------+
     |                                   |
  generateStream() -(SendPort)---------->+
                                         | ev_generate_stream()
                                         | while(has_next):
                                         |   ev_stream_next()
     +<----(SendPort)-- TokenChunk ------+
     +<----(SendPort)-- TokenChunk ------+
     +<----(SendPort)-- TokenChunk ------+
     +<----(SendPort)-- StreamDone ------+
     |                                   |
  dispose() ----(SendPort)-------------->+
                                         | ev_free()
                                         | exit
```

---

## Component Diagram: v1.1

```
+------------------+     +-------------------+
|  Flutter App     |     |  Dart SDK         |
|                  |     |  edge_veda.dart   |
+--------+---------+     +--------+----------+
         |                        |
         v                        v
+--------+------------------------+----------+
|        Main Isolate                        |
|  +-----------------------------------+     |
|  | EdgeVeda class                    |     |
|  |   - init() spawns worker          |     |
|  |   - generate() one-shot (legacy)  |     |
|  |   - generateStream() via worker   |     |
|  +-----------------------------------+     |
+--------------------------------------------+
         |                    ^
         | SendPort           | ReceivePort
         v                    |
+--------------------------------------------+
|        Worker Isolate (persistent)  [NEW]  |
|  +-----------------------------------+     |
|  | Maintains native context          |     |
|  | Handles stream commands           |     |
|  | Polls ev_stream_next() in loop    |     |
|  +-----------------------------------+     |
+--------------------------------------------+
         |
         | FFI calls
         v
+--------------------------------------------+
|        Native Library                      |
|  +-----------------------------------+     |
|  | libedge_veda.so / .xcframework   |     |
|  |   - ev_stream_* IMPLEMENTED [NEW] |     |
|  +-----------------------------------+     |
|  +-----------------------------------+     |
|  | Platform Backend                  |     |
|  |   - Metal (iOS)                   |     |
|  |   - Vulkan (Android) [NEW]        |     |
|  |   - CPU (fallback)                |     |
|  +-----------------------------------+     |
+--------------------------------------------+
```

---

## Build Order: v1.1

### Phase 1: Android CPU Build

**Goal:** Get libedge_veda.so building and loading on Android

1. Create `scripts/build-android.sh`
2. Update CMakeLists.txt for Android SHARED library
3. Verify Flutter loads library via DynamicLibrary.open()
4. Test ev_version(), ev_init/ev_free cycle

**Deliverable:** generate() works on Android (CPU backend)

### Phase 2: Android Vulkan Backend

**Goal:** GPU acceleration on supported devices

1. Configure GGML_VULKAN in CMake
2. Handle vulkan-shaders-gen cross-compilation
3. Implement runtime backend selection with CPU fallback
4. Benchmark CPU vs Vulkan

**Deliverable:** Vulkan acceleration with fallback

### Phase 3: Streaming C++ Implementation

**Goal:** Complete ev_stream_* implementation

1. Implement ev_generate_stream() - tokenize, evaluate prompt
2. Implement ev_stream_next() - sample one token, advance state
3. Implement ev_stream_has_next(), ev_stream_cancel(), ev_stream_free()
4. Test from C++ directly

**Deliverable:** Streaming works in C++ layer

### Phase 4: Dart Streaming Integration

**Goal:** Stream<String> API in Dart

1. Implement worker isolate pattern
2. Add generateStream() to EdgeVeda class
3. Handle cancellation and cleanup
4. Integration tests

**Deliverable:** Full streaming API in Flutter

### Build Order Rationale

| Order | Component | Rationale |
|-------|-----------|-----------|
| 1 | Android CPU | Validates build system without Vulkan complexity |
| 2 | Android Vulkan | Can iterate on GPU with working base |
| 3 | Streaming C++ | Single-threaded, testable without Dart |
| 4 | Dart Streaming | Depends on working streaming in C++ |

**Why Android before Streaming:**
- Android is more self-contained (build system only)
- Streaming touches both C++ and Dart
- Users want Android support (platform expansion)
- Streaming is additive (existing generate() still works)

---

## Sources

### Official Documentation
- [Flutter Android C Interop](https://docs.flutter.dev/platform-integration/android/c-interop)
- [Dart Isolates](https://dart.dev/language/isolates)
- [ReceivePort/SendPort](https://api.flutter.dev/flutter/dart-isolate/ReceivePort-class.html)
- [NativeCallable.listener](https://api.flutter.dev/flutter/dart-ffi/NativeCallable/NativeCallable.listener.html)
- [Android NDK CMake](https://developer.android.com/studio/projects/add-native-code)

### llama.cpp References
- [llama.cpp Android Build](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md)
- [Vulkan Android Discussion](https://github.com/ggml-org/llama.cpp/discussions/8874)
- [llama.android Example](https://github.com/ggml-org/llama.cpp/tree/master/examples/llama.android)

### Existing Codebase Analysis
- `/Users/ram/Documents/explore/edge/core/CMakeLists.txt` - Build configuration
- `/Users/ram/Documents/explore/edge/core/src/engine.cpp` - C++ implementation
- `/Users/ram/Documents/explore/edge/flutter/lib/src/edge_veda_impl.dart` - Dart SDK
- `/Users/ram/Documents/explore/edge/flutter/android/build.gradle` - Android build config
- `/Users/ram/Documents/explore/edge/core/third_party/llama.cpp/examples/simple/simple.cpp` - llama.cpp streaming pattern
