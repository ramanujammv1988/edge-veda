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
/// - Streaming uses long-lived worker isolate (StreamingWorker) for persistent context
///
/// ## Memory pressure handling
///
/// Due to the per-request Isolate.run() architecture, real-time memory
/// pressure callbacks from C++ are not supported. Instead, use:
/// - [EdgeVeda.getMemoryStats] to poll current memory usage
/// - [EdgeVeda.isMemoryPressure] to check if usage exceeds threshold
///
/// ## Streaming
///
/// Use [generateStream] for token-by-token generation with a long-lived worker
/// isolate that maintains native context across multiple ev_stream_next calls.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/bindings.dart';
import 'isolate/worker_isolate.dart';
import 'types.dart' show
    EdgeVedaConfig,
    EdgeVedaException,
    GenerateOptions,
    GenerateResponse,
    MemoryStats,
    MemoryException,
    NativeErrorCode,
    InitializationException,
    ModelLoadException,
    GenerationException,
    ConfigurationException,
    TokenChunk,
    CancelToken,
    VisionConfig,
    VisionException;

/// Main Edge Veda SDK class for on-device AI inference
///
/// Uses Isolate.run() for all FFI calls to keep the UI responsive.
/// Each operation creates a fresh native context in the background isolate.
/// For streaming, uses a long-lived worker isolate via [StreamingWorker].
class EdgeVeda {
  /// Stored configuration (primitives only - safe across isolates)
  EdgeVedaConfig? _config;

  /// Whether the SDK has been initialized and validated
  bool _isInitialized = false;

  /// Worker isolate for streaming operations
  StreamingWorker? _worker;

  /// Whether streaming is currently active
  bool _isStreaming = false;

  /// Whether vision has been initialized
  bool _isVisionInitialized = false;

  /// Vision configuration (stored for isolate transfer)
  VisionConfig? _visionConfig;

  // Note: NO Pointer storage here - pointers can't transfer between isolates

  /// Whether the SDK is initialized
  bool get isInitialized => _isInitialized;

  /// Whether a streaming operation is currently in progress
  bool get isStreaming => _isStreaming;

  /// Whether vision is initialized
  bool get isVisionInitialized => _isVisionInitialized;

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
            final result = bindings.evGenerate(ctx, promptPtr, paramsPtr, outputPtr);
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
          bindings.evFree(ctx);
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

  /// Generate text as a stream of tokens
  ///
  /// Returns a Stream that yields [TokenChunk] objects as they are generated.
  /// The final chunk has `isFinal=true` to signal stream completion.
  ///
  /// Use [cancelToken] to cancel generation mid-stream:
  /// ```dart
  /// final cancelToken = CancelToken();
  /// final stream = edgeVeda.generateStream('Hello', cancelToken: cancelToken);
  ///
  /// await for (final chunk in stream) {
  ///   print(chunk.token);
  ///   if (shouldStop) {
  ///     cancelToken.cancel();
  ///     break;
  ///   }
  /// }
  /// ```
  ///
  /// Errors during generation are propagated as stream errors.
  ///
  /// Only one streaming operation can be active at a time. If [generateStream]
  /// is called while another stream is active, a [GenerationException] is thrown.
  Stream<TokenChunk> generateStream(
    String prompt, {
    GenerateOptions? options,
    CancelToken? cancelToken,
  }) async* {
    _ensureInitialized();

    if (prompt.isEmpty) {
      throw GenerationException('Prompt cannot be empty');
    }

    if (_isStreaming) {
      throw GenerationException(
        'Streaming already in progress. Wait for current stream to complete or cancel it.',
      );
    }

    options ??= const GenerateOptions();
    _validateOptions(options);

    // Create and spawn worker if needed
    _worker ??= StreamingWorker();
    if (!_worker!.isActive) {
      print('EdgeVeda: [1/4] Spawning streaming worker...');
      try {
        await _worker!.spawn();
        print('EdgeVeda: [2/4] Worker spawned successfully');
      } catch (e) {
        print('EdgeVeda: Worker spawn FAILED: $e');
        throw GenerationException('Worker spawn failed: $e');
      }

      print('EdgeVeda: [3/4] Loading model in worker (this takes 30-60 seconds)...');
      try {
        await _worker!.init(
          modelPath: _config!.modelPath,
          numThreads: _config!.numThreads,
          contextSize: _config!.contextLength,
          useGpu: _config!.useGpu,
          memoryLimitBytes: _config!.maxMemoryMb * 1024 * 1024,
        );
        print('EdgeVeda: [4/4] Worker ready!');
      } catch (e) {
        print('EdgeVeda: Worker init FAILED: $e');
        throw GenerationException('Worker init failed: $e');
      }
    } else {
      print('EdgeVeda: Worker already active, reusing');
    }

    _isStreaming = true;
    int tokenIndex = 0;

    // Set up cancellation listener
    void Function()? cancelListener;
    if (cancelToken != null) {
      cancelListener = () {
        _worker?.cancel();
      };
      cancelToken.addListener(cancelListener);
    }

    try {
      // Start the stream
      print('EdgeVeda: Starting stream with prompt: "${prompt.substring(0, prompt.length > 50 ? 50 : prompt.length)}..."');
      await _worker!.startStream(
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        topK: options.topK,
        repeatPenalty: options.repeatPenalty,
      );
      print('EdgeVeda: Stream started, beginning token loop');

      // Yield tokens until stream ends
      while (true) {
        // Check cancellation before requesting next token
        if (cancelToken?.isCancelled == true) {
          break;
        }

        final response = await _worker!.nextToken();

        if (response.isFinal) {
          // Stream ended - yield final empty chunk to signal completion
          yield TokenChunk(
            token: '',
            index: tokenIndex,
            isFinal: true,
          );
          break;
        }

        if (response.token != null && response.token!.isNotEmpty) {
          yield TokenChunk(
            token: response.token!,
            index: tokenIndex++,
            isFinal: false,
          );
        }
      }
    } catch (e) {
      // Convert to GenerationException if not already
      if (e is GenerationException) {
        rethrow;
      }
      throw GenerationException(
        'Streaming failed',
        details: e.toString(),
        originalError: e,
      );
    } finally {
      _isStreaming = false;
      if (cancelListener != null && cancelToken != null) {
        cancelToken.removeListener(cancelListener);
      }
    }
  }

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
  /// Disposes vision and streaming resources, clears configuration state.
  /// After calling dispose(), you must call [init] again before using the SDK.
  Future<void> dispose() async {
    await disposeVision();
    if (_worker != null) {
      await _worker!.dispose();
      _worker = null;
    }
    _isStreaming = false;
    _isInitialized = false;
    _config = null;
  }

