/// Long-lived worker isolate for persistent image generation (Stable Diffusion)
///
/// This isolate maintains a persistent native SD context across multiple
/// generation calls. Unlike Isolate.run(), the SD model is loaded ONCE
/// and reused for every generateImage() call until dispose() is called.
///
/// Mirrors [WhisperWorker] exactly but for image generation instead of
/// audio transcription.
///
/// Usage:
/// 1. Create ImageWorker instance
/// 2. Call spawn() to start the worker isolate
/// 3. Call initImage() to load the SD model (~2GB, takes 30-60s)
/// 4. Call generateImage() for each prompt
/// 5. Call dispose() when done
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import 'image_worker_messages.dart';

/// Worker isolate manager for persistent image generation
///
/// Manages a long-lived isolate that holds the native SD context.
/// Provides async methods to interact with the worker.
class ImageWorker {
  /// Port for sending commands to worker
  SendPort? _commandPort;

  /// Port for receiving responses from worker
  ReceivePort? _responsePort;

  /// The worker isolate
  Isolate? _isolate;

  /// Whether the worker is active
  bool _isActive = false;

  /// Stream controller for responses
  StreamController<ImageWorkerResponse>? _responseController;

  /// Whether the worker is active and ready
  bool get isActive => _isActive;

  /// Stream of responses from the worker
  Stream<ImageWorkerResponse> get responses =>
      _responseController?.stream ?? const Stream.empty();

  /// Spawn the worker isolate
  ///
  /// Must be called before any other operations.
  /// Creates the isolate and establishes bidirectional communication.
  Future<void> spawn() async {
    if (_isActive) {
      throw StateError('ImageWorker already spawned');
    }

    _responsePort = ReceivePort();
    _responseController = StreamController<ImageWorkerResponse>.broadcast();

    // Create init port to receive worker's command port
    final initPort = ReceivePort();

    // Spawn the worker isolate
    _isolate = await Isolate.spawn(
      _imageWorkerEntryPoint,
      initPort.sendPort,
    );

    // Wait for worker to send its command port
    _commandPort = await initPort.first as SendPort;
    initPort.close();

    // Set up response handling
    _responsePort!.listen((message) {
      if (message is ImageWorkerResponse) {
        _responseController?.add(message);

        // Auto-cleanup on dispose
        if (message is ImageDisposedResponse) {
          _cleanup();
        }
      }
    });

    // Send the response port to worker
    _commandPort!.send(_responsePort!.sendPort);

    _isActive = true;
  }

  /// Initialize native SD context in worker
  ///
  /// Loads the SD model once. Subsequent generateImage() calls
  /// reuse this context without reloading.
  ///
  /// SD model loading is slow (~30-60 seconds for a 2GB model),
  /// so a 120-second timeout is used.
  Future<ImageInitSuccessResponse> initImage({
    required String modelPath,
    int numThreads = 0,
    bool useGpu = true,
  }) async {
    _ensureActive();

    final completer = Completer<ImageInitSuccessResponse>();

    final subscription = responses.listen((response) {
      if (response is ImageInitSuccessResponse) {
        completer.complete(response);
      } else if (response is ImageInitErrorResponse) {
        completer.completeError(StateError(response.message));
      }
    });

    _commandPort!.send(InitImageCommand(
      modelPath: modelPath,
      numThreads: numThreads,
      useGpu: useGpu,
    ));

    try {
      // SD model loading can take 30-60 seconds for ~2GB models
      return await completer.future.timeout(const Duration(seconds: 120));
    } finally {
      await subscription.cancel();
    }
  }

