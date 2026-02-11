package com.edgeveda

import com.edgeveda.sdk.EdgeVeda
import com.edgeveda.sdk.EdgeVedaConfig
import com.edgeveda.sdk.GenerateOptions
import com.edgeveda.sdk.Backend
import com.edgeveda.sdk.EdgeVedaException
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.turbomodule.core.CallInvokerHolderImpl
import com.facebook.react.turbomodule.core.interfaces.TurboModule
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.onCompletion
import org.json.JSONObject
import org.json.JSONArray
import java.io.File

/**
 * Edge Veda Android Native Module
 * TurboModule implementation for on-device LLM inference
 */
class EdgeVedaModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext), TurboModule {

    companion object {
        const val NAME = "EdgeVeda"

        // Event names
        const val EVENT_TOKEN_GENERATED = "EdgeVeda_TokenGenerated"
        const val EVENT_GENERATION_COMPLETE = "EdgeVeda_GenerationComplete"
        const val EVENT_GENERATION_ERROR = "EdgeVeda_GenerationError"
        const val EVENT_MODEL_LOAD_PROGRESS = "EdgeVeda_ModelLoadProgress"
    }

    private var edgeVeda: EdgeVeda? = null
    private val activeGenerations = mutableMapOf<String, Job>()
    private val coroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    override fun getName(): String = NAME

    /**
     * Send event to JavaScript
     */
    private fun sendEvent(eventName: String, params: WritableMap) {
        reactApplicationContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(eventName, params)
    }

