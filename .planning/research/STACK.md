# Tech Stack Research

## Core Inference (C++)
- **llama.cpp**: Keep current submodule (b7952).
- **ggml-metal.m**: Included in llama.cpp for iOS GPU acceleration.
- **ggml-vulkan.cpp**: Included in llama.cpp for Android GPU acceleration.
- **Android NNAPI**: Alternative valid backend if Vulkan fails (older devices).

## Native Bridges
- **Android (Kotlin)**:
    - **JNI (Java Native Interface)**: Standard way to access C++ from JVM.
    - **Direct ByteBuffer**: `NewDirectByteBuffer` for zero-copy data transfer.
    - **Android NDK**: Required for compiling C++ for Android.
    - **Lifecycle**: `androidx.lifecycle` to bind C++ context to UI lifecycle.

- **iOS/macOS (Swift/Obj-C)**:
    - **Bridging Header**: Expose C headers to Swift.
    - **C Interop**: Direct calling of C functions from Swift is clean.
    - **MetalKit**: For direct GPU profiling/debug.

- **React Native**:
    - **JSI (JavaScript Interface)**: Replaces the old Async Bridge. Allows sync C++ calls.
    - **TurboModules**: New architecture for Native Modules.
    - **react-native-new-architecture**: Required for JSI/TurboModules.

## Performance
- **mmap**: `llama_model_load_from_file` with `use_mmap=true`.
- **Quantization**: `Q4_K` or `Q8_0` for KV cache (reduces VRAM usage).
