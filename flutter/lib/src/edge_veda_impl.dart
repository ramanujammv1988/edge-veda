/// Main implementation of Edge Veda SDK using background isolates
///
/// All FFI calls run in background isolates via Isolate.run() to prevent
/// blocking the UI thread. This is critical because FFI calls are synchronous
/// and would freeze the UI during inference (Pitfall 3 - Critical).
///
/// Key design decisions:
/// - No Pointer storage on main isolate (pointers can't transfer between isolates)
/// - Each Isolate.run() re-loads DynamicLibrary, creates context, performs op, frees context
/// - Only primitive data (String, int, etc.) crosses isolate boundaries
/// - Streaming deferred to v2 (requires long-lived worker isolate pattern)
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'ffi/bindings.dart';
import 'ffi/native_memory.dart' show NativeConfigScope, NativeParamsScope;
import 'types.dart';

/// Main Edge Veda SDK class for on-device AI inference
///
/// Uses Isolate.run() for all FFI calls to keep the UI responsive.
/// Each operation creates a fresh native context in the background isolate.
class EdgeVeda {
  /// Stored configuration (primitives only - safe across isolates)
  EdgeVedaConfig? _config;

  /// Whether the SDK has been initialized and validated
  bool _isInitialized = false;

  // Note: NO Pointer storage here - pointers can't transfer between isolates

  /// Whether the SDK is initialized
  bool get isInitialized => _isInitialized;

  /// Current configuration
  EdgeVedaConfig? get config => _config;

  /// Initialize Edge Veda with the given configuration
  ///
  /// Validates the configuration and tests that the model can be loaded.
  /// The actual context is created fresh in each background isolate call.
  Future<void> init(EdgeVedaConfig config) async {
    if (_isInitialized) {
      throw InitializationException(
        'EdgeVeda is already initialized. Call dispose() first.',
      );
    }

    // Validate configuration (safe on main isolate - no FFI)
    _validateConfig(config);

    // Validate model file exists (safe on main isolate - just File.exists)
    final file = File(config.modelPath);
    if (!await file.exists()) {
      throw ModelLoadException('Model file not found: ${config.modelPath}');
    }

    // Capture config values as primitives for isolate transfer
    final modelPath = config.modelPath;
    final numThreads = config.numThreads;
    final contextSize = config.contextLength;
    final useGpu = config.useGpu;

    // Test initialization in background isolate to verify model loads
    // Pass only primitive data - no Pointers!
    try {
      await Isolate.run<void>(() {
        final bindings = EdgeVedaNativeBindings.instance; // Re-load in isolate

        // Allocate config struct
        final configPtr = calloc<EvConfig>();
        final modelPathPtr = modelPath.toNativeUtf8();
        final errorPtr = calloc<ffi.Int32>();

        try {
          // Populate config
          configPtr.ref.modelPath = modelPathPtr;
          configPtr.ref.backend = useGpu ? EvBackend.auto_.value : EvBackend.cpu.value;
          configPtr.ref.numThreads = numThreads;
          configPtr.ref.contextSize = contextSize;
          configPtr.ref.batchSize = 512;
          configPtr.ref.memoryLimitBytes = 0;
          configPtr.ref.autoUnloadOnMemoryPressure = true;
          configPtr.ref.gpuLayers = useGpu ? -1 : 0;
          configPtr.ref.useMmap = true;
          configPtr.ref.useMlock = false;
          configPtr.ref.seed = -1;
          configPtr.ref.reserved = ffi.nullptr;

          final ctx = bindings.evInit(configPtr, errorPtr);
          if (ctx == ffi.nullptr) {
            final errorCode = NativeErrorCode.fromCode(errorPtr.value);
            final exception = errorCode.toException('Init validation failed');
            throw exception ?? InitializationException('Unknown init error');
          }
          // Immediately free - we just tested it works
          bindings.evFree(ctx);
        } finally {
          calloc.free(modelPathPtr);
          calloc.free(configPtr);
          calloc.free(errorPtr);
        }
      });
    } on EdgeVedaException {
      rethrow;
    } catch (e) {
      throw InitializationException(
        'Initialization failed',
        details: e.toString(),
        originalError: e,
      );
    }

    _config = config;
    _isInitialized = true;
  }

