/// Long-lived worker isolate for persistent whisper (speech-to-text) inference
///
/// This isolate maintains a persistent native whisper context across multiple
/// transcription calls. Unlike Isolate.run(), the whisper model is loaded ONCE
/// and reused for every transcribeChunk() call until dispose() is called.
///
/// Mirrors [VisionWorker] exactly but for audio transcription instead of
/// image description.
///
/// Usage:
/// 1. Create WhisperWorker instance
/// 2. Call spawn() to start the worker isolate
/// 3. Call initWhisper() to load the whisper model
/// 4. Call transcribeChunk() for each audio chunk
/// 5. Call dispose() when done
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import 'whisper_worker_messages.dart';

/// Worker isolate manager for persistent whisper inference
///
/// Manages a long-lived isolate that holds the native whisper context.
/// Provides async methods to interact with the worker.
class WhisperWorker {
  /// Port for sending commands to worker
  SendPort? _commandPort;

  /// Port for receiving responses from worker
  ReceivePort? _responsePort;

  /// The worker isolate
  Isolate? _isolate;

  /// Whether the worker is active
  bool _isActive = false;

  /// Stream controller for responses
  StreamController<WhisperWorkerResponse>? _responseController;

  /// Whether the worker is active and ready
  bool get isActive => _isActive;

  /// Stream of responses from the worker
  Stream<WhisperWorkerResponse> get responses =>
      _responseController?.stream ?? const Stream.empty();

  /// Spawn the worker isolate
  ///
  /// Must be called before any other operations.
  /// Creates the isolate and establishes bidirectional communication.
  Future<void> spawn() async {
    if (_isActive) {
      throw StateError('WhisperWorker already spawned');
    }

    _responsePort = ReceivePort();
    _responseController = StreamController<WhisperWorkerResponse>.broadcast();

    // Create init port to receive worker's command port
    final initPort = ReceivePort();

    // Spawn the worker isolate
    _isolate = await Isolate.spawn(
      _whisperWorkerEntryPoint,
      initPort.sendPort,
    );

    // Wait for worker to send its command port
    _commandPort = await initPort.first as SendPort;
    initPort.close();

    // Set up response handling
    _responsePort!.listen((message) {
      if (message is WhisperWorkerResponse) {
        _responseController?.add(message);

        // Auto-cleanup on dispose
        if (message is WhisperDisposedResponse) {
          _cleanup();
        }
      }
    });

    // Send the response port to worker
    _commandPort!.send(_responsePort!.sendPort);

    _isActive = true;
  }

  /// Initialize native whisper context in worker
  ///
  /// Loads the whisper model once. Subsequent transcribeChunk() calls
  /// reuse this context without reloading.
  Future<WhisperInitSuccessResponse> initWhisper({
    required String modelPath,
    int numThreads = 4,
    bool useGpu = true,
  }) async {
    _ensureActive();

    final completer = Completer<WhisperInitSuccessResponse>();

    final subscription = responses.listen((response) {
      if (response is WhisperInitSuccessResponse) {
        completer.complete(response);
      } else if (response is WhisperInitErrorResponse) {
        completer.completeError(StateError(response.message));
      }
    });

    _commandPort!.send(InitWhisperCommand(
      modelPath: modelPath,
      numThreads: numThreads,
      useGpu: useGpu,
    ));

    try {
      // Whisper model loading can take 5-10 seconds
      return await completer.future.timeout(const Duration(seconds: 60));
    } finally {
      await subscription.cancel();
    }
  }

  /// Transcribe a chunk of PCM audio samples
  ///
  /// Sends float32 PCM samples (16kHz mono) to the worker isolate for
  /// transcription. Returns a [WhisperTranscribeResponse] containing
  /// segments with text and timing data.
  ///
  /// The whisper context is reused across calls (no model reload).
  Future<WhisperTranscribeResponse> transcribeChunk(
    Float32List pcmSamples, {
    String language = 'en',
    bool translate = false,
  }) async {
    _ensureActive();

    final completer = Completer<WhisperTranscribeResponse>();

    final subscription = responses.listen((response) {
      if (response is WhisperTranscribeResponse) {
        completer.complete(response);
      } else if (response is WhisperErrorResponse) {
        completer.completeError(StateError(response.message));
      }
    });

    _commandPort!.send(TranscribeChunkCommand(
      pcmSamples: pcmSamples,
      language: language,
      translate: translate,
    ));

    try {
      // Whisper transcription typically takes 1-5 seconds per chunk
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
    }
  }

