/// Long-lived worker isolate for streaming inference
///
/// This isolate maintains a persistent native context across multiple
/// streaming requests. Unlike Isolate.run(), the context is NOT freed
/// after each operation - it persists until dispose() is called.
///
/// Usage:
/// 1. Create StreamingWorker instance
/// 2. Call spawn() to start the worker isolate
/// 3. Call init() to initialize native context
/// 4. Call startStream() to begin streaming
/// 5. Call nextToken() repeatedly to get tokens
/// 6. Call cancel() or wait for stream to end naturally
/// 7. Call dispose() when done
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import 'worker_messages.dart';

/// Worker isolate manager for streaming inference
///
/// Manages a long-lived isolate that holds the native context.
/// Provides async methods to interact with the worker.
class StreamingWorker {
  /// Port for sending commands to worker
  SendPort? _commandPort;

  /// Port for receiving responses from worker
  ReceivePort? _responsePort;

  /// The worker isolate
  Isolate? _isolate;

  /// Whether the worker is active
  bool _isActive = false;

  /// Stream controller for responses
  StreamController<WorkerResponse>? _responseController;

  /// Whether the worker is active and ready
  bool get isActive => _isActive;

  /// Stream of responses from the worker
  Stream<WorkerResponse> get responses =>
      _responseController?.stream ?? const Stream.empty();

  /// Spawn the worker isolate
  ///
  /// Must be called before any other operations.
  /// Creates the isolate and establishes bidirectional communication.
  Future<void> spawn() async {
    if (_isActive) {
      throw StateError('Worker already spawned');
    }

    _responsePort = ReceivePort();
    _responseController = StreamController<WorkerResponse>.broadcast();

    // Create init port to receive worker's command port
    final initPort = ReceivePort();

    // Spawn the worker isolate
    _isolate = await Isolate.spawn(
      _workerEntryPoint,
      initPort.sendPort,
    );

    // Wait for worker to send its command port
    _commandPort = await initPort.first as SendPort;
    initPort.close();

    // Set up response handling
    _responsePort!.listen((message) {
      if (message is WorkerResponse) {
        _responseController?.add(message);

        // Auto-cleanup on dispose
        if (message is DisposedResponse) {
          _cleanup();
        }
      }
    });

    // Send the response port to worker
    _commandPort!.send(_responsePort!.sendPort);

    _isActive = true;
  }

  /// Initialize native context in worker
  Future<InitSuccessResponse> init({
    required String modelPath,
    required int numThreads,
    required int contextSize,
    required bool useGpu,
    int memoryLimitBytes = 0,
  }) async {
    _ensureActive();

    final completer = Completer<InitSuccessResponse>();

    final subscription = responses.listen((response) {
      if (response is InitSuccessResponse) {
        completer.complete(response);
      } else if (response is InitErrorResponse) {
        completer.completeError(StateError(response.message));
      }
    });

    _commandPort!.send(InitWorkerCommand(
      modelPath: modelPath,
      numThreads: numThreads,
      contextSize: contextSize,
      useGpu: useGpu,
      memoryLimitBytes: memoryLimitBytes,
    ));

    try {
      return await completer.future.timeout(const Duration(seconds: 60));
    } finally {
      await subscription.cancel();
    }
  }

