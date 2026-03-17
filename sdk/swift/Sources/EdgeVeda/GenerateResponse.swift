import Foundation

/// Response from text generation.
public struct GenerateResponse: Sendable {
    /// Generated text.
    public let text: String

    /// Number of tokens in the prompt.
    public let promptTokens: Int

    /// Number of tokens generated.
    public let completionTokens: Int

    /// Total tokens used.
    public var totalTokens: Int { promptTokens + completionTokens }

    /// Generation latency in milliseconds.
    public let latencyMs: Int

    /// Tokens per second throughput.
    public var tokensPerSecond: Double? {
        guard latencyMs > 0 else { return nil }
        return Double(completionTokens) / Double(latencyMs) * 1000
    }
}
