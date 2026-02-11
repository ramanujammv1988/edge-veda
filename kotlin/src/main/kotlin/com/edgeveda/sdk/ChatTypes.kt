package com.edgeveda.sdk

import java.util.Date

/**
 * Represents a message in a chat conversation
 */
data class ChatMessage(
    /** The role of the message sender */
    val role: ChatRole,
    
    /** The content of the message */
    val content: String,
    
    /** When the message was created */
    val timestamp: Date = Date()
)

/**
 * The role of a message in a chat conversation
 */
enum class ChatRole {
    /** System messages set the behavior and context */
    SYSTEM,
    
    /** User messages contain user input */
    USER,
    
    /** Assistant messages contain AI responses */
    ASSISTANT;
    
    /** Lowercase string representation for template formatting */
    val value: String
        get() = name.lowercase()
}

/**
 * Pre-configured system prompts for different use cases
 */
sealed class SystemPromptPreset {
    /** General helpful AI assistant */
    object Assistant : SystemPromptPreset()
    
    /** Expert programmer assistant */
    object Coder : SystemPromptPreset()
    
    /** Brief, to-the-point assistant */
    object Concise : SystemPromptPreset()
    
    /** Creative and expressive assistant */
    object Creative : SystemPromptPreset()
    
    /** Custom system prompt */
    data class Custom(val prompt: String) : SystemPromptPreset()
    
    /** The text of the system prompt */
    val text: String
        get() = when (this) {
            is Assistant -> "You are a helpful AI assistant."
            is Coder -> "You are an expert programmer. Provide clear, concise code examples."
            is Concise -> "You are a concise assistant. Keep responses brief and to the point."
            is Creative -> "You are a creative AI with vivid imagination. Be expressive and original."
            is Custom -> prompt
        }
}