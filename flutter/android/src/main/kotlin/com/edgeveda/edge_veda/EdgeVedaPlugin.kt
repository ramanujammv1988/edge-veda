package com.edgeveda.edge_veda

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * EdgeVedaPlugin
 *
 * Flutter plugin registration for Edge Veda SDK.
 * The actual native functionality is accessed through Dart FFI bindings,
 * so this class is primarily for plugin registration and lifecycle management.
 */
class EdgeVedaPlugin: FlutterPlugin {

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    // Edge Veda uses FFI for native communication
    // This is just for plugin registration
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    // Cleanup if needed
  }
}
