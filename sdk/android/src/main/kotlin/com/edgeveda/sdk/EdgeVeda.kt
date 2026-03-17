package com.edgeveda.sdk

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.Closeable

/**
 * Edge Veda Android SDK — on-device AI inference.
 *
 * ```kotlin
 * val veda = EdgeVeda.builder(context)
 *     .setModel("path/to/model.gguf")
 *     .setMaxTokens(512)
 *     .build()
 *
 * // Streaming
 * veda.generateStream("What is AI?")
 *     .collect { token -> print(token) }
 *
 * // Single-shot
 * val response = veda.generate("What is AI?")
 * println(response.text)
 *
 * veda.close()
 * ```
 */
class EdgeVeda private constructor(
    private var nativeHandle: Long,
) : Closeable {

    /**
     * Builder for constructing an EdgeVeda instance.
     */
    class Builder(private val context: Context) {
        private var modelPath: String = ""
        private var numThreads: Int = 4
        private var contextSize: Int = 2048
        private var gpuLayers: Int = -1
        private var useGpu: Boolean = true
        private var maxMemoryMb: Int = 1536

        fun setModel(path: String) = apply { modelPath = path }
        fun setNumThreads(threads: Int) = apply { numThreads = threads }
        fun setContextSize(size: Int) = apply { contextSize = size }
        fun setGpuLayers(layers: Int) = apply { gpuLayers = layers }
        fun setUseGpu(use: Boolean) = apply { useGpu = use }
        fun setMaxMemoryMb(mb: Int) = apply { maxMemoryMb = mb }

        /**
         * Build and initialize the EdgeVeda instance.
         * This loads the model and should be called on a background thread.
         */
        suspend fun build(): EdgeVeda = withContext(Dispatchers.IO) {
            require(modelPath.isNotEmpty()) { "Model path must be set" }
            val handle = NativeBridge.evInit(
                modelPath, numThreads, contextSize,
                gpuLayers, useGpu, maxMemoryMb
            )
            if (handle == 0L) {
                throw ModelLoadException("Failed to initialize Edge Veda context")
            }
            EdgeVeda(handle)
        }
    }

    companion object {
        /** Create a builder for EdgeVeda. */
        fun builder(context: Context) = Builder(context)

        /** Get the native library version. */
        fun version(): String = NativeBridge.evVersion()
    }

    private fun requireHandle(): Long {
        check(nativeHandle != 0L) { "EdgeVeda has been closed" }
        return nativeHandle
    }

    /**
     * Generate a complete response for the given prompt.
     */
    suspend fun generate(
        prompt: String,
        options: GenerateOptions = GenerateOptions(),
    ): GenerateResponse = withContext(Dispatchers.IO) {
        val handle = requireHandle()
        val startTime = System.currentTimeMillis()

        val fullPrompt = if (options.systemPrompt != null) {
            "${options.systemPrompt}\n\n$prompt"
        } else {
            prompt
        }

        val text = NativeBridge.evGenerate(
            handle, fullPrompt, options.maxTokens,
            options.temperature, options.topP, options.topK,
            options.repeatPenalty, options.confidenceThreshold
        ) ?: throw InferenceException("Generation returned null")

        val latencyMs = System.currentTimeMillis() - startTime
        GenerateResponse(
            text = text,
            latencyMs = latencyMs,
        )
    }

    /**
     * Stream tokens as a Kotlin Flow.
     */
    fun generateStream(
        prompt: String,
        options: GenerateOptions = GenerateOptions(),
    ): Flow<String> = flow {
        val handle = requireHandle()

        val fullPrompt = if (options.systemPrompt != null) {
            "${options.systemPrompt}\n\n$prompt"
        } else {
            prompt
        }

        val streamHandle = NativeBridge.evGenerateStream(
            handle, fullPrompt, options.maxTokens,
            options.temperature, options.topP, options.topK,
            options.repeatPenalty, options.confidenceThreshold
        )
        if (streamHandle == 0L) {
            throw InferenceException("Failed to start stream")
        }

        try {
            while (true) {
                val token = NativeBridge.evStreamNext(streamHandle) ?: break
                emit(token)
            }
        } finally {
            NativeBridge.evStreamFree(streamHandle)
        }
    }.flowOn(Dispatchers.IO)

    /**
     * Compute text embeddings.
     */
    suspend fun embed(text: String): EmbeddingResult = withContext(Dispatchers.IO) {
        val handle = requireHandle()
        val embeddings = NativeBridge.evEmbed(handle, text)
            ?: throw InferenceException("Embedding failed")
        EmbeddingResult(embedding = embeddings)
    }

    /**
     * Get current memory usage statistics.
     */
    fun getMemoryUsage(): MemoryStats {
        val handle = requireHandle()
        val data = NativeBridge.evGetMemoryUsage(handle)
            ?: throw EdgeVedaException("Failed to get memory stats")
        return MemoryStats(
            currentBytes = data[0],
            peakBytes = data[1],
            limitBytes = data[2],
            modelBytes = data[3],
            contextBytes = data[4],
        )
    }

    /**
     * Release all native resources.
     */
    override fun close() {
        if (nativeHandle != 0L) {
            NativeBridge.evFree(nativeHandle)
            nativeHandle = 0
        }
    }
}
