package com.edgeveda.sdk

/**
 * Result of a text embedding operation.
 */
data class EmbeddingResult(
    val embedding: FloatArray,
) {
    val dimensions: Int get() = embedding.size

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EmbeddingResult) return false
        return embedding.contentEquals(other.embedding)
    }

    override fun hashCode(): Int = embedding.contentHashCode()
}
