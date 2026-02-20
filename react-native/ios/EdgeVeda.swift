import Foundation
import React
import EdgeVeda

#if RCT_NEW_ARCH_ENABLED
import EdgeVedaSpec
#endif

/**
 * Edge Veda iOS Native Module Implementation
 * Dual architecture support - Bridge and TurboModule
 */

@objc(EdgeVeda)
class EdgeVeda: RCTEventEmitter {

    // MARK: - Properties

    private var edgeVedaEngine: EdgeVeda.EdgeVeda?
    private var activeGenerations: [String: Task<Void, Never>] = [:]
    private let actorQueue = DispatchQueue(label: "com.edgeveda.react-native", qos: .userInitiated)

    // Vision context (loaded separately from the LLM)
    private var visionEngine: EdgeVeda.VisionContext?

    // Whisper STT context
    private var whisperEngine: EdgeVeda.WhisperContext?

    // Image generation context
    private var imageEngine: EdgeVeda.ImageGenerationContext?

    // MARK: - Lifecycle

    override init() {
        super.init()
    }

    // MARK: - Event Emitter

    override func supportedEvents() -> [String]! {
        return [
            "EdgeVeda_TokenGenerated",
            "EdgeVeda_GenerationComplete",
            "EdgeVeda_GenerationError",
            "EdgeVeda_ModelLoadProgress",
            "EdgeVeda_ImageProgress"
        ]
    }

    override static func requiresMainQueueSetup() -> Bool {
        return false
    }

    // MARK: - Public Methods

