package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for GenerationStats, DeviceInfo, GenerateOptions presets, and FinishReason.
 *
 * MemoryStats and MemoryPressureEvent are covered by MemoryStatsTest.kt.
 * GenerateOptions validation is partially covered by EdgeVedaTest.kt;
 * this file adds preset factory and additional validation tests.
 */
class TypesTest {

    // ── GenerationStats ───────────────────────────────────────────────────────

    @Test
    fun `GenerationStats stores all fields correctly`() {
        val stats = GenerationStats(
            tokensGenerated = 42,
            timeMs = 1000L,
            tokensPerSecond = 42.0,
            promptTokens = 10,
            finishReason = FinishReason.EOS_TOKEN
        )
        assertEquals(42, stats.tokensGenerated)
        assertEquals(1000L, stats.timeMs)
        assertEquals(42.0, stats.tokensPerSecond, 0.001)
        assertEquals(10, stats.promptTokens)
        assertEquals(FinishReason.EOS_TOKEN, stats.finishReason)
    }

    @Test
    fun `GenerationStats tokensPerSecond is a stored field`() {
        val stats = GenerationStats(
            tokensGenerated = 100,
            timeMs = 5000L,
            tokensPerSecond = 99.9,  // arbitrary — not recomputed
            promptTokens = 5,
            finishReason = FinishReason.MAX_TOKENS
        )
        // Stored verbatim, not derived from tokensGenerated / timeMs
        assertEquals(99.9, stats.tokensPerSecond, 0.001)
    }

    @Test
    fun `GenerationStats data class equality`() {
        val a = GenerationStats(10, 500L, 20.0, 5, FinishReason.STOP_SEQUENCE)
        val b = GenerationStats(10, 500L, 20.0, 5, FinishReason.STOP_SEQUENCE)
        assertEquals(a, b)
    }

    @Test
    fun `GenerationStats data class inequality on different tokensGenerated`() {
        val a = GenerationStats(10, 500L, 20.0, 5, FinishReason.EOS_TOKEN)
        val b = GenerationStats(11, 500L, 20.0, 5, FinishReason.EOS_TOKEN)
        assertNotEquals(a, b)
    }

    @Test
    fun `GenerationStats copy works correctly`() {
        val original = GenerationStats(10, 500L, 20.0, 5, FinishReason.EOS_TOKEN)
        val copy = original.copy(finishReason = FinishReason.CANCELLED)
        assertEquals(FinishReason.EOS_TOKEN, original.finishReason)
        assertEquals(FinishReason.CANCELLED, copy.finishReason)
    }

    // ── DeviceInfo ────────────────────────────────────────────────────────────

    @Test
    fun `DeviceInfo stores hasVulkanSupport correctly`() {
        val info = makeDeviceInfo(hasVulkan = true)
        assertTrue(info.hasVulkanSupport)
    }

    @Test
    fun `DeviceInfo stores hasNnapiSupport correctly`() {
        val info = makeDeviceInfo(hasNnapi = true)
        assertTrue(info.hasNnapiSupport)
    }

    @Test
    fun `DeviceInfo stores totalMemoryMb correctly`() {
        val info = makeDeviceInfo(totalMb = 6144L)
        assertEquals(6144L, info.totalMemoryMb)
    }

    @Test
    fun `DeviceInfo stores availableMemoryMb correctly`() {
        val info = makeDeviceInfo(availableMb = 2048L)
        assertEquals(2048L, info.availableMemoryMb)
    }

    @Test
    fun `DeviceInfo stores cpuCores correctly`() {
        val info = makeDeviceInfo(cores = 8)
        assertEquals(8, info.cpuCores)
    }

    @Test
    fun `DeviceInfo stores cpuArchitecture correctly`() {
        val info = makeDeviceInfo(arch = "arm64-v8a")
        assertEquals("arm64-v8a", info.cpuArchitecture)
    }

    @Test
    fun `DeviceInfo stores optional gpuVendor as null when absent`() {
        val info = makeDeviceInfo()
        assertNull(info.gpuVendor)
    }

    @Test
    fun `DeviceInfo stores optional gpuModel when provided`() {
        val info = DeviceInfo(
            hasVulkanSupport = true, hasNnapiSupport = false,
            totalMemoryMb = 8192L, availableMemoryMb = 4096L,
            cpuCores = 8, cpuArchitecture = "arm64-v8a",
            androidVersion = 34, gpuVendor = "Qualcomm", gpuModel = "Adreno 750"
        )
        assertEquals("Qualcomm", info.gpuVendor)
        assertEquals("Adreno 750", info.gpuModel)
    }

    @Test
    fun `DeviceInfo data class equality`() {
        val a = makeDeviceInfo()
        val b = makeDeviceInfo()
        assertEquals(a, b)
    }

