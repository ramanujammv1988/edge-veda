/// Long-lived worker isolate for persistent vision inference
///
/// This isolate maintains a persistent native vision context across multiple
/// frame inferences. Unlike Isolate.run(), the vision context (model + mmproj
/// ~600MB) is loaded ONCE and reused for every describeFrame() call until
/// dispose() is called.
///
/// Modeled directly on StreamingWorker in worker_isolate.dart.
///
/// Usage:
/// 1. Create VisionWorker instance
/// 2. Call spawn() to start the worker isolate
/// 3. Call initVision() to load the VLM model + mmproj
/// 4. Call describeFrame() for each camera frame
/// 5. Call dispose() when done
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import 'vision_worker_messages.dart';

/// Worker isolate manager for persistent vision inference
///
/// Manages a long-lived isolate that holds the native vision context.
/// Provides async methods to interact with the worker.
class VisionWorker {
  /// Port for sending commands to worker
  SendPort? _commandPort;

  /// Port for receiving responses from worker
  ReceivePort? _responsePort;

  /// The worker isolate
  Isolate? _isolate;

  /// Whether the worker is active
  bool _isActive = false;

  /// Stream controller for responses
  StreamController<VisionWorkerResponse>? _responseController;

  /// Whether the worker is active and ready
  bool get isActive => _isActive;

  /// Stream of responses from the worker
  Stream<VisionWorkerResponse> get responses =>
      _responseController?.stream ?? const Stream.empty();

  /// Spawn the worker isolate
  ///
  /// Must be called before any other operations.
  /// Creates the isolate and establishes bidirectional communication.
  Future<void> spawn() async {
    if (_isActive) {
      throw StateError('VisionWorker already spawned');
    }

    _responsePort = ReceivePort();
    _responseController = StreamController<VisionWorkerResponse>.broadcast();

    // Create init port to receive worker's command port
    final initPort = ReceivePort();

    // Spawn the worker isolate
    _isolate = await Isolate.spawn(
      _visionWorkerEntryPoint,
      initPort.sendPort,
    );

    // Wait for worker to send its command port
    _commandPort = await initPort.first as SendPort;
    initPort.close();

    // Set up response handling
    _responsePort!.listen((message) {
      if (message is VisionWorkerResponse) {
        _responseController?.add(message);

        // Auto-cleanup on dispose
        if (message is VisionDisposedResponse) {
          _cleanup();
        }
      }
    });

    // Send the response port to worker
    _commandPort!.send(_responsePort!.sendPort);

    _isActive = true;
  }

  /// Initialize native vision context in worker
  ///
  /// Loads the VLM model and mmproj once. Subsequent describeFrame() calls
  /// reuse this context without reloading.
  Future<VisionInitSuccessResponse> initVision({
    required String modelPath,
    required String mmprojPath,
    required int numThreads,
    required int contextSize,
    required bool useGpu,
    int memoryLimitBytes = 0,
  }) async {
    _ensureActive();

    final completer = Completer<VisionInitSuccessResponse>();

    final subscription = responses.listen((response) {
      if (response is VisionInitSuccessResponse) {
        completer.complete(response);
      } else if (response is VisionInitErrorResponse) {
        completer.completeError(StateError(response.message));
      }
    });

    _commandPort!.send(InitVisionCommand(
      modelPath: modelPath,
      mmprojPath: mmprojPath,
      numThreads: numThreads,
      contextSize: contextSize,
      useGpu: useGpu,
      memoryLimitBytes: memoryLimitBytes,
    ));

    try {
      // Vision model loading can take 5-10 seconds
      return await completer.future.timeout(const Duration(seconds: 60));
    } finally {
      await subscription.cancel();
    }
  }

