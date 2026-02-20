package com.edgeveda.example

import com.edgeveda.sdk.ChatMessage
import com.edgeveda.sdk.ChatRole
import com.edgeveda.sdk.ChatTemplate
import com.edgeveda.sdk.GenerateOptions
import com.edgeveda.sdk.MemoryStats
import com.edgeveda.sdk.ModelRegistry
import com.edgeveda.sdk.NativeErrorCode
import org.junit.Assert.*
import org.junit.Test

/**
 * SDK smoke tests for the sample app module.
 *
 * These tests exercise the public Edge Veda SDK surface without requiring an
 * Android device, a downloaded model file, or any native library. They verify
 * that data models, registry queries, template formatting, and error-code
 * mappings all work correctly as observable from the sample app's perspective.
 */
class SdkSmokeTest {

    // ── ModelRegistry ─────────────────────────────────────────────────────────

    @Test
    fun `ModelRegistry contains at least 9 models across all categories`() {
        val all = ModelRegistry.getAllTextModels() +
                  ModelRegistry.getVisionModels() +
                  ModelRegistry.getWhisperModels() +
                  ModelRegistry.getEmbeddingModels()
        assertTrue("Expected at least 9 models, found ${all.size}", all.size >= 9)
    }

    @Test
    fun `ModelRegistry getAllTextModels returns 5 text models`() =
        assertEquals(5, ModelRegistry.getAllTextModels().size)

    @Test
    fun `ModelRegistry getWhisperModels returns 2 whisper models`() =
        assertEquals(2, ModelRegistry.getWhisperModels().size)

    @Test
    fun `ModelRegistry getModelById returns model for known id`() {
        val model = ModelRegistry.getModelById("llama-3.2-1b-instruct-q4")
        assertNotNull(model)
        assertEquals("Llama 3.2 1B Instruct", model!!.name)
    }

    @Test
    fun `ModelRegistry getModelById returns null for unknown id`() =
        assertNull(ModelRegistry.getModelById("definitely-not-a-real-model"))

    // ── ChatTemplate ──────────────────────────────────────────────────────────

    @Test
    fun `ChatTemplate CHATML formats user message with im_start token`() {
        val result = ChatTemplate.CHATML.format(
            listOf(ChatMessage(ChatRole.USER, "hello"))
        )
        assertTrue(result.contains("<|im_start|>user"))
    }

    @Test
    fun `ChatTemplate LLAMA3 output starts with begin_of_text`() {
        val result = ChatTemplate.LLAMA3.format(
            listOf(ChatMessage(ChatRole.USER, "hello"))
        )
        assertTrue(result.startsWith("<|begin_of_text|>"))
    }

    @Test
    fun `ChatTemplate GEMMA3 does not produce system turn token`() {
        val result = ChatTemplate.GEMMA3.format(
            listOf(
                ChatMessage(ChatRole.SYSTEM, "Be brief"),
                ChatMessage(ChatRole.USER, "Hi")
            )
        )
        assertFalse(result.contains("<start_of_turn>system"))
        assertTrue(result.contains("Be brief")) // merged into user turn
    }

    // ── GenerateOptions presets ───────────────────────────────────────────────

    @Test
    fun `GenerateOptions creative preset has high temperature`() {
        val opts = GenerateOptions.creative()
        assertNotNull(opts.temperature)
        assertTrue("Creative temperature should be >= 0.9", opts.temperature!! >= 0.9f)
    }

    @Test
    fun `GenerateOptions deterministic preset has low temperature`() {
        val opts = GenerateOptions.deterministic()
        assertNotNull(opts.temperature)
        assertTrue("Deterministic temperature should be <= 0.5", opts.temperature!! <= 0.5f)
    }

    @Test
    fun `GenerateOptions balanced preset has mid-range temperature`() {
        val opts = GenerateOptions.balanced()
        assertNotNull(opts.temperature)
        val temp = opts.temperature!!
        assertTrue("Balanced temperature should be between 0.5 and 0.9", temp in 0.5f..0.9f)
    }

    // ── NativeErrorCode ───────────────────────────────────────────────────────

    @Test
    fun `NativeErrorCode OK maps to code zero`() =
        assertEquals(NativeErrorCode.OK, NativeErrorCode.fromCode(0))

    @Test
    fun `NativeErrorCode fromCode returns UNKNOWN for unmapped code`() =
        assertEquals(NativeErrorCode.UNKNOWN, NativeErrorCode.fromCode(-42))

    @Test
    fun `NativeErrorCode OK throwIfError does not throw`() {
        NativeErrorCode.OK.throwIfError() // must not throw
    }

    // ── MemoryStats ───────────────────────────────────────────────────────────

    @Test
    fun `MemoryStats isCritical is true when usage exceeds 90 percent`() {
        val stats = MemoryStats(
            currentBytes = 950_000_000L,
            peakBytes = 950_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 850_000_000L,
            contextBytes = 100_000_000L
        )
        assertTrue(stats.isCritical)
    }

    @Test
    fun `MemoryStats usagePercent is zero when limitBytes is zero`() {
        val stats = MemoryStats(
            currentBytes = 500_000_000L,
            peakBytes = 500_000_000L,
            limitBytes = 0L,
            modelBytes = 400_000_000L,
            contextBytes = 100_000_000L
        )
        assertEquals(0.0, stats.usagePercent, 0.0001)
    }
}
