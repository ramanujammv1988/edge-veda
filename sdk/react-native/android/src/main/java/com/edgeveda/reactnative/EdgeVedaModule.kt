package com.edgeveda.reactnative

import com.facebook.react.bridge.*
import kotlinx.coroutines.*

class EdgeVedaModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val contexts = mutableMapOf<Int, Long>()
    private var nextHandle = 1

    override fun getName() = "EdgeVeda"

    init {
        System.loadLibrary("edge_veda_rn")
    }

    @ReactMethod
    fun initialize(config: ReadableMap, promise: Promise) {
        scope.launch {
            try {
                val modelPath = config.getString("modelPath")
                    ?: throw Exception("modelPath required")
                val numThreads = if (config.hasKey("numThreads")) config.getInt("numThreads") else 4
                val contextSize = if (config.hasKey("contextSize")) config.getInt("contextSize") else 2048
                val gpuLayers = if (config.hasKey("gpuLayers")) config.getInt("gpuLayers") else -1

                val handle = nativeInit(modelPath, numThreads, contextSize, gpuLayers)
                if (handle == 0L) {
                    promise.reject("ERR_INIT", "Failed to initialize")
                    return@launch
                }

                val id = nextHandle++
                contexts[id] = handle
                promise.resolve(id)
            } catch (e: Exception) {
                promise.reject("ERR_INIT", e.message)
            }
        }
    }

    @ReactMethod
    fun generate(handle: Int, prompt: String, options: ReadableMap, promise: Promise) {
        scope.launch {
            try {
                val nativeHandle = contexts[handle]
                    ?: throw Exception("Invalid handle")
                val maxTokens = if (options.hasKey("maxTokens")) options.getInt("maxTokens") else 512
                val temperature = if (options.hasKey("temperature")) options.getDouble("temperature").toFloat() else 0.7f

                val startTime = System.currentTimeMillis()
                val text = nativeGenerate(nativeHandle, prompt, maxTokens, temperature)
                    ?: throw Exception("Generation failed")
                val latencyMs = System.currentTimeMillis() - startTime

                val result = Arguments.createMap().apply {
                    putString("text", text)
                    putInt("promptTokens", 0)
                    putInt("completionTokens", 0)
                    putInt("totalTokens", 0)
                    putDouble("latencyMs", latencyMs.toDouble())
                }
                promise.resolve(result)
            } catch (e: Exception) {
                promise.reject("ERR_GENERATE", e.message)
            }
        }
    }

    @ReactMethod
    fun dispose(handle: Int) {
        val nativeHandle = contexts.remove(handle) ?: return
        scope.launch {
            nativeFree(nativeHandle)
        }
    }

    override fun onCatalystInstanceDestroy() {
        scope.cancel()
        contexts.values.forEach { nativeFree(it) }
        contexts.clear()
    }

    // JNI
    private external fun nativeInit(
        modelPath: String, numThreads: Int,
        contextSize: Int, gpuLayers: Int
    ): Long

    private external fun nativeGenerate(
        handle: Long, prompt: String,
        maxTokens: Int, temperature: Float
    ): String?

    private external fun nativeFree(handle: Long)
}
