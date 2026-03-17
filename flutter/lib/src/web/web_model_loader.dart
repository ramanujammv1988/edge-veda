/// Model loading utilities for web platform.
///
/// Handles downloading GGUF models via fetch() and caching in IndexedDB.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Load and cache models for web platform.
class WebModelLoader {
  static const String _dbName = 'edge_veda_models';
  static const String _storeName = 'models';

  /// Download a model and cache it in IndexedDB.
  ///
  /// Returns the model bytes. If already cached, returns from cache.
  /// [onProgress] reports download progress (0.0 to 1.0).
  static Future<Uint8List> loadModel(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    // Try cache first
    final cached = await _getFromCache(url);
    if (cached != null) {
      onProgress?.call(1.0);
      return cached;
    }

    // Download
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) {
      throw Exception('Failed to download model: ${response.status}');
    }

    final contentLength = int.tryParse(
      response.headers.get('content-length') ?? '',
    );

    final reader = response.body!.getReader();
    final chunks = <Uint8List>[];
    var received = 0;

    while (true) {
      final result = await reader.read().toDart;
      if (result.done) break;

      final chunk = (result.value! as JSUint8Array).toDart;
      chunks.add(chunk);
      received += chunk.length;

      if (contentLength != null && contentLength > 0) {
        onProgress?.call(received / contentLength);
      }
    }

    // Combine chunks
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final bytes = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setAll(offset, chunk);
      offset += chunk.length;
    }

    // Cache for next time
    await _putInCache(url, bytes);

    return bytes;
  }

  /// Check if a model is cached.
  static Future<bool> isCached(String url) async {
    final cached = await _getFromCache(url);
    return cached != null;
  }

  /// Clear all cached models.
  static Future<void> clearCache() async {
    final factory = web.window.indexedDB;
    factory.deleteDatabase(_dbName);
  }

  static Future<Uint8List?> _getFromCache(String url) async {
    try {
      final db = await _openDB();
      final tx = db.transaction(_storeName.toJS, 'readonly');
      final store = tx.objectStore(_storeName);
      final request = store.get(url.toJS);

      final completer = Completer<Uint8List?>();
      request.onsuccess = ((web.Event _) {
        final result = request.result;
        if (result != null && result is JSArrayBuffer) {
          completer.complete(result.toDart.asUint8List());
        } else {
          completer.complete(null);
        }
      }).toJS;
      request.onerror = ((web.Event _) {
        completer.complete(null);
      }).toJS;

      return completer.future;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _putInCache(String url, Uint8List data) async {
    try {
      final db = await _openDB();
      final tx = db.transaction(_storeName.toJS, 'readwrite');
      final store = tx.objectStore(_storeName);
      store.put(data.buffer.toJS, url.toJS);
    } catch (_) {
      // Cache failures are non-fatal
    }
  }

  static Future<web.IDBDatabase> _openDB() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, 1);

    request.onupgradeneeded = ((web.IDBVersionChangeEvent event) {
      final db = (event.target as web.IDBOpenDBRequest).result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }).toJS;

    request.onsuccess = ((web.Event event) {
      completer.complete(request.result as web.IDBDatabase);
    }).toJS;

    request.onerror = ((web.Event event) {
      completer.completeError(Exception('Failed to open IndexedDB'));
    }).toJS;

    return completer.future;
  }
}
