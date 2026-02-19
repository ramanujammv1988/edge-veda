package com.edgeveda.sdk

/**
 * Chat template formats for different model families
 */
enum class ChatTemplate {
    /** Llama 3 chat format */
    LLAMA3,
    
    /** ChatML format (used by OpenAI, GPT-4, etc.) */
    CHATML,
    
    /** Mistral/Mixtral chat format */
    MISTRAL;
    
    /**
     * Formats a list of messages according to the template
     * @param messages The messages to format
     * @return The formatted prompt string
     */
    fun format(messages: List<ChatMessage>): String {
        return when (this) {
            LLAMA3 -> formatLlama3(messages)
            CHATML -> formatChatML(messages)
            MISTRAL -> formatMistral(messages)
        }
    }
    
    private fun formatLlama3(messages: List<ChatMessage>): String {
        val prompt = StringBuilder()

        // Required BOS token for Llama 3 chat format
        prompt.append("<|begin_of_text|>")

        for (message in messages) {
            prompt.append("<|start_header_id|>${message.role.value}<|end_header_id|>\n\n")
            prompt.append("${message.content}<|eot_id|>")
        }

        // Add assistant prompt to continue generation
        prompt.append("<|start_header_id|>assistant<|end_header_id|>\n\n")

        return prompt.toString()
    }
    
    private fun formatChatML(messages: List<ChatMessage>): String {
        val prompt = StringBuilder()
        
        for (message in messages) {
            prompt.append("<|im_start|>${message.role.value}\n")
            prompt.append("${message.content}<|im_end|>\n")
        }
        
        // Add assistant prompt to continue generation
        prompt.append("<|im_start|>assistant\n")
        
        return prompt.toString()
    }
    
    private fun formatMistral(messages: List<ChatMessage>): String {
        val prompt = StringBuilder()

        // Mistral requires the system prompt to be embedded inside the first
        // [INST] block using <<SYS>> markers, not placed before it as bare text.
        val systemText = messages.firstOrNull { it.role == ChatRole.SYSTEM }?.content
        val conversationMessages = messages.filter { it.role != ChatRole.SYSTEM }

        var isFirstUserMessage = true
        for (message in conversationMessages) {
            when (message.role) {
                ChatRole.USER -> {
                    val content = if (isFirstUserMessage && systemText != null) {
                        "<<SYS>>\n$systemText\n<</SYS>>\n\n${message.content}"
                    } else {
                        message.content
                    }
                    prompt.append("<s>[INST] $content [/INST]")
                    isFirstUserMessage = false
                }
                ChatRole.ASSISTANT -> {
                    prompt.append(" ${message.content}</s>")
                }
                ChatRole.SYSTEM -> { /* handled above */ }
            }
        }

        return prompt.toString()
    }
}