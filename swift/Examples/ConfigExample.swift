import Foundation
import EdgeVeda

/// Example demonstrating different configurations and their use cases
@available(iOS 15.0, macOS 12.0, *)
@main
struct ConfigExample {
    static func main() async {
        let modelPath = "/path/to/your/model.gguf"

        print("EdgeVeda Swift SDK - Configuration Example")
        print("===========================================\n")

        // Test different configurations
        await testConfiguration(
            name: "Default (Auto)",
            config: .default,
            modelPath: modelPath
        )

        await testConfiguration(
            name: "CPU Only",
            config: .cpu,
            modelPath: modelPath
        )

        await testConfiguration(
            name: "Metal GPU",
            config: .metal,
            modelPath: modelPath
        )

        await testConfiguration(
            name: "Low Memory",
            config: .lowMemory,
            modelPath: modelPath
        )

        // Custom configuration
        let customConfig = EdgeVedaConfig(
            backend: .auto,
            threads: 4,
            contextSize: 2048,
            gpuLayers: 20,
            batchSize: 256,
            useMemoryMapping: true,
            lockMemory: false,
            verbose: false
        )

        await testConfiguration(
            name: "Custom",
            config: customConfig,
            modelPath: modelPath
        )
    }

    static func testConfiguration(
        name: String,
        config: EdgeVedaConfig,
        modelPath: String
    ) async {
        print("Testing: \(name)")
        print(String(repeating: "-", count: 40))
        print("Config:")
        print("  - Backend: \(config.backend.rawValue)")
        print("  - Threads: \(config.threads == 0 ? "Auto" : "\(config.threads)")")
        print("  - Context: \(config.contextSize)")
        print("  - GPU Layers: \(config.gpuLayers)")
        print("  - Batch Size: \(config.batchSize)")
        print("  - Memory Mapping: \(config.useMemoryMapping)")

        do {
            let startTime = Date()
            let edgeVeda = try await EdgeVeda(
                modelPath: modelPath,
                config: config
            )
            let loadTime = Date().timeIntervalSince(startTime)

            print("  - Load Time: \(String(format: "%.2f", loadTime))s")

            let memoryMB = await edgeVeda.memoryUsage / 1_024_000
            print("  - Memory: \(memoryMB) MB")

            // Quick inference test
            let prompt = "Hello"
            let inferenceStart = Date()
            _ = try await edgeVeda.generate(
                prompt,
                options: GenerateOptions(maxTokens: 10, temperature: 0.0)
            )
            let inferenceTime = Date().timeIntervalSince(inferenceStart)
            print("  - Inference Time: \(String(format: "%.2f", inferenceTime))s")

            await edgeVeda.unloadModel()
            print("  - Status: ✓ Success\n")

        } catch EdgeVedaError.unsupportedBackend(let backend) {
            print("  - Status: ✗ \(backend) not supported on this device\n")
        } catch {
            print("  - Status: ✗ \(error.localizedDescription)\n")
        }
    }
}
