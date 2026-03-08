package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for NativeErrorCode — verifies the JNI integer error code mapping to
 * Kotlin EdgeVedaException subclasses. Mirrors the exception hierarchy tests in the
 * Flutter gold standard (edge_veda_test.dart EdgeVedaException group).
 */
class NativeErrorCodeTest {

    // ── fromCode mapping ──────────────────────────────────────────────────────

    @Test
    fun `fromCode maps 0 to OK`() =
        assertEquals(NativeErrorCode.OK, NativeErrorCode.fromCode(0))

    @Test
    fun `fromCode maps -1 to INVALID_PARAM`() =
        assertEquals(NativeErrorCode.INVALID_PARAM, NativeErrorCode.fromCode(-1))

    @Test
    fun `fromCode maps -2 to OUT_OF_MEMORY`() =
        assertEquals(NativeErrorCode.OUT_OF_MEMORY, NativeErrorCode.fromCode(-2))

    @Test
    fun `fromCode maps -3 to MODEL_LOAD_FAILED`() =
        assertEquals(NativeErrorCode.MODEL_LOAD_FAILED, NativeErrorCode.fromCode(-3))

    @Test
    fun `fromCode maps -4 to BACKEND_INIT_FAILED`() =
        assertEquals(NativeErrorCode.BACKEND_INIT_FAILED, NativeErrorCode.fromCode(-4))

    @Test
    fun `fromCode maps -5 to INFERENCE_FAILED`() =
        assertEquals(NativeErrorCode.INFERENCE_FAILED, NativeErrorCode.fromCode(-5))

    @Test
    fun `fromCode maps -6 to CONTEXT_INVALID`() =
        assertEquals(NativeErrorCode.CONTEXT_INVALID, NativeErrorCode.fromCode(-6))

    @Test
    fun `fromCode maps -7 to STREAM_ENDED`() =
        assertEquals(NativeErrorCode.STREAM_ENDED, NativeErrorCode.fromCode(-7))

    @Test
    fun `fromCode maps -8 to NOT_IMPLEMENTED`() =
        assertEquals(NativeErrorCode.NOT_IMPLEMENTED, NativeErrorCode.fromCode(-8))

    @Test
    fun `fromCode maps -9 to MEMORY_LIMIT_EXCEEDED`() =
        assertEquals(NativeErrorCode.MEMORY_LIMIT_EXCEEDED, NativeErrorCode.fromCode(-9))

    @Test
    fun `fromCode maps -10 to UNSUPPORTED_BACKEND`() =
        assertEquals(NativeErrorCode.UNSUPPORTED_BACKEND, NativeErrorCode.fromCode(-10))

    @Test
    fun `fromCode maps -999 to UNKNOWN`() =
        assertEquals(NativeErrorCode.UNKNOWN, NativeErrorCode.fromCode(-999))

    @Test
    fun `fromCode maps unrecognised negative code to UNKNOWN`() =
        assertEquals(NativeErrorCode.UNKNOWN, NativeErrorCode.fromCode(-42))

    @Test
    fun `fromCode maps unrecognised positive code to UNKNOWN`() =
        assertEquals(NativeErrorCode.UNKNOWN, NativeErrorCode.fromCode(999))

    // ── toException: non-error codes return null ───────────────────────────────

    @Test
    fun `OK toException returns null`() =
        assertNull(NativeErrorCode.OK.toException())

    @Test
    fun `STREAM_ENDED toException returns null`() =
        assertNull(NativeErrorCode.STREAM_ENDED.toException())

    // ── toException: error codes return correct exception types ───────────────

    @Test
    fun `INVALID_PARAM toException returns InvalidConfiguration`() {
        val ex = NativeErrorCode.INVALID_PARAM.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.InvalidConfiguration)
    }

    @Test
    fun `OUT_OF_MEMORY toException returns OutOfMemoryError`() {
        val ex = NativeErrorCode.OUT_OF_MEMORY.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.OutOfMemoryError)
    }

    @Test
    fun `MODEL_LOAD_FAILED toException returns ModelLoadError`() {
        val ex = NativeErrorCode.MODEL_LOAD_FAILED.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.ModelLoadError)
    }

    @Test
    fun `BACKEND_INIT_FAILED toException returns ModelLoadError`() {
        val ex = NativeErrorCode.BACKEND_INIT_FAILED.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.ModelLoadError)
    }

    @Test
    fun `INFERENCE_FAILED toException returns GenerationError`() {
        val ex = NativeErrorCode.INFERENCE_FAILED.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.GenerationError)
    }

    @Test
    fun `CONTEXT_INVALID toException returns ContextOverflowError`() {
        val ex = NativeErrorCode.CONTEXT_INVALID.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.ContextOverflowError)
    }

    @Test
    fun `NOT_IMPLEMENTED toException returns UnsupportedOperationError`() {
        val ex = NativeErrorCode.NOT_IMPLEMENTED.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.UnsupportedOperationError)
    }

    @Test
    fun `MEMORY_LIMIT_EXCEEDED toException returns OutOfMemoryError`() {
        val ex = NativeErrorCode.MEMORY_LIMIT_EXCEEDED.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.OutOfMemoryError)
    }

    @Test
    fun `UNSUPPORTED_BACKEND toException returns InvalidConfiguration`() {
        val ex = NativeErrorCode.UNSUPPORTED_BACKEND.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.InvalidConfiguration)
    }

    @Test
    fun `UNKNOWN toException returns NativeError`() {
        val ex = NativeErrorCode.UNKNOWN.toException()
        assertNotNull(ex)
        assertTrue(ex is EdgeVedaException.NativeError)
    }

    @Test
    fun `toException message contains custom context when provided`() {
        val ex = NativeErrorCode.INFERENCE_FAILED.toException("model inference blew up")
        assertNotNull(ex)
        assertTrue(ex!!.message!!.contains("model inference blew up"))
    }

    // ── throwIfError ──────────────────────────────────────────────────────────

    @Test
    fun `throwIfError does not throw for OK`() {
        NativeErrorCode.OK.throwIfError() // must not throw
    }

    @Test
    fun `throwIfError does not throw for STREAM_ENDED`() {
        NativeErrorCode.STREAM_ENDED.throwIfError() // must not throw
    }

    @Test(expected = EdgeVedaException.GenerationError::class)
    fun `throwIfError throws GenerationError for INFERENCE_FAILED`() {
        NativeErrorCode.INFERENCE_FAILED.throwIfError()
    }

    @Test(expected = EdgeVedaException.ModelLoadError::class)
    fun `throwIfError throws ModelLoadError for MODEL_LOAD_FAILED`() {
        NativeErrorCode.MODEL_LOAD_FAILED.throwIfError()
    }

    @Test(expected = EdgeVedaException.OutOfMemoryError::class)
    fun `throwIfError throws OutOfMemoryError for OUT_OF_MEMORY`() {
        NativeErrorCode.OUT_OF_MEMORY.throwIfError()
    }

    // ── enum invariants ───────────────────────────────────────────────────────

    @Test
    fun `OK has code 0`() =
        assertEquals(0, NativeErrorCode.OK.code)

    @Test
    fun `all error codes except OK and STREAM_ENDED have negative code values`() {
        val nonErrors = setOf(NativeErrorCode.OK, NativeErrorCode.STREAM_ENDED)
        NativeErrorCode.entries.filter { it !in nonErrors }.forEach { code ->
            assertTrue("${code.name} should have negative code", code.code < 0)
        }
    }

    @Test
    fun `enum contains exactly 12 entries`() =
        assertEquals(12, NativeErrorCode.entries.size)
}