  /// Describe a single camera frame
  ///
  /// Sends RGB bytes to the worker isolate for vision inference.
  /// Returns a [VisionResultResponse] containing both the description text
  /// and timing data from the native inference engine.
  ///
  /// The vision context is reused across calls (no model reload).
  Future<VisionResultResponse> describeFrame(
    Uint8List rgbBytes,
    int width,
    int height, {
    String prompt = 'Describe what you see.',
    int maxTokens = 100,
    double temperature = 0.3,
  }) async {
    _ensureActive();

    final completer = Completer<VisionResultResponse>();

    final subscription = responses.listen((response) {
      if (response is VisionResultResponse) {
        completer.complete(response);
      } else if (response is VisionErrorResponse) {
        completer.completeError(StateError(response.message));
      }
    });

    _commandPort!.send(DescribeFrameCommand(
      rgbBytes: rgbBytes,
      width: width,
      height: height,
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: temperature,
    ));

    try {
      // Vision inference can take 2-5 seconds per frame
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
    }
  }

  /// Dispose worker and free all native vision resources
  ///
  /// Frees the native vision context (model + mmproj) and terminates
  /// the worker isolate.
  Future<void> dispose() async {
    if (!_isActive || _commandPort == null) return;

    final completer = Completer<void>();

    final subscription = responses.listen((response) {
      if (response is VisionDisposedResponse) {
        completer.complete();
      }
    });

    _commandPort!.send(DisposeVisionCommand());

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
      throw StateError('VisionWorker not active. Call spawn() first.');
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

/// Entry point for the vision worker isolate
///
/// This function runs in the spawned isolate and maintains the native
/// vision context (ev_vision_context) for the lifetime of the isolate.
/// The context pointer NEVER crosses the isolate boundary.
void _visionWorkerEntryPoint(SendPort mainSendPort) {
  // Set up command port for receiving commands
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  // Wait for main's response port
  late final SendPort responseSendPort;
  bool hasResponsePort = false;

  // Native state (lives for duration of isolate)
  ffi.Pointer<EvVisionContextImpl>? nativeVisionContext;
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
    if (message is InitVisionCommand) {
      _handleInitVision(message, responseSendPort, (ctx, b) {
        nativeVisionContext = ctx;
        bindings = b;
      });
    } else if (message is DescribeFrameCommand) {
      if (nativeVisionContext == null || bindings == null) {
        responseSendPort.send(VisionErrorResponse(
          message: 'Vision worker not initialized',
          errorCode: -6, // EV_ERROR_CONTEXT_INVALID
        ));
        return;
      }
      _handleDescribeFrame(
        message,
        nativeVisionContext!,
        bindings!,
        responseSendPort,
      );
    } else if (message is DisposeVisionCommand) {
      // Cleanup native vision context
      if (nativeVisionContext != null && bindings != null) {
        bindings!.evVisionFree(nativeVisionContext!);
        nativeVisionContext = null;
      }
      responseSendPort.send(VisionDisposedResponse());
      Isolate.exit();
    }
  });
}

/// Handle vision initialization command
///
/// Loads the VLM model + mmproj into a persistent vision context.
void _handleInitVision(
  InitVisionCommand cmd,
  SendPort responseSendPort,
  void Function(ffi.Pointer<EvVisionContextImpl>, EdgeVedaNativeBindings)
      onSuccess,
) {
  final bindings = EdgeVedaNativeBindings.instance;

  final configPtr = calloc<EvVisionConfig>();
  final modelPathPtr = cmd.modelPath.toNativeUtf8();
  final mmprojPathPtr = cmd.mmprojPath.toNativeUtf8();
  final errorPtr = calloc<ffi.Int32>();

  try {
    configPtr.ref.modelPath = modelPathPtr;
    configPtr.ref.mmprojPath = mmprojPathPtr;
    configPtr.ref.numThreads = cmd.numThreads;
    configPtr.ref.contextSize = cmd.contextSize;
    configPtr.ref.batchSize = 512;
    configPtr.ref.memoryLimitBytes = cmd.memoryLimitBytes;
    configPtr.ref.gpuLayers = cmd.useGpu ? -1 : 0;
    configPtr.ref.useMmap = true;
    configPtr.ref.reserved = ffi.nullptr;

    final ctx = bindings.evVisionInit(configPtr, errorPtr);

    if (ctx == ffi.nullptr) {
      responseSendPort.send(VisionInitErrorResponse(
        message: 'Failed to initialize vision context',
        errorCode: errorPtr.value,
      ));
      return;
    }

    // Get backend name
    final backendInt = bindings.evDetectBackend();
    final backendPtr = bindings.evBackendName(backendInt);
    final backendName = backendPtr.toDartString();

    onSuccess(ctx, bindings);
    responseSendPort.send(VisionInitSuccessResponse(backend: backendName));
  } finally {
    calloc.free(mmprojPathPtr);
    calloc.free(modelPathPtr);
    calloc.free(configPtr);
    calloc.free(errorPtr);
  }
}

