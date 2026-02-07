/// FFI bindings for Edge Veda native library
///
/// This file provides FFI bindings that exactly match the edge_veda.h C API.
/// All struct layouts and function signatures must be byte-for-byte compatible.
///
/// Memory ownership rules:
/// - Dart allocates with toNativeUtf8() -> Dart frees with calloc.free()
/// - C++ allocates via ev_generate() -> C++ frees with ev_free_string()
library;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

// =============================================================================
// Error Codes (matching ev_error_t in edge_veda.h)
// =============================================================================

/// Error codes returned by Edge Veda API functions
enum EvError {
  /// Operation successful
  success(0),

  /// Invalid parameter provided
  invalidParam(-1),

  /// Out of memory
  outOfMemory(-2),

  /// Failed to load model
  modelLoadFailed(-3),

  /// Failed to initialize backend
  backendInitFailed(-4),

  /// Inference operation failed
  inferenceFailed(-5),

  /// Invalid context
  contextInvalid(-6),

  /// Stream has ended
  streamEnded(-7),

  /// Feature not implemented
  notImplemented(-8),

  /// Memory limit exceeded
  memoryLimitExceeded(-9),

  /// Backend not supported on this platform
  unsupportedBackend(-10),

  /// Unknown error
  unknown(-999);

  final int value;
  const EvError(this.value);

  /// Create from C int value
  static EvError fromValue(int value) {
    return EvError.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EvError.unknown,
    );
  }
}

// =============================================================================
// Backend Types (matching ev_backend_t in edge_veda.h)
// =============================================================================

/// Backend types for inference
enum EvBackend {
  /// Automatically detect best backend
  auto_(0),

  /// Metal (iOS/macOS)
  metal(1),

  /// Vulkan (Android)
  vulkan(2),

  /// CPU fallback
  cpu(3);

  final int value;
  const EvBackend(this.value);

  /// Create from C int value
  static EvBackend fromValue(int value) {
    return EvBackend.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EvBackend.auto_,
    );
  }
}

// =============================================================================
// FFI Struct Definitions (matching edge_veda.h exactly)
// =============================================================================

/// Opaque context handle for Edge Veda inference engine
/// Corresponds to: typedef struct ev_context_impl* ev_context;
final class EvContextImpl extends Opaque {}

/// Configuration structure for initializing Edge Veda context
/// Corresponds to: ev_config in edge_veda.h
final class EvConfig extends Struct {
  /// Model file path (GGUF format)
  external Pointer<Utf8> modelPath;

  /// Backend to use (use EV_BACKEND_AUTO for automatic detection)
  @Int32()
  external int backend;

  /// Number of threads for CPU backend (0 = auto-detect)
  @Int32()
  external int numThreads;

  /// Context size (number of tokens)
  @Int32()
  external int contextSize;

  /// Batch size for processing
  @Int32()
  external int batchSize;

  /// Memory limit in bytes (0 = no limit)
  @Size()
  external int memoryLimitBytes;

  /// Enable memory auto-unload when limit is reached
  @Bool()
  external bool autoUnloadOnMemoryPressure;

  /// GPU layers to offload (-1 = all, 0 = none, >0 = specific count)
  @Int32()
  external int gpuLayers;

  /// Use memory mapping for model file
  @Bool()
  external bool useMmap;

  /// Lock model in memory (prevent swapping)
  @Bool()
  external bool useMlock;

  /// Seed for random number generation (-1 = random)
  @Int32()
  external int seed;

  /// Reserved for future use - must be NULL
  external Pointer<Void> reserved;
}

/// Parameters for text generation
/// Corresponds to: ev_generation_params in edge_veda.h
final class EvGenerationParams extends Struct {
  /// Maximum number of tokens to generate
  @Int32()
  external int maxTokens;

  /// Temperature for sampling (0.0 = deterministic, higher = more random)
  @Float()
  external double temperature;

  /// Top-p (nucleus) sampling threshold
  @Float()
  external double topP;

  /// Top-k sampling limit
  @Int32()
  external int topK;

  /// Repetition penalty (1.0 = no penalty)
  @Float()
  external double repeatPenalty;

  /// Frequency penalty
  @Float()
  external double frequencyPenalty;

  /// Presence penalty
  @Float()
  external double presencePenalty;

  /// Stop sequences (NULL-terminated array of strings)
  external Pointer<Pointer<Utf8>> stopSequences;

  /// Number of stop sequences
  @Int32()
  external int numStopSequences;

