import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class EdgeVedaTests: XCTestCase {

    // MARK: - Configuration Tests

    func testDefaultConfig() {
        let config = EdgeVedaConfig.default

        XCTAssertEqual(config.backend, .auto)
        XCTAssertEqual(config.threads, 0)
        XCTAssertEqual(config.contextSize, 2048)
        XCTAssertEqual(config.gpuLayers, -1)
        XCTAssertEqual(config.batchSize, 512)
        XCTAssertTrue(config.useMemoryMapping)
        XCTAssertFalse(config.lockMemory)
        XCTAssertFalse(config.verbose)
    }

    func testCPUConfig() {
        let config = EdgeVedaConfig.cpu

        XCTAssertEqual(config.backend, .cpu)
        XCTAssertEqual(config.gpuLayers, 0)
    }

    func testMetalConfig() {
        let config = EdgeVedaConfig.metal

        XCTAssertEqual(config.backend, .metal)
        XCTAssertEqual(config.gpuLayers, -1)
    }

    func testLowMemoryConfig() {
        let config = EdgeVedaConfig.lowMemory

        XCTAssertEqual(config.contextSize, 1024)
        XCTAssertEqual(config.batchSize, 256)
        XCTAssertTrue(config.useMemoryMapping)
    }

    func testHighPerformanceConfig() {
        let config = EdgeVedaConfig.highPerformance

        XCTAssertEqual(config.backend, .metal)
        XCTAssertEqual(config.contextSize, 4096)
        XCTAssertEqual(config.gpuLayers, -1)
        XCTAssertEqual(config.batchSize, 1024)
        XCTAssertTrue(config.lockMemory)
    }

    func testCustomConfig() {
        let config = EdgeVedaConfig(
            backend: .cpu,
            threads: 4,
            contextSize: 1024,
            gpuLayers: 0,
            batchSize: 256,
            useMemoryMapping: false,
            lockMemory: true,
            verbose: true
        )

        XCTAssertEqual(config.backend, .cpu)
        XCTAssertEqual(config.threads, 4)
        XCTAssertEqual(config.contextSize, 1024)
        XCTAssertEqual(config.gpuLayers, 0)
        XCTAssertEqual(config.batchSize, 256)
        XCTAssertFalse(config.useMemoryMapping)
        XCTAssertTrue(config.lockMemory)
        XCTAssertTrue(config.verbose)
    }

    // MARK: - Generation Options Tests

    func testDefaultGenerateOptions() {
        let options = GenerateOptions.default

        XCTAssertEqual(options.maxTokens, 512)
        XCTAssertEqual(options.temperature, 0.7, accuracy: 0.01)
        XCTAssertEqual(options.topP, 0.9, accuracy: 0.01)
        XCTAssertEqual(options.topK, 40)
        XCTAssertEqual(options.repeatPenalty, 1.1, accuracy: 0.01)
        XCTAssertTrue(options.stopSequences.isEmpty)
    }

    func testCreativeGenerateOptions() {
        let options = GenerateOptions.creative

        XCTAssertEqual(options.temperature, 0.9, accuracy: 0.01)
        XCTAssertEqual(options.topP, 0.95, accuracy: 0.01)
        XCTAssertEqual(options.repeatPenalty, 1.2, accuracy: 0.01)
    }

    func testPreciseGenerateOptions() {
        let options = GenerateOptions.precise

        XCTAssertEqual(options.temperature, 0.3, accuracy: 0.01)
        XCTAssertEqual(options.topP, 0.8, accuracy: 0.01)
        XCTAssertEqual(options.topK, 20)
        XCTAssertEqual(options.repeatPenalty, 1.05, accuracy: 0.01)
    }

    func testGreedyGenerateOptions() {
        let options = GenerateOptions.greedy

        XCTAssertEqual(options.temperature, 0.0, accuracy: 0.01)
        XCTAssertEqual(options.topP, 1.0, accuracy: 0.01)
        XCTAssertEqual(options.topK, 1)
        XCTAssertEqual(options.repeatPenalty, 1.0, accuracy: 0.01)
    }

    func testCustomGenerateOptions() {
        let options = GenerateOptions(
            maxTokens: 256,
            temperature: 0.5,
            topP: 0.85,
            topK: 30,
            repeatPenalty: 1.15,
            stopSequences: ["</s>", "\n\n"]
        )

        XCTAssertEqual(options.maxTokens, 256)
        XCTAssertEqual(options.temperature, 0.5, accuracy: 0.01)
        XCTAssertEqual(options.topP, 0.85, accuracy: 0.01)
        XCTAssertEqual(options.topK, 30)
        XCTAssertEqual(options.repeatPenalty, 1.15, accuracy: 0.01)
        XCTAssertEqual(options.stopSequences, ["</s>", "\n\n"])
    }

    // MARK: - Backend Tests

    func testBackendCValues() {
        XCTAssertEqual(Backend.cpu.cValue, 0)
        XCTAssertEqual(Backend.metal.cValue, 1)
        XCTAssertEqual(Backend.auto.cValue, 2)
    }

    func testBackendRawValues() {
        XCTAssertEqual(Backend.cpu.rawValue, "CPU")
        XCTAssertEqual(Backend.metal.rawValue, "Metal")
        XCTAssertEqual(Backend.auto.rawValue, "Auto")
    }

    // MARK: - Error Tests

    func testModelNotFoundError() {
        let error = EdgeVedaError.modelNotFound(path: "/path/to/model.gguf")

        XCTAssertEqual(
            error.errorDescription,
            "Model file not found at path: /path/to/model.gguf"
        )
        XCTAssertEqual(
            error.recoverySuggestion,
            "Verify the model file path is correct and the file exists."
        )
    }

    func testModelNotLoadedError() {
        let error = EdgeVedaError.modelNotLoaded

        XCTAssertEqual(
            error.errorDescription,
            "Model is not loaded. Call init(modelPath:config:) first."
        )
        XCTAssertEqual(
            error.recoverySuggestion,
            "Initialize EdgeVeda with a valid model path before performing operations."
        )
    }

    func testLoadFailedError() {
        let error = EdgeVedaError.loadFailed(reason: "Invalid GGUF format")

        XCTAssertEqual(
            error.errorDescription,
            "Failed to load model: Invalid GGUF format"
        )
        XCTAssertEqual(
            error.recoverySuggestion,
            "Ensure the model file is a valid GGUF format and not corrupted."
        )
    }

    func testGenerationFailedError() {
        let error = EdgeVedaError.generationFailed(reason: "Context overflow")

        XCTAssertEqual(
            error.errorDescription,
            "Text generation failed: Context overflow"
        )
    }

    func testInvalidParameterError() {
        let error = EdgeVedaError.invalidParameter(name: "temperature", value: "-1.0")

        XCTAssertEqual(
            error.errorDescription,
            "Invalid parameter 'temperature': -1.0"
        )
    }

    func testOutOfMemoryError() {
        let error = EdgeVedaError.outOfMemory

        XCTAssertEqual(
            error.errorDescription,
            "Out of memory. Try using a smaller model or reducing context size."
        )
        XCTAssertEqual(
            error.recoverySuggestion,
            "Try using EdgeVedaConfig.lowMemory or a smaller model."
        )
    }

    func testUnsupportedBackendError() {
        let error = EdgeVedaError.unsupportedBackend(.metal)

        XCTAssertEqual(
            error.errorDescription,
            "Backend 'Metal' is not supported on this device."
        )
        XCTAssertEqual(
            error.recoverySuggestion,
            "Metal is only available on Apple Silicon devices. Use .cpu backend instead."
        )
    }

    func testFFIError() {
        let error = EdgeVedaError.ffiError(message: "Null pointer exception")

        XCTAssertEqual(
            error.errorDescription,
            "FFI error: Null pointer exception"
        )
    }

    func testUnknownError() {
        let error = EdgeVedaError.unknown(message: "Something went wrong")

        XCTAssertEqual(
            error.errorDescription,
            "Unknown error: Something went wrong"
        )
    }

    // MARK: - Types Tests

    func testStreamToken() {
        let token = StreamToken(
            text: "Hello",
            position: 0,
            probability: 0.95,
            isFinal: false
        )

        XCTAssertEqual(token.text, "Hello")
        XCTAssertEqual(token.position, 0)
        XCTAssertEqual(token.probability, 0.95, accuracy: 0.01)
        XCTAssertFalse(token.isFinal)
    }

    func testModelInfo() {
        let info = ModelInfo(
            architecture: "llama",
            parameterCount: 7_000_000_000,
            contextSize: 4096,
            vocabularySize: 32000,
            metadata: ["version": "1.0", "quantization": "Q4_0"]
        )

        XCTAssertEqual(info.architecture, "llama")
        XCTAssertEqual(info.parameterCount, 7_000_000_000)
        XCTAssertEqual(info.contextSize, 4096)
        XCTAssertEqual(info.vocabularySize, 32000)
        XCTAssertEqual(info.metadata["version"], "1.0")
        XCTAssertEqual(info.metadata["quantization"], "Q4_0")
    }

    func testPerformanceMetrics() {
        let metrics = PerformanceMetrics(
            tokensPerSecond: 25.5,
            promptProcessingTime: 150.0,
            generationTime: 2000.0,
            totalTime: 2150.0,
            tokenCount: 50,
            peakMemoryUsage: 4_000_000_000
        )

        XCTAssertEqual(metrics.tokensPerSecond, 25.5, accuracy: 0.1)
        XCTAssertEqual(metrics.promptProcessingTime, 150.0)
        XCTAssertEqual(metrics.generationTime, 2000.0)
        XCTAssertEqual(metrics.totalTime, 2150.0)
        XCTAssertEqual(metrics.tokenCount, 50)
        XCTAssertEqual(metrics.peakMemoryUsage, 4_000_000_000)
    }

    func testGenerationResult() {
        let metrics = PerformanceMetrics(
            tokensPerSecond: 25.5,
            promptProcessingTime: 150.0,
            generationTime: 2000.0,
            totalTime: 2150.0,
            tokenCount: 50,
            peakMemoryUsage: 4_000_000_000
        )

        let result = GenerationResult(
            text: "Generated text",
            metrics: metrics,
            stopReason: .maxTokens
        )

        XCTAssertEqual(result.text, "Generated text")
        XCTAssertEqual(result.stopReason, .maxTokens)
    }

    func testStopReason() {
        XCTAssertEqual(StopReason.maxTokens.rawValue, "max_tokens")
        XCTAssertEqual(StopReason.stopSequence.rawValue, "stop_sequence")
        XCTAssertEqual(StopReason.endOfText.rawValue, "end_of_text")
        XCTAssertEqual(StopReason.cancelled.rawValue, "cancelled")
        XCTAssertEqual(StopReason.error.rawValue, "error")
    }

    func testDeviceInfo() {
        let deviceInfo = DeviceInfo.current()

        XCTAssertFalse(deviceInfo.availableBackends.isEmpty)
        XCTAssertTrue(deviceInfo.availableBackends.contains(.cpu))
        XCTAssertTrue(deviceInfo.availableBackends.contains(.auto))
        XCTAssertGreaterThan(deviceInfo.totalMemory, 0)
    }

    // MARK: - EdgeVeda Integration Tests (will fail without actual C library)

    func testEdgeVedaInitWithInvalidPath() async {
        do {
            _ = try await EdgeVeda(
                modelPath: "/nonexistent/model.gguf",
                config: .default
            )
            XCTFail("Should throw modelNotFound error")
        } catch EdgeVedaError.modelNotFound {
            // Expected error
            XCTAssert(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Concurrency Tests

    func testEdgeVedaActorIsolation() async {
        // This test verifies that EdgeVeda is properly isolated as an actor
        // The actual test would require a valid model file

        // Verify EdgeVeda conforms to actor requirements
        XCTAssertTrue(EdgeVeda.self is any Actor.Type)
    }

    // MARK: - Performance Tests

    func testConfigurationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = EdgeVedaConfig.default
                _ = EdgeVedaConfig.cpu
                _ = EdgeVedaConfig.metal
                _ = EdgeVedaConfig.lowMemory
                _ = EdgeVedaConfig.highPerformance
            }
        }
    }

    func testGenerateOptionsPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = GenerateOptions.default
                _ = GenerateOptions.creative
                _ = GenerateOptions.precise
                _ = GenerateOptions.greedy
            }
        }
    }
}
