package com.edgeveda.edge_veda

/**
 * Native interface for Edge Veda SDK.
 * This class handles JNI calls to the C++ core engine via bridge_jni.cpp.
 */
class NativeEdgeVeda {

    companion object {
        init {
            try {
                System.loadLibrary("edge_veda")
            } catch (e: UnsatisfiedLinkError) {
                System.err.println("Failed to load edge_veda library: ${e.message}")
            }
        }
    }

    /**
     * Get the version string of the underlying Edge Veda C++ Core.
     */
    external fun getVersionNative(): String

    /**
     * Initialize the engine with configuration.
     * @return Context handle (pointer address) or 0 on failure.
     */
    external fun initContextNative(
        modelPath: String,
        numThreads: Int,
        contextSize: Int,
        batchSize: Int
    ): Long

    /**
     * Free the engine context.
     */
    external fun freeContextNative(contextHandle: Long)

    /**
     * Generate text from a prompt.
     * @return Generated text string.
     */
    external fun generateNative(
        contextHandle: Long,
        promptText: String,
        maxTokens: Int
    ): String

    // ============================================================================
    // Whisper (Speech-to-Text)
    // ============================================================================

    /**
     * Get whisper engine version string.
     */
    external fun whisperVersionNative(): String

    /**
     * Initialize whisper context with model.
     * @param modelPath Path to Whisper GGUF model file
     * @param numThreads CPU threads (0 = auto)
     * @param useGpu Whether to use GPU acceleration
     * @return Context handle or 0 on failure
     */
    external fun whisperInitNative(
        modelPath: String,
        numThreads: Int,
        useGpu: Boolean
    ): Long

    /**
     * Transcribe PCM audio to text.
     * @param contextHandle Whisper context from whisperInitNative
     * @param audioData 16kHz mono float32 PCM samples
     * @param numSamples Number of samples in audioData
     * @param language Language code ("en", "auto", etc.)
     * @return Transcribed text or empty string on failure
     */
    external fun whisperTranscribeNative(
        contextHandle: Long,
        audioData: FloatArray,
        numSamples: Int,
        language: String
    ): String

    /**
     * Free whisper context and release resources.
     */
    external fun whisperFreeNative(contextHandle: Long)

    /**
     * Check if whisper context is valid and model is loaded.
     */
    external fun whisperIsValidNative(contextHandle: Long): Boolean
}
