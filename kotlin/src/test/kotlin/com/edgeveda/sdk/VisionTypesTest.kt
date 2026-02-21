package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for Vision data types: VisionConfig, VisionGenerationParams,
 * VisionTimings, VisionResult, and FrameData.
 *
 * Key focus: FrameData's custom equals/hashCode for ByteArray content comparison,
 * and VisionTimings stored field values.
 */
class VisionTypesTest {

    // ── VisionConfig defaults ─────────────────────────────────────────────────

    @Test
    fun `VisionConfig stores modelPath and mmprojPath`() {
        val cfg = VisionConfig(
            modelPath = "/data/model.gguf",
            mmprojPath = "/data/mmproj.gguf"
        )
        assertEquals("/data/model.gguf", cfg.modelPath)
        assertEquals("/data/model.gguf", cfg.modelPath)
        assertEquals("/data/mmproj.gguf", cfg.mmprojPath)
    }

    @Test
    fun `VisionConfig default numThreads is 4`() {
        val cfg = VisionConfig(modelPath = "/m.gguf", mmprojPath = "/p.gguf")
        assertEquals(4, cfg.numThreads)
    }

    @Test
    fun `VisionConfig default contextSize is 2048`() {
        val cfg = VisionConfig(modelPath = "/m.gguf", mmprojPath = "/p.gguf")
        assertEquals(2048, cfg.contextSize)
    }

    @Test
    fun `VisionConfig default gpuLayers is minus 1`() {
        val cfg = VisionConfig(modelPath = "/m.gguf", mmprojPath = "/p.gguf")
        assertEquals(-1, cfg.gpuLayers)
    }

    @Test
    fun `VisionConfig default memoryLimitBytes is 0`() {
        val cfg = VisionConfig(modelPath = "/m.gguf", mmprojPath = "/p.gguf")
        assertEquals(0L, cfg.memoryLimitBytes)
    }

    @Test
    fun `VisionConfig default useMmap is true`() {
        val cfg = VisionConfig(modelPath = "/m.gguf", mmprojPath = "/p.gguf")
        assertTrue(cfg.useMmap)
    }

    @Test
    fun `VisionConfig accepts custom numThreads`() {
        val cfg = VisionConfig(modelPath = "/m.gguf", mmprojPath = "/p.gguf", numThreads = 8)
        assertEquals(8, cfg.numThreads)
    }

