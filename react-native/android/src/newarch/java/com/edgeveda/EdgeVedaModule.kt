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

    // Vision, Whisper, and image generation contexts
    private var visionContext: com.edgeveda.sdk.VisionContext? = null
    private var whisperContext: com.edgeveda.sdk.WhisperContext? = null
    private var imageContext: com.edgeveda.sdk.ImageGenerationContext? = null

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

    // ---------------------------------------------------------------------------
    // Reset Context
    // ---------------------------------------------------------------------------

    override fun resetContext(promise: Promise) {
        moduleScope.launch {
            try {
                edgeVeda?.resetContext()
                promise.resolve(null)
            } catch (e: Exception) {
                promise.reject("RESET_CONTEXT_FAILED", "Failed to reset context: ${e.message}", e)
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Vision Inference
    // ---------------------------------------------------------------------------

    override fun initVision(config: String, promise: Promise) {
        moduleScope.launch {
            try {
                val configJson = JSONObject(config)
                val visionConfig = com.edgeveda.sdk.VisionConfig(
                    modelPath = configJson.optString("modelPath"),
                    mmprojPath = configJson.optString("mmprojPath"),
                    numThreads = configJson.optInt("numThreads", 4),
                    contextSize = configJson.optInt("contextSize", 2048),
                    gpuLayers = configJson.optInt("gpuLayers", -1)
                )
                visionContext = com.edgeveda.sdk.VisionContext(visionConfig)
                promise.resolve(visionContext?.backendName ?: "cpu")
            } catch (e: Exception) {
                promise.reject("VISION_INIT_FAILED", "Failed to initialize vision: ${e.message}", e)
            }
        }
    }

    override fun describeImage(
        rgbBytes: String, width: Double, height: Double,
        prompt: String, params: String, promise: Promise
    ) {
        moduleScope.launch {
            try {
                val engine = visionContext ?: throw IllegalStateException("Vision context not initialized")
                val paramsJson = JSONObject(params)
                val result = engine.describeImage(
                    rgbBase64 = rgbBytes,
                    width = width.toInt(),
                    height = height.toInt(),
                    prompt = prompt,
                    maxTokens = paramsJson.optInt("maxTokens", 100),
                    temperature = paramsJson.optDouble("temperature", 0.3).toFloat()
                )
                promise.resolve(result.toString())
            } catch (e: Exception) {
                promise.reject("VISION_INFERENCE_FAILED", "Vision inference failed: ${e.message}", e)
            }
        }
    }

    override fun freeVision(promise: Promise) {
        moduleScope.launch {
            visionContext?.free()
            visionContext = null
            promise.resolve(null)
        }
    }

    override fun isVisionLoaded(): Boolean = visionContext != null

    // ---------------------------------------------------------------------------
    // Embedding
    // ---------------------------------------------------------------------------

    override fun embed(text: String, promise: Promise) {
        moduleScope.launch {
            try {
                val engine = edgeVeda ?: throw IllegalStateException("Model not loaded")
                val result = engine.embed(text)
                promise.resolve(result.toString())
            } catch (e: Exception) {
                promise.reject("EMBED_FAILED", "Embedding failed: ${e.message}", e)
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Whisper STT
    // ---------------------------------------------------------------------------

    override fun initWhisper(modelPath: String, config: String, promise: Promise) {
        moduleScope.launch {
            try {
                val configJson = JSONObject(config)
                val whisperConfig = com.edgeveda.sdk.WhisperConfig(
                    modelPath = modelPath,
                    numThreads = configJson.optInt("numThreads", 4),
                    useGpu = configJson.optBoolean("useGpu", false)
                )
                whisperContext = com.edgeveda.sdk.WhisperContext(whisperConfig)
                promise.resolve(whisperContext?.backendName ?: "cpu")
            } catch (e: Exception) {
                promise.reject("WHISPER_INIT_FAILED", "Failed to initialize Whisper: ${e.message}", e)
            }
        }
    }

    override fun transcribeAudio(pcmBase64: String, nSamples: Double, params: String, promise: Promise) {
        moduleScope.launch {
            try {
                val engine = whisperContext ?: throw IllegalStateException("Whisper context not initialized")
                val paramsJson = JSONObject(params)
                val result = engine.transcribe(
                    pcmBase64 = pcmBase64,
                    nSamples = nSamples.toInt(),
                    language = paramsJson.optString("language", "en"),
                    translate = paramsJson.optBoolean("translate", false),
                    maxTokens = paramsJson.optInt("maxTokens", 0)
                )
                promise.resolve(result.toString())
            } catch (e: Exception) {
                promise.reject("TRANSCRIPTION_FAILED", "Transcription failed: ${e.message}", e)
            }
        }
    }

    override fun freeWhisper(promise: Promise) {
        moduleScope.launch {
            whisperContext?.free()
            whisperContext = null
            promise.resolve(null)
        }
    }

    override fun isWhisperLoaded(): Boolean = whisperContext != null

    // ---------------------------------------------------------------------------
    // Image Generation
    // ---------------------------------------------------------------------------

    override fun initImageGeneration(modelPath: String, config: String, promise: Promise) {
        moduleScope.launch {
            try {
                val configJson = JSONObject(config)
                val imgConfig = com.edgeveda.sdk.ImageGenerationConfig(
                    modelPath = modelPath,
                    width = configJson.optInt("width", 512),
                    height = configJson.optInt("height", 512)
                )
                imageContext = com.edgeveda.sdk.ImageGenerationContext(imgConfig)
                promise.resolve(null)
            } catch (e: Exception) {
                promise.reject("IMAGE_GEN_INIT_FAILED", "Failed to initialize image generation: ${e.message}", e)
            }
        }
    }

    override fun generateImage(params: String, promise: Promise) {
        moduleScope.launch {
            try {
                val engine = imageContext ?: throw IllegalStateException("Image generation context not initialized")
                val paramsJson = JSONObject(params)

                // Set up progress callback → emit EdgeVeda_ImageProgress events
                engine.setProgressCallback { step, totalSteps, elapsedSeconds ->
                    sendEvent("EdgeVeda_ImageProgress",
                        Arguments.createMap().apply {
                            putInt("step", step)
                            putInt("totalSteps", totalSteps)
                            putDouble("elapsedSeconds", elapsedSeconds.toDouble())
                        }
                    )
                }

                val result = engine.generate(
                    prompt = paramsJson.optString("prompt"),
                    negativePrompt = paramsJson.optString("negativePrompt", ""),
                    width = paramsJson.optInt("width", 512),
                    height = paramsJson.optInt("height", 512),
                    steps = paramsJson.optInt("steps", 20),
                    cfgScale = paramsJson.optDouble("cfgScale", 7.0).toFloat(),
                    seed = paramsJson.optInt("seed", -1)
                )
                promise.resolve(result.toString())
            } catch (e: Exception) {
                promise.reject("IMAGE_GEN_FAILED", "Image generation failed: ${e.message}", e)
            }
        }
    }

    override fun freeImageGeneration(promise: Promise) {
        moduleScope.launch {
            imageContext?.free()
            imageContext = null
            promise.resolve(null)
        }
    }

    override fun isImageGenerationLoaded(): Boolean = imageContext != null

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