  /// Reserved for future use - must be NULL
  external Pointer<Void> reserved;
}

/// Memory usage statistics
/// Corresponds to: ev_memory_stats in edge_veda.h
final class EvMemoryStats extends Struct {
  /// Current memory usage in bytes
  @Size()
  external int currentBytes;

  /// Peak memory usage in bytes
  @Size()
  external int peakBytes;

  /// Memory limit in bytes (0 = no limit)
  @Size()
  external int limitBytes;

  /// Memory used by model in bytes
  @Size()
  external int modelBytes;

  /// Memory used by context in bytes
  @Size()
  external int contextBytes;

  /// Reserved for future use (8 size_t values)
  @Array(8)
  external Array<Size> reserved;
}

// =============================================================================
// Streaming Types (matching edge_veda.h)
// =============================================================================

/// Opaque stream handle for streaming generation
/// Corresponds to: typedef struct ev_stream_impl* ev_stream;
final class EvStreamImpl extends Opaque {}

// =============================================================================
// Vision Types (matching edge_veda.h Vision API)
// =============================================================================

/// Opaque context handle for Edge Veda vision inference engine
/// Corresponds to: typedef struct ev_vision_context_impl* ev_vision_context;
final class EvVisionContextImpl extends Opaque {}

/// Configuration structure for initializing vision context
/// Corresponds to: ev_vision_config in edge_veda.h
final class EvVisionConfig extends Struct {
  /// Path to VLM GGUF model file
  external Pointer<Utf8> modelPath;

  /// Path to mmproj (multimodal projector) GGUF file
  external Pointer<Utf8> mmprojPath;

  /// Number of CPU threads (0 = auto-detect)
  @Int32()
  external int numThreads;

  /// Token context window size (0 = auto, based on model)
  @Int32()
  external int contextSize;

  /// Batch size for processing (0 = default 512)
  @Int32()
  external int batchSize;

  /// Memory limit in bytes (0 = no limit)
  @Size()
  external int memoryLimitBytes;

  /// GPU layers to offload (-1 = all, 0 = none)
  @Int32()
  external int gpuLayers;

  /// Use memory mapping for model file
  @Bool()
  external bool useMmap;

  /// Reserved for future use - must be NULL
  external Pointer<Void> reserved;
}

/// Timing data from last vision inference
/// Corresponds to: ev_timings_data in edge_veda.h
final class EvTimingsData extends Struct {
  /// Model load time in milliseconds
  @Double()
  external double modelLoadMs;

  /// Image encoding time in milliseconds
  @Double()
  external double imageEncodeMs;

  /// Prompt evaluation time in milliseconds
  @Double()
  external double promptEvalMs;

  /// Token decode/generation time in milliseconds
  @Double()
  external double decodeMs;

  /// Number of prompt tokens processed
  @Int32()
  external int promptTokens;

  /// Number of tokens generated
  @Int32()
  external int generatedTokens;
}

// =============================================================================
// Native Function Type Definitions
// =============================================================================

// Version / Error
typedef EvVersionNative = Pointer<Utf8> Function();
typedef EvVersionDart = Pointer<Utf8> Function();

typedef EvErrorStringNative = Pointer<Utf8> Function(Int32 error);
typedef EvErrorStringDart = Pointer<Utf8> Function(int error);

// Backend detection
typedef EvDetectBackendNative = Int32 Function();
typedef EvDetectBackendDart = int Function();

typedef EvIsBackendAvailableNative = Bool Function(Int32 backend);
typedef EvIsBackendAvailableDart = bool Function(int backend);

typedef EvBackendNameNative = Pointer<Utf8> Function(Int32 backend);
typedef EvBackendNameDart = Pointer<Utf8> Function(int backend);

// Configuration
typedef EvConfigDefaultNative = Void Function(Pointer<EvConfig> config);
typedef EvConfigDefaultDart = void Function(Pointer<EvConfig> config);

// Context management
typedef EvInitNative = Pointer<EvContextImpl> Function(
  Pointer<EvConfig> config,
  Pointer<Int32> error,
);
typedef EvInitDart = Pointer<EvContextImpl> Function(
  Pointer<EvConfig> config,
  Pointer<Int32> error,
);

typedef EvFreeNative = Void Function(Pointer<EvContextImpl> ctx);
typedef EvFreeDart = void Function(Pointer<EvContextImpl> ctx);

typedef EvIsValidNative = Bool Function(Pointer<EvContextImpl> ctx);
typedef EvIsValidDart = bool Function(Pointer<EvContextImpl> ctx);