    @Test
    fun `VisionConfig data class equality`() {
        val a = VisionConfig("/m.gguf", "/p.gguf")
        val b = VisionConfig("/m.gguf", "/p.gguf")
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    // ── VisionGenerationParams defaults ───────────────────────────────────────

    @Test
    fun `VisionGenerationParams default maxTokens is 100`() {
        val params = VisionGenerationParams()
        assertEquals(100, params.maxTokens)
    }

    @Test
    fun `VisionGenerationParams default temperature is 0_3f`() {
        val params = VisionGenerationParams()
        assertEquals(0.3f, params.temperature, 0.001f)
    }

    @Test
    fun `VisionGenerationParams default topP is 0_9f`() {
        val params = VisionGenerationParams()
        assertEquals(0.9f, params.topP, 0.001f)
    }

    @Test
    fun `VisionGenerationParams default topK is 40`() {
        val params = VisionGenerationParams()
        assertEquals(40, params.topK)
    }

    @Test
    fun `VisionGenerationParams default repeatPenalty is 1_1f`() {
        val params = VisionGenerationParams()
        assertEquals(1.1f, params.repeatPenalty, 0.001f)
    }

    @Test
    fun `VisionGenerationParams accepts custom values`() {
        val params = VisionGenerationParams(
            maxTokens = 512,
            temperature = 0.7f,
            topP = 0.95f,
            topK = 50,
            repeatPenalty = 1.05f
        )
        assertEquals(512, params.maxTokens)
        assertEquals(0.7f, params.temperature, 0.001f)
    }

    @Test
    fun `VisionGenerationParams data class copy works`() {
        val original = VisionGenerationParams()
        val copy = original.copy(maxTokens = 256)
        assertEquals(256, copy.maxTokens)
        assertEquals(100, original.maxTokens) // original unchanged
    }

    // ── VisionTimings ─────────────────────────────────────────────────────────

    @Test
    fun `VisionTimings stores all timing fields`() {
        val timings = VisionTimings(
            modelLoadMs = 200.0,
            imageEncodeMs = 50.0,
            promptEvalMs = 30.0,
            decodeMs = 150.0,
            promptTokens = 10,
            generatedTokens = 80,
            totalMs = 430.0,
            tokensPerSecond = 186.0
        )
        assertEquals(200.0, timings.modelLoadMs, 0.001)
        assertEquals(50.0, timings.imageEncodeMs, 0.001)
        assertEquals(30.0, timings.promptEvalMs, 0.001)
        assertEquals(150.0, timings.decodeMs, 0.001)
        assertEquals(10, timings.promptTokens)
        assertEquals(80, timings.generatedTokens)
        assertEquals(430.0, timings.totalMs, 0.001)
        assertEquals(186.0, timings.tokensPerSecond, 0.001)
    }

    @Test
    fun `VisionTimings tokensPerSecond is stored field not computed`() {
        // tokensPerSecond is a stored data class field — provide it explicitly
        val timings = VisionTimings(
            modelLoadMs = 0.0,
            imageEncodeMs = 0.0,
            promptEvalMs = 0.0,
            decodeMs = 1000.0,
            promptTokens = 5,
            generatedTokens = 50,
            totalMs = 1000.0,
            tokensPerSecond = 50.0
        )
        assertEquals(50.0, timings.tokensPerSecond, 0.001)
    }

    @Test
    fun `VisionTimings data class equality`() {
        val a = VisionTimings(1.0, 2.0, 3.0, 4.0, 5, 6, 10.0, 60.0)
        val b = VisionTimings(1.0, 2.0, 3.0, 4.0, 5, 6, 10.0, 60.0)
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    // ── VisionResult ──────────────────────────────────────────────────────────

    @Test
    fun `VisionResult stores description and timings`() {
        val timings = VisionTimings(0.0, 0.0, 0.0, 0.0, 0, 0, 0.0, 0.0)
        val result = VisionResult(description = "A cat sitting on a mat", timings = timings)
        assertEquals("A cat sitting on a mat", result.description)
        assertEquals(timings, result.timings)
    }

    @Test
    fun `VisionResult data class equality`() {
        val timings = VisionTimings(1.0, 2.0, 3.0, 4.0, 5, 10, 15.0, 100.0)
        val a = VisionResult("description", timings)
        val b = VisionResult("description", timings)
        assertEquals(a, b)
    }

    // ── FrameData custom equals and hashCode ─────────────────────────────────

    @Test
    fun `FrameData with same ByteArray content are equal`() {
        val a = FrameData(byteArrayOf(1, 2, 3, 4), width = 2, height = 2)
        val b = FrameData(byteArrayOf(1, 2, 3, 4), width = 2, height = 2)
        assertEquals("Same content must be equal", a, b)
    }

    @Test
    fun `FrameData with same content have same hashCode`() {
        val a = FrameData(byteArrayOf(10, 20, 30), width = 1, height = 1)
        val b = FrameData(byteArrayOf(10, 20, 30), width = 1, height = 1)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun `FrameData with different ByteArray content are not equal`() {
        val a = FrameData(byteArrayOf(1, 2, 3), width = 1, height = 1)
        val b = FrameData(byteArrayOf(4, 5, 6), width = 1, height = 1)
        assertNotEquals("Different content must not be equal", a, b)
    }

    @Test
    fun `FrameData with same content but different width are not equal`() {
        val a = FrameData(byteArrayOf(1, 2, 3, 4, 5, 6), width = 2, height = 3)
        val b = FrameData(byteArrayOf(1, 2, 3, 4, 5, 6), width = 3, height = 2)
        assertNotEquals(a, b)
    }

    @Test
    fun `FrameData with same content but different height are not equal`() {
        val a = FrameData(byteArrayOf(1, 2, 3, 4), width = 2, height = 2)
        val b = FrameData(byteArrayOf(1, 2, 3, 4), width = 2, height = 1)
        assertNotEquals(a, b)
    }

    @Test
    fun `FrameData same reference equals itself`() {
        val frame = FrameData(byteArrayOf(1, 2, 3), width = 1, height = 1)
        assertEquals(frame, frame)
    }

    @Test
    fun `FrameData does not equal null`() {
        val frame = FrameData(byteArrayOf(1, 2, 3), width = 1, height = 1)
        assertNotEquals(frame, null)
    }

    @Test
    fun `FrameData does not equal object of different type`() {
        val frame = FrameData(byteArrayOf(1, 2, 3), width = 1, height = 1)
        assertNotEquals(frame, "not a FrameData")
    }

    @Test
    fun `FrameData stores width and height correctly`() {
        val frame = FrameData(ByteArray(640 * 480 * 3), width = 640, height = 480)
        assertEquals(640, frame.width)
        assertEquals(480, frame.height)
    }

    @Test
    fun `FrameData two instances with same large payload are equal`() {
        val size = 100 * 100 * 3 // 100x100 RGB
        val pixelData = ByteArray(size) { (it % 256).toByte() }
        val a = FrameData(pixelData.clone(), width = 100, height = 100)
        val b = FrameData(pixelData.clone(), width = 100, height = 100)
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }
}
