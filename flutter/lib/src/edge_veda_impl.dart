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

import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:image/image.dart' as img;

import 'budget.dart';
import 'ffi/bindings.dart';
import 'isolate/image_worker.dart';
import 'isolate/image_worker_messages.dart';
import 'isolate/worker_isolate.dart';
import 'scheduler.dart';
import 'types.dart' show
    EdgeVedaConfig,
    EdgeVedaException,
    GenerateOptions,
    GenerateResponse,
    MemoryStats,
    NativeErrorCode,
    InitializationException,
    ModelLoadException,
    GenerationException,
    ConfigurationException,
    TokenChunk,
    CancelToken,
    VisionConfig,
    VisionException,
    EmbeddingResult,
    EmbeddingException,
    ImageGenerationConfig,
    ImageGenerationException,
    ImageProgress,
    ImageResult;

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

  /// Worker isolate for image generation (Stable Diffusion)
  ImageWorker? _imageWorker;

  /// Whether image generation has been initialized
  bool _isImageInitialized = false;

  /// Idle timer for auto-disposing image model after inactivity
  Timer? _imageIdleTimer;

  /// Duration of inactivity before auto-disposing the image model (~2.5GB)
  static const _imageIdleTimeout = Duration(seconds: 60);

  /// Optional Scheduler for budget-aware image generation
  Scheduler? _scheduler;

  // Note: NO Pointer storage here - pointers can't transfer between isolates

  /// Whether the SDK is initialized
  bool get isInitialized => _isInitialized;

  /// Whether a streaming operation is currently in progress
  bool get isStreaming => _isStreaming;

  /// Whether vision is initialized
  bool get isVisionInitialized => _isVisionInitialized;

  /// Whether image generation is initialized
  bool get isImageInitialized => _isImageInitialized;

  /// Current configuration
  EdgeVedaConfig? get config => _config;

  /// Connect a [Scheduler] for budget-aware image generation.
  ///
  /// Call this after creating both the EdgeVeda and Scheduler instances.
  /// When set, image generation will register as a workload, gate on
  /// QoS policy, and report latency to the Scheduler.
  void setScheduler(Scheduler scheduler) {
    _scheduler = scheduler;
  }

  /// Initialize Edge Veda with the given configuration
  ///
  /// Validates the configuration and tests that the model can be loaded.
  /// The actual context is created fresh in each background isolate call.
  Future<void> init(EdgeVedaConfig config) async {
    if (_isInitialized) {
      throw const InitializationException(
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
    final flashAttn = config.flashAttn;
    final kvCacheTypeK = config.kvCacheTypeK;
    final kvCacheTypeV = config.kvCacheTypeV;

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
          configPtr.ref.flashAttn = flashAttn;
          configPtr.ref.kvCacheTypeK = kvCacheTypeK;
          configPtr.ref.kvCacheTypeV = kvCacheTypeV;
          configPtr.ref.reserved = ffi.nullptr;

          final ctx = bindings.evInit(configPtr, errorPtr);
          if (ctx == ffi.nullptr) {
            final errorCode = NativeErrorCode.fromCode(errorPtr.value);
            final exception = errorCode.toException('Init validation failed');
            throw exception ?? const InitializationException('Unknown init error');
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
      throw const ConfigurationException('Model path cannot be empty');
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
      throw const GenerationException('Prompt cannot be empty');
    }

    options ??= const GenerateOptions();

    // Validate generation options (safe on main isolate - no FFI)
    _validateOptions(options);

    // Capture all config values as primitives for isolate transfer
    final modelPath = _config!.modelPath;
    final numThreads = _config!.numThreads;
    final contextSize = _config!.contextLength;
    final useGpu = _config!.useGpu;
    final flashAttn = _config!.flashAttn;
    final kvCacheTypeK = _config!.kvCacheTypeK;
    final kvCacheTypeV = _config!.kvCacheTypeV;

    // Capture generation options as primitives
    final maxTokens = options.maxTokens;
    final temperature = options.temperature;
    final topP = options.topP;
    final topK = options.topK;
    final repeatPenalty = options.repeatPenalty;

    final startTime = DateTime.now();

    // Run entire generate in background isolate
    final Future<String> generateFuture = Isolate.run<String>(() {
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
        configPtr.ref.flashAttn = flashAttn;
        configPtr.ref.kvCacheTypeK = kvCacheTypeK;
        configPtr.ref.kvCacheTypeV = kvCacheTypeV;
        configPtr.ref.reserved = ffi.nullptr;

        ctx = bindings.evInit(configPtr, errorPtr);
        if (ctx == ffi.nullptr) {
          final errorCode = NativeErrorCode.fromCode(errorPtr.value);
          final exception = errorCode.toException('Generation init failed');
          throw exception ?? const GenerationException('Unknown init error');
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
        paramsPtr.ref.grammarStr = ffi.nullptr;
        paramsPtr.ref.grammarRoot = ffi.nullptr;
        paramsPtr.ref.confidenceThreshold = 0.0;
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
              throw exception ?? const GenerationException('Unknown generation error');
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
      throw const GenerationException('Prompt cannot be empty');
    }

    if (_isStreaming) {
      throw const GenerationException(
        'Streaming already in progress. Wait for current stream to complete or cancel it.',
      );
    }

    options ??= const GenerateOptions();
    _validateOptions(options);

    // Create and spawn worker if needed
    _worker ??= StreamingWorker();
    if (!_worker!.isActive) {
      debugPrint('EdgeVeda: [1/4] Spawning streaming worker...');
      try {
        await _worker!.spawn();
        debugPrint('EdgeVeda: [2/4] Worker spawned successfully');
      } catch (e) {
        debugPrint('EdgeVeda: Worker spawn FAILED: $e');
        throw GenerationException('Worker spawn failed: $e');
      }

      debugPrint('EdgeVeda: [3/4] Loading model in worker (this takes 30-60 seconds)...');
      try {
        await _worker!.init(
          modelPath: _config!.modelPath,
          numThreads: _config!.numThreads,
          contextSize: _config!.contextLength,
          useGpu: _config!.useGpu,
          memoryLimitBytes: _config!.maxMemoryMb * 1024 * 1024,
          flashAttn: _config!.flashAttn,
          kvCacheTypeK: _config!.kvCacheTypeK,
          kvCacheTypeV: _config!.kvCacheTypeV,
        );
        debugPrint('EdgeVeda: [4/4] Worker ready!');
      } catch (e) {
        debugPrint('EdgeVeda: Worker init FAILED: $e');
        throw GenerationException('Worker init failed: $e');
      }
    } else {
      debugPrint('EdgeVeda: Worker already active, reusing');
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
      debugPrint('EdgeVeda: Starting stream with prompt: "${prompt.substring(0, prompt.length > 50 ? 50 : prompt.length)}..."');
      await _worker!.startStream(
        prompt: prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        topP: options.topP,
        topK: options.topK,
        repeatPenalty: options.repeatPenalty,
        confidenceThreshold: options.confidenceThreshold,
        grammarStr: options.grammarStr ?? '',
        grammarRoot: options.grammarRoot ?? '',
      );
      debugPrint('EdgeVeda: Stream started, beginning token loop');

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
            confidence: response.confidence >= 0.0 ? response.confidence : null,
            needsCloudHandoff: response.needsCloudHandoff,
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

  /// Compute text embeddings using the loaded model
  ///
  /// Returns an [EmbeddingResult] containing the L2-normalized embedding vector.
  /// The model must be an embedding model (nomic-embed, bge, etc.) -- using a
  /// generative model will produce meaningless embeddings.
  ///
  /// Runs in a background isolate via Isolate.run().
  Future<EmbeddingResult> embed(String text) async {
    _ensureInitialized();

    if (text.isEmpty) {
      throw const EmbeddingException('Text cannot be empty');
    }

    // Capture config values as primitives for isolate transfer
    final modelPath = _config!.modelPath;
    final numThreads = _config!.numThreads;
    final contextSize = _config!.contextLength;
    final useGpu = _config!.useGpu;
    final flashAttn = _config!.flashAttn;
    final kvCacheTypeK = _config!.kvCacheTypeK;
    final kvCacheTypeV = _config!.kvCacheTypeV;

    return await Isolate.run(() {
      final bindings = EdgeVedaNativeBindings.instance;

      // Allocate config and init context (same pattern as generate)
      final configPtr = calloc<EvConfig>();
      final modelPathPtr = modelPath.toNativeUtf8();
      final errorPtr = calloc<ffi.Int32>();

      try {
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
        configPtr.ref.flashAttn = flashAttn;
        configPtr.ref.kvCacheTypeK = kvCacheTypeK;
        configPtr.ref.kvCacheTypeV = kvCacheTypeV;
        configPtr.ref.reserved = ffi.nullptr;

        final ctx = bindings.evInit(configPtr, errorPtr);
        if (ctx == ffi.nullptr) {
          final errorCode = NativeErrorCode.fromCode(errorPtr.value);
          final exception = errorCode.toException('Embedding init failed');
          throw exception ?? const ModelLoadException('Failed to load model for embedding');
        }

        try {
          // Call ev_embed
          final textPtr = text.toNativeUtf8();
          final result = calloc<EvEmbedResult>();

          try {
            final err = bindings.evEmbed(ctx, textPtr, result);
            if (err != 0) {
              throw const EmbeddingException('Embedding failed',
                  details: 'Error code: \$err');
            }

            // Copy embedding to Dart list
            final dims = result.ref.dimensions;
            final tokenCount = result.ref.tokenCount;
            final floatPtr = result.ref.embeddings;

            // Create Dart-owned copy (safe to return from isolate)
            final embedding = List<double>.generate(
              dims,
              (i) => floatPtr[i].toDouble(),
            );

            // Free native embedding
            bindings.evFreeEmbeddings(result);

            return EmbeddingResult(
              embedding: embedding,
              tokenCount: tokenCount,
            );
          } finally {
            calloc.free(textPtr);
            calloc.free(result);
          }
        } finally {
          bindings.evFree(ctx);
        }
      } finally {
        calloc.free(modelPathPtr);
        calloc.free(configPtr);
        calloc.free(errorPtr);
      }
    });
  }

  /// Embed multiple texts in a single model load/unload cycle.
  ///
  /// Much faster than calling [embed] in a loop because the model is loaded
  /// once and reused for all texts. Returns embeddings in the same order.
  /// The [onProgress] callback fires after each text is embedded.
  Future<List<EmbeddingResult>> embedBatch(
    List<String> texts, {
    void Function(int completed, int total)? onProgress,
  }) async {
    _ensureInitialized();

    if (texts.isEmpty) return [];

    final modelPath = _config!.modelPath;
    final numThreads = _config!.numThreads;
    final contextSize = _config!.contextLength;
    final useGpu = _config!.useGpu;
    final flashAttn = _config!.flashAttn;
    final kvCacheTypeK = _config!.kvCacheTypeK;
    final kvCacheTypeV = _config!.kvCacheTypeV;

    // Run all embeddings in a single isolate with one model load
    return await Isolate.run(() {
      final bindings = EdgeVedaNativeBindings.instance;

      final configPtr = calloc<EvConfig>();
      final modelPathPtr = modelPath.toNativeUtf8();
      final errorPtr = calloc<ffi.Int32>();

      try {
        configPtr.ref.modelPath = modelPathPtr;
        configPtr.ref.backend =
            useGpu ? EvBackend.auto_.value : EvBackend.cpu.value;
        configPtr.ref.numThreads = numThreads;
        configPtr.ref.contextSize = contextSize;
        configPtr.ref.batchSize = 512;
        configPtr.ref.memoryLimitBytes = 0;
        configPtr.ref.autoUnloadOnMemoryPressure = true;
        configPtr.ref.gpuLayers = useGpu ? -1 : 0;
        configPtr.ref.useMmap = true;
        configPtr.ref.useMlock = false;
        configPtr.ref.seed = -1;
        configPtr.ref.flashAttn = flashAttn;
        configPtr.ref.kvCacheTypeK = kvCacheTypeK;
        configPtr.ref.kvCacheTypeV = kvCacheTypeV;
        configPtr.ref.reserved = ffi.nullptr;

        final ctx = bindings.evInit(configPtr, errorPtr);
        if (ctx == ffi.nullptr) {
          final errorCode = NativeErrorCode.fromCode(errorPtr.value);
          final exception = errorCode.toException('Embedding init failed');
          throw exception ??
              const ModelLoadException('Failed to load model for embedding');
        }
        try {
          final results = <EmbeddingResult>[];
          for (int idx = 0; idx < texts.length; idx++) {
            final text = texts[idx];
            final textPtr = text.toNativeUtf8();
            final result = calloc<EvEmbedResult>();
            try {
              final err = bindings.evEmbed(ctx, textPtr, result);
              if (err != 0) {
                throw EmbeddingException('Embedding failed',
                    details: 'Error code: $err');
              }
              final dims = result.ref.dimensions;
              final tokenCount = result.ref.tokenCount;
              final floatPtr = result.ref.embeddings;
              final embedding = List<double>.generate(
                dims,
                (i) => floatPtr[i].toDouble(),
              );
              bindings.evFreeEmbeddings(result);
              results.add(EmbeddingResult(
                embedding: embedding,
                tokenCount: tokenCount,
              ));
            } finally {
              calloc.free(textPtr);
              calloc.free(result);
            }
          }
          return results;
        } finally {
          bindings.evFree(ctx);
        }
      } finally {
        calloc.free(modelPathPtr);
        calloc.free(configPtr);
        calloc.free(errorPtr);
      }
    });
  }

  /// Ensure SDK is initialized before operations
  void _ensureInitialized() {
    if (!_isInitialized || _config == null) {
      throw const InitializationException(
        'EdgeVeda not initialized. Call init() first.',
      );
    }
  }

  /// Reset the idle timer for image model auto-disposal
  ///
  /// Cancels any existing timer and starts a new 60-second countdown.
  /// When the timer fires, the image model is disposed to free ~2.5GB.
  void _resetImageIdleTimer() {
    _imageIdleTimer?.cancel();
    _imageIdleTimer = Timer(_imageIdleTimeout, () {
      debugPrint('EdgeVeda: Image model idle for 60s, auto-disposing to free memory');
      disposeImageGeneration();
    });
  }

  /// Dispose and free all resources
  ///
  /// Disposes vision and streaming resources, clears configuration state.
  /// After calling dispose(), you must call [init] again before using the SDK.
  Future<void> dispose() async {
    await disposeVision();
    await disposeImageGeneration();
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
      throw const VisionException('Vision already initialized. Call disposeVision() first.');
    }

    // Validate config
    if (config.modelPath.isEmpty) {
      throw const VisionException('Model path cannot be empty');
    }
    if (config.mmprojPath.isEmpty) {
      throw const VisionException('Mmproj path cannot be empty');
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
      throw const VisionException('Vision not initialized. Call initVision() first.');
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
          throw const VisionException('Vision init failed in describe');
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
        paramsPtr.ref.grammarStr = ffi.nullptr;
        paramsPtr.ref.grammarRoot = ffi.nullptr;
        paramsPtr.ref.confidenceThreshold = 0.0;
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
  // Image Generation (Phase 23 - Stable Diffusion)
  // ===========================================================================

  /// Initialize image generation with a Stable Diffusion model
  ///
  /// This loads the SD model into a persistent worker isolate (~2GB, takes
  /// 30-60 seconds). The model stays loaded for subsequent [generateImage]
  /// calls until [disposeImageGeneration] is called.
  ///
  /// This is independent of text inference -- both can be active at once,
  /// though memory usage will be high (~2.5GB+ combined).
  ///
  /// Example:
  /// ```dart
  /// await edgeVeda.initImageGeneration(
  ///   modelPath: '/path/to/sd-v2-1-turbo-q8.gguf',
  /// );
  /// ```
  Future<void> initImageGeneration({
    required String modelPath,
    int numThreads = 0,
    bool useGpu = true,
  }) async {
    if (_isImageInitialized) {
      throw const ImageGenerationException(
        'Image generation already initialized. Call disposeImageGeneration() first.',
      );
    }

    // Validate model file exists
    if (modelPath.isEmpty) {
      throw const ImageGenerationException('Model path cannot be empty');
    }
    final file = File(modelPath);
    if (!await file.exists()) {
      throw ImageGenerationException('SD model file not found: $modelPath');
    }

    // Spawn and initialize worker
    _imageWorker = ImageWorker();
    try {
      await _imageWorker!.spawn();
      await _imageWorker!.initImage(
        modelPath: modelPath,
        numThreads: numThreads,
        useGpu: useGpu,
      );
    } catch (e) {
      // Clean up on failure
      try {
        await _imageWorker?.dispose();
      } catch (_) {}
      _imageWorker = null;
      if (e is ImageGenerationException) rethrow;
      throw ImageGenerationException(
        'Image generation initialization failed',
        details: e.toString(),
        originalError: e,
      );
    }

    _isImageInitialized = true;

    // Register image workload with Scheduler for budget enforcement.
    // Priority is low -- text/vision are more important than image generation.
    _scheduler?.registerWorkload(WorkloadId.image,
        priority: WorkloadPriority.low);
    _scheduler?.registerMemoryEviction(
        WorkloadId.image, () => disposeImageGeneration());
    debugPrint('EdgeVeda: Image workload registered with Scheduler');

    _resetImageIdleTimer();
  }

  /// Generate an image from a text prompt
  ///
  /// Returns PNG-encoded bytes as [Uint8List]. The SD model must be loaded
  /// first via [initImageGeneration].
  ///
  /// The optional [onProgress] callback fires for each denoising step,
  /// providing step number and total steps for progress UI.
  ///
  /// Example:
  /// ```dart
  /// final pngBytes = await edgeVeda.generateImage(
  ///   'a sunset over mountains, oil painting style',
  ///   config: ImageGenerationConfig(steps: 4, seed: 42),
  ///   onProgress: (progress) {
  ///     print('Step ${progress.step}/${progress.totalSteps}');
  ///   },
  /// );
  ///
  /// // Save or display the PNG image
  /// await File('output.png').writeAsBytes(pngBytes);
  /// ```
  Future<Uint8List> generateImage(
    String prompt, {
    ImageGenerationConfig? config,
    void Function(ImageProgress)? onProgress,
  }) async {
    if (!_isImageInitialized || _imageWorker == null) {
      throw const ImageGenerationException(
        'Image generation not initialized. Call initImageGeneration() first.',
      );
    }

    if (prompt.isEmpty) {
      throw const ImageGenerationException('Prompt cannot be empty');
    }

    config ??= const ImageGenerationConfig();

    // Check Scheduler QoS -- refuse to start if paused (thermal/battery)
    if (_scheduler != null) {
      final knobs = _scheduler!.getKnobsForWorkload(WorkloadId.image);
      if (knobs.maxFps == 0) {
        throw const ImageGenerationException(
          'Image generation paused by Scheduler (thermal/battery pressure). '
          'Try again when conditions improve.',
        );
      }
    }

    // Cancel idle timer during generation
    _imageIdleTimer?.cancel();

    final stream = _imageWorker!.generateImage(
      prompt: prompt,
      negativePrompt: config.negativePrompt,
      width: config.width,
      height: config.height,
      steps: config.steps,
      cfgScale: config.cfgScale,
      seed: config.seed,
      sampler: config.sampler.value,
      schedule: config.schedule.value,
    );

    ImageCompleteResponse? completeResponse;

    await for (final response in stream) {
      if (response is ImageProgressResponse && onProgress != null) {
        onProgress(ImageProgress(
          step: response.step,
          totalSteps: response.totalSteps,
          elapsedSeconds: response.elapsedSeconds,
        ));
      } else if (response is ImageCompleteResponse) {
        completeResponse = response;
      }
    }

    if (completeResponse == null) {
      throw const ImageGenerationException('Image generation produced no result');
    }

    // Report generation latency to Scheduler for budget enforcement
    _scheduler?.reportLatency(
        WorkloadId.image, completeResponse.generationTimeMs);

    // Reset idle timer -- generation just completed
    _resetImageIdleTimer();

    // Convert raw RGB pixels to PNG using the `image` package
    final rawImage = img.Image.fromBytes(
      width: completeResponse.width,
      height: completeResponse.height,
      bytes: completeResponse.pixelData.buffer,
      numChannels: completeResponse.channels,
    );
    return Uint8List.fromList(img.encodePng(rawImage));
  }

  /// Generate an image and return raw pixel data (no PNG encoding)
  ///
  /// Use this when you need the raw RGB bytes instead of PNG, for example
  /// when displaying directly in a Canvas or passing to another processing
  /// pipeline. Returns an [ImageResult] with pixel data and metadata.
  Future<ImageResult> generateImageRaw(
    String prompt, {
    ImageGenerationConfig? config,
    void Function(ImageProgress)? onProgress,
  }) async {
    if (!_isImageInitialized || _imageWorker == null) {
      throw const ImageGenerationException(
        'Image generation not initialized. Call initImageGeneration() first.',
      );
    }

    if (prompt.isEmpty) {
      throw const ImageGenerationException('Prompt cannot be empty');
    }

    config ??= const ImageGenerationConfig();

    // Check Scheduler QoS -- refuse to start if paused (thermal/battery)
    if (_scheduler != null) {
      final knobs = _scheduler!.getKnobsForWorkload(WorkloadId.image);
      if (knobs.maxFps == 0) {
        throw const ImageGenerationException(
          'Image generation paused by Scheduler (thermal/battery pressure). '
          'Try again when conditions improve.',
        );
      }
    }

    // Cancel idle timer during generation
    _imageIdleTimer?.cancel();

    final stream = _imageWorker!.generateImage(
      prompt: prompt,
      negativePrompt: config.negativePrompt,
      width: config.width,
      height: config.height,
      steps: config.steps,
      cfgScale: config.cfgScale,
      seed: config.seed,
      sampler: config.sampler.value,
      schedule: config.schedule.value,
    );

    ImageCompleteResponse? completeResponse;

    await for (final response in stream) {
      if (response is ImageProgressResponse && onProgress != null) {
        onProgress(ImageProgress(
          step: response.step,
          totalSteps: response.totalSteps,
          elapsedSeconds: response.elapsedSeconds,
        ));
      } else if (response is ImageCompleteResponse) {
        completeResponse = response;
      }
    }

    if (completeResponse == null) {
      throw const ImageGenerationException('Image generation produced no result');
    }

    // Report generation latency to Scheduler for budget enforcement
    _scheduler?.reportLatency(
        WorkloadId.image, completeResponse.generationTimeMs);

    // Reset idle timer -- generation just completed
    _resetImageIdleTimer();

    return ImageResult(
      pixelData: completeResponse.pixelData,
      width: completeResponse.width,
      height: completeResponse.height,
      channels: completeResponse.channels,
      generationTimeMs: completeResponse.generationTimeMs,
    );
  }

  /// Dispose image generation resources
  ///
  /// Frees the SD model and terminates the image worker isolate.
  /// Does not affect text inference, vision, or STT.
  Future<void> disposeImageGeneration() async {
    // Unregister from Scheduler before cleanup (defensive -- eviction may
    // have already removed the callback, but remove is safe to call twice)
    _scheduler?.unregisterWorkload(WorkloadId.image);
    _scheduler?.unregisterMemoryEviction(WorkloadId.image);
    debugPrint('EdgeVeda: Image workload unregistered from Scheduler');

    _imageIdleTimer?.cancel();
    _imageIdleTimer = null;
    if (_imageWorker != null) {
      await _imageWorker!.dispose();
      _imageWorker = null;
    }
    _isImageInitialized = false;
  }

  // ===========================================================================
  // Memory Monitoring (R3.3 - Memory pressure handling via polling)
  // ===========================================================================

  /// Get current memory statistics from native layer
  ///
  /// Routes through the active StreamingWorker isolate to query the
  /// already-loaded model context. This avoids loading a second model
  /// (~600MB) just to read memory stats.
  ///
  /// Returns zero-valued stats when no worker is active (no crash,
  /// no model load).
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

    // Route through active worker to avoid loading a second model context
    // (the old implementation loaded a full ~600MB model just to read stats)
    if (_worker != null && _worker!.isActive) {
      return _worker!.getMemoryStats();
    }

    // No active worker -- return zero stats without loading a model.
    // When the model isn't loaded, memory usage IS effectively zero.
    return MemoryStats(
      currentBytes: 0,
      peakBytes: 0,
      limitBytes: _config!.maxMemoryMb * 1024 * 1024,
      modelBytes: 0,
      contextBytes: 0,
    );
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
