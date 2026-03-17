package com.edgeveda.sdk

/**
 * Options for text generation.
 */
data class GenerateOptions(
    val systemPrompt: String? = null,
    val maxTokens: Int = 512,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,
    val confidenceThreshold: Float = 0.0f,
)