  /// Dispose worker and free all native whisper resources
  ///
  /// Frees the native whisper context (model) and terminates
  /// the worker isolate.
  Future<void> dispose() async {
    if (!_isActive || _commandPort == null) return;

    final completer = Completer<void>();

    final subscription = responses.listen((response) {
      if (response is WhisperDisposedResponse) {
        completer.complete();
      }
    });

    _commandPort!.send(DisposeWhisperCommand());

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
      throw StateError('WhisperWorker not active. Call spawn() first.');
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

/// Entry point for the whisper worker isolate
///
/// This function runs in the spawned isolate and maintains the native
/// whisper context (ev_whisper_context) for the lifetime of the isolate.
/// The context pointer NEVER crosses the isolate boundary.
void _whisperWorkerEntryPoint(SendPort mainSendPort) {
  // Set up command port for receiving commands
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  // Wait for main's response port
  late final SendPort responseSendPort;
  bool hasResponsePort = false;

  // Native state (lives for duration of isolate)
  ffi.Pointer<EvWhisperContextImpl>? nativeWhisperContext;
  EdgeVedaNativeBindings? bindings;
  int numThreads = 4;

  commandPort.listen((message) {
    // First message is always the response port
    if (!hasResponsePort && message is SendPort) {
      responseSendPort = message;
      hasResponsePort = true;
      return;
    }

    if (!hasResponsePort) return;

    // Handle commands
    if (message is InitWhisperCommand) {
      _handleInitWhisper(message, responseSendPort, (ctx, b) {
        nativeWhisperContext = ctx;
        bindings = b;
        numThreads = message.numThreads;
      });
    } else if (message is TranscribeChunkCommand) {
      if (nativeWhisperContext == null || bindings == null) {
        responseSendPort.send(WhisperErrorResponse(
          message: 'Whisper worker not initialized',
          errorCode: -6, // EV_ERROR_CONTEXT_INVALID
        ));
        return;
      }
      _handleTranscribeChunk(
        message,
        nativeWhisperContext!,
        bindings!,
        numThreads,
        responseSendPort,
      );
    } else if (message is DisposeWhisperCommand) {
      // Cleanup native whisper context
      if (nativeWhisperContext != null && bindings != null) {
        bindings!.evWhisperFree(nativeWhisperContext!);
        nativeWhisperContext = null;
      }
      responseSendPort.send(WhisperDisposedResponse());
      Isolate.exit();
    }
  });
}

/// Handle whisper initialization command
///
/// Loads the whisper model into a persistent whisper context.
void _handleInitWhisper(
  InitWhisperCommand cmd,
  SendPort responseSendPort,
  void Function(ffi.Pointer<EvWhisperContextImpl>, EdgeVedaNativeBindings)
      onSuccess,
) {
  final bindings = EdgeVedaNativeBindings.instance;

  final configPtr = calloc<EvWhisperConfig>();
  final modelPathPtr = cmd.modelPath.toNativeUtf8();
  final errorPtr = calloc<ffi.Int32>();

  try {
    configPtr.ref.modelPath = modelPathPtr;
    configPtr.ref.numThreads = cmd.numThreads;
    configPtr.ref.useGpu = cmd.useGpu;
    configPtr.ref.reserved = ffi.nullptr;

    final ctx = bindings.evWhisperInit(configPtr, errorPtr);

    if (ctx == ffi.nullptr) {
      responseSendPort.send(WhisperInitErrorResponse(
        message: 'Failed to initialize whisper context',
        errorCode: errorPtr.value,
      ));
      return;
    }

    // Get backend name
    final backendInt = bindings.evDetectBackend();
    final backendPtr = bindings.evBackendName(backendInt);
    final backendName = backendPtr.toDartString();

    onSuccess(ctx, bindings);
    responseSendPort.send(WhisperInitSuccessResponse(backend: backendName));
  } finally {
    calloc.free(modelPathPtr);
    calloc.free(configPtr);
    calloc.free(errorPtr);
  }
}

/// Handle transcription command
///
/// Performs whisper transcription on a chunk of PCM audio samples using
/// the persistent context. Extracts segments with text and timing data.
void _handleTranscribeChunk(
  TranscribeChunkCommand cmd,
  ffi.Pointer<EvWhisperContextImpl> ctx,
  EdgeVedaNativeBindings bindings,
  int defaultNumThreads,
  SendPort responseSendPort,
) {
  final nSamples = cmd.pcmSamples.length;

  // Allocate native memory for PCM samples
  final nativeSamples = calloc<ffi.Float>(nSamples);
  final nativeSamplesTyped =
      nativeSamples.asTypedList(nSamples);
  nativeSamplesTyped.setAll(0, cmd.pcmSamples);

  // Set up whisper params
  final paramsPtr = calloc<EvWhisperParams>();
  final languagePtr = cmd.language.toNativeUtf8();

  paramsPtr.ref.nThreads = defaultNumThreads;
  paramsPtr.ref.language = languagePtr;
  paramsPtr.ref.translate = cmd.translate;
  paramsPtr.ref.reserved = ffi.nullptr;

  // Allocate result struct
  final resultPtr = calloc<EvWhisperResult>();

  try {
    final result = bindings.evWhisperTranscribe(
      ctx,
      nativeSamples,
      nSamples,
      paramsPtr,
      resultPtr,
    );

    if (result != 0) {
      responseSendPort.send(WhisperErrorResponse(
        message: 'Whisper transcription failed: error code $result',
        errorCode: result,
      ));
      return;
    }

    // Extract segments from native result
    final segments = <WhisperSegment>[];
    final nSegments = resultPtr.ref.nSegments;
    final segmentsPtr = resultPtr.ref.segments;

    for (int i = 0; i < nSegments; i++) {
      final seg = segmentsPtr[i];
      final text = seg.text.toDartString();
      segments.add(WhisperSegment(
        text: text,
        startMs: seg.startMs,
        endMs: seg.endMs,
      ));
    }

    final processTimeMs = resultPtr.ref.processTimeMs;

    // Free the result (segments are owned by context, result struct zeroed)
    bindings.evWhisperFreeResult(resultPtr);

    responseSendPort.send(WhisperTranscribeResponse(
      segments: segments,
      processTimeMs: processTimeMs,
    ));
  } finally {
    calloc.free(languagePtr);
    calloc.free(paramsPtr);
    calloc.free(nativeSamples);
    calloc.free(resultPtr);
  }
}