  // ===========================================================================
  // Vision Inference (Phase 8 - VLM)
  // ===========================================================================

  /// Initialize vision inference with VLM model
  ///
  /// This loads the SmolVLM2 model and mmproj (~540MB total).
  /// Call this separately from [init] - vision models only load
  /// when explicitly requested by the developer.
  ///
  /// Example:
  /// ```dart
  /// await edgeVeda.initVision(VisionConfig(
  ///   modelPath: '/path/to/smolvlm2.gguf',
  ///   mmprojPath: '/path/to/mmproj.gguf',
  /// ));
  /// ```
  Future<void> initVision(VisionConfig config) async {
    if (_isVisionInitialized) {
      throw VisionException('Vision already initialized. Call disposeVision() first.');
    }

    // Validate config
    if (config.modelPath.isEmpty) {
      throw VisionException('Model path cannot be empty');
    }
    if (config.mmprojPath.isEmpty) {
      throw VisionException('Mmproj path cannot be empty');
    }

    // Verify files exist
    if (!await File(config.modelPath).exists()) {
      throw VisionException('VLM model file not found: ${config.modelPath}');
    }
    if (!await File(config.mmprojPath).exists()) {
      throw VisionException('Mmproj file not found: ${config.mmprojPath}');
    }

    // Capture primitives for isolate transfer
    final modelPath = config.modelPath;
    final mmprojPath = config.mmprojPath;
    final numThreads = config.numThreads;
    final contextSize = config.contextSize;
    final useGpu = config.useGpu;
    final maxMemoryMb = config.maxMemoryMb;

    // Test vision init in background isolate
    try {
      await Isolate.run<void>(() {
        final bindings = EdgeVedaNativeBindings.instance;
        final configPtr = calloc<EvVisionConfig>();
        final modelPathPtr = modelPath.toNativeUtf8();
        final mmprojPathPtr = mmprojPath.toNativeUtf8();
        final errorPtr = calloc<ffi.Int32>();

        try {
          configPtr.ref.modelPath = modelPathPtr;
          configPtr.ref.mmprojPath = mmprojPathPtr;
          configPtr.ref.numThreads = numThreads;
          configPtr.ref.contextSize = contextSize;
          configPtr.ref.batchSize = 512;
          configPtr.ref.memoryLimitBytes = maxMemoryMb * 1024 * 1024;
          configPtr.ref.gpuLayers = useGpu ? -1 : 0;
          configPtr.ref.useMmap = true;
          configPtr.ref.reserved = ffi.nullptr;

          final ctx = bindings.evVisionInit(configPtr, errorPtr);
          if (ctx == ffi.nullptr) {
            final errorCode = NativeErrorCode.fromCode(errorPtr.value);
            throw VisionException('Vision init failed: ${errorCode.name}');
          }
          bindings.evVisionFree(ctx);
        } finally {
          calloc.free(mmprojPathPtr);
          calloc.free(modelPathPtr);
          calloc.free(configPtr);
          calloc.free(errorPtr);
        }
      });
    } catch (e) {
      if (e is VisionException) rethrow;
      throw VisionException(
        'Vision initialization failed',
        details: e.toString(),
        originalError: e,
      );
    }

    _visionConfig = config;
    _isVisionInitialized = true;
  }