  /// Validate configuration before initialization
  ///
  /// Runs on main isolate (no FFI calls - safe).
  void _validateConfig(EdgeVedaConfig config) {
    if (config.modelPath.isEmpty) {
      throw ConfigurationException('Model path cannot be empty');
    }

    if (config.numThreads < 1 || config.numThreads > 32) {
      throw ConfigurationException(
        'numThreads must be between 1 and 32',
        details: 'Got: ${config.numThreads}',
      );
    }

    if (config.contextLength < 128 || config.contextLength > 32768) {
      throw ConfigurationException(
        'contextLength must be between 128 and 32768',
        details: 'Got: ${config.contextLength}',
      );
    }

    if (config.maxMemoryMb < 256) {
      throw ConfigurationException(
        'maxMemoryMb must be at least 256 MB',
        details: 'Got: ${config.maxMemoryMb}',
      );
    }
  }

  /// Validate generation options before generating
  ///
  /// Runs on main isolate (no FFI calls - safe).
  void _validateOptions(GenerateOptions options) {
    if (options.maxTokens < 1 || options.maxTokens > 32768) {
      throw ConfigurationException(
        'maxTokens must be between 1 and 32768',
        details: 'Got: ${options.maxTokens}',
      );
    }

    if (options.temperature < 0.0 || options.temperature > 2.0) {
      throw ConfigurationException(
        'temperature must be between 0.0 and 2.0',
        details: 'Got: ${options.temperature}',
      );
    }

    if (options.topP < 0.0 || options.topP > 1.0) {
      throw ConfigurationException(
        'topP must be between 0.0 and 1.0',
        details: 'Got: ${options.topP}',
      );
    }

    if (options.topK < 1 || options.topK > 100) {
      throw ConfigurationException(
        'topK must be between 1 and 100',
        details: 'Got: ${options.topK}',
      );
    }

    if (options.repeatPenalty < 0.0 || options.repeatPenalty > 2.0) {
      throw ConfigurationException(
        'repeatPenalty must be between 0.0 and 2.0',
        details: 'Got: ${options.repeatPenalty}',
      );
    }
  }

