package com.edgeveda.sdk

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Manages a multi-turn chat conversation with context tracking
 */
class ChatSession(
    private val edgeVeda: EdgeVeda,
    systemPrompt: SystemPromptPreset = SystemPromptPreset.Assistant,
    private val maxContextLength: Int = 2048,
    private val template: ChatTemplate = ChatTemplate.LLAMA3
) {
    private val messages = mutableListOf<ChatMessage>()
    private val systemPromptText: String? = systemPrompt.text
    
    init {
        // Add system prompt if provided
        systemPromptText?.let {
            messages.add(ChatMessage(ChatRole.SYSTEM, it))
        }
    }
    
    /**
     * Sends a message and returns the complete response
     * @param message The user message to send
     * @param options Generation options
     * @return The assistant's response
     */
    suspend fun send(message: String, options: GenerateOptions = GenerateOptions()): String {
        // Add user message
        messages.add(ChatMessage(ChatRole.USER, message))
        
        // Format the prompt
        val prompt = formatPrompt()
        
        // Generate response
        val response = edgeVeda.generate(prompt, options)
        
        // Add assistant response
        messages.add(ChatMessage(ChatRole.ASSISTANT, response))
        
        return response
    }
    
    /**
     * Sends a message and streams the response token by token
     * @param message The user message to send
     * @param options Generation options
     * @return A flow of response tokens
     */
    fun sendStream(message: String, options: GenerateOptions = GenerateOptions()): Flow<String> = flow {
        // Add user message
        messages.add(ChatMessage(ChatRole.USER, message))
        
        // Format the prompt
        val prompt = formatPrompt()
        val fullResponse = StringBuilder()
        
        // Stream tokens
        edgeVeda.generateStream(prompt, options).collect { token ->
            fullResponse.append(token)
            emit(token)
        }
        
        // Add complete assistant response
        messages.add(ChatMessage(ChatRole.ASSISTANT, fullResponse.toString()))
    }
    
    /**
     * Resets the conversation, keeping only the system prompt
     */
    suspend fun reset() {
        messages.clear()
        
        // Re-add system prompt if it exists
        systemPromptText?.let {
            messages.add(ChatMessage(ChatRole.SYSTEM, it))
        }
        
        // Reset the EdgeVeda context
        edgeVeda.resetContext()
    }
    
    /**
     * Returns the number of conversation turns (user messages)
     */
    val turnCount: Int
        get() = messages.count { it.role == ChatRole.USER }
    
    /**
     * Returns the estimated context usage as a percentage (0.0 to 1.0)
     */
    val contextUsage: Double
        get() {
            val totalTokens = estimateTokens()
            return totalTokens.toDouble() / maxContextLength.toDouble()
        }
    
    /**
     * Returns all messages in the conversation
     */
    val allMessages: List<ChatMessage>
        get() = messages.toList()
    
    /**
     * Returns the last N messages in the conversation
     * @param count Number of messages to return
     * @return The last N messages
     */
    fun lastMessages(count: Int): List<ChatMessage> {
        val startIndex = maxOf(0, messages.size - count)
        return messages.subList(startIndex, messages.size)
    }
    
    /**
     * Formats all messages into a prompt using the chat template
     */
    private fun formatPrompt(): String {
        return template.format(messages)
    }
    
    /**
     * Estimates the total token count for all messages
     * Uses a rough heuristic: ~4 characters per token
     */
    private fun estimateTokens(): Int {
        val totalChars = messages.sumOf { it.content.length }
        return totalChars / 4
    }
}