  /// Start streaming generation
  Future<void> startStream({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    double repeatPenalty = 1.1,
  }) async {
    _ensureActive();

    final completer = Completer<void>();

    final subscription = responses.listen((response) {
      if (response is StreamStartedResponse) {
        completer.complete();
      } else if (response is StreamErrorResponse) {
        completer.completeError(StateError(response.message));
      }
    });

    _commandPort!.send(StartStreamCommand(
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
      repeatPenalty: repeatPenalty,
    ));

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
    }
  }

  /// Request next token from stream
  ///
  /// Returns TokenResponse with token text, or isFinal=true when done.
  Future<TokenResponse> nextToken() async {
    _ensureActive();

    final completer = Completer<TokenResponse>();

    final subscription = responses.listen((response) {
      if (response is TokenResponse) {
        completer.complete(response);
      } else if (response is StreamErrorResponse) {
        completer.completeError(StateError(response.message));
      } else if (response is CancelledResponse) {
        completer.complete(TokenResponse.end());
      }
    });

    _commandPort!.send(NextTokenCommand());

    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
    }
  }

  /// Cancel active stream
  void cancel() {
    if (!_isActive || _commandPort == null) return;
    _commandPort!.send(CancelStreamCommand());
  }

  /// Dispose worker and free all resources
  Future<void> dispose() async {
    if (!_isActive || _commandPort == null) return;

    final completer = Completer<void>();

    final subscription = responses.listen((response) {
      if (response is DisposedResponse) {
        completer.complete();
      }
    });

    _commandPort!.send(DisposeWorkerCommand());

    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      // Force cleanup on timeout
      _cleanup();
    } finally {
      await subscription.cancel();
    }
  }

  void _ensureActive() {
    if (!_isActive || _commandPort == null) {
      throw StateError('Worker not active. Call spawn() first.');
    }
  }

  void _cleanup() {
    _isActive = false;
    _responsePort?.close();
    _responsePort = null;
    _commandPort = null;
    _responseController?.close();
    _responseController = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

// =============================================================================
// Worker Isolate Entry Point (runs in background isolate)
// =============================================================================

/// Entry point for the worker isolate
///
/// This function runs in the spawned isolate and maintains the native context.
void _workerEntryPoint(SendPort mainSendPort) {
  // Set up command port for receiving commands
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  // Wait for main's response port
  late final SendPort responseSendPort;
  bool hasResponsePort = false;

  // Native state (lives for duration of isolate)
  ffi.Pointer<EvContextImpl>? nativeContext;
  ffi.Pointer<EvStreamImpl>? currentStream;
  EdgeVedaNativeBindings? bindings;

  commandPort.listen((message) {
    // First message is always the response port
    if (!hasResponsePort && message is SendPort) {
      responseSendPort = message;
      hasResponsePort = true;
      return;
    }

    if (!hasResponsePort) return;

    // Handle commands
    if (message is InitWorkerCommand) {
      _handleInit(message, responseSendPort, (ctx, b) {
        nativeContext = ctx;
        bindings = b;
      });
    } else if (message is StartStreamCommand) {
      if (nativeContext == null || bindings == null) {
        responseSendPort.send(StreamErrorResponse(
          message: 'Worker not initialized',
          errorCode: -6, // EV_ERROR_CONTEXT_INVALID
        ));
        return;
      }
      currentStream = _handleStartStream(
        message,
        nativeContext!,
        bindings!,
        responseSendPort,
      );
    } else if (message is NextTokenCommand) {
      if (currentStream == null || bindings == null) {
        responseSendPort.send(TokenResponse.end());
        return;
      }
      _handleNextToken(currentStream!, bindings!, responseSendPort);
    } else if (message is CancelStreamCommand) {
      if (currentStream != null && bindings != null) {
        bindings!.evStreamCancel(currentStream!);
        bindings!.evStreamFree(currentStream!);
        currentStream = null;
      }
      responseSendPort.send(CancelledResponse());
    } else if (message is DisposeWorkerCommand) {
      // Cleanup
      if (currentStream != null && bindings != null) {
        bindings!.evStreamFree(currentStream!);
        currentStream = null;
      }
      if (nativeContext != null && bindings != null) {
        bindings!.evFree(nativeContext!);
        nativeContext = null;
      }
      responseSendPort.send(DisposedResponse());
      Isolate.exit();
    }
  });
}

void _handleInit(
  InitWorkerCommand cmd,
  SendPort responseSendPort,
  void Function(ffi.Pointer<EvContextImpl>, EdgeVedaNativeBindings) onSuccess,
) {
  final bindings = EdgeVedaNativeBindings.instance;

  final configPtr = calloc<EvConfig>();
  final modelPathPtr = cmd.modelPath.toNativeUtf8();
  final errorPtr = calloc<ffi.Int32>();

  try {
    configPtr.ref.modelPath = modelPathPtr;
    configPtr.ref.backend =
        cmd.useGpu ? EvBackend.auto_.value : EvBackend.cpu.value;
    configPtr.ref.numThreads = cmd.numThreads;
    configPtr.ref.contextSize = cmd.contextSize;
    configPtr.ref.batchSize = 512;
    configPtr.ref.memoryLimitBytes = cmd.memoryLimitBytes;
    configPtr.ref.autoUnloadOnMemoryPressure = true;
    configPtr.ref.gpuLayers = cmd.useGpu ? -1 : 0;
    configPtr.ref.useMmap = true;
    configPtr.ref.useMlock = false;
    configPtr.ref.seed = -1;
    configPtr.ref.reserved = ffi.nullptr;

    final ctx = bindings.evInit(configPtr, errorPtr);

    if (ctx == ffi.nullptr) {
      responseSendPort.send(InitErrorResponse(
        message: 'Failed to initialize native context',
        errorCode: errorPtr.value,
      ));
      return;
    }

    // Get backend name
    final backendInt = bindings.evDetectBackend();
    final backendPtr = bindings.evBackendName(backendInt);
    final backendName = backendPtr.toDartString();

    onSuccess(ctx, bindings);
    responseSendPort.send(InitSuccessResponse(backend: backendName));
  } finally {
    calloc.free(modelPathPtr);
    calloc.free(configPtr);
    calloc.free(errorPtr);
  }
}

ffi.Pointer<EvStreamImpl>? _handleStartStream(
  StartStreamCommand cmd,
  ffi.Pointer<EvContextImpl> ctx,
  EdgeVedaNativeBindings bindings,
  SendPort responseSendPort,
) {
  final promptPtr = cmd.prompt.toNativeUtf8();
  final paramsPtr = calloc<EvGenerationParams>();
  final errorPtr = calloc<ffi.Int32>();

  try {
    paramsPtr.ref.maxTokens = cmd.maxTokens;
    paramsPtr.ref.temperature = cmd.temperature;
    paramsPtr.ref.topP = cmd.topP;
    paramsPtr.ref.topK = cmd.topK;
    paramsPtr.ref.repeatPenalty = cmd.repeatPenalty;
    paramsPtr.ref.frequencyPenalty = 0.0;
    paramsPtr.ref.presencePenalty = 0.0;
    paramsPtr.ref.stopSequences = ffi.nullptr;
    paramsPtr.ref.numStopSequences = 0;
    paramsPtr.ref.grammarStr = ffi.nullptr;
    paramsPtr.ref.grammarRoot = ffi.nullptr;
    paramsPtr.ref.confidenceThreshold = 0.0;
    paramsPtr.ref.reserved = ffi.nullptr;

    final stream =
        bindings.evGenerateStream(ctx, promptPtr, paramsPtr, errorPtr);

    if (stream == ffi.nullptr) {
      responseSendPort.send(StreamErrorResponse(
        message: 'Failed to start stream',
        errorCode: errorPtr.value,
      ));
      return null;
    }

    responseSendPort.send(StreamStartedResponse());
    return stream;
  } finally {
    calloc.free(promptPtr);
    calloc.free(paramsPtr);
    calloc.free(errorPtr);
  }
}

void _handleNextToken(
  ffi.Pointer<EvStreamImpl> stream,
  EdgeVedaNativeBindings bindings,
  SendPort responseSendPort,
) {
  final errorPtr = calloc<ffi.Int32>();

  try {
    final tokenPtr = bindings.evStreamNext(stream, errorPtr);
    final errorCode = errorPtr.value;

    if (tokenPtr == ffi.nullptr) {
      // Stream ended (either naturally or cancelled)
      responseSendPort.send(TokenResponse(
        token: null,
        isFinal: true,
        errorCode: errorCode,
      ));
      return;
    }

    // Got a token
    final token = tokenPtr.toDartString();
    bindings.evFreeString(tokenPtr);

    responseSendPort.send(TokenResponse(
      token: token,
      isFinal: false,
      errorCode: 0,
    ));
  } finally {
    calloc.free(errorPtr);
  }
}
