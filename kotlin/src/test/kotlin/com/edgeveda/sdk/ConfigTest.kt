package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for EdgeVedaConfig, BenchmarkResult, and Backend.
 *
 * EdgeVedaTest.kt already covers Backend enum and GenerateOptions validation;
 * this file covers EdgeVedaConfig defaults, builder chain, presets, and
 * BenchmarkResult formatting.
 */
class ConfigTest {

    // ── EdgeVedaConfig defaults ───────────────────────────────────────────────

    @Test
    fun `EdgeVedaConfig default backend is AUTO`() {
        assertEquals(Backend.AUTO, EdgeVedaConfig().backend)
    }

    @Test
    fun `EdgeVedaConfig default numThreads is 0 (auto-detect)`() {
        assertEquals(0, EdgeVedaConfig().numThreads)
    }

    @Test
    fun `EdgeVedaConfig default maxTokens is 512`() {
        assertEquals(512, EdgeVedaConfig().maxTokens)
    }

    @Test
    fun `EdgeVedaConfig default contextSize is 2048`() {
        assertEquals(2048, EdgeVedaConfig().contextSize)
    }

    @Test
    fun `EdgeVedaConfig default batchSize is 512`() {
        assertEquals(512, EdgeVedaConfig().batchSize)
    }

    @Test
    fun `EdgeVedaConfig default useGpu is true`() {
        assertTrue(EdgeVedaConfig().useGpu)
    }

    @Test
    fun `EdgeVedaConfig default useMmap is true`() {
        assertTrue(EdgeVedaConfig().useMmap)
    }

    @Test
    fun `EdgeVedaConfig default useMlock is false`() {
        assertFalse(EdgeVedaConfig().useMlock)
    }

    @Test
    fun `EdgeVedaConfig default temperature is 0_7f`() {
        assertEquals(0.7f, EdgeVedaConfig().temperature, 0.001f)
    }

    @Test
    fun `EdgeVedaConfig default topP is 0_9f`() {
        assertEquals(0.9f, EdgeVedaConfig().topP, 0.001f)
    }

    @Test
    fun `EdgeVedaConfig default topK is 40`() {
        assertEquals(40, EdgeVedaConfig().topK)
    }

    @Test
    fun `EdgeVedaConfig default repeatPenalty is 1_1f`() {
        assertEquals(1.1f, EdgeVedaConfig().repeatPenalty, 0.001f)
    }

    @Test
    fun `EdgeVedaConfig default seed is -1`() {
        assertEquals(-1L, EdgeVedaConfig().seed)
    }

    // ── Builder chain ─────────────────────────────────────────────────────────

    @Test
    fun `withBackend sets backend`() {
        val config = EdgeVedaConfig().withBackend(Backend.CPU)
        assertEquals(Backend.CPU, config.backend)
    }

    @Test
    fun `withBackend does not mutate other fields`() {
        val original = EdgeVedaConfig()
        val modified = original.withBackend(Backend.VULKAN)
        assertEquals(original.maxTokens, modified.maxTokens)
        assertEquals(original.contextSize, modified.contextSize)
    }

    @Test
    fun `withNumThreads sets numThreads`() {
        val config = EdgeVedaConfig().withNumThreads(8)
        assertEquals(8, config.numThreads)
    }

    @Test
    fun `withMaxTokens sets maxTokens`() {
        val config = EdgeVedaConfig().withMaxTokens(1024)
        assertEquals(1024, config.maxTokens)
    }

    @Test
    fun `withContextSize sets contextSize`() {
        val config = EdgeVedaConfig().withContextSize(4096)
        assertEquals(4096, config.contextSize)
    }

    @Test
    fun `withTemperature sets temperature`() {
        val config = EdgeVedaConfig().withTemperature(0.3f)
        assertEquals(0.3f, config.temperature, 0.001f)
    }

    @Test
    fun `withTopP sets topP`() {
        val config = EdgeVedaConfig().withTopP(0.8f)
        assertEquals(0.8f, config.topP, 0.001f)
    }

    @Test
    fun `withTopK sets topK`() {
        val config = EdgeVedaConfig().withTopK(20)
        assertEquals(20, config.topK)
    }

    @Test
    fun `builder chain is fluent`() {
        val config = EdgeVedaConfig()
            .withBackend(Backend.CPU)
            .withNumThreads(4)
            .withMaxTokens(256)
            .withTemperature(0.5f)
        assertEquals(Backend.CPU, config.backend)
        assertEquals(4, config.numThreads)
        assertEquals(256, config.maxTokens)
        assertEquals(0.5f, config.temperature, 0.001f)
    }

