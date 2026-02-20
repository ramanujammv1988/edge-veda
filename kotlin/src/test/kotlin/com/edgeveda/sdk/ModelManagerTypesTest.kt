package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for ModelManager data classes and enums that don't require Android Context.
 *
 * Covers: DownloadProgress (computed props), ModelType (enum), DownloadableModelInfo.
 * Mirrors the Flutter gold standard DownloadProgress percentage tests.
 */
class ModelManagerTypesTest {

    // ── DownloadProgress.progress ─────────────────────────────────────────────

    @Test
    fun `progress is 0_0 when totalBytes is zero`() {
        val dp = DownloadProgress(totalBytes = 0L, downloadedBytes = 0L)
        assertEquals(0.0, dp.progress, 0.0001)
    }

    @Test
    fun `progress is 0_0 when nothing downloaded`() {
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 0L)
        assertEquals(0.0, dp.progress, 0.0001)
    }

    @Test
    fun `progress is 0_5 when half downloaded`() {
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 500L)
        assertEquals(0.5, dp.progress, 0.0001)
    }

    @Test
    fun `progress is 1_0 when fully downloaded`() {
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 1_000L)
        assertEquals(1.0, dp.progress, 0.0001)
    }

    @Test
    fun `progress uses downloadedBytes divided by totalBytes`() {
        val dp = DownloadProgress(totalBytes = 774_217_728L, downloadedBytes = 257_000_000L)
        val expected = 257_000_000.0 / 774_217_728.0
        assertEquals(expected, dp.progress, 0.0001)
    }

    // ── DownloadProgress.progressPercent ─────────────────────────────────────

    @Test
    fun `progressPercent is 0 when nothing downloaded`() {
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 0L)
        assertEquals(0, dp.progressPercent)
    }

    @Test
    fun `progressPercent is 50 when half downloaded`() {
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 500L)
        assertEquals(50, dp.progressPercent)
    }

    @Test
    fun `progressPercent is 100 when fully downloaded`() {
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 1_000L)
        assertEquals(100, dp.progressPercent)
    }

    @Test
    fun `progressPercent is 0 when totalBytes is zero`() {
        val dp = DownloadProgress(totalBytes = 0L, downloadedBytes = 0L)
        assertEquals(0, dp.progressPercent)
    }

    @Test
    fun `progressPercent is integer truncation of progress times 100`() {
        // 333 / 1000 = 0.333 → 33%
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 333L)
        assertEquals(33, dp.progressPercent)
    }

    // ── DownloadProgress fields ────────────────────────────────────────────────

    @Test
    fun `DownloadProgress stores totalBytes and downloadedBytes`() {
        val dp = DownloadProgress(totalBytes = 5_000L, downloadedBytes = 2_500L)
        assertEquals(5_000L, dp.totalBytes)
        assertEquals(2_500L, dp.downloadedBytes)
    }

    @Test
    fun `DownloadProgress optional fields default to null`() {
        val dp = DownloadProgress(totalBytes = 1_000L, downloadedBytes = 500L)
        assertNull(dp.speedBytesPerSecond)
        assertNull(dp.estimatedSecondsRemaining)
    }

    @Test
    fun `DownloadProgress stores optional speed and remaining`() {
        val dp = DownloadProgress(
            totalBytes = 1_000L,
            downloadedBytes = 500L,
            speedBytesPerSecond = 1024.0,
            estimatedSecondsRemaining = 30
        )
        assertEquals(1024.0, dp.speedBytesPerSecond!!, 0.001)
        assertEquals(30, dp.estimatedSecondsRemaining)
    }

    // ── ModelType enum ────────────────────────────────────────────────────────

    @Test
    fun `ModelType has exactly five variants`() =
        assertEquals(5, ModelType.entries.size)

    @Test
    fun `ModelType contains TEXT`() =
        assertNotNull(ModelType.TEXT)

    @Test
    fun `ModelType contains VISION`() =
        assertNotNull(ModelType.VISION)

    @Test
    fun `ModelType contains MMPROJ`() =
        assertNotNull(ModelType.MMPROJ)

    @Test
    fun `ModelType contains WHISPER`() =
        assertNotNull(ModelType.WHISPER)

    @Test
    fun `ModelType contains EMBEDDING`() =
        assertNotNull(ModelType.EMBEDDING)

    @Test
    fun `ModelType values are distinct`() {
        val values = ModelType.entries
        assertEquals(values.size, values.toSet().size)
    }

    // ── DownloadableModelInfo ─────────────────────────────────────────────────

    @Test
    fun `DownloadableModelInfo stores id name sizeBytes and modelType`() {
        val model = DownloadableModelInfo(
            id = "test-model",
            name = "Test Model",
            sizeBytes = 1_000_000L,
            downloadUrl = "https://example.com/model.gguf",
            modelType = ModelType.TEXT
        )
        assertEquals("test-model", model.id)
        assertEquals("Test Model", model.name)
        assertEquals(1_000_000L, model.sizeBytes)
        assertEquals(ModelType.TEXT, model.modelType)
    }

    @Test
    fun `DownloadableModelInfo optional fields default to null or empty`() {
        val model = DownloadableModelInfo(
            id = "minimal-model",
            name = "Minimal",
            sizeBytes = 100L,
            downloadUrl = "https://example.com/m.gguf"
        )
        assertNull(model.description)
        assertNull(model.checksum)
        assertNull(model.quantization)
        assertNull(model.modelType)
        assertEquals("GGUF", model.format) // default value
    }

    @Test
    fun `DownloadableModelInfo data class equality works`() {
        val a = DownloadableModelInfo(
            id = "model-a",
            name = "Model A",
            sizeBytes = 500L,
            downloadUrl = "https://example.com/a.gguf",
            modelType = ModelType.WHISPER
        )
        val b = DownloadableModelInfo(
            id = "model-a",
            name = "Model A",
            sizeBytes = 500L,
            downloadUrl = "https://example.com/a.gguf",
            modelType = ModelType.WHISPER
        )
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun `DownloadableModelInfo copy creates modified instance`() {
        val original = DownloadableModelInfo(
            id = "model-x",
            name = "Model X",
            sizeBytes = 1_000L,
            downloadUrl = "https://example.com/x.gguf",
            modelType = ModelType.TEXT
        )
        val copy = original.copy(modelType = ModelType.EMBEDDING)
        assertEquals("model-x", copy.id)
        assertEquals(ModelType.EMBEDDING, copy.modelType)
        assertEquals(ModelType.TEXT, original.modelType) // original unchanged
    }
}
