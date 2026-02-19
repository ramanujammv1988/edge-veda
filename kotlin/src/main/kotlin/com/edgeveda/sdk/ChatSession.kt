package com.edgeveda.sdk

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Manages a multi-turn chat conversation with context tracking
 */
class ChatSession(
    private val edgeVeda: EdgeVeda,
    systemPrompt: SystemPromptPreset = SystemPromptPreset.Assistant,
    private val maxContextLength: Int = 2048,
    private val template: ChatTemplate = ChatTemplate.LLAMA3
) {
    private val messages = CopyOnWriteArrayList<ChatMessage>()
    private val systemPromptText: String = systemPrompt.text
    
    init {
        if (systemPromptText.isNotEmpty()) {
            messages.add(ChatMessage(ChatRole.SYSTEM, systemPromptText))
        }
    }
    
    /**
     * Sends a message and returns the complete response
     * @param message The user message to send
     * @param options Generation options
     * @return The assistant's response
     */
    suspend fun send(message: String, options: GenerateOptions = GenerateOptions()): String {
        val userMsg = ChatMessage(ChatRole.USER, message)

        // Build the prompt from a snapshot that includes the new user message,
        // without committing it to history yet (guards against history corruption
        // if generation fails).
        val prompt = template.format(messages.toList() + userMsg)

        // Generate response — may throw; history is unchanged if it does
        val response = edgeVeda.generate(prompt, options)

        // Commit both messages only on success
        messages.add(userMsg)
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
        val userMsg = ChatMessage(ChatRole.USER, message)

        // Build prompt from snapshot + new message without touching history yet
        val prompt = template.format(messages.toList() + userMsg)
        val fullResponse = StringBuilder()

        // Stream tokens — history is unchanged if collection fails or is cancelled
        edgeVeda.generateStream(prompt, options).collect { token ->
            fullResponse.append(token)
            emit(token)
        }

        // Commit both messages only after the stream completes successfully
        messages.add(userMsg)
        messages.add(ChatMessage(ChatRole.ASSISTANT, fullResponse.toString()))
    }
    
    /**
     * Resets the conversation, keeping only the system prompt
     */
    suspend fun reset() {
        messages.clear()

        if (systemPromptText.isNotEmpty()) {
            messages.add(ChatMessage(ChatRole.SYSTEM, systemPromptText))
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
     * Returns the estimated context usage as a percentage (0.0 to 1.0).
     * Uses a rough heuristic of ~4 characters per token; capped at 1.0.
     */
    val contextUsage: Double
        get() = (estimateTokens().toDouble() / maxContextLength.toDouble()).coerceIn(0.0, 1.0)
    
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
        val snapshot = messages.toList()
        val startIndex = maxOf(0, snapshot.size - count)
        return snapshot.subList(startIndex, snapshot.size)
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