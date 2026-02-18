# Architecture Research

## Native Bridge Design

### Android (Kotlin)
```
[ViewModel] <-> [JNI Wrapper (Java)] <-> [JNI Layer (C++)] <-> [Edge Veda Core]
```
- **Lifecycle**: ViewModel owns the C++ pointer context. `onCleared()` triggers `ev_free()`.
- **Data**: ByteBuffers for heavy data (audio/models). Primitives for config.

### React Native (JSI)
```
[JS Thread] <-> [JSI HostObject (C++)] <-> [Edge Veda Core]
```
- **HostObject**: Exposes `generate()` as a distinct method in JS.
- **Shared Memory**: `ArrayBuffer` in JS maps to `uint8_t*` in C++.
- **Threading**: Inference MUST run on a background thread, not the JS thread (to avoid freezing UI). Use `CallInvoker` to send updates back to JS.

## Hardware Acceleration
- **Unified Memory (Metal)**: CPU and GPU share memory. `mmap` works perfectly here.
- **Discrete/Unified (Vulkan)**: Android memory models vary. Need explicit buffer management in `ggml-vulkan`.

## Unified C++ Bridge
- Current `EdgeVeda_infer_token` is a stub/wrapper.
- **Optimization**: Replace with direct loop calling `llama_decode` to support batching and KV-cache management directly.