// Generation parameters
typedef EvGenerationParamsDefaultNative = Void Function(
  Pointer<EvGenerationParams> params,
);
typedef EvGenerationParamsDefaultDart = void Function(
  Pointer<EvGenerationParams> params,
);

// Single-shot generation
typedef EvGenerateNative = Int32 Function(
  Pointer<EvContextImpl> ctx,
  Pointer<Utf8> prompt,
  Pointer<EvGenerationParams> params,
  Pointer<Pointer<Utf8>> output,
);
typedef EvGenerateDart = int Function(
  Pointer<EvContextImpl> ctx,
  Pointer<Utf8> prompt,
  Pointer<EvGenerationParams> params,
  Pointer<Pointer<Utf8>> output,
);

typedef EvFreeStringNative = Void Function(Pointer<Utf8> str);
typedef EvFreeStringDart = void Function(Pointer<Utf8> str);

// Memory management
typedef EvGetMemoryUsageNative = Int32 Function(
  Pointer<EvContextImpl> ctx,
  Pointer<EvMemoryStats> stats,
);
typedef EvGetMemoryUsageDart = int Function(
  Pointer<EvContextImpl> ctx,
  Pointer<EvMemoryStats> stats,
);

typedef EvSetMemoryLimitNative = Int32 Function(
  Pointer<EvContextImpl> ctx,
  Size limitBytes,
);
typedef EvSetMemoryLimitDart = int Function(
  Pointer<EvContextImpl> ctx,
  int limitBytes,
);

/// Memory pressure callback function type
/// void (*ev_memory_pressure_callback)(void* user_data, size_t current_bytes, size_t limit_bytes)
typedef EvMemoryPressureCallbackNative = Void Function(
  Pointer<Void> userData,
  Size currentBytes,
  Size limitBytes,
);

typedef EvSetMemoryPressureCallbackNative = Int32 Function(
  Pointer<EvContextImpl> ctx,
  Pointer<NativeFunction<EvMemoryPressureCallbackNative>> callback,
  Pointer<Void> userData,
);
typedef EvSetMemoryPressureCallbackDart = int Function(
  Pointer<EvContextImpl> ctx,
  Pointer<NativeFunction<EvMemoryPressureCallbackNative>> callback,
  Pointer<Void> userData,
);

typedef EvMemoryCleanupNative = Int32 Function(Pointer<EvContextImpl> ctx);
typedef EvMemoryCleanupDart = int Function(Pointer<EvContextImpl> ctx);

// Utility functions
typedef EvSetVerboseNative = Void Function(Bool enable);
typedef EvSetVerboseDart = void Function(bool enable);

typedef EvGetLastErrorNative = Pointer<Utf8> Function(Pointer<EvContextImpl> ctx);
typedef EvGetLastErrorDart = Pointer<Utf8> Function(Pointer<EvContextImpl> ctx);

typedef EvResetNative = Int32 Function(Pointer<EvContextImpl> ctx);
typedef EvResetDart = int Function(Pointer<EvContextImpl> ctx);

// =============================================================================
// Streaming Generation Function Types
// =============================================================================

/// ev_stream ev_generate_stream(ev_context ctx, const char* prompt, const ev_generation_params* params, ev_error_t* error)
typedef EvGenerateStreamNative = Pointer<EvStreamImpl> Function(
  Pointer<EvContextImpl> ctx,
  Pointer<Utf8> prompt,
  Pointer<EvGenerationParams> params,
  Pointer<Int32> error,
);
typedef EvGenerateStreamDart = Pointer<EvStreamImpl> Function(
  Pointer<EvContextImpl> ctx,
  Pointer<Utf8> prompt,
  Pointer<EvGenerationParams> params,
  Pointer<Int32> error,
);

/// char* ev_stream_next(ev_stream stream, ev_error_t* error)
typedef EvStreamNextNative = Pointer<Utf8> Function(
  Pointer<EvStreamImpl> stream,
  Pointer<Int32> error,
);
typedef EvStreamNextDart = Pointer<Utf8> Function(
  Pointer<EvStreamImpl> stream,
  Pointer<Int32> error,
);

/// bool ev_stream_has_next(ev_stream stream)
typedef EvStreamHasNextNative = Bool Function(Pointer<EvStreamImpl> stream);
typedef EvStreamHasNextDart = bool Function(Pointer<EvStreamImpl> stream);