  /// Describe an image using the VLM
  ///
  /// [imageBytes] must be RGB888 format (width * height * 3 bytes).
  /// Use [CameraUtils.convertBgraToRgb] or [CameraUtils.convertYuv420ToRgb]
  /// to convert camera frames.
  ///
  /// Returns a text description of the image content.
  /// This runs in a background isolate to avoid blocking the UI.
  ///
  /// Example:
  /// ```dart
  /// final description = await edgeVeda.describeImage(
  ///   rgbBytes,
  ///   width: 640,
  ///   height: 480,
  ///   prompt: 'What objects are in this image?',
  /// );
  /// ```
  Future<String> describeImage(
    Uint8List imageBytes, {
    required int width,
    required int height,
    String prompt = 'Describe this image.',
    GenerateOptions? options,
  }) async {
    if (!_isVisionInitialized || _visionConfig == null) {
      throw VisionException('Vision not initialized. Call initVision() first.');
    }

    // Validate input
    final expectedBytes = width * height * 3;
    if (imageBytes.length != expectedBytes) {
      throw VisionException(
        'Image byte count mismatch: expected $expectedBytes '
        '(${width}x${height}x3 RGB), got ${imageBytes.length}',
      );
    }

    options ??= const GenerateOptions(maxTokens: 256);

    // Capture all primitives for isolate transfer
    final modelPath = _visionConfig!.modelPath;
    final mmprojPath = _visionConfig!.mmprojPath;
    final numThreads = _visionConfig!.numThreads;
    final contextSize = _visionConfig!.contextSize;
    final useGpu = _visionConfig!.useGpu;
    final maxMemoryMb = _visionConfig!.maxMemoryMb;
    final maxTokens = options.maxTokens;
    final temperature = options.temperature;
    final topP = options.topP;
    final topK = options.topK;
    final repeatPenalty = options.repeatPenalty;

    // Run in background isolate (Pitfall P5 - never block UI)
    return Isolate.run<String>(() {
      final bindings = EdgeVedaNativeBindings.instance;
      final configPtr = calloc<EvVisionConfig>();
      final modelPathPtr = modelPath.toNativeUtf8();
      final mmprojPathPtr = mmprojPath.toNativeUtf8();
      final errorPtr = calloc<ffi.Int32>();

      ffi.Pointer<EvVisionContextImpl>? ctx;
      try {
        // Set up vision config
        configPtr.ref.modelPath = modelPathPtr;
        configPtr.ref.mmprojPath = mmprojPathPtr;
        configPtr.ref.numThreads = numThreads;
        configPtr.ref.contextSize = contextSize;
        configPtr.ref.batchSize = 512;
        configPtr.ref.memoryLimitBytes = maxMemoryMb * 1024 * 1024;
        configPtr.ref.gpuLayers = useGpu ? -1 : 0;
        configPtr.ref.useMmap = true;
        configPtr.ref.reserved = ffi.nullptr;

        // Init vision context
        ctx = bindings.evVisionInit(configPtr, errorPtr);
        if (ctx == ffi.nullptr) {
          throw VisionException('Vision init failed in describe');
        }

        // Allocate native memory for image bytes
        final nativeBytes = calloc<ffi.UnsignedChar>(imageBytes.length);
        final nativeBytesTyped = nativeBytes.cast<ffi.Uint8>().asTypedList(imageBytes.length);
        nativeBytesTyped.setAll(0, imageBytes);

        // Set up generation params
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

        final promptPtr = prompt.toNativeUtf8();
        final outputPtr = calloc<ffi.Pointer<Utf8>>();

        try {
          final result = bindings.evVisionDescribe(
            ctx, nativeBytes, width, height, promptPtr, paramsPtr, outputPtr,
          );
          if (result != 0) {
            throw VisionException('Vision describe failed: error code $result');
          }

          final output = outputPtr.value.toDartString();
          bindings.evFreeString(outputPtr.value);
          return output;
        } finally {
          calloc.free(promptPtr);
          calloc.free(paramsPtr);
          calloc.free(outputPtr);
          calloc.free(nativeBytes);
        }
      } finally {
        if (ctx != null && ctx != ffi.nullptr) {
          bindings.evVisionFree(ctx);
        }
        calloc.free(mmprojPathPtr);
        calloc.free(modelPathPtr);
        calloc.free(configPtr);
        calloc.free(errorPtr);
      }
    });
  }