/// Handle frame description command
///
/// Performs vision inference on a single frame using the persistent context.
/// Performs vision inference on a single frame using the persistent context.
/// Extracts timing data via evVisionGetLastTimings after each inference call.
void _handleDescribeFrame(
  DescribeFrameCommand cmd,
  ffi.Pointer<EvVisionContextImpl> ctx,
  EdgeVedaNativeBindings bindings,
  SendPort responseSendPort,
) {
  // Allocate native memory for image bytes
  final nativeBytes = calloc<ffi.UnsignedChar>(cmd.rgbBytes.length);
  final nativeBytesTyped =
      nativeBytes.cast<ffi.Uint8>().asTypedList(cmd.rgbBytes.length);
  nativeBytesTyped.setAll(0, cmd.rgbBytes);

  // Set up generation params
  final paramsPtr = calloc<EvGenerationParams>();
  paramsPtr.ref.maxTokens = cmd.maxTokens;
  paramsPtr.ref.temperature = cmd.temperature;
  paramsPtr.ref.topP = 0.9;
  paramsPtr.ref.topK = 40;
  paramsPtr.ref.repeatPenalty = 1.1;
  paramsPtr.ref.frequencyPenalty = 0.0;
  paramsPtr.ref.presencePenalty = 0.0;
  paramsPtr.ref.stopSequences = ffi.nullptr;
  paramsPtr.ref.numStopSequences = 0;
  paramsPtr.ref.reserved = ffi.nullptr;

  final promptPtr = cmd.prompt.toNativeUtf8();
  final outputPtr = calloc<ffi.Pointer<Utf8>>();

  try {
    final result = bindings.evVisionDescribe(
      ctx,
      nativeBytes,
      cmd.width,
      cmd.height,
      promptPtr,
      paramsPtr,
      outputPtr,
    );

    if (result != 0) {
      responseSendPort.send(VisionErrorResponse(
        message: 'Vision describe failed: error code $result',
        errorCode: result,
      ));
      return;
    }

    final description = outputPtr.value.toDartString();
    bindings.evFreeString(outputPtr.value);

    // Extract timing data from native engine
    double modelLoadMs = 0.0;
    double imageEncodeMs = 0.0;
    double promptEvalMs = 0.0;
    double decodeMs = 0.0;
    int promptTokens = 0;
    int generatedTokens = 0;

    final timingsPtr = calloc<EvTimingsData>();
    try {
      final timingsResult =
          bindings.evVisionGetLastTimings(ctx, timingsPtr);
      if (timingsResult == 0) {
        modelLoadMs = timingsPtr.ref.modelLoadMs;
        imageEncodeMs = timingsPtr.ref.imageEncodeMs;
        promptEvalMs = timingsPtr.ref.promptEvalMs;
        decodeMs = timingsPtr.ref.decodeMs;
        promptTokens = timingsPtr.ref.promptTokens;
        generatedTokens = timingsPtr.ref.generatedTokens;
      }
    } finally {
      calloc.free(timingsPtr);
    }

    responseSendPort.send(VisionResultResponse(
      description: description,
      modelLoadMs: modelLoadMs,
      imageEncodeMs: imageEncodeMs,
      promptEvalMs: promptEvalMs,
      decodeMs: decodeMs,
      promptTokens: promptTokens,
      generatedTokens: generatedTokens,
    ));
  } finally {
    calloc.free(promptPtr);
    calloc.free(paramsPtr);
    calloc.free(outputPtr);
    calloc.free(nativeBytes);
  }
}
