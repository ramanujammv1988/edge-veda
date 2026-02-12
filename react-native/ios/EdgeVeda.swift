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
            "EdgeVeda_ModelLoadProgress"
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