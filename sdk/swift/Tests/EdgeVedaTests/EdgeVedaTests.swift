import XCTest
@testable import EdgeVeda

final class EdgeVedaTests: XCTestCase {
    func testConfigDefaults() {
        let config = Config(modelPath: "/tmp/test.gguf")
        XCTAssertEqual(config.numThreads, 4)
        XCTAssertEqual(config.contextSize, 2048)
        XCTAssertEqual(config.gpuLayers, -1)
        XCTAssertTrue(config.useGpu)
        XCTAssertEqual(config.maxMemoryMB, 1536)
    }

    func testGenerateOptionsDefaults() {
        let opts = GenerateOptions.default
        XCTAssertNil(opts.systemPrompt)
        XCTAssertEqual(opts.maxTokens, 512)
        XCTAssertEqual(opts.temperature, 0.7, accuracy: 0.01)
        XCTAssertEqual(opts.topP, 0.9, accuracy: 0.01)
        XCTAssertEqual(opts.topK, 40)
    }

    func testGenerateResponseMetrics() {
        let response = GenerateResponse(
            text: "Hello",
            promptTokens: 10,
            completionTokens: 50,
            latencyMs: 1000
        )
        XCTAssertEqual(response.totalTokens, 60)
        XCTAssertEqual(response.tokensPerSecond!, 50.0, accuracy: 0.1)
    }

    func testMemoryStats() {
        let stats = MemoryStats(
            currentBytes: 800_000_000,
            peakBytes: 900_000_000,
            limitBytes: 1_000_000_000,
            modelBytes: 600_000_000,
            contextBytes: 200_000_000
        )
        XCTAssertEqual(stats.usagePercent, 0.8, accuracy: 0.01)
        XCTAssertTrue(stats.isHighPressure)
    }
}