    /**
     * Initialize the model
     */
    @objc
    func initialize(_ modelPath: String,
                   config: String,
                   resolve: @escaping RCTPromiseResolveBlock,
                   reject: @escaping RCTPromiseRejectBlock) {

        Task {
            // Validate model path
            guard FileManager.default.fileExists(atPath: modelPath) else {
                reject("INVALID_MODEL_PATH", "Model file not found at path: \(modelPath)", nil)
                return
            }

            // Parse config
            guard let configData = config.data(using: .utf8),
                  let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                reject("INVALID_CONFIG", "Failed to parse configuration", nil)
                return
            }

            do {
                // Send progress event
                self.sendEvent(withName: "EdgeVeda_ModelLoadProgress", 
                             body: ["progress": 0.3, "message": "Initializing model..."])

                // Parse EdgeVedaConfig from JSON
                let edgeVedaConfig = try self.parseConfig(from: configDict)

                // Initialize EdgeVeda
                self.edgeVedaEngine = try await EdgeVeda.EdgeVeda(modelPath: modelPath, config: edgeVedaConfig)

                self.sendEvent(withName: "EdgeVeda_ModelLoadProgress",
                             body: ["progress": 1.0, "message": "Model loaded successfully"])

                resolve(nil)
            } catch let error as EdgeVeda.EdgeVedaError {
                reject("MODEL_LOAD_FAILED", error.errorDescription ?? "Failed to load model", error)
            } catch {
                reject("MODEL_LOAD_FAILED", "Failed to load model: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Generate text completion
     */
    @objc
    func generate(_ prompt: String,
                 options: String,
                 resolve: @escaping RCTPromiseResolveBlock,
                 reject: @escaping RCTPromiseRejectBlock) {

        Task {
            guard let edgeVedaEngine = self.edgeVedaEngine else {
                reject("MODEL_NOT_LOADED", "Model is not loaded", nil)
                return
            }

            // Parse options
            guard let optionsData = options.data(using: .utf8),
                  let optionsDict = try? JSONSerialization.jsonObject(with: optionsData) as? [String: Any] else {
                reject("INVALID_OPTIONS", "Failed to parse options", nil)
                return
            }

            do {
                let generateOptions = try self.parseGenerateOptions(from: optionsDict)
                let result = try await edgeVedaEngine.generate(prompt, options: generateOptions)
                resolve(result)
            } catch let error as EdgeVeda.EdgeVedaError {
                reject("GENERATION_FAILED", error.errorDescription ?? "Generation failed", error)
            } catch {
                reject("GENERATION_FAILED", "Generation failed: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Generate text with streaming
     */
    @objc
    func generateStream(_ prompt: String,
                       options: String,
                       requestId: String,
                       resolve: @escaping RCTPromiseResolveBlock,
                       reject: @escaping RCTPromiseRejectBlock) {

        guard let edgeVedaEngine = self.edgeVedaEngine else {
            reject("MODEL_NOT_LOADED", "Model is not loaded", nil)
            return
        }

        // Parse options
        guard let optionsData = options.data(using: .utf8),
              let optionsDict = try? JSONSerialization.jsonObject(with: optionsData) as? [String: Any] else {
            reject("INVALID_OPTIONS", "Failed to parse options", nil)
            return
        }

        let task = Task {
            do {
                let generateOptions = try self.parseGenerateOptions(from: optionsDict)
                let stream = edgeVedaEngine.generateStream(prompt, options: generateOptions)

                for try await token in stream {
                    // Check if generation was cancelled
                    if Task.isCancelled {
                        break
                    }

                    self.sendEvent(withName: "EdgeVeda_TokenGenerated",
                                 body: ["requestId": requestId, "token": token])
                }

                self.sendEvent(withName: "EdgeVeda_GenerationComplete", 
                             body: ["requestId": requestId])
                self.activeGenerations.removeValue(forKey: requestId)
                resolve(nil)

            } catch let error as EdgeVeda.EdgeVedaError {
                self.sendEvent(withName: "EdgeVeda_GenerationError",
                             body: ["requestId": requestId, "error": error.errorDescription ?? "Unknown error"])
                self.activeGenerations.removeValue(forKey: requestId)
                reject("GENERATION_FAILED", error.errorDescription ?? "Streaming failed", error)
            } catch {
                self.sendEvent(withName: "EdgeVeda_GenerationError",
                             body: ["requestId": requestId, "error": error.localizedDescription])
                self.activeGenerations.removeValue(forKey: requestId)
                reject("GENERATION_FAILED", "Streaming failed: \(error.localizedDescription)", error)
            }
        }

        activeGenerations[requestId] = task
    }

    /**
     * Cancel generation
     */
    @objc
    func cancelGeneration(_ requestId: String,
                         resolve: @escaping RCTPromiseResolveBlock,
                         reject: @escaping RCTPromiseRejectBlock) {

        if let task = activeGenerations[requestId] {
            task.cancel()
            activeGenerations.removeValue(forKey: requestId)
        }

        resolve(nil)
    }

    /**
     * Get memory usage
     */
    @objc
    func getMemoryUsage(_ resolve: @escaping RCTPromiseResolveBlock,
                       reject: @escaping RCTPromiseRejectBlock) {

        Task {
            guard let edgeVedaEngine = self.edgeVedaEngine else {
                reject("MODEL_NOT_LOADED", "Model is not loaded", nil)
                return
            }

            let memoryBytes = await edgeVedaEngine.memoryUsage

            let usage: [String: Any] = [
                "totalBytes": memoryBytes,
                "modelBytes": memoryBytes, // Swift SDK returns total, not broken down
                "kvCacheBytes": 0, // Not separately tracked in Swift SDK
                "availableBytes": ProcessInfo.processInfo.physicalMemory - memoryBytes
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: usage),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                resolve(jsonString)
            } else {
                reject("SERIALIZATION_ERROR", "Failed to serialize memory usage", nil)
            }
        }
    }

    /**
     * Get model info
     */
    @objc
    func getModelInfo(_ resolve: @escaping RCTPromiseResolveBlock,
                     reject: @escaping RCTPromiseRejectBlock) {

        Task {
            guard let edgeVedaEngine = self.edgeVedaEngine else {
                reject("MODEL_NOT_LOADED", "Model is not loaded", nil)
                return
            }

            do {
                let modelInfo = try await edgeVedaEngine.getModelInfo()

                if let jsonData = try? JSONSerialization.data(withJSONObject: modelInfo),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resolve(jsonString)
                } else {
                    reject("SERIALIZATION_ERROR", "Failed to serialize model info", nil)
                }
            } catch let error as EdgeVeda.EdgeVedaError {
                reject("GET_MODEL_INFO_FAILED", error.errorDescription ?? "Failed to get model info", error)
            } catch {
                reject("GET_MODEL_INFO_FAILED", "Failed to get model info: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Check if model is loaded
     */
    @objc
    func isModelLoaded() -> Bool {
        return edgeVedaEngine != nil
    }

    /**
     * Unload model
     */
    @objc
    func unloadModel(_ resolve: @escaping RCTPromiseResolveBlock,
                    reject: @escaping RCTPromiseRejectBlock) {

        Task {
            guard let edgeVedaEngine = self.edgeVedaEngine else {
                resolve(nil)
                return
            }

            // Cancel all active generations
            for (_, task) in activeGenerations {
                task.cancel()
            }
            activeGenerations.removeAll()

            // Unload model
            await edgeVedaEngine.unloadModel()
            self.edgeVedaEngine = nil

            resolve(nil)
        }
    }

    /**
     * Validate model file
     */
    @objc
    func validateModel(_ modelPath: String,
                      resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) {

        DispatchQueue.global(qos: .utility).async {
            // Check if file exists
            guard FileManager.default.fileExists(atPath: modelPath) else {
                resolve(false)
                return
            }

            // Check file extension
            let isValid = modelPath.hasSuffix(".gguf")
            resolve(isValid)
        }
    }

    /**
     * Get available GPU devices
     */
    @objc
    func getAvailableGpuDevices() -> String {
        let deviceInfo = EdgeVeda.DeviceInfo.current()
        let devices: [String] = deviceInfo.availableBackends.map { $0.rawValue }

        if let jsonData = try? JSONSerialization.data(withJSONObject: devices),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "[]"
    }

    // MARK: - Reset Context

    /**
     * Reset the KV context (clears conversation history while keeping model loaded)
     */
    @objc
    func resetContext(_ resolve: @escaping RCTPromiseResolveBlock,
                     reject: @escaping RCTPromiseRejectBlock) {
        Task {
            do {
                try await edgeVedaEngine?.resetContext()
                resolve(nil)
            } catch {
                reject("RESET_CONTEXT_FAILED", "Failed to reset context: \(error.localizedDescription)", error)
            }
        }
    }

    // MARK: - Vision Inference

    /**
     * Initialize vision inference context (VLM + mmproj)
     */
    @objc
    func initVision(_ config: String,
                   resolve: @escaping RCTPromiseResolveBlock,
                   reject: @escaping RCTPromiseRejectBlock) {
        Task {
            guard let configData = config.data(using: .utf8),
                  let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                reject("INVALID_CONFIG", "Failed to parse vision configuration", nil)
                return
            }

            do {
                let visionConfig = EdgeVeda.VisionConfig(
                    modelPath: configDict["modelPath"] as? String ?? "",
                    mmprojPath: configDict["mmprojPath"] as? String ?? "",
                    numThreads: configDict["numThreads"] as? Int ?? 4,
                    contextSize: configDict["contextSize"] as? Int ?? 2048,
                    gpuLayers: configDict["gpuLayers"] as? Int ?? -1
                )
                visionEngine = try await EdgeVeda.VisionContext(config: visionConfig)
                resolve(visionEngine?.backendName ?? "cpu")
            } catch {
                reject("VISION_INIT_FAILED", "Failed to initialize vision context: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Describe an image using vision inference
     */
    @objc
    func describeImage(_ rgbBytes: String,
                      width: Int,
                      height: Int,
                      prompt: String,
                      params: String,
                      resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) {
        Task {
            guard let engine = visionEngine else {
                reject("VISION_NOT_LOADED", "Vision context is not initialized", nil)
                return
            }

            guard let paramsData = params.data(using: .utf8),
                  let paramsDict = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any] else {
                reject("INVALID_PARAMS", "Failed to parse vision params", nil)
                return
            }

            do {
                let result = try await engine.describeImage(
                    rgbBase64: rgbBytes,
                    width: width,
                    height: height,
                    prompt: prompt,
                    maxTokens: paramsDict["maxTokens"] as? Int ?? 100,
                    temperature: paramsDict["temperature"] as? Float ?? 0.3
                )

                if let jsonData = try? JSONSerialization.data(withJSONObject: result),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resolve(jsonString)
                } else {
                    reject("SERIALIZATION_ERROR", "Failed to serialize vision result", nil)
                }
            } catch {
                reject("VISION_INFERENCE_FAILED", "Vision inference failed: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Free vision context
     */
    @objc
    func freeVision(_ resolve: @escaping RCTPromiseResolveBlock,
                   reject: @escaping RCTPromiseRejectBlock) {
        Task {
            await visionEngine?.free()
            visionEngine = nil
            resolve(nil)
        }
    }

    /**
     * Check if vision context is loaded
     */
    @objc
    func isVisionLoaded() -> Bool {
        return visionEngine != nil
    }

    // MARK: - Embedding

    /**
     * Generate a text embedding vector
     */
    @objc
    func embed(_ text: String,
              resolve: @escaping RCTPromiseResolveBlock,
              reject: @escaping RCTPromiseRejectBlock) {
        Task {
            guard let engine = edgeVedaEngine else {
                reject("MODEL_NOT_LOADED", "Model is not loaded", nil)
                return
            }

            do {
                let result = try await engine.embed(text)
                let resultDict: [String: Any] = [
                    "embedding": result.embedding,
                    "dimensions": result.dimensions,
                    "tokenCount": result.tokenCount,
                    "timeMs": result.timeMs ?? 0
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: resultDict),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resolve(jsonString)
                } else {
                    reject("SERIALIZATION_ERROR", "Failed to serialize embedding result", nil)
                }
            } catch {
                reject("EMBED_FAILED", "Embedding failed: \(error.localizedDescription)", error)
            }
        }
    }

    // MARK: - Whisper STT

    /**
     * Initialize Whisper STT context
     */
    @objc
    func initWhisper(_ modelPath: String,
                    config: String,
                    resolve: @escaping RCTPromiseResolveBlock,
                    reject: @escaping RCTPromiseRejectBlock) {
        Task {
            guard let configData = config.data(using: .utf8),
                  let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                reject("INVALID_CONFIG", "Failed to parse Whisper config", nil)
                return
            }

            do {
                let whisperConfig = EdgeVeda.WhisperConfig(
                    modelPath: modelPath,
                    numThreads: configDict["numThreads"] as? Int ?? 4,
                    useGpu: configDict["useGpu"] as? Bool ?? false
                )
                whisperEngine = try await EdgeVeda.WhisperContext(config: whisperConfig)
                resolve(whisperEngine?.backendName ?? "cpu")
            } catch {
                reject("WHISPER_INIT_FAILED", "Failed to initialize Whisper: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Transcribe audio to text
     */
    @objc
    func transcribeAudio(_ pcmBase64: String,
                        nSamples: Int,
                        params: String,
                        resolve: @escaping RCTPromiseResolveBlock,
                        reject: @escaping RCTPromiseRejectBlock) {
        Task {
            guard let engine = whisperEngine else {
                reject("WHISPER_NOT_LOADED", "Whisper context is not initialized", nil)
                return
            }

            guard let paramsData = params.data(using: .utf8),
                  let paramsDict = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any] else {
                reject("INVALID_PARAMS", "Failed to parse Whisper params", nil)
                return
            }

            do {
                let result = try await engine.transcribe(
                    pcmBase64: pcmBase64,
                    nSamples: nSamples,
                    language: paramsDict["language"] as? String ?? "en",
                    translate: paramsDict["translate"] as? Bool ?? false,
                    maxTokens: paramsDict["maxTokens"] as? Int ?? 0
                )

                if let jsonData = try? JSONSerialization.data(withJSONObject: result),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resolve(jsonString)
                } else {
                    reject("SERIALIZATION_ERROR", "Failed to serialize transcription result", nil)
                }
            } catch {
                reject("TRANSCRIPTION_FAILED", "Transcription failed: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Free Whisper STT context
     */
    @objc
    func freeWhisper(_ resolve: @escaping RCTPromiseResolveBlock,
                    reject: @escaping RCTPromiseRejectBlock) {
        Task {
            await whisperEngine?.free()
            whisperEngine = nil
            resolve(nil)
        }
    }

    /**
     * Check if Whisper context is loaded
     */
    @objc
    func isWhisperLoaded() -> Bool {
        return whisperEngine != nil
    }

    // MARK: - Image Generation

    /**
     * Initialize Stable Diffusion image generation context
     */
    @objc
    func initImageGeneration(_ modelPath: String,
                            config: String,
                            resolve: @escaping RCTPromiseResolveBlock,
                            reject: @escaping RCTPromiseRejectBlock) {
        Task {
            guard let configData = config.data(using: .utf8),
                  let configDict = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
                reject("INVALID_CONFIG", "Failed to parse image generation config", nil)
                return
            }

            do {
                let imgConfig = EdgeVeda.ImageGenerationConfig(
                    modelPath: modelPath,
                    width: configDict["width"] as? Int ?? 512,
                    height: configDict["height"] as? Int ?? 512
                )
                imageEngine = try await EdgeVeda.ImageGenerationContext(config: imgConfig)
                resolve(nil)
            } catch {
                reject("IMAGE_GEN_INIT_FAILED", "Failed to initialize image generation: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Generate an image from a text prompt
     */
    @objc
    func generateImage(_ params: String,
                      resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) {
        Task {
            guard let engine = imageEngine else {
                reject("IMAGE_GEN_NOT_LOADED", "Image generation context is not initialized", nil)
                return
            }

            guard let paramsData = params.data(using: .utf8),
                  let paramsDict = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any] else {
                reject("INVALID_PARAMS", "Failed to parse image generation params", nil)
                return
            }

            do {
                // Set up progress callback → emit EdgeVeda_ImageProgress events
                engine.setProgressCallback { [weak self] step, totalSteps, elapsedSeconds in
                    self?.sendEvent(withName: "EdgeVeda_ImageProgress", body: [
                        "step": step,
                        "totalSteps": totalSteps,
                        "elapsedSeconds": elapsedSeconds
                    ])
                }

                let result = try await engine.generate(
                    prompt: paramsDict["prompt"] as? String ?? "",
                    negativePrompt: paramsDict["negativePrompt"] as? String ?? "",
                    width: paramsDict["width"] as? Int ?? 512,
                    height: paramsDict["height"] as? Int ?? 512,
                    steps: paramsDict["steps"] as? Int ?? 20,
                    cfgScale: paramsDict["cfgScale"] as? Float ?? 7.0,
                    seed: paramsDict["seed"] as? Int ?? -1
                )

                if let jsonData = try? JSONSerialization.data(withJSONObject: result),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resolve(jsonString)
                } else {
                    reject("SERIALIZATION_ERROR", "Failed to serialize image result", nil)
                }
            } catch {
                reject("IMAGE_GEN_FAILED", "Image generation failed: \(error.localizedDescription)", error)
            }
        }
    }

    /**
     * Free image generation context
     */
    @objc
    func freeImageGeneration(_ resolve: @escaping RCTPromiseResolveBlock,
                            reject: @escaping RCTPromiseRejectBlock) {
        Task {
            await imageEngine?.free()
            imageEngine = nil
            resolve(nil)
        }
    }

    /**
     * Check if image generation context is loaded
     */
    @objc
    func isImageGenerationLoaded() -> Bool {
        return imageEngine != nil
    }

    // MARK: - Helper Methods

    private func parseConfig(from dict: [String: Any]) throws -> EdgeVeda.EdgeVedaConfig {
        var backend: EdgeVeda.Backend = .auto
        if let backendStr = dict["backend"] as? String {
            switch backendStr.lowercased() {
            case "cpu": backend = .cpu
            case "metal": backend = .metal
            case "auto": backend = .auto
            default: backend = .auto
            }
        }

        let threads = dict["threads"] as? Int ?? 0
        let contextSize = dict["contextSize"] as? Int ?? 2048
        let gpuLayers = dict["gpuLayers"] as? Int ?? -1
        let batchSize = dict["batchSize"] as? Int ?? 512
        let useMemoryMapping = dict["useMemoryMapping"] as? Bool ?? true
        let lockMemory = dict["lockMemory"] as? Bool ?? false
        let verbose = dict["verbose"] as? Bool ?? false

        return EdgeVeda.EdgeVedaConfig(
            backend: backend,
            threads: threads,
            contextSize: contextSize,
            gpuLayers: gpuLayers,
            batchSize: batchSize,
            useMemoryMapping: useMemoryMapping,
            lockMemory: lockMemory,
            verbose: verbose
        )
    }

    private func parseGenerateOptions(from dict: [String: Any]) throws -> EdgeVeda.GenerateOptions {
        let maxTokens = dict["maxTokens"] as? Int ?? 512
        let temperature = dict["temperature"] as? Float ?? 0.7
        let topP = dict["topP"] as? Float ?? 0.9
        let topK = dict["topK"] as? Int ?? 40
        let repeatPenalty = dict["repeatPenalty"] as? Float ?? 1.1
        let stopSequences = dict["stopSequences"] as? [String] ?? []

        return EdgeVeda.GenerateOptions(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            repeatPenalty: repeatPenalty,
            stopSequences: stopSequences
        )
    }
}