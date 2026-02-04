import Foundation
import EdgeVeda

/// Advanced example demonstrating streaming with performance monitoring
@available(iOS 15.0, macOS 12.0, *)
@main
struct StreamingExample {
    static func main() async {
        let modelPath = "/path/to/your/model.gguf"

        print("EdgeVeda Swift SDK - Streaming Example")
        print("=======================================\n")

        do {
            // Initialize with high-performance configuration
            print("Loading model with high-performance config...")
            let edgeVeda = try await EdgeVeda(
                modelPath: modelPath,
                config: .highPerformance
            )
            print("Model loaded!\n")

            // Get device info
            let deviceInfo = DeviceInfo.current()
            print("Device Info:")
            print("  - Recommended backend: \(deviceInfo.recommendedBackend)")
            print("  - Available backends: \(deviceInfo.availableBackends.map { $0.rawValue }.joined(separator: ", "))")
            print("  - Total memory: \(deviceInfo.totalMemory / 1_024_000_000) GB\n")

            // Example prompts
            let prompts = [
                "Explain quantum computing in simple terms:",
                "Write a haiku about programming:",
                "List 5 tips for learning Swift:"
            ]

            // Process each prompt with streaming
            for (index, prompt) in prompts.enumerated() {
                print("[\(index + 1)/\(prompts.count)] \(prompt)")
                print(String(repeating: "-", count: 50))

                var tokenCount = 0
                let startTime = Date()

                // Stream tokens
                for try await token in edgeVeda.generateStream(prompt, options: .default) {
                    print(token, terminator: "")
                    fflush(stdout)
                    tokenCount += 1
                }

                let duration = Date().timeIntervalSince(startTime)
                let tokensPerSecond = Double(tokenCount) / duration

                print("\n")
                print("Stats: \(tokenCount) tokens in \(String(format: "%.2f", duration))s (\(String(format: "%.1f", tokensPerSecond)) tok/s)")
                print("\n")

                // Reset context between prompts
                try await edgeVeda.resetContext()
            }

            // Memory usage after processing
            let finalMemory = await edgeVeda.memoryUsage
            print("Final memory usage: \(finalMemory / 1_024_000) MB")

            // Cleanup
            await edgeVeda.unloadModel()
            print("\nDone!")

        } catch {
            print("Error: \(error.localizedDescription)")
            if let suggestion = (error as? EdgeVedaError)?.recoverySuggestion {
                print("Suggestion: \(suggestion)")
            }
        }
    }
}