/// void ev_stream_cancel(ev_stream stream)
typedef EvStreamCancelNative = Void Function(Pointer<EvStreamImpl> stream);
typedef EvStreamCancelDart = void Function(Pointer<EvStreamImpl> stream);

/// void ev_stream_free(ev_stream stream)
typedef EvStreamFreeNative = Void Function(Pointer<EvStreamImpl> stream);
typedef EvStreamFreeDart = void Function(Pointer<EvStreamImpl> stream);

// =============================================================================
// Vision Function Types (matching edge_veda.h Vision API)
// =============================================================================

/// void ev_vision_config_default(ev_vision_config* config)
typedef EvVisionConfigDefaultNative = Void Function(
  Pointer<EvVisionConfig> config,
);
typedef EvVisionConfigDefaultDart = void Function(
  Pointer<EvVisionConfig> config,
);

/// ev_vision_context ev_vision_init(const ev_vision_config* config, ev_error_t* error)
typedef EvVisionInitNative = Pointer<EvVisionContextImpl> Function(
  Pointer<EvVisionConfig> config,
  Pointer<Int32> error,
);
typedef EvVisionInitDart = Pointer<EvVisionContextImpl> Function(
  Pointer<EvVisionConfig> config,
  Pointer<Int32> error,
);

/// ev_error_t ev_vision_describe(ev_vision_context ctx, const unsigned char* image_bytes, int width, int height, const char* prompt, const ev_generation_params* params, char** output)
typedef EvVisionDescribeNative = Int32 Function(
  Pointer<EvVisionContextImpl> ctx,
  Pointer<UnsignedChar> imageBytes,
  Int32 width,
  Int32 height,
  Pointer<Utf8> prompt,
  Pointer<EvGenerationParams> params,
  Pointer<Pointer<Utf8>> output,
);
typedef EvVisionDescribeDart = int Function(
  Pointer<EvVisionContextImpl> ctx,
  Pointer<UnsignedChar> imageBytes,
  int width,
  int height,
  Pointer<Utf8> prompt,
  Pointer<EvGenerationParams> params,
  Pointer<Pointer<Utf8>> output,
);

/// void ev_vision_free(ev_vision_context ctx)
typedef EvVisionFreeNative = Void Function(Pointer<EvVisionContextImpl> ctx);
typedef EvVisionFreeDart = void Function(Pointer<EvVisionContextImpl> ctx);

/// bool ev_vision_is_valid(ev_vision_context ctx)
typedef EvVisionIsValidNative = Bool Function(Pointer<EvVisionContextImpl> ctx);
typedef EvVisionIsValidDart = bool Function(Pointer<EvVisionContextImpl> ctx);

/// ev_error_t ev_vision_get_last_timings(ev_vision_context ctx, ev_timings_data* timings)
typedef EvVisionGetLastTimingsNative = Int32 Function(
  Pointer<EvVisionContextImpl> ctx,
  Pointer<EvTimingsData> timings,
);
typedef EvVisionGetLastTimingsDart = int Function(
  Pointer<EvVisionContextImpl> ctx,
  Pointer<EvTimingsData> timings,
);

// =============================================================================
// Native Library Bindings
// =============================================================================

/// FFI bindings for Edge Veda native library
///
/// Provides singleton access to native library functions.
/// All function signatures match edge_veda.h exactly.
class EdgeVedaNativeBindings {
  static EdgeVedaNativeBindings? _instance;
  late final DynamicLibrary _dylib;

  EdgeVedaNativeBindings._() {
    _dylib = _loadLibrary();
    _initBindings();
  }

  /// Get singleton instance
  static EdgeVedaNativeBindings get instance {
    _instance ??= EdgeVedaNativeBindings._();
    return _instance!;
  }