    // ── Validation ────────────────────────────────────────────────────────────

    @Test(expected = IllegalArgumentException::class)
    fun `negative numThreads throws IllegalArgumentException`() {
        EdgeVedaConfig(numThreads = -1)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `zero maxTokens throws IllegalArgumentException`() {
        EdgeVedaConfig(maxTokens = 0)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `negative maxTokens throws IllegalArgumentException`() {
        EdgeVedaConfig(maxTokens = -1)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `negative temperature throws IllegalArgumentException`() {
        EdgeVedaConfig(temperature = -0.1f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `topP greater than 1 throws IllegalArgumentException`() {
        EdgeVedaConfig(topP = 1.1f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `topP less than 0 throws IllegalArgumentException`() {
        EdgeVedaConfig(topP = -0.1f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `zero topK throws IllegalArgumentException`() {
        EdgeVedaConfig(topK = 0)
    }

    @Test
    fun `temperature of 0 is valid (greedy decoding)`() {
        val config = EdgeVedaConfig(temperature = 0.0f)
        assertEquals(0.0f, config.temperature, 0.0f)
    }

    @Test
    fun `numThreads of 0 is valid (auto-detect)`() {
        val config = EdgeVedaConfig(numThreads = 0)
        assertEquals(0, config.numThreads)
    }

    // ── Presets ───────────────────────────────────────────────────────────────

    @Test
    fun `mobile preset has maxTokens of 256`() {
        assertEquals(256, EdgeVedaConfig.mobile().maxTokens)
    }

    @Test
    fun `mobile preset has contextSize of 1024`() {
        assertEquals(1024, EdgeVedaConfig.mobile().contextSize)
    }

    @Test
    fun `mobile preset has useGpu true`() {
        assertTrue(EdgeVedaConfig.mobile().useGpu)
    }

    @Test
    fun `highQuality preset has contextSize of 4096`() {
        assertEquals(4096, EdgeVedaConfig.highQuality().contextSize)
    }

    @Test
    fun `highQuality preset has maxTokens of 1024`() {
        assertEquals(1024, EdgeVedaConfig.highQuality().maxTokens)
    }

    @Test
    fun `highQuality preset has useMlock true`() {
        assertTrue(EdgeVedaConfig.highQuality().useMlock)
    }

    @Test
    fun `fast preset has contextSize of 512`() {
        assertEquals(512, EdgeVedaConfig.fast().contextSize)
    }

    @Test
    fun `fast preset has temperature below default`() {
        assertTrue(EdgeVedaConfig.fast().temperature < EdgeVedaConfig().temperature)
    }

    @Test
    fun `fast preset has maxTokens of 128`() {
        assertEquals(128, EdgeVedaConfig.fast().maxTokens)
    }

    // ── BenchmarkResult ───────────────────────────────────────────────────────

    @Test
    fun `BenchmarkResult stores all fields correctly`() {
        val result = BenchmarkResult(tokensPerSecond = 42.9, timeMs = 2500.0, tokensProcessed = 100)
        assertEquals(42.9, result.tokensPerSecond, 0.001)
        assertEquals(2500.0, result.timeMs, 0.001)
        assertEquals(100, result.tokensProcessed)
    }

    @Test
    fun `BenchmarkResult toString contains tokensPerSec`() {
        val result = BenchmarkResult(42.9, 2500.0, 100)
        assertTrue(result.toString().contains("tokensPerSec"))
    }

    @Test
    fun `BenchmarkResult toString contains timeMs`() {
        val result = BenchmarkResult(42.9, 2500.0, 100)
        assertTrue(result.toString().contains("timeMs"))
    }

    @Test
    fun `BenchmarkResult toString contains tokens`() {
        val result = BenchmarkResult(42.9, 2500.0, 100)
        assertTrue(result.toString().contains("tokens"))
    }

    @Test
    fun `BenchmarkResult data class equality`() {
        val a = BenchmarkResult(42.9, 2500.0, 100)
        val b = BenchmarkResult(42.9, 2500.0, 100)
        assertEquals(a, b)
    }

    @Test
    fun `BenchmarkResult data class inequality on different speed`() {
        val a = BenchmarkResult(42.9, 2500.0, 100)
        val b = BenchmarkResult(40.0, 2500.0, 100)
        assertNotEquals(a, b)
    }

    @Test
    fun `BenchmarkResult copy works correctly`() {
        val original = BenchmarkResult(42.9, 2500.0, 100)
        val copy = original.copy(tokensProcessed = 200)
        assertEquals(100, original.tokensProcessed)
        assertEquals(200, copy.tokensProcessed)
    }
}
