import Foundation

/// Manages a multi-turn chat conversation with context tracking
@available(iOS 15.0, macOS 12.0, *)
public actor ChatSession {
    // MARK: - Properties
    
    /// The EdgeVeda instance used for generation
    private let edgeVeda: EdgeVeda
    
    /// The conversation message history
    private var messages: [ChatMessage] = []
    
    /// Maximum context length in tokens
    private let maxContextLength: Int
    
    /// The system prompt (if any)
    private let systemPrompt: String?
    
    /// The chat template used for formatting
    private let template: ChatTemplate
    
    // MARK: - Initialization
    
    /// Creates a new chat session
    /// - Parameters:
    ///   - edgeVeda: The EdgeVeda instance to use for generation
    ///   - systemPrompt: The system prompt preset to use (defaults to .assistant)
    ///   - maxContextLength: Maximum context length in tokens (defaults to 2048)
    ///   - template: The chat template to use (defaults to .llama3)
    public init(
        edgeVeda: EdgeVeda,
        systemPrompt: SystemPromptPreset = .assistant,
        maxContextLength: Int = 2048,
        template: ChatTemplate = .llama3
    ) {
        self.edgeVeda = edgeVeda
        self.maxContextLength = maxContextLength
        self.template = template
        
        // Add system prompt if provided
        self.systemPrompt = systemPrompt.text
        if let prompt = self.systemPrompt {
            self.messages.append(ChatMessage(role: .system, content: prompt))
        }
    }
    
    // MARK: - Public Methods
    
    /// Sends a message and returns the complete response
    /// - Parameters:
    ///   - message: The user message to send
    ///   - options: Generation options
    /// - Returns: The assistant's response
    public func send(_ message: String, options: GenerateOptions = GenerateOptions()) async throws -> String {
        // Add user message
        messages.append(ChatMessage(role: .user, content: message))
        
        // Format the prompt
        let prompt = formatPrompt()
        
        // Generate response
        let response = try await edgeVeda.generate(prompt, options: options)
        
        // Add assistant response
        messages.append(ChatMessage(role: .assistant, content: response))
        
        return response
    }
    
    /// Sends a message and streams the response token by token
    /// - Parameters:
    ///   - message: The user message to send
    ///   - options: Generation options
    /// - Returns: An async stream of response tokens
    public func sendStream(_ message: String, options: GenerateOptions = GenerateOptions()) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Add user message
                await self.addMessage(ChatMessage(role: .user, content: message))
                
                let prompt = await self.formatPrompt()
                var fullResponse = ""
                
                do {
                    for try await token in await self.edgeVeda.generateStream(prompt, options: options) {
                        fullResponse += token
                        continuation.yield(token)
                    }
                    
                    // Add complete assistant response
                    await self.addMessage(ChatMessage(role: .assistant, content: fullResponse))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Resets the conversation, keeping only the system prompt
    public func reset() async throws {
        messages.removeAll()
        
        // Re-add system prompt if it exists
        if let prompt = systemPrompt {
            messages.append(ChatMessage(role: .system, content: prompt))
        }
        
        // Reset the EdgeVeda context
        try await edgeVeda.resetContext()
    }
    
    /// Returns the number of conversation turns (user messages)
    public var turnCount: Int {
        messages.filter { $0.role == .user }.count
    }
    
    /// Returns the estimated context usage as a percentage (0.0 to 1.0)
    public var contextUsage: Double {
        let totalTokens = estimateTokens()
        return Double(totalTokens) / Double(maxContextLength)
    }
    
    /// Returns all messages in the conversation
    public var allMessages: [ChatMessage] {
        messages
    }
    
    /// Returns the last N messages in the conversation
    /// - Parameter count: Number of messages to return
    /// - Returns: The last N messages
    public func lastMessages(count: Int) -> [ChatMessage] {
        let startIndex = max(0, messages.count - count)
        return Array(messages[startIndex...])
    }
    
    // MARK: - Private Methods
    
    /// Adds a message to the conversation history
    private func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }
    
    /// Formats all messages into a prompt using the chat template
    private func formatPrompt() -> String {
        template.format(messages: messages)
    }
    
    /// Estimates the total token count for all messages
    /// Uses a rough heuristic: ~4 characters per token
    private func estimateTokens() -> Int {
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        return totalChars / 4
    }
}