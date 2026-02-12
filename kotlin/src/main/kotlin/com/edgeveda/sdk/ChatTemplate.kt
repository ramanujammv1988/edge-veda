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
        
        for (message in messages) {
            when (message.role) {
                ChatRole.SYSTEM -> {
                    // Mistral typically includes system messages at the start
                    prompt.append("${message.content}\n\n")
                }
                ChatRole.USER -> {
                    prompt.append("[INST] ${message.content} [/INST]")
                }
                ChatRole.ASSISTANT -> {
                    prompt.append(" ${message.content}</s>")
                }
            }
        }
        
        return prompt.toString()
    }
}