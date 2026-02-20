package com.edgeveda.sdk

import com.edgeveda.sdk.internal.NativeBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * WhisperSession - Persistent speech-to-text (STT) inference manager
 *
 * Maintains a persistent native Whisper context that is loaded once and reused
 * for all audio transcriptions. Supports automatic language detection, translation,
 * and timestamp-accurate segment extraction.
 *
 * Pattern mirrors VisionWorker, adapted for audio transcription with Whisper models.
 *
 * Usage:
 * ```kotlin
 * val session = WhisperSession()
 * session.initialize(WhisperConfig(modelPath = "/path/to/ggml-model.bin"))
 * 
 * // Transcribe audio (PCM 16kHz mono float32, range [-1.0, 1.0])
 * val result = session.transcribe(pcmSamples)
 * 
 * result.segments.forEach { segment ->
 *     println("[${segment.startMs}ms - ${segment.endMs}ms] ${segment.text}")
 * }
 * 
 * // Translate to English
 * val translated = session.transcribe(
 *     pcmSamples,
 *     WhisperTranscribeParams(language = "auto", translate = true)
 * )
 * 
 * // Cleanup
 * session.cleanup()
 * ```
 */
class WhisperSession {
    private val _isInitialized = AtomicBoolean(false)
    @Volatile private var backend = ""

    /**
     * Whether the whisper context is initialized and ready
     */
    val isInitialized: Boolean
        get() = _isInitialized.get()

    /**
     * Backend name (e.g., "Metal", "CPU")
     */
    val backendName: String
        get() = backend

    /**
     * Initialize the whisper context with STT model
     *
     * Loads the Whisper model once. Subsequent transcription requests reuse
     * this context without reloading.
     *
     * @param config Whisper configuration
     * @return Backend name (e.g., "Metal", "CPU")
     * @throws EdgeVedaException if initialization fails
     */
    suspend fun initialize(config: WhisperConfig): String = withContext(Dispatchers.Default) {
        if (!_isInitialized.compareAndSet(false, true)) {
            throw EdgeVedaException.InvalidConfiguration(
                "WhisperSession already initialized"
            )
        }

        try {
            val configJson = JSONObject().apply {
                put("modelPath", config.modelPath)
                put("numThreads", config.numThreads)
                put("useGpu", config.useGpu)
            }.toString()

            backend = NativeBridge.initWhisper(configJson)
            backend
        } catch (e: EdgeVedaException) {
            _isInitialized.set(false) // rollback on failure
            throw e
        } catch (e: Exception) {
            _isInitialized.set(false) // rollback on failure
            throw EdgeVedaException.ModelLoadError(
                "Failed to initialize whisper context: ${e.message}",
                e
            )
        }
    }

    /**
     * Transcribe PCM audio samples to text with timing segments
     *
     * Audio must be PCM 16kHz mono float32 with samples in range [-1.0, 1.0].
     * Use WhisperTranscribeParams to control language detection, translation,
     * and threading.
     *
     * @param pcmSamples PCM audio data (16kHz, mono, float32, range [-1.0, 1.0])
     * @param params Optional transcription parameters
     * @return Transcription result with text segments and timestamps
     * @throws EdgeVedaException if transcription fails
     */
    suspend fun transcribe(
        pcmSamples: FloatArray,
        params: WhisperTranscribeParams = WhisperTranscribeParams()
    ): WhisperResult = withContext(Dispatchers.Default) {
        if (!_isInitialized.get()) {
            throw EdgeVedaException.InvalidConfiguration(
                "WhisperSession not initialized. Call initialize() first."
            )
        }

        try {
            val paramsJson = JSONObject().apply {
                put("language", params.language)
                put("translate", params.translate)
                put("nThreads", params.nThreads)
            }.toString()

            val resultJson = NativeBridge.transcribeAudio(pcmSamples, paramsJson)
            val parsed = JSONObject(resultJson)

            // Parse segments array
            val segmentsArray = parsed.getJSONArray("segments")
            val segments = mutableListOf<WhisperSegment>()

            for (i in 0 until segmentsArray.length()) {
                val segmentObj = segmentsArray.getJSONObject(i)
                segments.add(
                    WhisperSegment(
                        text = segmentObj.getString("text"),
                        startMs = segmentObj.getLong("start_ms"),
                        endMs = segmentObj.getLong("end_ms")
                    )
                )
            }

            WhisperResult(
                segments = segments,
                fullText = segments.joinToString(" ") { it.text.trim() }
            )
        } catch (e: EdgeVedaException) {
            throw e
        } catch (e: Exception) {
            throw EdgeVedaException.GenerationError(
                "Whisper transcription failed: ${e.message}",
                e
            )
        }
    }