  /// Generate text from a prompt
  ///
  /// Runs the entire generation in a background isolate to keep UI responsive.
  /// Creates a fresh native context, performs generation, and returns result.
  Future<GenerateResponse> generate(
    String prompt, {
    GenerateOptions? options,
    Duration? timeout,
  }) async {
    _ensureInitialized();

    if (prompt.isEmpty) {
      throw GenerationException('Prompt cannot be empty');
    }

    options ??= const GenerateOptions();

    // Validate generation options (safe on main isolate - no FFI)
    _validateOptions(options);

    // Capture all config values as primitives for isolate transfer
    final modelPath = _config!.modelPath;
    final numThreads = _config!.numThreads;
    final contextSize = _config!.contextLength;
    final useGpu = _config!.useGpu;

    // Capture generation options as primitives
    final maxTokens = options.maxTokens;
    final temperature = options.temperature;
    final topP = options.topP;
    final topK = options.topK;
    final repeatPenalty = options.repeatPenalty;

    final startTime = DateTime.now();

    // Run entire generate in background isolate
    Future<String> generateFuture = Isolate.run<String>(() {
      final bindings = EdgeVedaNativeBindings.instance;

      // Allocate config struct
      final configPtr = calloc<EvConfig>();
      final modelPathPtr = modelPath.toNativeUtf8();
      final errorPtr = calloc<ffi.Int32>();

      ffi.Pointer<EvContextImpl>? ctx;
      try {
        // Populate config
        configPtr.ref.modelPath = modelPathPtr;
        configPtr.ref.backend = useGpu ? EvBackend.auto_.value : EvBackend.cpu.value;
        configPtr.ref.numThreads = numThreads;
        configPtr.ref.contextSize = contextSize;
        configPtr.ref.batchSize = 512;
        configPtr.ref.memoryLimitBytes = 0;
        configPtr.ref.autoUnloadOnMemoryPressure = true;
        configPtr.ref.gpuLayers = useGpu ? -1 : 0;
        configPtr.ref.useMmap = true;
        configPtr.ref.useMlock = false;
        configPtr.ref.seed = -1;
        configPtr.ref.reserved = ffi.nullptr;

        ctx = bindings.evInit(configPtr, errorPtr);
        if (ctx == ffi.nullptr) {
          final errorCode = NativeErrorCode.fromCode(errorPtr.value);
          final exception = errorCode.toException('Generation init failed');
          throw exception ?? GenerationException('Unknown init error');
        }

        // Allocate generation params
        final paramsPtr = calloc<EvGenerationParams>();
        paramsPtr.ref.maxTokens = maxTokens;
        paramsPtr.ref.temperature = temperature;
        paramsPtr.ref.topP = topP;
        paramsPtr.ref.topK = topK;
        paramsPtr.ref.repeatPenalty = repeatPenalty;
        paramsPtr.ref.frequencyPenalty = 0.0;
        paramsPtr.ref.presencePenalty = 0.0;
        paramsPtr.ref.stopSequences = ffi.nullptr;
        paramsPtr.ref.numStopSequences = 0;
        paramsPtr.ref.reserved = ffi.nullptr;

        // Allocate output pointer
        final outputPtr = calloc<ffi.Pointer<Utf8>>();

        try {
          final promptPtr = prompt.toNativeUtf8();
          try {
            final result = bindings.evGenerate(ctx!, promptPtr, paramsPtr, outputPtr);
            if (result != 0) {
              final errorCode = NativeErrorCode.fromCode(result);
              final exception = errorCode.toException('Generation failed');
              throw exception ?? GenerationException('Unknown generation error');
            }

            // Read output and free C++-allocated string
            final output = outputPtr.value.toDartString();
            bindings.evFreeString(outputPtr.value);
            return output;
          } finally {
            calloc.free(promptPtr);
          }
        } finally {
          calloc.free(paramsPtr);
          calloc.free(outputPtr);
        }
      } finally {
        if (ctx != null && ctx != ffi.nullptr) {
          bindings.evFree(ctx!);
        }
        calloc.free(modelPathPtr);
        calloc.free(configPtr);
        calloc.free(errorPtr);
      }
    });

    // Apply timeout if specified
    String generatedText;
    try {
      if (timeout != null) {
        generatedText = await generateFuture.timeout(
          timeout,
          onTimeout: () {
            throw GenerationException(
              'Generation timed out after ${timeout.inSeconds}s',
            );
          },
        );
      } else {
        generatedText = await generateFuture;
      }
    } on EdgeVedaException {
      rethrow;
    } catch (e) {
      throw GenerationException(
        'Generation failed',
        details: e.toString(),
        originalError: e,
      );
    }

    final latencyMs = DateTime.now().difference(startTime).inMilliseconds;

    return GenerateResponse(
      text: generatedText,
      promptTokens: 0, // TODO: Get from native if needed
      completionTokens: 0, // TODO: Get from native if needed
      latencyMs: latencyMs,
    );
  }

  // TODO(v2): Implement streaming with SendPort/ReceivePort worker isolate
  // Stream<TokenChunk> generateStream(
  //   String prompt, {
  //   GenerateOptions? options,
  // }) {
  //   // Streaming requires a long-lived worker isolate pattern:
  //   // 1. Spawn a persistent worker isolate
  //   // 2. Keep native context alive in that isolate
  //   // 3. Use SendPort/ReceivePort for bidirectional communication
  //   // 4. Stream tokens back to main isolate via ReceivePort
  //   // This is more complex than Isolate.run() and deferred to v2.
  //   throw UnimplementedError('Streaming deferred to v2');
  // }

  /// Ensure SDK is initialized before operations
  void _ensureInitialized() {
    if (!_isInitialized || _config == null) {
      throw InitializationException(
        'EdgeVeda not initialized. Call init() first.',
      );
    }
  }

  /// Dispose and free all resources
  ///
  /// Since we don't store any native context on the main isolate,
  /// this just clears the configuration state.
  Future<void> dispose() async {
    _isInitialized = false;
    _config = null;
  }
}
