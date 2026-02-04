# Changelog

All notable changes to the Edge Veda Flutter SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Flutter Web support (WASM + WebGPU)
- Speech-to-Text integration (Whisper)
- Text-to-Speech integration (Kokoro-82M)
- Voice Activity Detection (VAD)
- Prompt caching
- LoRA adapter support
- macOS and Windows desktop support

## [1.0.0] - 2026-02-04

### Added
- Initial release of Edge Veda Flutter SDK
- On-device LLM inference with llama.cpp integration
- FFI bindings for native C++ core
- Hardware acceleration support (Metal on iOS, Vulkan on Android)
- Streaming text generation with real-time tokens
- Model download and management system
- Checksum verification for model integrity
- Memory-safe operations with configurable limits
- Pre-configured model registry (Llama 3.2, Phi 3.5, Gemma 2, TinyLlama)
- Comprehensive error handling with typed exceptions
- Example chat application
- Full API documentation

### Features
- EdgeVeda class for LLM inference
- ModelManager for downloading and caching models
- GenerateOptions for fine-grained control
- Token streaming with TokenChunk
- Progress tracking for model downloads
- Memory usage monitoring
- Support for system prompts and JSON mode
- Stop sequences for controlled generation

### Platform Support
- iOS 13.0+ with Metal acceleration
- Android API 24+ with Vulkan support

### Documentation
- Complete README with quick start guide
- API reference documentation
- Example application
- Best practices and troubleshooting