    @Test
    fun `DeviceInfo data class inequality on different Vulkan support`() {
        val a = makeDeviceInfo(hasVulkan = true)
        val b = makeDeviceInfo(hasVulkan = false)
        assertNotEquals(a, b)
    }

    // ── GenerateOptions presets ───────────────────────────────────────────────

    @Test
    fun `GenerateOptions DEFAULT has null maxTokens`() {
        assertNull(GenerateOptions.DEFAULT.maxTokens)
    }

    @Test
    fun `GenerateOptions DEFAULT has null temperature`() {
        assertNull(GenerateOptions.DEFAULT.temperature)
    }

    @Test
    fun `GenerateOptions DEFAULT has null topP`() {
        assertNull(GenerateOptions.DEFAULT.topP)
    }

    @Test
    fun `GenerateOptions DEFAULT has empty stopSequences`() {
        assertTrue(GenerateOptions.DEFAULT.stopSequences.isEmpty())
    }

    @Test
    fun `GenerateOptions creative has temperature of 1_0f`() {
        assertEquals(1.0f, GenerateOptions.creative().temperature!!, 0.001f)
    }

    @Test
    fun `GenerateOptions creative has topP of 0_95f`() {
        assertEquals(0.95f, GenerateOptions.creative().topP!!, 0.001f)
    }

    @Test
    fun `GenerateOptions deterministic has temperature of 0_3f`() {
        assertEquals(0.3f, GenerateOptions.deterministic().temperature!!, 0.001f)
    }

    @Test
    fun `GenerateOptions deterministic temperature is lower than creative`() {
        val det = GenerateOptions.deterministic().temperature!!
        val cre = GenerateOptions.creative().temperature!!
        assertTrue(det < cre)
    }

    @Test
    fun `GenerateOptions balanced has temperature of 0_7f`() {
        assertEquals(0.7f, GenerateOptions.balanced().temperature!!, 0.001f)
    }

    @Test
    fun `GenerateOptions balanced temperature is between deterministic and creative`() {
        val det = GenerateOptions.deterministic().temperature!!
        val bal = GenerateOptions.balanced().temperature!!
        val cre = GenerateOptions.creative().temperature!!
        assertTrue(bal in det..cre)
    }

    // ── GenerateOptions validation ────────────────────────────────────────────

    @Test(expected = IllegalArgumentException::class)
    fun `GenerateOptions negative maxTokens throws`() {
        GenerateOptions(maxTokens = -1)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `GenerateOptions zero maxTokens throws`() {
        GenerateOptions(maxTokens = 0)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `GenerateOptions negative temperature throws`() {
        GenerateOptions(temperature = -0.1f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `GenerateOptions topP greater than 1 throws`() {
        GenerateOptions(topP = 1.1f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `GenerateOptions topP less than 0 throws`() {
        GenerateOptions(topP = -0.1f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `GenerateOptions zero topK throws`() {
        GenerateOptions(topK = 0)
    }

    @Test
    fun `GenerateOptions temperature of 0 is valid (greedy decoding)`() {
        val opts = GenerateOptions(temperature = 0.0f)
        assertEquals(0.0f, opts.temperature!!, 0.0f)
    }

    // ── FinishReason ──────────────────────────────────────────────────────────

    @Test
    fun `FinishReason has exactly 5 values`() {
        assertEquals(5, FinishReason.entries.size)
    }

    @Test
    fun `FinishReason contains MAX_TOKENS`() {
        assertTrue(FinishReason.entries.contains(FinishReason.MAX_TOKENS))
    }

    @Test
    fun `FinishReason contains EOS_TOKEN`() {
        assertTrue(FinishReason.entries.contains(FinishReason.EOS_TOKEN))
    }

    @Test
    fun `FinishReason contains STOP_SEQUENCE`() {
        assertTrue(FinishReason.entries.contains(FinishReason.STOP_SEQUENCE))
    }

    @Test
    fun `FinishReason contains CANCELLED`() {
        assertTrue(FinishReason.entries.contains(FinishReason.CANCELLED))
    }

    @Test
    fun `FinishReason contains ERROR`() {
        assertTrue(FinishReason.entries.contains(FinishReason.ERROR))
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun makeDeviceInfo(
        hasVulkan: Boolean = false,
        hasNnapi: Boolean = false,
        totalMb: Long = 4096L,
        availableMb: Long = 2048L,
        cores: Int = 4,
        arch: String = "arm64-v8a",
        androidVersion: Int = 33,
    ) = DeviceInfo(
        hasVulkanSupport = hasVulkan,
        hasNnapiSupport = hasNnapi,
        totalMemoryMb = totalMb,
        availableMemoryMb = availableMb,
        cpuCores = cores,
        cpuArchitecture = arch,
        androidVersion = androidVersion,
        gpuVendor = null,
        gpuModel = null,
    )
}
