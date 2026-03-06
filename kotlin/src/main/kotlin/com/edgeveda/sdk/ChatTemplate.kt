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
    MISTRAL,

    /** Generic ### System/User/Assistant format */
    GENERIC,

    /** Qwen3 ChatML format (same tokens as CHATML, kept separate for future tool-calling) */
    QWEN3,

    /** Gemma 3 format — system merged into first user turn; "model" role for assistant */
    GEMMA3;

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
            GENERIC -> formatGeneric(messages)
            QWEN3 -> formatQwen3(messages)
            GEMMA3 -> formatGemma3(messages)
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

    private fun formatGeneric(messages: List<ChatMessage>): String {
        val prompt = StringBuilder()
        for (msg in messages) {
            when (msg.role) {
                ChatRole.SYSTEM    -> prompt.append("### System:\n${msg.content}\n\n")
                ChatRole.USER      -> prompt.append("### User:\n${msg.content}\n")
                ChatRole.ASSISTANT -> prompt.append("### Assistant:\n${msg.content}\n")
            }
        }
        prompt.append("### Assistant:\n")
        return prompt.toString()
    }

    private fun formatQwen3(messages: List<ChatMessage>): String {
        val prompt = StringBuilder()
        for (msg in messages) {
            when (msg.role) {
                ChatRole.SYSTEM    -> prompt.append("<|im_start|>system\n${msg.content}<|im_end|>\n")
                ChatRole.USER      -> prompt.append("<|im_start|>user\n${msg.content}<|im_end|>\n")
                ChatRole.ASSISTANT -> prompt.append("<|im_start|>assistant\n${msg.content}<|im_end|>\n")
            }
        }
        prompt.append("<|im_start|>assistant\n")
        return prompt.toString()
    }

    private fun formatGemma3(messages: List<ChatMessage>): String {
        val prompt = StringBuilder()
        var pendingSystem: String? = null

        for (msg in messages) {
            when (msg.role) {
                ChatRole.SYSTEM -> pendingSystem = msg.content
                ChatRole.USER -> {
                    val content = if (pendingSystem != null) {
                        "$pendingSystem\n\n${msg.content}".also { pendingSystem = null }
                    } else {
                        msg.content
                    }
                    prompt.append("<start_of_turn>user\n${content}<end_of_turn>\n")
                }
                ChatRole.ASSISTANT ->
                    prompt.append("<start_of_turn>model\n${msg.content}<end_of_turn>\n")
            }
        }

        prompt.append("<start_of_turn>model\n")
        return prompt.toString()
    }
}