# Research Summary

## Stack
- **Core**: llama.cpp with Metal and Vulkan backends.
- **Android**: Kotlin via JNI with Direct ByteBuffers.
- **React Native**: C++ TurboModules via JSI.
- **Optimization**: mmap loading + Q4_K/Q8_0 KV cache.

## Key Findings
1.  **Zero-Copy is Essential**: For audio/image inputs, copying data across boundaries kills performance. Use `NewDirectByteBuffer` (JNI) and `ArrayBuffer` / JSI (React Native).
2.  **Thread Safety**: Inference must be off-main-thread. Handling lifecycle (user leaving screen during generation) is the #1 crash risk ("Context invalid").
3.  **Vulkan Fragmentation**: Android support defaults to CPU if Vulkan init fails.
4.  **OOM Handling**: iOS Metal allows unified memory, but going over limit kills the app. Dynamic `n_gpu_layers` calculation is a must-have differentiator.

## Recommendations
- Implement "Safe Loading": Calculate available RAM before loading model layers to GPU.
- Use "Lifecycle-Aware" C++ wrappers that automatically cancel/free on UI destruction.
- Implement the "Truth Dashboard" early to validate the 200ms TTFT claims realistically.
