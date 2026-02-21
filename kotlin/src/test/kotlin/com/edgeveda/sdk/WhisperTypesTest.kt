package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for Whisper data types: WhisperConfig, WhisperTranscribeParams,
 * WhisperSegment, and WhisperResult.
 *
 * All tests are pure (no coroutines, no native calls) — they cover default values,
 * factory presets, computed properties, and validation guards.
 */
class WhisperTypesTest {

    // ── WhisperConfig ─────────────────────────────────────────────────────────

    @Test
    fun `WhisperConfig stores modelPath correctly`() {
        val cfg = WhisperConfig(modelPath = "/data/user/0/com.app/files/model.bin")
        assertEquals("/data/user/0/com.app/files/model.bin", cfg.modelPath)
    }

    @Test
    fun `WhisperConfig default numThreads is 4`() {
        val cfg = WhisperConfig(modelPath = "/path/model.bin")
        assertEquals(4, cfg.numThreads)
    }

    @Test
    fun `WhisperConfig default useGpu is true`() {
        val cfg = WhisperConfig(modelPath = "/path/model.bin")
        assertTrue(cfg.useGpu)
    }

    @Test
    fun `WhisperConfig accepts custom numThreads`() {
        val cfg = WhisperConfig(modelPath = "/path/model.bin", numThreads = 8)
        assertEquals(8, cfg.numThreads)
    }

