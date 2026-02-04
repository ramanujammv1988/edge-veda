import Foundation
import EdgeVeda

/// Simple example demonstrating basic EdgeVeda usage
@available(iOS 15.0, macOS 12.0, *)
@main
struct SimpleExample {
    static func main() async {
        // Example model path - update with actual path
        let modelPath = "/path/to/your/model.gguf"

        print("EdgeVeda Swift SDK - Simple Example")
        print("=====================================\n")

        do {
            // 1. Initialize EdgeVeda with auto-detected configuration
            print("Loading model...")
            let edgeVeda = try await EdgeVeda(
                modelPath: modelPath,
                config: .default
            )
            print("Model loaded successfully!\n")

            // 2. Check memory usage
            let memoryMB = await edgeVeda.memoryUsage / 1_024_000
            print("Memory usage: \(memoryMB) MB\n")

            // 3. Simple generation
            print("Generating response...")
            let prompt = "What is the capital of France?"
            let response = try await edgeVeda.generate(prompt)
            print("Prompt: \(prompt)")
            print("Response: \(response)\n")

            // 4. Generation with custom options
            print("Generating with custom options...")
            let creativePrompt = "Write a short poem about coding"
            let creativeResponse = try await edgeVeda.generate(
                creativePrompt,
                options: .creative
            )
            print("Prompt: \(creativePrompt)")
            print("Response: \(creativeResponse)\n")

            // 5. Streaming generation
            print("Streaming response:")
            print("Prompt: Tell me a joke\n")
            print("Response: ", terminator: "")

            for try await token in edgeVeda.generateStream("Tell me a joke") {
                print(token, terminator: "")
                fflush(stdout)
            }
            print("\n")

            // 6. Cleanup
            print("Unloading model...")
            await edgeVeda.unloadModel()
            print("Done!")

        } catch EdgeVedaError.modelNotFound(let path) {
            print("Error: Model file not found at '\(path)'")
            print("Please update the modelPath variable with your GGUF model path")
        } catch EdgeVedaError.outOfMemory {
            print("Error: Out of memory")
            print("Try using a smaller model or EdgeVedaConfig.lowMemory")
        } catch EdgeVedaError.unsupportedBackend(let backend) {
            print("Error: Backend '\(backend)' not supported on this device")
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}
