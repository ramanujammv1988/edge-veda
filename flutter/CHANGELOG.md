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

## [1.1.0] - 2026-02-06

### Added
- Vision Language Model (VLM) support with SmolVLM2-500M for real-time image description
- `initVision()` and `describeImage()` APIs for camera-based object recognition
- Camera utilities (`CameraUtils`) for BGRA/YUV420 to RGB conversion
- Vision tab in demo app with continuous camera scanning and AR-style overlay
- Streaming text generation via `generateStream()` with progressive token display
- `CancelToken` for mid-stream generation cancellation
- Pull-based streaming architecture (ev_stream_next loop, not callback-based)
- `VisionConfig` and `VisionSession` for vision model lifecycle management
- SmolVLM2-500M and mmproj entries in `ModelRegistry`
- Dark minimal theme for demo app (Claude-inspired aesthetic)

### Changed
- Upgraded llama.cpp from b4658 to b7952
- Integrated libmtmd (multimodal encoding) from llama.cpp tools/mtmd
- XCFramework now includes vision engine (~7.6MB with vision support)
- Demo app redesigned with dark theme, polished chat bubbles, and streamlined UI

### Platform Support
- iOS 13.0+ with Metal acceleration (text + vision)
- Android API 24+ with CPU backend (vision support pending Android build)

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
