package com.edgeveda.sdk

/**
 * Maps C core / JNI integer error codes to Kotlin [EdgeVedaException] subclasses.
 *
 * The native C engine returns integer error codes through the JNI boundary.
 * This enum provides a type-safe mapping from those codes to rich Kotlin exceptions.
 * Codes match `ev_error_t` in `edge_veda.h` (all errors are negative; 0 = success).
 *
 * ## Usage
 * ```kotlin
 * val code = NativeErrorCode.fromCode(resultCode)
 * code.throwIfError("Failed during model load")
 * ```
 *
 * ## Error Code Table
 * | Code | Name                 | Description                               |
 * |------|----------------------|-------------------------------------------|
 * |  0   | OK                   | Success (no error)                        |
 * | -1   | INVALID_PARAM        | Invalid parameter value                   |
 * | -2   | OUT_OF_MEMORY        | System ran out of memory                  |
 * | -3   | MODEL_LOAD_FAILED    | Model failed to load                      |
 * | -4   | BACKEND_INIT_FAILED  | Backend (Vulkan/CPU) failed to initialise |
 * | -5   | INFERENCE_FAILED     | Text generation / inference failed        |
 * | -6   | CONTEXT_INVALID      | Context invalid or prompt exceeds window  |
 * | -7   | STREAM_ENDED         | Normal end-of-stream (not an error)       |
 * | -8   | NOT_IMPLEMENTED      | Feature not implemented                   |
 * | -9   | MEMORY_LIMIT_EXCEEDED| Configured memory limit exceeded          |
 * | -10  | UNSUPPORTED_BACKEND  | Backend not supported on this device      |
 * | -999 | UNKNOWN              | Unknown or unmapped error code            |
 */
enum class NativeErrorCode(val code: Int) {
    /** Operation completed successfully (no error) */
    OK(0),

    /** An invalid parameter was passed to the engine */
    INVALID_PARAM(-1),

    /** System ran out of memory during operation */
    OUT_OF_MEMORY(-2),

    /** Model failed to load (corrupt file, unsupported format, etc.) */
    MODEL_LOAD_FAILED(-3),

    /** Backend (Vulkan/CPU) failed to initialise */
    BACKEND_INIT_FAILED(-4),

    /** Text generation / inference failed mid-operation */
    INFERENCE_FAILED(-5),

    /** Context is invalid or prompt exceeded the context window */
    CONTEXT_INVALID(-6),

    /** Normal end-of-stream signal — not an error */
    STREAM_ENDED(-7),

    /** Feature is not yet implemented in the native engine */
    NOT_IMPLEMENTED(-8),

    /** Configured memory limit was exceeded */
    MEMORY_LIMIT_EXCEEDED(-9),

    /** Backend is not supported on this device */
    UNSUPPORTED_BACKEND(-10),

    /** Unknown or unmapped error code */
    UNKNOWN(-999);

    /**
     * Convert this native error code to an [EdgeVedaException].
     *
     * Returns `null` for [OK] and [STREAM_ENDED] since neither represents an error.
     *
     * @param context Optional additional context string for the error message.
     * @return The corresponding [EdgeVedaException], or `null` if the code is [OK]/[STREAM_ENDED].
     */
    fun toException(context: String? = null): EdgeVedaException? {
        val msg = context ?: "Native engine error"

        return when (this) {
            OK -> null
            INVALID_PARAM -> EdgeVedaException.InvalidConfiguration(msg)
            OUT_OF_MEMORY -> EdgeVedaException.OutOfMemoryError(msg)
            MODEL_LOAD_FAILED -> EdgeVedaException.ModelLoadError(msg)
            BACKEND_INIT_FAILED -> EdgeVedaException.ModelLoadError("Backend initialization failed: $msg")
            INFERENCE_FAILED -> EdgeVedaException.GenerationError(msg)
            CONTEXT_INVALID -> EdgeVedaException.ContextOverflowError(msg)
            STREAM_ENDED -> null
            NOT_IMPLEMENTED -> EdgeVedaException.UnsupportedOperationError(msg)
            MEMORY_LIMIT_EXCEEDED -> EdgeVedaException.OutOfMemoryError("Memory limit exceeded: $msg")
            UNSUPPORTED_BACKEND -> EdgeVedaException.InvalidConfiguration("Unsupported backend: $msg")
            UNKNOWN -> EdgeVedaException.NativeError(msg)
        }
    }

    /**
     * Throw the corresponding [EdgeVedaException] if this code is not [OK].
     *
     * @param context Optional context string for the error message.
     * @throws EdgeVedaException if the code represents an error.
     */
    fun throwIfError(context: String? = null) {
        toException(context)?.let { throw it }
    }

    companion object {
        private val codeMap = entries.associateBy { it.code }

        /**
         * Look up a [NativeErrorCode] from a raw integer code.
         *
         * Returns [UNKNOWN] for unmapped values.
         *
         * @param code The raw integer error code from JNI.
         * @return The corresponding [NativeErrorCode].
         */
        fun fromCode(code: Int): NativeErrorCode {
            return codeMap[code] ?: UNKNOWN
        }
    }
}