    /**
     * Clean up and free native whisper resources
     *
     * Frees the native whisper context (model). The session cannot be used
     * after cleanup unless initialize() is called again.
     *
     * @throws EdgeVedaException if cleanup fails
     */
    suspend fun cleanup() = withContext(Dispatchers.Default) {
        if (!_isInitialized.get()) {
            return@withContext
        }

        try {
            NativeBridge.freeWhisper()
            _isInitialized.set(false)
            backend = ""
        } catch (e: Exception) {
            throw EdgeVedaException.NativeError(
                "Failed to cleanup whisper context: ${e.message}",
                e
            )
        }
    }
}

/**
 * Configuration for WhisperSession initialization.
 *
 * @property modelPath Path to the Whisper GGML model file
 * @property numThreads Number of CPU threads (0 = auto-detect, default: 4)
 * @property useGpu Enable GPU acceleration if available (default: true)
 */
data class WhisperConfig(
    val modelPath: String,
    val numThreads: Int = 4,
    val useGpu: Boolean = true
) {
    init {
        require(modelPath.isNotEmpty()) { "modelPath cannot be empty" }
        require(numThreads >= 0) { "numThreads must be >= 0" }
    }
}

/**
 * Parameters for audio transcription.
 *
 * @property language Language code (e.g., "en", "es", "fr", "auto" for detection, default: "en")
 * @property translate Translate to English if source language is not English (default: false)
 * @property nThreads Number of threads for transcription (0 = auto-detect, default: 4)
 */
data class WhisperTranscribeParams(
    val language: String = "en",
    val translate: Boolean = false,
    val nThreads: Int = 4
) {
    init {
        require(language.isNotEmpty()) { "language cannot be empty" }
        require(nThreads >= 0) { "nThreads must be >= 0" }
    }

    companion object {
        /**
         * Default params for automatic language detection
         */
        fun autoDetect(): WhisperTranscribeParams = WhisperTranscribeParams(
            language = "auto",
            translate = false
        )

        /**
         * Params for transcription + translation to English
         */
        fun autoTranslate(): WhisperTranscribeParams = WhisperTranscribeParams(
            language = "auto",
            translate = true
        )

        /**
         * Params for fast CPU-only transcription
         */
        fun fast(): WhisperTranscribeParams = WhisperTranscribeParams(
            language = "en",
            translate = false,
            nThreads = 2
        )
    }
}

/**
 * Result from Whisper transcription.
 *
 * @property segments List of text segments with timestamps
 * @property fullText Complete transcription text (all segments joined)
 */
data class WhisperResult(
    val segments: List<WhisperSegment>,
    val fullText: String
) {
    /**
     * Total duration of transcribed audio in milliseconds
     */
    val durationMs: Long
        get() = segments.lastOrNull()?.endMs ?: 0L

    /**
     * Number of segments in the transcription
     */
    val segmentCount: Int
        get() = segments.size
}

/**
 * A single transcribed text segment with timing information.
 *
 * @property text Transcribed text for this segment
 * @property startMs Start time in milliseconds
 * @property endMs End time in milliseconds
 */
data class WhisperSegment(
    val text: String,
    val startMs: Long,
    val endMs: Long
) {
    /**
     * Duration of this segment in milliseconds
     */
    val durationMs: Long
        get() = endMs - startMs

    /**
     * Start time in seconds (for convenience)
     */
    val startSeconds: Double
        get() = startMs / 1000.0

    /**
     * End time in seconds (for convenience)
     */
    val endSeconds: Double
        get() = endMs / 1000.0
}