/// Web implementation of Edge Veda using WASM via Web Workers.
///
/// This replaces FFI bindings on the web platform, communicating with
/// a Web Worker that runs the WASM module off the main thread.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web Worker-based Edge Veda implementation.
///
/// All inference runs in a Web Worker to avoid blocking the UI thread.
/// Communication uses postMessage/onMessage protocol.
class EdgeVedaWeb {
  web.Worker? _worker;
  int _nextId = 0;
  final Map<int, Completer<JSObject>> _pendingRequests = {};
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();

  bool get isReady => _worker != null;

  /// Initialize the WASM engine in a Web Worker.
  Future<void> initialize(Map<String, dynamic> config) async {
    _worker = web.Worker('worker.js'.toJS);

    _worker!.onmessage = ((web.MessageEvent event) {
      final data = (event.data as JSObject);
      _handleWorkerMessage(data);
    }).toJS;

    _worker!.onerror = ((web.Event event) {
      _eventController.add({'type': 'error', 'message': 'Worker error'});
    }).toJS;

    await _sendRequest('init', config);
  }

  /// Generate complete text response.
  Future<String> generate(
    String prompt,
    Map<String, dynamic> options,
  ) async {
    final result = await _sendRequest('generate', {
      'prompt': prompt,
      ...options,
    });
    return (result as JSObject).getProperty('text'.toJS).toString();
  }

  /// Stream tokens from generation.
  Stream<String> generateStream(
    String prompt,
    Map<String, dynamic> options,
  ) {
    final controller = StreamController<String>();
    final id = _nextId++;

    // Listen for stream events with this ID
    late StreamSubscription sub;
    sub = _eventController.stream.listen((event) {
      if (event['id'] != id) return;

      switch (event['type']) {
        case 'stream_token':
          controller.add(event['token'] as String);
        case 'stream_end':
          controller.close();
          sub.cancel();
        case 'error':
          controller.addError(Exception(event['error']));
          controller.close();
          sub.cancel();
      }
    });

    // Start the stream
    _postMessage('stream_start', id, {
      'prompt': prompt,
      ...options,
    });

    // Auto-request tokens
    _streamTokenLoop(id, controller);

    controller.onCancel = () {
      _postMessage('stream_cancel', id, {});
      sub.cancel();
    };

    return controller.stream;
  }

  Future<void> _streamTokenLoop(
    int id,
    StreamController<String> controller,
  ) async {
    while (!controller.isClosed) {
      _postMessage('stream_next', id, {});
      // Small yield to not block
      await Future.delayed(Duration.zero);
    }
  }

  /// Dispose the WASM engine.
  void dispose() {
    if (_worker != null) {
      _postMessage('dispose', _nextId++, {});
      _worker!.terminate();
      _worker = null;
    }
    _eventController.close();
  }

  Future<JSAny?> _sendRequest(String type, Map<String, dynamic> payload) {
    final id = _nextId++;
    final completer = Completer<JSObject>();
    _pendingRequests[id] = completer;
    _postMessage(type, id, payload);
    return completer.future;
  }

  void _postMessage(String type, int id, Map<String, dynamic> payload) {
    final msg = <String, dynamic>{
      'type': type,
      'id': id,
      'payload': payload,
    };
    _worker?.postMessage(msg.jsify());
  }

  void _handleWorkerMessage(JSObject data) {
    final type = (data.getProperty('type'.toJS) as JSString).toDart;
    final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;

    // Handle stream events
    if (type == 'stream_token' || type == 'stream_end') {
      final payload = data.getProperty('payload'.toJS);
      _eventController.add({
        'type': type,
        'id': id,
        if (type == 'stream_token' && payload != null)
          'token':
              ((payload as JSObject).getProperty('token'.toJS) as JSString)
                  .toDart,
      });
      return;
    }

    // Handle request responses
    final completer = _pendingRequests.remove(id);
    if (completer == null) return;

    if (type == 'error') {
      final error = (data.getProperty('error'.toJS) as JSString).toDart;
      completer.completeError(Exception(error));
    } else {
      completer.complete(data);
    }
  }
}
