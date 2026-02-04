# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2024-02-04

### Added
- **Core**: Initial release of C++ inference core wrapping llama.cpp, whisper.cpp, and Kokoro-82M.
- **Flutter**: Support for iOS and Android with Dart FFI bindings.
- **iOS**: Swift Package Manager support with Metal acceleration.
- **Android**: JNI bindings with Vulkan/NNAPI support.
- **React Native**: Initial JSI module structure.
- **Docs**: Comprehensive README with architecture overview and benchmarks.
- **License**: Apache 2.0 License.

### Changed
- Standardized API for streaming generation across platforms.
- Optimized memory usage for 4-bit quantized models.

### Fixed
- Initial build scripts for cross-platform compilation.