  /// Load the native library based on platform
  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libedge_veda.so');
    } else if (Platform.isIOS) {
      // On iOS, the library is statically linked
      return DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libedge_veda.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libedge_veda.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('edge_veda.dll');
    } else {
      throw UnsupportedError(
        'Platform ${Platform.operatingSystem} is not supported',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Version / Error Functions
  // ---------------------------------------------------------------------------

  /// Get the version string of the Edge Veda SDK
  late final EvVersionDart evVersion;

  /// Get human-readable error message for error code
  late final EvErrorStringDart evErrorString;

  // ---------------------------------------------------------------------------
  // Backend Detection Functions
  // ---------------------------------------------------------------------------

  /// Detect the best available backend for current platform
  late final EvDetectBackendDart evDetectBackend;

  /// Check if a specific backend is available
  late final EvIsBackendAvailableDart evIsBackendAvailable;

  /// Get human-readable name for backend type
  late final EvBackendNameDart evBackendName;

  // ---------------------------------------------------------------------------
  // Configuration Functions
  // ---------------------------------------------------------------------------

  /// Get default configuration with recommended settings
  late final EvConfigDefaultDart evConfigDefault;

  // ---------------------------------------------------------------------------
  // Context Management Functions
  // ---------------------------------------------------------------------------

  /// Initialize Edge Veda context with configuration
  late final EvInitDart evInit;

  /// Free Edge Veda context and release all resources
  late final EvFreeDart evFree;

  /// Check if context is valid and ready for inference
  late final EvIsValidDart evIsValid;

  // ---------------------------------------------------------------------------
  // Generation Parameter Functions
  // ---------------------------------------------------------------------------

  /// Get default generation parameters
  late final EvGenerationParamsDefaultDart evGenerationParamsDefault;

  // ---------------------------------------------------------------------------
  // Single-Shot Generation Functions
  // ---------------------------------------------------------------------------

  /// Generate a complete response for given prompt
  late final EvGenerateDart evGenerate;

  /// Free string allocated by Edge Veda
  late final EvFreeStringDart evFreeString;

  // ---------------------------------------------------------------------------
  // Memory Management Functions
  // ---------------------------------------------------------------------------

  /// Get current memory usage statistics
  late final EvGetMemoryUsageDart evGetMemoryUsage;

  /// Set memory limit for context
  late final EvSetMemoryLimitDart evSetMemoryLimit;

  /// Register callback for memory pressure events
  late final EvSetMemoryPressureCallbackDart evSetMemoryPressureCallback;

  /// Manually trigger garbage collection and memory cleanup
  late final EvMemoryCleanupDart evMemoryCleanup;

  // ---------------------------------------------------------------------------
  // Utility Functions
  // ---------------------------------------------------------------------------

  /// Enable or disable verbose logging
  late final EvSetVerboseDart evSetVerbose;

  /// Get last error message for context
  late final EvGetLastErrorDart evGetLastError;

  /// Reset context state (clear conversation history)
  late final EvResetDart evReset;

  // ---------------------------------------------------------------------------
  // Streaming Generation Functions
  // ---------------------------------------------------------------------------

  /// Start streaming generation for given prompt
  late final EvGenerateStreamDart evGenerateStream;

  /// Get next token from streaming generation
  late final EvStreamNextDart evStreamNext;

  /// Check if stream has more tokens available
  late final EvStreamHasNextDart evStreamHasNext;

  /// Cancel ongoing streaming generation
  late final EvStreamCancelDart evStreamCancel;

  /// Free stream handle and release resources
  late final EvStreamFreeDart evStreamFree;

  // ---------------------------------------------------------------------------
  // Vision Functions
  // ---------------------------------------------------------------------------

  /// Get default vision configuration with recommended settings
  late final EvVisionConfigDefaultDart evVisionConfigDefault;

  /// Initialize vision context with VLM model and mmproj
  late final EvVisionInitDart evVisionInit;

  /// Describe an image using the vision model
  late final EvVisionDescribeDart evVisionDescribe;

  /// Free vision context and release all resources
  late final EvVisionFreeDart evVisionFree;

  /// Check if vision context is valid and ready for inference
  late final EvVisionIsValidDart evVisionIsValid;

  /// Get last inference timing data from vision context.
  ///
  /// This binding is resolved lazily because ev_vision_get_last_timings may
  /// not exist in older XCFramework builds. The VisionWorker wraps calls in
  /// try-catch so a lookup failure is gracefully handled.
  EvVisionGetLastTimingsDart get evVisionGetLastTimings {
    _evVisionGetLastTimings ??= _dylib.lookupFunction<
        EvVisionGetLastTimingsNative,
        EvVisionGetLastTimingsDart>('ev_vision_get_last_timings');
    return _evVisionGetLastTimings!;
  }

  EvVisionGetLastTimingsDart? _evVisionGetLastTimings;

  // ---------------------------------------------------------------------------
  // Binding Initialization
  // ---------------------------------------------------------------------------

  void _initBindings() {
    // Version / Error
    evVersion = _dylib.lookupFunction<EvVersionNative, EvVersionDart>(
      'ev_version',
    );
    evErrorString = _dylib.lookupFunction<EvErrorStringNative, EvErrorStringDart>(
      'ev_error_string',
    );

    // Backend detection
    evDetectBackend = _dylib.lookupFunction<EvDetectBackendNative, EvDetectBackendDart>(
      'ev_detect_backend',
    );
    evIsBackendAvailable = _dylib.lookupFunction<EvIsBackendAvailableNative, EvIsBackendAvailableDart>(
      'ev_is_backend_available',
    );
    evBackendName = _dylib.lookupFunction<EvBackendNameNative, EvBackendNameDart>(
      'ev_backend_name',
    );

    // Configuration
    evConfigDefault = _dylib.lookupFunction<EvConfigDefaultNative, EvConfigDefaultDart>(
      'ev_config_default',
    );

    // Context management
    evInit = _dylib.lookupFunction<EvInitNative, EvInitDart>('ev_init');
    evFree = _dylib.lookupFunction<EvFreeNative, EvFreeDart>('ev_free');
    evIsValid = _dylib.lookupFunction<EvIsValidNative, EvIsValidDart>(
      'ev_is_valid',
    );

    // Generation parameters
    evGenerationParamsDefault = _dylib.lookupFunction<
      EvGenerationParamsDefaultNative,
      EvGenerationParamsDefaultDart
    >('ev_generation_params_default');

    // Single-shot generation
    evGenerate = _dylib.lookupFunction<EvGenerateNative, EvGenerateDart>(
      'ev_generate',
    );
    evFreeString = _dylib.lookupFunction<EvFreeStringNative, EvFreeStringDart>(
      'ev_free_string',
    );

    // Memory management
    evGetMemoryUsage = _dylib.lookupFunction<EvGetMemoryUsageNative, EvGetMemoryUsageDart>(
      'ev_get_memory_usage',
    );
    evSetMemoryLimit = _dylib.lookupFunction<EvSetMemoryLimitNative, EvSetMemoryLimitDart>(
      'ev_set_memory_limit',
    );
    evSetMemoryPressureCallback = _dylib.lookupFunction<
      EvSetMemoryPressureCallbackNative,
      EvSetMemoryPressureCallbackDart
    >('ev_set_memory_pressure_callback');
    evMemoryCleanup = _dylib.lookupFunction<EvMemoryCleanupNative, EvMemoryCleanupDart>(
      'ev_memory_cleanup',
    );

    // Utility functions
    evSetVerbose = _dylib.lookupFunction<EvSetVerboseNative, EvSetVerboseDart>(
      'ev_set_verbose',
    );
    evGetLastError = _dylib.lookupFunction<EvGetLastErrorNative, EvGetLastErrorDart>(
      'ev_get_last_error',
    );
    evReset = _dylib.lookupFunction<EvResetNative, EvResetDart>('ev_reset');

    // Streaming generation
    evGenerateStream = _dylib.lookupFunction<EvGenerateStreamNative, EvGenerateStreamDart>(
      'ev_generate_stream',
    );
    evStreamNext = _dylib.lookupFunction<EvStreamNextNative, EvStreamNextDart>(
      'ev_stream_next',
    );
    evStreamHasNext = _dylib.lookupFunction<EvStreamHasNextNative, EvStreamHasNextDart>(
      'ev_stream_has_next',
    );
    evStreamCancel = _dylib.lookupFunction<EvStreamCancelNative, EvStreamCancelDart>(
      'ev_stream_cancel',
    );
    evStreamFree = _dylib.lookupFunction<EvStreamFreeNative, EvStreamFreeDart>(
      'ev_stream_free',
    );

    // Vision functions
    evVisionConfigDefault = _dylib.lookupFunction<
      EvVisionConfigDefaultNative,
      EvVisionConfigDefaultDart
    >('ev_vision_config_default');
    evVisionInit = _dylib.lookupFunction<EvVisionInitNative, EvVisionInitDart>(
      'ev_vision_init',
    );
    evVisionDescribe = _dylib.lookupFunction<EvVisionDescribeNative, EvVisionDescribeDart>(
      'ev_vision_describe',
    );
    evVisionFree = _dylib.lookupFunction<EvVisionFreeNative, EvVisionFreeDart>(
      'ev_vision_free',
    );
    evVisionIsValid = _dylib.lookupFunction<EvVisionIsValidNative, EvVisionIsValidDart>(
      'ev_vision_is_valid',
    );
    // Note: evVisionGetLastTimings is resolved lazily (see getter above)
    // because it may not exist in older XCFramework builds.
  }
}
