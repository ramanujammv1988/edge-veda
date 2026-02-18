/// RAII-style native memory management helpers for Edge Veda FFI
///
/// This file provides memory management patterns that ensure cleanup in all code paths
/// (success, exception, early return). Following RAII (Resource Acquisition Is Initialization)
/// principles prevents memory leaks in FFI code.
///
/// ## Memory Ownership Rules
///
/// **Dart allocates -> Dart frees:**
/// When Dart code allocates memory using `toNativeUtf8()` or `calloc<T>()`,
/// Dart must free it using `calloc.free()`. Use the scope helpers in this file.
///
/// **C++ allocates -> C++ frees:**
/// When C++ code allocates memory (e.g., `ev_generate()` returns a string),
/// it must be freed using the corresponding C++ function (`ev_free_string()`).
/// Never use `calloc.free()` on memory allocated by C++.
///
/// ## Usage Example
///
/// ```dart
/// // Safe string passing to FFI
/// 'Hello, world!'.useNative((promptPtr) {
///   final result = bindings.evGenerate(ctx, promptPtr, params, outputPtr);
///   // promptPtr automatically freed after this block
/// });
///
/// // Safe config allocation
/// final configScope = NativeConfigScope(myConfig);
/// try {
///   final ctx = bindings.evInit(configScope.ptr, errorPtr);
///   // ... use ctx
/// } finally {
///   configScope.free();
/// }
/// ```
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

// =============================================================================
// String Scope Helper
// =============================================================================