  /// Generate an image from a text prompt
  ///
  /// Returns a Stream of [ImageWorkerResponse] yielding:
  /// - [ImageProgressResponse] for each denoising step
  /// - [ImageCompleteResponse] when generation is done
  /// - [ImageErrorResponse] if generation fails
  ///
  /// The SD context is reused across calls (no model reload).
  Stream<ImageWorkerResponse> generateImage({
    required String prompt,
    String? negativePrompt,
    int width = 512,
    int height = 512,
    int steps = 4,
    double cfgScale = 1.0,
    int seed = -1,
    int sampler = 0,
    int schedule = 0,
  }) {
    _ensureActive();

    final controller = StreamController<ImageWorkerResponse>();

    final subscription = responses.listen((response) {
      if (response is ImageProgressResponse) {
        controller.add(response);
      } else if (response is ImageCompleteResponse) {
        controller.add(response);
        controller.close();
      } else if (response is ImageErrorResponse) {
        controller.addError(StateError(response.message));
        controller.close();
      }
    });

    controller.onCancel = () {
      subscription.cancel();
    };

    _commandPort!.send(GenerateImageCommand(
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: width,
      height: height,
      steps: steps,
      cfgScale: cfgScale,
      seed: seed,
      sampler: sampler,
      schedule: schedule,
    ));

    return controller.stream;
  }

  /// Dispose worker and free all native SD resources
  ///
  /// Frees the native SD context (model) and terminates
  /// the worker isolate.
  Future<void> dispose() async {
    if (!_isActive || _commandPort == null) return;

    final completer = Completer<void>();

    final subscription = responses.listen((response) {
      if (response is ImageDisposedResponse) {
        completer.complete();
      }
    });

    _commandPort!.send(DisposeImageCommand());

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
      throw StateError('ImageWorker not active. Call spawn() first.');
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

/// Entry point for the image worker isolate
///
/// This function runs in the spawned isolate and maintains the native
/// SD context (ev_image_context) for the lifetime of the isolate.
/// The context pointer NEVER crosses the isolate boundary.
void _imageWorkerEntryPoint(SendPort mainSendPort) {
  // Set up command port for receiving commands
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  // Wait for main's response port
  late final SendPort responseSendPort;
  bool hasResponsePort = false;

  // Native state (lives for duration of isolate)
  ffi.Pointer<EvImageContextImpl>? nativeImageContext;
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
    if (message is InitImageCommand) {
      _handleInitImage(message, responseSendPort, (ctx, b) {
        nativeImageContext = ctx;
        bindings = b;
      });
    } else if (message is GenerateImageCommand) {
      if (nativeImageContext == null || bindings == null) {
        responseSendPort.send(ImageErrorResponse(
          message: 'Image worker not initialized',
          errorCode: -6, // EV_ERROR_CONTEXT_INVALID
        ));
        return;
      }
      _handleGenerateImage(
        message,
        nativeImageContext!,
        bindings!,
        responseSendPort,
      );
    } else if (message is DisposeImageCommand) {
      // Cleanup native image context
      if (nativeImageContext != null && bindings != null) {
        bindings!.evImageFree(nativeImageContext!);
        nativeImageContext = null;
      }
      responseSendPort.send(ImageDisposedResponse());
      Isolate.exit();
    }
  });
}

/// Handle image generation context initialization command
///
/// Loads the SD model into a persistent image context.
void _handleInitImage(
  InitImageCommand cmd,
  SendPort responseSendPort,
  void Function(ffi.Pointer<EvImageContextImpl>, EdgeVedaNativeBindings)
      onSuccess,
) {
  final bindings = EdgeVedaNativeBindings.instance;

  final configPtr = calloc<EvImageConfig>();
  final modelPathPtr = cmd.modelPath.toNativeUtf8();
  final errorPtr = calloc<ffi.Int32>();

  try {
    configPtr.ref.modelPath = modelPathPtr;
    configPtr.ref.numThreads = cmd.numThreads;
    configPtr.ref.useGpu = cmd.useGpu;
    configPtr.ref.wtype = -1; // auto from GGUF
    configPtr.ref.reserved = ffi.nullptr;

    final ctx = bindings.evImageInit(configPtr, errorPtr);

    if (ctx == ffi.nullptr) {
      responseSendPort.send(ImageInitErrorResponse(
        message: 'Failed to initialize image generation context',
        errorCode: errorPtr.value,
      ));
      return;
    }

    // Get backend name
    final backendInt = bindings.evDetectBackend();
    final backendPtr = bindings.evBackendName(backendInt);
    final backendName = backendPtr.toDartString();

    onSuccess(ctx, bindings);
    responseSendPort.send(ImageInitSuccessResponse(backend: backendName));
  } finally {
    calloc.free(modelPathPtr);
    calloc.free(configPtr);
    calloc.free(errorPtr);
  }
}