    /**
     * Initialize the model
     */
    @ReactMethod
    fun initialize(
        modelPath: String,
        config: String,
        promise: Promise
    ) {
        coroutineScope.launch {
            try {
                // Validate model path
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    promise.reject(
                        "INVALID_MODEL_PATH",
                        "Model file not found at path: $modelPath"
                    )
                    return@launch
                }

                // Parse config
                val configJson = try {
                    JSONObject(config)
                } catch (e: Exception) {
                    promise.reject("INVALID_CONFIG", "Failed to parse configuration", e)
                    return@launch
                }

                // Send progress event
                sendProgressEvent(0.3, "Initializing model...")

                // Parse EdgeVedaConfig from JSON
                val edgeVedaConfig = parseConfig(configJson)

                // Create and initialize EdgeVeda
                val instance = EdgeVeda.create()
                instance.init(modelPath, edgeVedaConfig)

                edgeVeda = instance
                sendProgressEvent(1.0, "Model loaded successfully")
                promise.resolve(null)

            } catch (e: EdgeVedaException) {
                promise.reject("MODEL_LOAD_FAILED", e.message ?: "Failed to load model", e)
            } catch (e: Exception) {
                promise.reject("MODEL_LOAD_FAILED", "Failed to load model: ${e.message}", e)
            }
        }
    }

    /**
     * Generate text completion
     */
    @ReactMethod
    fun generate(
        prompt: String,
        options: String,
        promise: Promise
    ) {
        val edgeVedaInstance = edgeVeda
        if (edgeVedaInstance == null) {
            promise.reject("MODEL_NOT_LOADED", "Model is not loaded")
            return
        }

        coroutineScope.launch {
            try {
                // Parse options
                val optionsJson = try {
                    JSONObject(options)
                } catch (e: Exception) {
                    promise.reject("INVALID_OPTIONS", "Failed to parse options", e)
                    return@launch
                }

                val generateOptions = parseGenerateOptions(optionsJson)
                val result = edgeVedaInstance.generate(prompt, generateOptions)
                promise.resolve(result)

            } catch (e: EdgeVedaException) {
                promise.reject("GENERATION_FAILED", e.message ?: "Generation failed", e)
            } catch (e: Exception) {
                promise.reject("GENERATION_FAILED", "Generation failed: ${e.message}", e)
            }
        }
    }

    /**
     * Generate text with streaming
     */
    @ReactMethod
    fun generateStream(
        prompt: String,
        options: String,
        requestId: String,
        promise: Promise
    ) {
        val edgeVedaInstance = edgeVeda
        if (edgeVedaInstance == null) {
            promise.reject("MODEL_NOT_LOADED", "Model is not loaded")
            return
        }

        // Parse options
        val optionsJson = try {
            JSONObject(options)
        } catch (e: Exception) {
            promise.reject("INVALID_OPTIONS", "Failed to parse options", e)
            return
        }

        val job = coroutineScope.launch {
            try {
                val generateOptions = parseGenerateOptions(optionsJson)

                edgeVedaInstance.generateStream(prompt, generateOptions)
                    .catch { e ->
                        val errorMessage = when (e) {
                            is EdgeVedaException -> e.message ?: "Unknown error"
                            else -> e.message ?: "Unknown error"
                        }
                        sendErrorEvent(requestId, errorMessage)
                        activeGenerations.remove(requestId)
                        promise.reject("GENERATION_FAILED", "Streaming failed: $errorMessage", e)
                    }
                    .onCompletion {
                        if (it == null) {
                            sendCompleteEvent(requestId)
                            activeGenerations.remove(requestId)
                            promise.resolve(null)
                        }
                    }
                    .collect { token ->
                        sendTokenEvent(requestId, token)
                    }

            } catch (e: EdgeVedaException) {
                sendErrorEvent(requestId, e.message ?: "Unknown error")
                activeGenerations.remove(requestId)
                promise.reject("GENERATION_FAILED", e.message ?: "Streaming failed", e)
            } catch (e: Exception) {
                sendErrorEvent(requestId, e.message ?: "Unknown error")
                activeGenerations.remove(requestId)
                promise.reject("GENERATION_FAILED", "Streaming failed: ${e.message}", e)
            }
        }

        activeGenerations[requestId] = job
    }

    /**
     * Cancel generation
     */
    @ReactMethod
    fun cancelGeneration(
        requestId: String,
        promise: Promise
    ) {
        activeGenerations[requestId]?.cancel()
        activeGenerations.remove(requestId)
        promise.resolve(null)
    }

    /**
     * Get memory usage (synchronous)
     */
    @ReactMethod(isBlockingSynchronousMethod = true)
    fun getMemoryUsage(): String {
        val edgeVedaInstance = edgeVeda
        if (edgeVedaInstance == null) {
            return JSONObject().apply {
                put("totalBytes", 0)
                put("modelBytes", 0)
                put("kvCacheBytes", 0)
                put("availableBytes", 0)
            }.toString()
        }

        val memoryBytes = edgeVedaInstance.memoryUsage
        val runtime = Runtime.getRuntime()
        val availableBytes = runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory())

        val usage = JSONObject().apply {
            put("totalBytes", if (memoryBytes >= 0) memoryBytes else 0)
            put("modelBytes", if (memoryBytes >= 0) memoryBytes else 0)
            put("kvCacheBytes", 0) // Not separately tracked in Kotlin SDK
            put("availableBytes", availableBytes)
        }

        return usage.toString()
    }

    /**
     * Get model info (synchronous)
     */
    @ReactMethod(isBlockingSynchronousMethod = true)
    fun getModelInfo(): String {
        if (edgeVeda == null) {
            throw IllegalStateException("Model is not loaded")
        }

        // Note: Kotlin SDK doesn't expose model info directly yet
        // Return basic info for now
        val info = JSONObject().apply {
            put("name", "unknown")
            put("architecture", "unknown")
            put("parameters", 0)
            put("contextLength", 2048)
            put("vocabSize", 32000)
            put("quantization", "q4_0")
        }

        return info.toString()
    }

    /**
     * Check if model is loaded (synchronous)
     */
    @ReactMethod(isBlockingSynchronousMethod = true)
    fun isModelLoaded(): Boolean {
        return edgeVeda != null
    }

    /**
     * Unload model
     */
    @ReactMethod
    fun unloadModel(promise: Promise) {
        coroutineScope.launch {
            try {
                val edgeVedaInstance = edgeVeda
                if (edgeVedaInstance == null) {
                    promise.resolve(null)
                    return@launch
                }

                // Cancel all active generations
                activeGenerations.values.forEach { it.cancel() }
                activeGenerations.clear()

                // Unload model
                edgeVedaInstance.unloadModel()
                edgeVeda = null

                promise.resolve(null)

            } catch (e: EdgeVedaException) {
                promise.reject("UNLOAD_FAILED", e.message ?: "Failed to unload model", e)
            } catch (e: Exception) {
                promise.reject("UNLOAD_FAILED", "Failed to unload model: ${e.message}", e)
            }
        }
    }

    /**
     * Validate model file
     */
    @ReactMethod
    fun validateModel(
        modelPath: String,
        promise: Promise
    ) {
        coroutineScope.launch {
            try {
                // Check if file exists
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    promise.resolve(false)
                    return@launch
                }

                // Check file extension
                val isValid = modelPath.endsWith(".gguf")
                promise.resolve(isValid)

            } catch (e: Exception) {
                promise.resolve(false)
            }
        }
    }

    /**
     * Get available GPU devices (synchronous)
     */
    @ReactMethod(isBlockingSynchronousMethod = true)
    fun getAvailableGpuDevices(): String {
        val devices = JSONArray().apply {
            put("CPU")
            // TODO: Detect actual GPU capabilities
            // For now, list potential backends
            put("Vulkan")
            put("NNAPI")
        }

        return devices.toString()
    }

    /**
     * Required for event emitter
     */
    @ReactMethod
    fun addListener(eventName: String) {
        // Required for TurboModule event support
    }

    /**
     * Required for event emitter
     */
    @ReactMethod
    fun removeListeners(count: Int) {
        // Required for TurboModule event support
    }

    // Helper methods

    private fun parseConfig(json: JSONObject): EdgeVedaConfig {
        val backend = when (json.optString("backend", "auto").lowercase()) {
            "cpu" -> Backend.CPU
            "vulkan" -> Backend.VULKAN
            "nnapi" -> Backend.NNAPI
            "auto" -> Backend.AUTO
            else -> Backend.AUTO
        }

        return EdgeVedaConfig(
            backend = backend,
            numThreads = json.optInt("threads", 0),
            contextSize = json.optInt("contextSize", 2048),
            batchSize = json.optInt("batchSize", 512),
            useGpu = json.optBoolean("useGpu", true),
            useMmap = json.optBoolean("useMemoryMapping", true),
            useMlock = json.optBoolean("lockMemory", false),
            temperature = json.optDouble("temperature", 0.7).toFloat(),
            topP = json.optDouble("topP", 0.9).toFloat(),
            topK = json.optInt("topK", 40),
            repeatPenalty = json.optDouble("repeatPenalty", 1.1).toFloat(),
            seed = json.optLong("seed", -1L)
        )
    }

    private fun parseGenerateOptions(json: JSONObject): GenerateOptions {
        val maxTokens = if (json.has("maxTokens")) json.getInt("maxTokens") else null
        val temperature = if (json.has("temperature")) json.getDouble("temperature").toFloat() else null
        val topP = if (json.has("topP")) json.getDouble("topP").toFloat() else null
        val topK = if (json.has("topK")) json.getInt("topK") else null
        val repeatPenalty = if (json.has("repeatPenalty")) json.getDouble("repeatPenalty").toFloat() else null

        val stopSequences = mutableListOf<String>()
        if (json.has("stopSequences")) {
            val array = json.getJSONArray("stopSequences")
            for (i in 0 until array.length()) {
                stopSequences.add(array.getString(i))
            }
        }

        return GenerateOptions(
            maxTokens = maxTokens,
            temperature = temperature,
            topP = topP,
            topK = topK,
            repeatPenalty = repeatPenalty,
            stopSequences = stopSequences
        )
    }

    private fun sendTokenEvent(requestId: String, token: String) {
        val params = Arguments.createMap().apply {
            putString("requestId", requestId)
            putString("token", token)
        }
        sendEvent(EVENT_TOKEN_GENERATED, params)
    }

    private fun sendCompleteEvent(requestId: String) {
        val params = Arguments.createMap().apply {
            putString("requestId", requestId)
        }
        sendEvent(EVENT_GENERATION_COMPLETE, params)
    }

    private fun sendErrorEvent(requestId: String, error: String) {
        val params = Arguments.createMap().apply {
            putString("requestId", requestId)
            putString("error", error)
        }
        sendEvent(EVENT_GENERATION_ERROR, params)
    }

    private fun sendProgressEvent(progress: Double, message: String) {
        val params = Arguments.createMap().apply {
            putDouble("progress", progress)
            putString("message", message)
        }
        sendEvent(EVENT_MODEL_LOAD_PROGRESS, params)
    }

    /**
     * Clean up when module is destroyed
     */
    override fun onCatalystInstanceDestroy() {
        super.onCatalystInstanceDestroy()
        coroutineScope.cancel()
        activeGenerations.clear()
        edgeVeda?.close()
        edgeVeda = null
    }
}