    @Test
    fun `WhisperConfig accepts useGpu false`() {
        val cfg = WhisperConfig(modelPath = "/path/model.bin", useGpu = false)
        assertFalse(cfg.useGpu)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `WhisperConfig throws when modelPath is empty`() {
        WhisperConfig(modelPath = "")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `WhisperConfig throws when numThreads is negative`() {
        WhisperConfig(modelPath = "/path/model.bin", numThreads = -1)
    }

    @Test
    fun `WhisperConfig allows numThreads zero for auto-detect`() {
        val cfg = WhisperConfig(modelPath = "/path/model.bin", numThreads = 0)
        assertEquals(0, cfg.numThreads)
    }

    // ── WhisperTranscribeParams defaults ──────────────────────────────────────

    @Test
    fun `WhisperTranscribeParams default language is en`() {
        val params = WhisperTranscribeParams()
        assertEquals("en", params.language)
    }

    @Test
    fun `WhisperTranscribeParams default translate is false`() {
        val params = WhisperTranscribeParams()
        assertFalse(params.translate)
    }

    @Test
    fun `WhisperTranscribeParams default nThreads is 4`() {
        val params = WhisperTranscribeParams()
        assertEquals(4, params.nThreads)
    }

    // ── WhisperTranscribeParams factory presets ────────────────────────────────

    @Test
    fun `autoDetect preset has auto language`() {
        val params = WhisperTranscribeParams.autoDetect()
        assertEquals("auto", params.language)
    }

    @Test
    fun `autoDetect preset has translate false`() {
        val params = WhisperTranscribeParams.autoDetect()
        assertFalse(params.translate)
    }

    @Test
    fun `autoTranslate preset has auto language`() {
        val params = WhisperTranscribeParams.autoTranslate()
        assertEquals("auto", params.language)
    }

    @Test
    fun `autoTranslate preset has translate true`() {
        val params = WhisperTranscribeParams.autoTranslate()
        assertTrue(params.translate)
    }

    @Test
    fun `fast preset has en language`() {
        val params = WhisperTranscribeParams.fast()
        assertEquals("en", params.language)
    }

    @Test
    fun `fast preset has translate false`() {
        val params = WhisperTranscribeParams.fast()
        assertFalse(params.translate)
    }

    @Test
    fun `fast preset has reduced thread count`() {
        val params = WhisperTranscribeParams.fast()
        assertTrue("fast preset should use fewer threads than default", params.nThreads < 4)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `WhisperTranscribeParams throws when language is empty`() {
        WhisperTranscribeParams(language = "")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `WhisperTranscribeParams throws when nThreads is negative`() {
        WhisperTranscribeParams(nThreads = -1)
    }

    // ── WhisperSegment computed properties ────────────────────────────────────

    @Test
    fun `WhisperSegment durationMs is endMs minus startMs`() {
        val seg = WhisperSegment(text = "hello", startMs = 1_000L, endMs = 2_500L)
        assertEquals(1_500L, seg.durationMs)
    }

    @Test
    fun `WhisperSegment durationMs is 0 when start equals end`() {
        val seg = WhisperSegment(text = "instant", startMs = 500L, endMs = 500L)
        assertEquals(0L, seg.durationMs)
    }

    @Test
    fun `WhisperSegment startSeconds is startMs divided by 1000`() {
        val seg = WhisperSegment(text = "hello", startMs = 1_500L, endMs = 3_000L)
        assertEquals(1.5, seg.startSeconds, 0.0001)
    }

    @Test
    fun `WhisperSegment endSeconds is endMs divided by 1000`() {
        val seg = WhisperSegment(text = "hello", startMs = 1_000L, endMs = 2_750L)
        assertEquals(2.75, seg.endSeconds, 0.0001)
    }

    @Test
    fun `WhisperSegment stores text correctly`() {
        val seg = WhisperSegment(text = "  Hello world  ", startMs = 0L, endMs = 1_000L)
        assertEquals("  Hello world  ", seg.text)
    }

    @Test
    fun `WhisperSegment data class equality`() {
        val a = WhisperSegment("hello", 0L, 1_000L)
        val b = WhisperSegment("hello", 0L, 1_000L)
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    // ── WhisperResult computed properties ─────────────────────────────────────

    @Test
    fun `WhisperResult segmentCount equals number of segments`() {
        val result = WhisperResult(
            segments = listOf(
                WhisperSegment("Hello", 0L, 1_000L),
                WhisperSegment("world", 1_000L, 2_000L),
                WhisperSegment("goodbye", 2_000L, 3_000L)
            ),
            fullText = "Hello world goodbye"
        )
        assertEquals(3, result.segmentCount)
    }

    @Test
    fun `WhisperResult durationMs equals last segment endMs`() {
        val result = WhisperResult(
            segments = listOf(
                WhisperSegment("Hello", 0L, 1_000L),
                WhisperSegment("world", 1_000L, 5_300L)
            ),
            fullText = "Hello world"
        )
        assertEquals(5_300L, result.durationMs)
    }

    @Test
    fun `WhisperResult fullText contains all segment texts`() {
        val result = WhisperResult(
            segments = listOf(
                WhisperSegment("Hello", 0L, 1_000L),
                WhisperSegment("world", 1_000L, 2_000L)
            ),
            fullText = "Hello world"
        )
        assertTrue(result.fullText.contains("Hello"))
        assertTrue(result.fullText.contains("world"))
    }

    @Test
    fun `WhisperResult with empty segments has durationMs of 0`() {
        val result = WhisperResult(segments = emptyList(), fullText = "")
        assertEquals(0L, result.durationMs)
    }

    @Test
    fun `WhisperResult with empty segments has segmentCount of 0`() {
        val result = WhisperResult(segments = emptyList(), fullText = "")
        assertEquals(0, result.segmentCount)
    }

    @Test
    fun `WhisperResult with empty segments has empty fullText`() {
        val result = WhisperResult(segments = emptyList(), fullText = "")
        assertEquals("", result.fullText)
    }

    @Test
    fun `WhisperResult with single segment`() {
        val result = WhisperResult(
            segments = listOf(WhisperSegment("Only segment", 100L, 1_500L)),
            fullText = "Only segment"
        )
        assertEquals(1, result.segmentCount)
        assertEquals(1_500L, result.durationMs)
        assertEquals("Only segment", result.fullText)
    }

    @Test
    fun `WhisperResult data class equality`() {
        val segs = listOf(WhisperSegment("Hi", 0L, 500L))
        val a = WhisperResult(segs, "Hi")
        val b = WhisperResult(segs, "Hi")
        assertEquals(a, b)
    }
}
