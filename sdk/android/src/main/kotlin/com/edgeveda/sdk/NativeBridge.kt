package com.edgeveda.sdk

/**
 * Internal JNI bridge to the Edge Veda C++ core.
 * All functions map to ev_* C API calls.
 */
internal object NativeBridge {
    init {
        System.loadLibrary("edge_veda_jni")
    }

    // Context
    @JvmStatic external fun evInit(
        modelPath: String, numThreads: Int, contextSize: Int,
        gpuLayers: Int, useGpu: Boolean, maxMemoryMb: Int
    ): Long

    @JvmStatic external fun evFree(handle: Long)

    // Generation
    @JvmStatic external fun evGenerate(
        handle: Long, prompt: String, maxTokens: Int,
        temperature: Float, topP: Float, topK: Int,
        repeatPenalty: Float, confidenceThreshold: Float
    ): String?

    // Streaming
    @JvmStatic external fun evGenerateStream(
        handle: Long, prompt: String, maxTokens: Int,
        temperature: Float, topP: Float, topK: Int,
        repeatPenalty: Float, confidenceThreshold: Float
    ): Long

    @JvmStatic external fun evStreamNext(handle: Long): String?
    @JvmStatic external fun evStreamCancel(handle: Long)
    @JvmStatic external fun evStreamFree(handle: Long)

    // Memory
    @JvmStatic external fun evGetMemoryUsage(handle: Long): LongArray?

    // Embeddings
    @JvmStatic external fun evEmbed(handle: Long, text: String): FloatArray?

    // Version
    @JvmStatic external fun evVersion(): String
}
