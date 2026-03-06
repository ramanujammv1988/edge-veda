package com.edgeveda.example

import android.app.Application

/**
 * Application class for the Edge Veda Example app.
 *
 * Handles global initialization such as loading native libraries
 * and setting up crash reporting.
 */
class EdgeVedaExampleApp : Application() {

    override fun onCreate() {
        super.onCreate()

        // Load the Edge Veda native library (JNI)
        try {
            System.loadLibrary("edgeveda_jni")
        } catch (e: UnsatisfiedLinkError) {
            // Native library not available — SDK will fall back to error state
            android.util.Log.w(TAG, "Native library not found: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "EdgeVedaExample"
    }
}