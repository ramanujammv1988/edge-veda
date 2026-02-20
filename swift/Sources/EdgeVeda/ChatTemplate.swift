import Foundation

/// Chat template formats for different model families
public enum ChatTemplate: Sendable {
    /// Llama 3 chat format
    case llama3
    
    /// ChatML format (used by OpenAI, GPT-4, etc.)
    case chatml
    
    /// Mistral/Mixtral chat format
    case mistral

    /// Generic markdown-style format (### System: / ### User: / ### Assistant:)
    case generic

    /// Qwen3 format — ChatML base with XML tool wrapping
    case qwen3

    /// Gemma3 format — <start_of_turn>user / <start_of_turn>model; system merged into first user turn
    case gemma3

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
        case .generic:
            return formatGeneric(messages: messages)
        case .qwen3:
            return formatQwen3(messages: messages)
        case .gemma3:
            return formatGemma3(messages: messages)
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

    private func formatGeneric(messages: [ChatMessage]) -> String {
        var prompt = ""
        for message in messages {
            switch message.role {
            case .system:
                prompt += "### System:\n\(message.content)\n\n"
            case .user:
                prompt += "### User:\n\(message.content)\n"
            case .assistant:
                prompt += "### Assistant:\n\(message.content)\n"
            }
        }
        prompt += "### Assistant:\n"
        return prompt
    }

    private func formatQwen3(messages: [ChatMessage]) -> String {
        // Qwen3 uses ChatML tokens as its base format.
        // Role names are lowercase: system / user / assistant.
        var prompt = ""
        for message in messages {
            switch message.role {
            case .system:
                prompt += "<|im_start|>system\n\(message.content)<|im_end|>\n"
            case .user:
                prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
            case .assistant:
                prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
            }
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    private func formatGemma3(messages: [ChatMessage]) -> String {
        // Gemma3 format rules:
        // • No standalone system turn — system content is prepended to the first user turn.
        // • User turns use <start_of_turn>user … <end_of_turn>.
        // • Assistant turns use <start_of_turn>model … <end_of_turn>.
        var prompt = ""
        var pendingSystem: String? = nil

        for message in messages {
            switch message.role {
            case .system:
                pendingSystem = message.content
            case .user:
                var content = message.content
                if let sys = pendingSystem {
                    content = "\(sys)\n\n\(content)"
                    pendingSystem = nil
                }
                prompt += "<start_of_turn>user\n\(content)<end_of_turn>\n"
            case .assistant:
                prompt += "<start_of_turn>model\n\(message.content)<end_of_turn>\n"
            }
        }

        prompt += "<start_of_turn>model\n"
        return prompt
    }
}