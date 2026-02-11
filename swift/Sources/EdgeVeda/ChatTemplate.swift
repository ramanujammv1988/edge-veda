import Foundation

/// Chat template formats for different model families
public enum ChatTemplate: Sendable {
    /// Llama 3 chat format
    case llama3
    
    /// ChatML format (used by OpenAI, GPT-4, etc.)
    case chatml
    
    /// Mistral/Mixtral chat format
    case mistral
    
    /// Formats a list of messages according to the template
    /// - Parameter messages: The messages to format
    /// - Returns: The formatted prompt string
    public func format(messages: [ChatMessage]) -> String {
        switch self {
        case .llama3:
            return formatLlama3(messages: messages)
        case .chatml:
            return formatChatML(messages: messages)
        case .mistral:
            return formatMistral(messages: messages)
        }
    }
    
    // MARK: - Private Formatters
    
    private func formatLlama3(messages: [ChatMessage]) -> String {
        var prompt = ""
        
        for message in messages {
            prompt += "<|start_header_id|>\(message.role.rawValue)<|end_header_id|>\n\n"
            prompt += "\(message.content)<|eot_id|>"
        }
        
        // Add assistant prompt to continue generation
        prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        
        return prompt
    }
    
    private func formatChatML(messages: [ChatMessage]) -> String {
        var prompt = ""
        
        for message in messages {
            prompt += "<|im_start|>\(message.role.rawValue)\n"
            prompt += "\(message.content)<|im_end|>\n"
        }
        
        // Add assistant prompt to continue generation
        prompt += "<|im_start|>assistant\n"
        
        return prompt
    }
    
    private func formatMistral(messages: [ChatMessage]) -> String {
        var prompt = ""
        
        for message in messages {
            switch message.role {
            case .system:
                // Mistral typically includes system messages at the start
                prompt += "\(message.content)\n\n"
            case .user:
                prompt += "[INST] \(message.content) [/INST]"
            case .assistant:
                prompt += " \(message.content)</s>"
            }
        }
        
        return prompt
    }
}