/// Handle image generation command
///
/// Sets up progress callback via NativeCallable, then calls evImageGenerate
/// which is a blocking call (15-60 seconds). Progress updates are sent to
/// the main isolate as they arrive.
void _handleGenerateImage(
  GenerateImageCommand cmd,
  ffi.Pointer<EvImageContextImpl> ctx,
  EdgeVedaNativeBindings bindings,
  SendPort responseSendPort,
) {
  final startTime = DateTime.now();

  // Set up gen params
  final paramsPtr = calloc<EvImageGenParams>();
  final promptPtr = cmd.prompt.toNativeUtf8();
  final negPromptPtr = cmd.negativePrompt != null
      ? cmd.negativePrompt!.toNativeUtf8()
      : ''.toNativeUtf8();

  // Allocate result struct
  final resultPtr = calloc<EvImageResult>();

  // Set up progress callback using NativeCallable.isolateLocal
  // .listener posts to event loop which is blocked by the synchronous
  // evImageGenerate FFI call; .isolateLocal fires synchronously on the
  // calling thread which is correct here since sd.cpp calls the progress
  // callback on the same thread that called evImageGenerate
  late final ffi.NativeCallable<EvImageProgressCbNative> nativeCallback;

  void onProgress(
    int step,
    int totalSteps,
    double elapsedS,
    ffi.Pointer<ffi.Void> userData,
  ) {
    responseSendPort.send(ImageProgressResponse(
      step: step,
      totalSteps: totalSteps,
      elapsedSeconds: elapsedS,
    ));
  }

  nativeCallback = ffi.NativeCallable<EvImageProgressCbNative>.isolateLocal(
    onProgress,
  );

  try {
    // Set progress callback on the context
    bindings.evImageSetProgressCallback(
      ctx,
      nativeCallback.nativeFunction,
      ffi.nullptr,
    );

    // Populate generation parameters
    paramsPtr.ref.prompt = promptPtr;
    paramsPtr.ref.negativePrompt = negPromptPtr;
    paramsPtr.ref.width = cmd.width;
    paramsPtr.ref.height = cmd.height;
    paramsPtr.ref.steps = cmd.steps;
    paramsPtr.ref.cfgScale = cmd.cfgScale;
    paramsPtr.ref.seed = cmd.seed;
    paramsPtr.ref.sampler = cmd.sampler;
    paramsPtr.ref.schedule = cmd.schedule;
    paramsPtr.ref.reserved = ffi.nullptr;

    // BLOCKING: evImageGenerate runs the full diffusion process (15-60 seconds)
    final result = bindings.evImageGenerate(ctx, paramsPtr, resultPtr);

    if (result != 0) {
      responseSendPort.send(ImageErrorResponse(
        message: 'Image generation failed: error code $result',
        errorCode: result,
      ));
      return;
    }

    // Extract pixel data from result (copy to Dart-owned memory)
    // Capture all values BEFORE freeing the native result
    final dataSize = resultPtr.ref.dataSize;
    final resultWidth = resultPtr.ref.width;
    final resultHeight = resultPtr.ref.height;
    final resultChannels = resultPtr.ref.channels;

    final pixelData = Uint8List(dataSize);
    final nativeData = resultPtr.ref.data;
    for (int i = 0; i < dataSize; i++) {
      pixelData[i] = nativeData[i];
    }

    final generationTimeMs =
        DateTime.now().difference(startTime).inMilliseconds.toDouble();

    // Free native result memory (after capturing all values)
    bindings.evImageFreeResult(resultPtr);

    responseSendPort.send(ImageCompleteResponse(
      pixelData: pixelData,
      width: resultWidth,
      height: resultHeight,
      channels: resultChannels,
      generationTimeMs: generationTimeMs,
    ));
  } finally {
    // Clear progress callback to avoid stale pointer
    bindings.evImageSetProgressCallback(ctx, ffi.nullptr, ffi.nullptr);

    // Close the native callable
    nativeCallback.close();

    calloc.free(promptPtr);
    calloc.free(negPromptPtr);
    calloc.free(paramsPtr);
    calloc.free(resultPtr);
  }
}
