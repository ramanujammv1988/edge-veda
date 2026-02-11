package com.edgeveda

import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import kotlinx.coroutines.*
import com.edgeveda.sdk.EdgeVeda
import com.edgeveda.sdk.EdgeVedaConfig
import com.edgeveda.sdk.GenerateOptions
import org.json.JSONObject
import org.json.JSONArray

/**
 * Edge Veda Android Native Module - New Architecture (TurboModule)
 * Implements the Codegen-generated NativeEdgeVedaSpec interface
 */
@ReactModule(name = EdgeVedaModule.NAME)
class EdgeVedaModule(reactContext: ReactApplicationContext) : 
    NativeEdgeVedaSpec(reactContext) {

    private var edgeVeda: EdgeVeda? = null
    private val moduleScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val activeGenerations = mutableMapOf<String, Job>()

    companion object {
        const val NAME = "EdgeVeda"
    }

    override fun getName(): String = NAME

    override fun onInvalidate() {
        super.onInvalidate()
        moduleScope.cancel()
        runBlocking {
            edgeVeda?.unloadModel()
        }
    }

    // MARK: - TurboModule Methods

    override fun initialize(modelPath: String, config: String, promise: Promise) {
        moduleScope.launch {
            try {
                val configJson = JSONObject(config)
                val edgeVedaConfig = parseConfig(configJson)

                sendEvent("EdgeVeda_ModelLoadProgress", 
                    Arguments.createMap().apply {
                        putDouble("progress", 0.3)
                        putString("message", "Initializing model...")
                    }
                )

                edgeVeda = EdgeVeda(modelPath, edgeVedaConfig)

                sendEvent("EdgeVeda_ModelLoadProgress",
                    Arguments.createMap().apply {
                        putDouble("progress", 1.0)
                        putString("message", "Model loaded successfully")
                    }
                )

                promise.resolve(null)
            } catch (e: Exception) {
                promise.reject("MODEL_LOAD_FAILED", "Failed to load model: ${e.message}", e)
            }
        }
    }

    override fun generate(prompt: String, options: String, promise: Promise) {
        moduleScope.launch {
            try {
                val engine = edgeVeda ?: throw IllegalStateException("Model not loaded")
                val optionsJson = JSONObject(options)
                val generateOptions = parseGenerateOptions(optionsJson)

                val result = engine.generate(prompt, generateOptions)
                promise.resolve(result)
            } catch (e: Exception) {
                promise.reject("GENERATION_FAILED", "Generation failed: ${e.message}", e)
            }
        }
    }

    override fun generateStream(prompt: String, options: String, requestId: String, promise: Promise) {
        val engine = edgeVeda
        if (engine == null) {
            promise.reject("MODEL_NOT_LOADED", "Model is not loaded", null)
            return
        }

        val job = moduleScope.launch {
            try {
                val optionsJson = JSONObject(options)
                val generateOptions = parseGenerateOptions(optionsJson)

                engine.generateStream(prompt, generateOptions).collect { token ->
                    sendEvent("EdgeVeda_TokenGenerated",
                        Arguments.createMap().apply {
                            putString("requestId", requestId)
                            putString("token", token)
                        }
                    )
                }

                sendEvent("EdgeVeda_GenerationComplete",
                    Arguments.createMap().apply {
                        putString("requestId", requestId)
                    }
                )
                activeGenerations.remove(requestId)
                promise.resolve(null)
            } catch (e: Exception) {
                sendEvent("EdgeVeda_GenerationError",
                    Arguments.createMap().apply {
                        putString("requestId", requestId)
                        putString("error", e.message ?: "Unknown error")
                    }
                )
                activeGenerations.remove(requestId)
                promise.reject("GENERATION_FAILED", "Streaming failed: ${e.message}", e)
            }
        }

        activeGenerations[requestId] = job
    }

    override fun cancelGeneration(requestId: String, promise: Promise) {
        activeGenerations[requestId]?.cancel()
        activeGenerations.remove(requestId)
        promise.resolve(null)
    }

    override fun getMemoryUsage(promise: Promise) {
        moduleScope.launch {
            try {
                val engine = edgeVeda ?: throw IllegalStateException("Model not loaded")
                val memoryBytes = engine.getMemoryUsage()

                val usage = JSONObject().apply {
                    put("totalBytes", memoryBytes)
                    put("modelBytes", memoryBytes)
                    put("kvCacheBytes", 0)
                    put("availableBytes", Runtime.getRuntime().maxMemory() - memoryBytes)
                }

                promise.resolve(usage.toString())
            } catch (e: Exception) {
                promise.reject("GET_MEMORY_USAGE_FAILED", "Failed to get memory usage: ${e.message}", e)
            }
        }
    }

    override fun getModelInfo(promise: Promise) {
        moduleScope.launch {
            try {
                val engine = edgeVeda ?: throw IllegalStateException("Model not loaded")
                val modelInfo = engine.getModelInfo()
                promise.resolve(modelInfo.toString())
            } catch (e: Exception) {
                promise.reject("GET_MODEL_INFO_FAILED", "Failed to get model info: ${e.message}", e)
            }
        }
    }

    override fun isModelLoaded(): Boolean {
        return edgeVeda != null
    }

    override fun unloadModel(promise: Promise) {
        moduleScope.launch {
            try {
                // Cancel all active generations
                activeGenerations.values.forEach { it.cancel() }
                activeGenerations.clear()

                edgeVeda?.unloadModel()
                edgeVeda = null
                promise.resolve(null)
            } catch (e: Exception) {
                promise.reject("UNLOAD_MODEL_FAILED", "Failed to unload model: ${e.message}", e)
            }
        }
    }

    override fun validateModel(modelPath: String, promise: Promise) {
        moduleScope.launch(Dispatchers.IO) {
            try {
                val file = java.io.File(modelPath)
                val isValid = file.exists() && file.extension == "gguf"
                promise.resolve(isValid)
            } catch (e: Exception) {
                promise.resolve(false)
            }
        }
    }

    override fun getAvailableGpuDevices(): String {
        val devices = JSONArray().apply {
            put("cpu")
            // Add GPU detection logic if needed
        }
        return devices.toString()
    }

    override fun addListener(eventName: String) {
        // Required for event emitter
    }

    override fun removeListeners(count: Double) {
        // Required for event emitter
    }

    // MARK: - Helper Methods

    private fun sendEvent(eventName: String, params: WritableMap?) {
        reactApplicationContext
            .getJSModule(RCTDeviceEventEmitter::class.java)
            .emit(eventName, params)
    }

    private fun parseConfig(json: JSONObject): EdgeVedaConfig {
        val backend = when (json.optString("backend", "auto").lowercase()) {
            "cpu" -> EdgeVedaConfig.Backend.CPU
            "gpu" -> EdgeVedaConfig.Backend.GPU
            else -> EdgeVedaConfig.Backend.AUTO
        }

        return EdgeVedaConfig(
            backend = backend,
            threads = json.optInt("threads", 0),
            contextSize = json.optInt("contextSize", 2048),
            gpuLayers = json.optInt("gpuLayers", -1),
            batchSize = json.optInt("batchSize", 512),
            useMemoryMapping = json.optBoolean("useMemoryMapping", true),
            lockMemory = json.optBoolean("lockMemory", false),
            verbose = json.optBoolean("verbose", false)
        )
    }

    private fun parseGenerateOptions(json: JSONObject): GenerateOptions {
        val stopSequences = mutableListOf<String>()
        val stopArray = json.optJSONArray("stopSequences")
        if (stopArray != null) {
            for (i in 0 until stopArray.length()) {
                stopSequences.add(stopArray.getString(i))
            }
        }

        return GenerateOptions(
            maxTokens = json.optInt("maxTokens", 512),
            temperature = json.optDouble("temperature", 0.7).toFloat(),
            topP = json.optDouble("topP", 0.9).toFloat(),
            topK = json.optInt("topK", 40),
            repeatPenalty = json.optDouble("repeatPenalty", 1.1).toFloat(),
            stopSequences = stopSequences
        )
    }
}