  /// Dispose vision resources
  ///
  /// Clears the vision configuration. Does not affect text inference.
  Future<void> disposeVision() async {
    _isVisionInitialized = false;
    _visionConfig = null;
  }

  // ===========================================================================
  // Memory Monitoring (R3.3 - Memory pressure handling via polling)
  // ===========================================================================

  /// Get current memory statistics from native layer
  ///
  /// Polls the native memory usage stats by creating a temporary context.
  /// This is the v1 approach for memory monitoring - real-time callbacks
  /// will be added in v2 with a long-lived worker isolate.
  ///
  /// Example:
  /// ```dart
  /// final stats = await edgeVeda.getMemoryStats();
  /// print('Memory usage: ${stats.usagePercent * 100}%');
  /// if (stats.isHighPressure) {
  ///   // Consider unloading or reducing context size
  /// }
  /// ```
  Future<MemoryStats> getMemoryStats() async {
    _ensureInitialized();

    // Capture config values as primitives for isolate transfer
    final modelPath = _config!.modelPath;
    final numThreads = _config!.numThreads;
    final contextSize = _config!.contextLength;
    final useGpu = _config!.useGpu;
    final maxMemoryBytes = _config!.maxMemoryMb * 1024 * 1024;

    // Run in background isolate (Pitfall 3 - Critical: no FFI on main)
    return Isolate.run<MemoryStats>(() {
      final bindings = EdgeVedaNativeBindings.instance;

      // Allocate config struct
      final configPtr = calloc<EvConfig>();
      final modelPathPtr = modelPath.toNativeUtf8();
      final errorPtr = calloc<ffi.Int32>();
      final statsPtr = calloc<EvMemoryStats>();

      ffi.Pointer<EvContextImpl>? ctx;
      try {
        // Populate config
        configPtr.ref.modelPath = modelPathPtr;
        configPtr.ref.backend = useGpu ? EvBackend.auto_.value : EvBackend.cpu.value;
        configPtr.ref.numThreads = numThreads;
        configPtr.ref.contextSize = contextSize;
        configPtr.ref.batchSize = 512;
        configPtr.ref.memoryLimitBytes = maxMemoryBytes;
        configPtr.ref.autoUnloadOnMemoryPressure = true;
        configPtr.ref.gpuLayers = useGpu ? -1 : 0;
        configPtr.ref.useMmap = true;
        configPtr.ref.useMlock = false;
        configPtr.ref.seed = -1;
        configPtr.ref.reserved = ffi.nullptr;

        ctx = bindings.evInit(configPtr, errorPtr);
        if (ctx == ffi.nullptr) {
          final errorCode = NativeErrorCode.fromCode(errorPtr.value);
          final exception = errorCode.toException('Failed to get memory stats');
          throw exception ?? MemoryException('Failed to get memory stats');
        }

        // Get memory stats
        final result = bindings.evGetMemoryUsage(ctx, statsPtr);
        if (result != 0) {
          final errorCode = NativeErrorCode.fromCode(result);
          final exception = errorCode.toException('Memory stats query failed');
          throw exception ?? MemoryException('Memory stats query failed');
        }

        // Extract values before freeing
        return MemoryStats(
          currentBytes: statsPtr.ref.currentBytes,
          peakBytes: statsPtr.ref.peakBytes,
          limitBytes: statsPtr.ref.limitBytes,
          modelBytes: statsPtr.ref.modelBytes,
          contextBytes: statsPtr.ref.contextBytes,
        );
      } finally {
        if (ctx != null && ctx != ffi.nullptr) {
          bindings.evFree(ctx);
        }
        calloc.free(statsPtr);
        calloc.free(modelPathPtr);
        calloc.free(configPtr);
        calloc.free(errorPtr);
      }
    });
  }

  /// Check if memory usage is above threshold
  ///
  /// Convenience method that polls memory stats and checks against threshold.
  /// Use this for quick memory pressure checks without detailed stats.
  ///
  /// [threshold] is the memory usage percentage (0.0 - 1.0) above which
  /// memory pressure is considered active. Defaults to 0.8 (80%).
  ///
  /// Example:
  /// ```dart
  /// if (await edgeVeda.isMemoryPressure()) {
  ///   print('Warning: High memory usage!');
  ///   // Reduce context size or unload model
  /// }
  /// ```
  Future<bool> isMemoryPressure({double threshold = 0.8}) async {
    final stats = await getMemoryStats();
    if (stats.limitBytes == 0) return false; // No limit set
    return stats.usagePercent > threshold;
  }
}
