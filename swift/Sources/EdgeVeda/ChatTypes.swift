import Foundation

/// Represents a message in a chat conversation
public struct ChatMessage: Sendable {
    /// The role of the message sender
    public let role: ChatRole
    
    /// The content of the message
    public let content: String
    
    /// When the message was created
    public let timestamp: Date
    
    /// Creates a new chat message
    /// - Parameters:
    ///   - role: The role of the message sender
    ///   - content: The content of the message
    ///   - timestamp: When the message was created (defaults to now)
    public init(role: ChatRole, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// The role of a message in a chat conversation
public enum ChatRole: String, Sendable, CaseIterable {
    /// System messages set the behavior and context
    case system
    
    /// User messages contain user input
    case user
    
    /// Assistant messages contain AI responses
    case assistant
}

/// Pre-configured system prompts for different use cases
public enum SystemPromptPreset: Sendable {
    /// General helpful AI assistant
    case assistant
    
    /// Expert programmer assistant
    case coder
    
    /// Brief, to-the-point assistant
    case concise
    
    /// Creative and expressive assistant
    case creative
    
    /// Custom system prompt
    case custom(String)
    
    /// The text of the system prompt
    public var text: String {
        switch self {
        case .assistant:
            return "You are a helpful AI assistant."
        case .coder:
            return "You are an expert programmer. Provide clear, concise code examples."
        case .concise:
            return "You are a concise assistant. Keep responses brief and to the point."
        case .creative:
            return "You are a creative AI with vivid imagination. Be expressive and original."
        case .custom(let prompt):
            return prompt
        }
    }
}