package com.edgeveda.sdk

/**
 * Maps C core / JNI integer error codes to Kotlin [EdgeVedaException] subclasses.
 *
 * The native C engine returns integer error codes through the JNI boundary.
 * This enum provides a type-safe mapping from those codes to rich Kotlin exceptions.
 *
 * ## Usage
 * ```kotlin
 * val code = NativeErrorCode.fromCode(resultCode)
 * code.throwIfError("Failed during model load")
 * ```
 *
 * ## Error Code Table
 * | Code | Name              | Description                        |
 * |------|-------------------|------------------------------------|
 * | 0    | OK                | Success (no error)                 |
 * | 1    | MODEL_NOT_FOUND   | Model file not found               |
 * | 2    | MODEL_LOAD_FAILED | Model failed to load               |
 * | 3    | OUT_OF_MEMORY     | System ran out of memory           |
 * | 4    | CONTEXT_OVERFLOW  | Prompt exceeds context window      |
 * | 5    | INVALID_PARAMETER | Invalid parameter value            |
 * | 6    | GENERATION_FAILED | Text generation failed             |
 * | 7    | CANCELLED         | Operation was cancelled            |
 * | -1   | UNKNOWN           | Unknown or unmapped error          |
 */
enum class NativeErrorCode(val code: Int) {
    /** Operation completed successfully (no error) */
    OK(0),

    /** Model file was not found at the specified path */
    MODEL_NOT_FOUND(1),

    /** Model failed to load (corrupt file, unsupported format, etc.) */
    MODEL_LOAD_FAILED(2),

    /** System ran out of memory during operation */
    OUT_OF_MEMORY(3),

    /** Prompt exceeded the model's context window size */
    CONTEXT_OVERFLOW(4),

    /** An invalid parameter was passed to the engine */
    INVALID_PARAMETER(5),

    /** Text generation failed mid-operation */
    GENERATION_FAILED(6),

    /** Operation was cancelled by the user */
    CANCELLED(7),

    /** Unknown or unmapped error code */
    UNKNOWN(-1);

    /**
     * Convert this native error code to an [EdgeVedaException].
     *
     * Returns `null` for [OK] since no error occurred.
     *
     * @param context Optional additional context string for the error message.
     * @return The corresponding [EdgeVedaException], or `null` if the code is [OK].
     */
    fun toException(context: String? = null): EdgeVedaException? {
        val msg = context ?: "Native engine error"

        return when (this) {
            OK -> null
            MODEL_NOT_FOUND -> EdgeVedaException.ModelNotFoundError(msg)
            MODEL_LOAD_FAILED -> EdgeVedaException.ModelLoadError(msg)
            OUT_OF_MEMORY -> EdgeVedaException.OutOfMemoryError(msg)
            CONTEXT_OVERFLOW -> EdgeVedaException.ContextOverflowError(msg)
            INVALID_PARAMETER -> EdgeVedaException.InvalidConfiguration(msg)
            GENERATION_FAILED -> EdgeVedaException.GenerationError(msg)
            CANCELLED -> EdgeVedaException.CancelledException(msg)
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