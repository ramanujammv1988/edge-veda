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
        // Mistral Instruct v0.1 format:
        // <s>[INST] <<SYS>>\n{system}\n<</SYS>>\n\n{user} [/INST] {assistant}</s>[INST] {user2} [/INST]…
        //
        // Rules:
        // • Prompt opens with <s> (BOS token) — one per conversation, not per turn.
        // • System prompt is injected inside the first [INST] block using <<SYS>>/<</SYS>> markers.
        // • Subsequent user turns use [INST]…[/INST] without <s>.
        // • Previous implementation placed system content as bare text before [INST], which
        //   Mistral models do not recognise, and omitted the <s> BOS token entirely.
        var prompt = "<s>"
        var pendingSystem: String? = nil

        for message in messages {
            switch message.role {
            case .system:
                // Defer system content until the next user turn so it lands inside [INST].
                pendingSystem = message.content
            case .user:
                prompt += "[INST]"
                if let sys = pendingSystem {
                    prompt += " <<SYS>>\n\(sys)\n<</SYS>>\n\n"
                    pendingSystem = nil
                } else {
                    prompt += " "
                }
                prompt += "\(message.content) [/INST]"
            case .assistant:
                prompt += " \(message.content)</s>"
            }
        }

        return prompt
    }
}