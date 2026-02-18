# Pitfalls Research

## Memory Leaks
- **JNI**: Forgetting to `DeleteLocalRef` or not freeing C++ context in `onDestroy`.
- **React Native**: JSI objects are C++ lifecycle managed. JS garbage collection doesn't potentially free C++ memory immediately. Explicit cleanup methods are safer.

## Concurrency
- **UI Freeze**: Calling inference on the Main Thread (Android) or JS Thread (React Native) will freeze the app. **MUST** use background threads/pools.
- **Race Conditions**: User closing chat while inference is running. C++ context freed while inference thread tries to access it -> Segfault. Need `std::shared_ptr` or robust mutex locking/cancellation.

## Hardware quirks
- **Vulkan**: Driver bugs on varying Android fragmentation (Pixel vs Samsung vs Xiaomi). Validating on one device isn't enough.
- **Metal**: OOM crashes if `n_gpu_layers` is too high. iOS kills the app instantly.

## Build System
- **Complex Linking**: Linking C++ + NDK + CMake + Gradle + CocoaPods + Swift is error-prone.
- **Binary Size**: `llama.cpp` + backends can bloom APK/IPA size. Strip symbols and unused backends for release.