/// Extension for safely using Dart strings in FFI calls
///
/// Converts the string to native UTF-8, executes the callback,
/// then automatically frees the native memory.
extension NativeStringScope on String {
  /// Execute a function with this string as a native UTF-8 pointer
  ///
  /// The pointer is automatically freed after the function returns,
  /// even if an exception is thrown.
  ///
  /// Example:
  /// ```dart
  /// final result = 'Hello'.useNative((ptr) => someFfiCall(ptr));
  /// ```
  R useNative<R>(R Function(Pointer<Utf8>) fn) {
    final ptr = toNativeUtf8();
    try {
      return fn(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Execute an async function with this string as a native UTF-8 pointer
  ///
  /// The pointer is automatically freed after the future completes,
  /// even if an exception is thrown.
  ///
  /// WARNING: The pointer must not be stored or used after the future completes.
  /// Do not pass to background isolates.
  Future<R> useNativeAsync<R>(Future<R> Function(Pointer<Utf8>) fn) async {
    final ptr = toNativeUtf8();
    try {
      return await fn(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
}

/// Extension for safely converting native strings to Dart
extension NativeStringConversion on Pointer<Utf8> {
  /// Convert native UTF-8 pointer to Dart string
  ///
  /// Returns empty string if pointer is null.
  /// Does NOT free the pointer - caller must manage memory.
  String toDartStringSafe() {
    if (this == nullptr) {
      return '';
    }
    return toDartString();
  }

  /// Convert native UTF-8 pointer to Dart string and free with ev_free_string
  ///
  /// Use this for strings allocated by C++ (e.g., ev_generate output).
  /// Returns empty string if pointer is null.
  String toDartStringAndFree(EdgeVedaNativeBindings bindings) {
    if (this == nullptr) {
      return '';
    }
    final str = toDartString();
    bindings.evFreeString(this);
    return str;
  }
}

// =============================================================================
// Config Scope Helper
// =============================================================================

/// Dart-side configuration for Edge Veda
///
/// This is the user-facing configuration class. Use [NativeConfigScope]
/// to convert it to native format for FFI calls.
class EdgeVedaConfig {
  /// Path to the GGUF model file
  final String modelPath;

  /// Backend to use (auto, metal, cpu)
  final EvBackend backend;

  /// Number of CPU threads (0 = auto-detect)
  final int numThreads;

  /// Context size in tokens
  final int contextSize;

  /// Batch size for processing
  final int batchSize;

  /// Memory limit in bytes (0 = no limit)
  final int memoryLimitBytes;

  /// Auto-unload on memory pressure
  final bool autoUnloadOnMemoryPressure;

  /// GPU layers to offload (-1 = all, 0 = none)
  final int gpuLayers;

  /// Use memory mapping for model
  final bool useMmap;

  /// Lock model in memory
  final bool useMlock;

  /// Random seed (-1 = random)
  final int seed;

  /// Flash attention type (-1=auto, 0=disabled, 1=enabled)
  final int flashAttn;

  /// KV cache type for keys (1=F16, 8=Q8_0)
  final int kvCacheTypeK;

  /// KV cache type for values (1=F16, 8=Q8_0)
  final int kvCacheTypeV;

  const EdgeVedaConfig({
    required this.modelPath,
    this.backend = EvBackend.auto_,
    this.numThreads = 0,
    this.contextSize = 2048,
    this.batchSize = 512,
    this.memoryLimitBytes = 0,
    this.autoUnloadOnMemoryPressure = true,
    this.gpuLayers = -1,
    this.useMmap = true,
    this.useMlock = false,
    this.seed = -1,
    this.flashAttn = -1,
    this.kvCacheTypeK = 8,
    this.kvCacheTypeV = 8,
  });
}

/// RAII scope for native ev_config struct
///
/// Allocates and populates an [EvConfig] struct, managing the lifetime
/// of both the struct and any strings it contains.
///
/// Usage:
/// ```dart
/// final scope = NativeConfigScope(config);
/// try {
///   final ctx = bindings.evInit(scope.ptr, errorPtr);
///   // ... use ctx
/// } finally {
///   scope.free();
/// }
/// ```
class NativeConfigScope {
  /// Pointer to the native ev_config struct
  final Pointer<EvConfig> ptr;

  /// Pointer to model path string (must be freed separately)
  Pointer<Utf8>? _modelPathPtr;

  /// Whether this scope has been freed
  bool _isFreed = false;

  /// Create a native config scope from Dart config
  NativeConfigScope(EdgeVedaConfig config) : ptr = calloc<EvConfig>() {
    _modelPathPtr = config.modelPath.toNativeUtf8();

    ptr.ref.modelPath = _modelPathPtr!;
    ptr.ref.backend = config.backend.value;
    ptr.ref.numThreads = config.numThreads;
    ptr.ref.contextSize = config.contextSize;
    ptr.ref.batchSize = config.batchSize;
    ptr.ref.memoryLimitBytes = config.memoryLimitBytes;
    ptr.ref.autoUnloadOnMemoryPressure = config.autoUnloadOnMemoryPressure;
    ptr.ref.gpuLayers = config.gpuLayers;
    ptr.ref.useMmap = config.useMmap;
    ptr.ref.useMlock = config.useMlock;
    ptr.ref.seed = config.seed;
    ptr.ref.flashAttn = config.flashAttn;
    ptr.ref.kvCacheTypeK = config.kvCacheTypeK;
    ptr.ref.kvCacheTypeV = config.kvCacheTypeV;
    ptr.ref.reserved = nullptr;
  }

  /// Free all native memory associated with this scope
  ///
  /// Safe to call multiple times.
  void free() {
    if (_isFreed) return;
    _isFreed = true;

    if (_modelPathPtr != null) {
      calloc.free(_modelPathPtr!);
      _modelPathPtr = null;
    }
    calloc.free(ptr);
  }

  /// Execute a function with the native config, automatically freeing after
  R use<R>(R Function(Pointer<EvConfig>) fn) {
    try {
      return fn(ptr);
    } finally {
      free();
    }
  }
}

// =============================================================================
// Generation Params Scope Helper
// =============================================================================

/// Dart-side generation parameters
///
/// This is the user-facing parameters class. Use [NativeParamsScope]
/// to convert it to native format for FFI calls.
class GenerationParams {
  /// Maximum tokens to generate
  final int maxTokens;

  /// Temperature (0.0 = deterministic)
  final double temperature;

  /// Top-p sampling threshold
  final double topP;

  /// Top-k sampling limit
  final int topK;

  /// Repetition penalty (1.0 = none)
  final double repeatPenalty;

  /// Frequency penalty
  final double frequencyPenalty;

  /// Presence penalty
  final double presencePenalty;

  /// Stop sequences
  final List<String> stopSequences;

  /// GBNF grammar string for constrained decoding (null = no constraint)
  final String? grammarStr;

  /// Grammar root rule name (null = "root")
  final String? grammarRoot;

  /// Confidence threshold for cloud handoff (0.0 = disabled)
  final double confidenceThreshold;

  const GenerationParams({
    this.maxTokens = 256,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.stopSequences = const [],
    this.grammarStr,
    this.grammarRoot,
    this.confidenceThreshold = 0.0,
  });

  /// Default parameters for quick use
  static const defaults = GenerationParams();
}

/// RAII scope for native ev_generation_params struct
///
/// Allocates and populates an [EvGenerationParams] struct, managing the lifetime
/// of both the struct and any stop sequence strings it contains.
///
/// Usage:
/// ```dart
/// final scope = NativeParamsScope(params);
/// try {
///   final result = bindings.evGenerate(ctx, prompt, scope.ptr, output);
///   // ... use result
/// } finally {
///   scope.free();
/// }
/// ```
class NativeParamsScope {
  /// Pointer to the native ev_generation_params struct
  final Pointer<EvGenerationParams> ptr;

  /// Pointers to stop sequence strings (must be freed)
  final List<Pointer<Utf8>> _stopSequencePtrs = [];

  /// Pointer to stop sequences array
  Pointer<Pointer<Utf8>>? _stopSequencesArrayPtr;

  /// Grammar string pointer (must be freed if non-null)
  Pointer<Utf8>? _grammarStrPtr;

  /// Grammar root pointer (must be freed if non-null)
  Pointer<Utf8>? _grammarRootPtr;

  /// Whether this scope has been freed
  bool _isFreed = false;

  /// Create a native params scope from Dart params
  NativeParamsScope(GenerationParams params) : ptr = calloc<EvGenerationParams>() {
    ptr.ref.maxTokens = params.maxTokens;
    ptr.ref.temperature = params.temperature;
    ptr.ref.topP = params.topP;
    ptr.ref.topK = params.topK;
    ptr.ref.repeatPenalty = params.repeatPenalty;
    ptr.ref.frequencyPenalty = params.frequencyPenalty;
    ptr.ref.presencePenalty = params.presencePenalty;
    ptr.ref.numStopSequences = params.stopSequences.length;
    ptr.ref.reserved = nullptr;

    // Allocate stop sequences if any
    if (params.stopSequences.isNotEmpty) {
      _stopSequencesArrayPtr = calloc<Pointer<Utf8>>(params.stopSequences.length);

      for (var i = 0; i < params.stopSequences.length; i++) {
        final strPtr = params.stopSequences[i].toNativeUtf8();
        _stopSequencePtrs.add(strPtr);
        _stopSequencesArrayPtr![i] = strPtr;
      }

      ptr.ref.stopSequences = _stopSequencesArrayPtr!;
    } else {
      ptr.ref.stopSequences = nullptr;
    }

    // Allocate grammar strings if any
    if (params.grammarStr != null && params.grammarStr!.isNotEmpty) {
      _grammarStrPtr = params.grammarStr!.toNativeUtf8();
      ptr.ref.grammarStr = _grammarStrPtr!;
    } else {
      ptr.ref.grammarStr = nullptr;
    }

    if (params.grammarRoot != null && params.grammarRoot!.isNotEmpty) {
      _grammarRootPtr = params.grammarRoot!.toNativeUtf8();
      ptr.ref.grammarRoot = _grammarRootPtr!;
    } else {
      ptr.ref.grammarRoot = nullptr;
    }

    ptr.ref.confidenceThreshold = params.confidenceThreshold;
  }

  /// Free all native memory associated with this scope
  ///
  /// Safe to call multiple times.
  void free() {
    if (_isFreed) return;
    _isFreed = true;

    // Free individual stop sequence strings
    for (final strPtr in _stopSequencePtrs) {
      calloc.free(strPtr);
    }
    _stopSequencePtrs.clear();

    // Free the stop sequences array
    if (_stopSequencesArrayPtr != null) {
      calloc.free(_stopSequencesArrayPtr!);
      _stopSequencesArrayPtr = null;
    }

    // Free grammar string pointers
    if (_grammarStrPtr != null) {
      calloc.free(_grammarStrPtr!);
      _grammarStrPtr = null;
    }
    if (_grammarRootPtr != null) {
      calloc.free(_grammarRootPtr!);
      _grammarRootPtr = null;
    }

    // Free the params struct
    calloc.free(ptr);
  }

  /// Execute a function with the native params, automatically freeing after
  R use<R>(R Function(Pointer<EvGenerationParams>) fn) {
    try {
      return fn(ptr);
    } finally {
      free();
    }
  }
}

// =============================================================================
// Memory Stats Scope Helper
// =============================================================================

/// RAII scope for native ev_memory_stats struct
///
/// Allocates an [EvMemoryStats] struct for receiving memory statistics.
///
/// Usage:
/// ```dart
/// final scope = NativeMemoryStatsScope();
/// try {
///   final result = bindings.evGetMemoryUsage(ctx, scope.ptr);
///   if (result == EvError.success.value) {
///     print('Current: ${scope.currentBytes}');
///   }
/// } finally {
///   scope.free();
/// }
/// ```
class NativeMemoryStatsScope {
  /// Pointer to the native ev_memory_stats struct
  final Pointer<EvMemoryStats> ptr;

  /// Whether this scope has been freed
  bool _isFreed = false;

  /// Create a memory stats scope
  NativeMemoryStatsScope() : ptr = calloc<EvMemoryStats>();

  /// Current memory usage in bytes
  int get currentBytes => _isFreed ? 0 : ptr.ref.currentBytes;

  /// Peak memory usage in bytes
  int get peakBytes => _isFreed ? 0 : ptr.ref.peakBytes;

  /// Memory limit in bytes
  int get limitBytes => _isFreed ? 0 : ptr.ref.limitBytes;

  /// Memory used by model in bytes
  int get modelBytes => _isFreed ? 0 : ptr.ref.modelBytes;

  /// Memory used by context in bytes
  int get contextBytes => _isFreed ? 0 : ptr.ref.contextBytes;

  /// Free native memory
  ///
  /// Safe to call multiple times.
  void free() {
    if (_isFreed) return;
    _isFreed = true;
    calloc.free(ptr);
  }

  /// Execute a function with the native stats struct, automatically freeing after
  R use<R>(R Function(Pointer<EvMemoryStats>) fn) {
    try {
      return fn(ptr);
    } finally {
      free();
    }
  }
}

// =============================================================================
// Output String Scope Helper
// =============================================================================

/// RAII scope for receiving output strings from FFI calls
///
/// Allocates a pointer-to-pointer for receiving string output from functions
/// like ev_generate that allocate their own string.
///
/// Usage:
/// ```dart
/// final scope = NativeOutputStringScope();
/// try {
///   final result = bindings.evGenerate(ctx, prompt, params, scope.ptr);
///   if (result == EvError.success.value) {
///     final output = scope.getDartStringAndFree(bindings);
///     print(output);
///   }
/// } finally {
///   scope.free();
/// }
/// ```
class NativeOutputStringScope {
  /// Pointer to pointer for receiving output string
  final Pointer<Pointer<Utf8>> ptr;

  /// Whether this scope has been freed
  bool _isFreed = false;

  /// Create an output string scope
  NativeOutputStringScope() : ptr = calloc<Pointer<Utf8>>() {
    ptr.value = nullptr;
  }

  /// Get the output string and free it using ev_free_string
  ///
  /// Must be called before [free]. Returns empty string if no output.
  String getDartStringAndFree(EdgeVedaNativeBindings bindings) {
    if (_isFreed || ptr.value == nullptr) {
      return '';
    }
    final str = ptr.value.toDartString();
    bindings.evFreeString(ptr.value);
    ptr.value = nullptr;
    return str;
  }

  /// Free the pointer-to-pointer (not the string itself)
  ///
  /// Call [getDartStringAndFree] first to get the output and free the
  /// C++-allocated string. This only frees the Dart-allocated pointer.
  ///
  /// Safe to call multiple times.
  void free() {
    if (_isFreed) return;
    _isFreed = true;
    calloc.free(ptr);
  }
}

// =============================================================================
// Error Code Scope Helper
// =============================================================================

/// RAII scope for receiving error codes from FFI calls
///
/// Allocates an int pointer for receiving error codes from functions
/// like ev_init that return error codes via output parameter.
///
/// Usage:
/// ```dart
/// final scope = NativeErrorScope();
/// try {
///   final ctx = bindings.evInit(config, scope.ptr);
///   if (ctx == nullptr) {
///     print('Error: ${scope.error}');
///   }
/// } finally {
///   scope.free();
/// }
/// ```
class NativeErrorScope {
  /// Pointer for receiving error code
  final Pointer<Int32> ptr;

  /// Whether this scope has been freed
  bool _isFreed = false;

  /// Create an error scope
  NativeErrorScope() : ptr = calloc<Int32>() {
    ptr.value = 0;
  }

  /// Get the error code value
  int get value => _isFreed ? 0 : ptr.value;

  /// Get the error as enum
  EvError get error => EvError.fromValue(value);

  /// Check if operation succeeded
  bool get isSuccess => value == EvError.success.value;

  /// Free native memory
  ///
  /// Safe to call multiple times.
  void free() {
    if (_isFreed) return;
    _isFreed = true;
    calloc.free(ptr);
  }
}
