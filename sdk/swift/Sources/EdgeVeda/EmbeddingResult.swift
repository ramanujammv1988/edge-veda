import Foundation

/// Result of a text embedding operation.
public struct EmbeddingResult: Sendable {
    /// The embedding vector.
    public let embedding: [Float]

    /// Number of dimensions.
    public var dimensions: Int { embedding.count }

    /// Number of tokens in the input text.
    public let tokenCount: Int
}
