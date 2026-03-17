package com.edgeveda.sdk

/**
 * Response from text generation.
 */
data class GenerateResponse(
    val text: String,
    val promptTokens: Int = 0,
    val completionTokens: Int = 0,
    val latencyMs: Long = 0,
) {
    val totalTokens: Int get() = promptTokens + completionTokens
    val tokensPerSecond: Double? get() =
        if (latencyMs > 0) (completionTokens.toDouble() / latencyMs) * 1000 else null
}
