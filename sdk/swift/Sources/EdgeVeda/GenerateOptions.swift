import Foundation

/// Options for text generation.
public struct GenerateOptions: Sendable {
    public var systemPrompt: String?
    public var maxTokens: Int = 512
    public var temperature: Float = 0.7
    public var topP: Float = 0.9
    public var topK: Int = 40
    public var repeatPenalty: Float = 1.1
    public var confidenceThreshold: Float = 0.0

    public static let `default` = GenerateOptions()

    public init(
        systemPrompt: String? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int = 40,
        repeatPenalty: Float = 1.1,
        confidenceThreshold: Float = 0.0
    ) {
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.confidenceThreshold = confidenceThreshold
    }
}
