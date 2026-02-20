package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for ModelAdvisor top-level functions: estimateModelMemory and recommendModels.
 *
 * detectDeviceCapabilities() requires Android Context and is not tested here (needs Robolectric).
 * All tests here are pure JVM — no mocks, no Android APIs.
 */
class ModelAdvisorTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun makeProfile(
        hasVulkan: Boolean = true,
        totalMemoryMb: Long = 8192L,
        availableForModelMb: Long = 4096L,
        processorCount: Int = 8,
        deviceModel: String = "Test Device",
        androidVersion: Int = 34
    ) = DeviceProfile(
        hasVulkan = hasVulkan,
        totalMemoryMb = totalMemoryMb,
        availableForModelMb = availableForModelMb,
        processorCount = processorCount,
        deviceModel = deviceModel,
        androidVersion = androidVersion
    )

    private fun makeModel(
        id: String,
        sizeBytes: Long,
        modelType: ModelType = ModelType.TEXT
    ) = DownloadableModelInfo(
        id = id,
        name = id,
        sizeBytes = sizeBytes,
        downloadUrl = "https://example.com/$id.gguf",
        modelType = modelType
    )

    // ── estimateModelMemory ───────────────────────────────────────────────────

    @Test
    fun `estimateModelMemory adds 10 percent overhead`() {
        val model = makeModel("test-model", sizeBytes = 1_000_000_000L)
        val estimate = estimateModelMemory(model)
        assertEquals(1_100_000_000L, estimate)
    }

    @Test
    fun `estimateModelMemory for 500MB model returns 550MB`() {
        val model = makeModel("small-model", sizeBytes = 500L * 1024 * 1024)
        val estimate = estimateModelMemory(model)
        val expectedBytes = (500L * 1024 * 1024 * 1.1).toLong()
        assertEquals(expectedBytes, estimate)
    }

    @Test
    fun `estimateModelMemory for zero sizeBytes returns 0`() {
        val model = makeModel("empty-model", sizeBytes = 0L)
        val estimate = estimateModelMemory(model)
        assertEquals(0L, estimate)
    }

    @Test
    fun `estimateModelMemory for small model gives overhead greater than original`() {
        val sizeBytes = 100_000_000L
        val model = makeModel("tiny-model", sizeBytes = sizeBytes)
        val estimate = estimateModelMemory(model)
        assertTrue("Estimate should be greater than original", estimate > sizeBytes)
    }

    @Test
    fun `estimateModelMemory uses sizeBytes times 1_1`() {
        val sizeBytes = 774_217_728L // llama 3.2 1B approximate size
        val model = makeModel("llama-model", sizeBytes = sizeBytes)
        val expected = (sizeBytes * 1.1).toLong()
        assertEquals(expected, estimateModelMemory(model))
    }

    // ── recommendModels — budget filtering ───────────────────────────────────

    @Test
    fun `recommendModels returns empty list when models list is empty`() {
        val profile = makeProfile()
        val result = recommendModels(profile, emptyList())
        assertTrue(result.isEmpty())
    }

    @Test
    fun `recommendModels returns empty list when profile has zero available memory`() {
        val profile = makeProfile(availableForModelMb = 0L)
        val models = listOf(makeModel("small", sizeBytes = 1_000L))
        val result = recommendModels(profile, models)
        assertTrue(result.isEmpty())
    }

    @Test
    fun `recommendModels includes model that fits within 70 percent budget`() {
        // Budget = 4096 MB * 0.7 = 2867.2 MB = ~3006 MB in bytes
        val profile = makeProfile(availableForModelMb = 4096L)
        // Use a model well within budget: 500MB → estimate 550MB
        val smallModel = makeModel("small-text", sizeBytes = 500L * 1024 * 1024)
        val result = recommendModels(profile, listOf(smallModel))
        assertTrue("Model within budget should be recommended", result.contains(smallModel))
    }

    @Test
    fun `recommendModels excludes model that exceeds 70 percent budget`() {
        // Budget = 1000 MB * 0.7 = 700 MB = 734_003_200 bytes
        val profile = makeProfile(availableForModelMb = 1000L)
        // Use a model that exceeds the budget: 800MB → estimate 880MB > 700MB
        val largeModel = makeModel("large-text", sizeBytes = 800L * 1024 * 1024)
        val result = recommendModels(profile, listOf(largeModel))
        assertFalse("Model exceeding budget should not be recommended", result.contains(largeModel))
    }

    // ── recommendModels — Vulkan filtering ───────────────────────────────────

    @Test
    fun `recommendModels excludes VISION models when Vulkan not available`() {
        val profile = makeProfile(hasVulkan = false, availableForModelMb = 8192L)
        val visionModel = makeModel("vision", sizeBytes = 400L * 1024 * 1024, modelType = ModelType.VISION)
        val result = recommendModels(profile, listOf(visionModel))
        assertFalse("VISION model must be excluded without Vulkan", result.contains(visionModel))
    }

    @Test
    fun `recommendModels excludes MMPROJ models when Vulkan not available`() {
        val profile = makeProfile(hasVulkan = false, availableForModelMb = 8192L)
        val mmprojModel = makeModel("mmproj", sizeBytes = 200L * 1024 * 1024, modelType = ModelType.MMPROJ)
        val result = recommendModels(profile, listOf(mmprojModel))
        assertFalse("MMPROJ model must be excluded without Vulkan", result.contains(mmprojModel))
    }

    @Test
    fun `recommendModels includes VISION models when Vulkan available and within budget`() {
        val profile = makeProfile(hasVulkan = true, availableForModelMb = 4096L)
        val visionModel = makeModel("vision", sizeBytes = 400L * 1024 * 1024, modelType = ModelType.VISION)
        val result = recommendModels(profile, listOf(visionModel))
        assertTrue("VISION model within budget must be included with Vulkan", result.contains(visionModel))
    }

    @Test
    fun `recommendModels includes TEXT models regardless of Vulkan support`() {
        val profile = makeProfile(hasVulkan = false, availableForModelMb = 4096L)
        val textModel = makeModel("text", sizeBytes = 500L * 1024 * 1024, modelType = ModelType.TEXT)
        val result = recommendModels(profile, listOf(textModel))
        assertTrue("TEXT model must be included even without Vulkan", result.contains(textModel))
    }

    @Test
    fun `recommendModels includes WHISPER models regardless of Vulkan support`() {
        val profile = makeProfile(hasVulkan = false, availableForModelMb = 4096L)
        val whisperModel = makeModel("whisper", sizeBytes = 74L * 1024 * 1024, modelType = ModelType.WHISPER)
        val result = recommendModels(profile, listOf(whisperModel))
        assertTrue("WHISPER model must be included even without Vulkan", result.contains(whisperModel))
    }

    @Test
    fun `recommendModels includes EMBEDDING models regardless of Vulkan support`() {
        val profile = makeProfile(hasVulkan = false, availableForModelMb = 4096L)
        val embModel = makeModel("emb", sizeBytes = 42L * 1024 * 1024, modelType = ModelType.EMBEDDING)
        val result = recommendModels(profile, listOf(embModel))
        assertTrue("EMBEDDING model must be included even without Vulkan", result.contains(embModel))
    }

    // ── recommendModels — sorting ─────────────────────────────────────────────

    @Test
    fun `recommendModels returns models sorted by sizeBytes descending`() {
        val profile = makeProfile(availableForModelMb = 8192L)
        val small = makeModel("small", sizeBytes = 100L * 1024 * 1024)
        val medium = makeModel("medium", sizeBytes = 500L * 1024 * 1024)
        val large = makeModel("large", sizeBytes = 1_000L * 1024 * 1024)

        val result = recommendModels(profile, listOf(small, large, medium))

        assertEquals(3, result.size)
        assertTrue("First must be largest", result[0].sizeBytes >= result[1].sizeBytes)
        assertTrue("Second must be >= third", result[1].sizeBytes >= result[2].sizeBytes)
    }

    @Test
    fun `recommendModels with mixed Vulkan-required and text models on Vulkan device`() {
        val profile = makeProfile(hasVulkan = true, availableForModelMb = 4096L)
        val textModel = makeModel("text", sizeBytes = 500L * 1024 * 1024, modelType = ModelType.TEXT)
        val visionModel = makeModel("vision", sizeBytes = 400L * 1024 * 1024, modelType = ModelType.VISION)

        val result = recommendModels(profile, listOf(textModel, visionModel))
        assertEquals(2, result.size)
    }

    @Test
    fun `recommendModels with mixed models on non-Vulkan device only returns non-vision models`() {
        val profile = makeProfile(hasVulkan = false, availableForModelMb = 4096L)
        val textModel = makeModel("text", sizeBytes = 500L * 1024 * 1024, modelType = ModelType.TEXT)
        val visionModel = makeModel("vision", sizeBytes = 400L * 1024 * 1024, modelType = ModelType.VISION)

        val result = recommendModels(profile, listOf(textModel, visionModel))
        assertEquals(1, result.size)
        assertTrue(result.contains(textModel))
        assertFalse(result.contains(visionModel))
    }

    // ── DeviceProfile data class ──────────────────────────────────────────────

    @Test
    fun `DeviceProfile stores all fields correctly`() {
        val profile = DeviceProfile(
            hasVulkan = true,
            totalMemoryMb = 8192L,
            availableForModelMb = 4096L,
            processorCount = 8,
            deviceModel = "Samsung Galaxy S24",
            androidVersion = 34
        )
        assertTrue(profile.hasVulkan)
        assertEquals(8192L, profile.totalMemoryMb)
        assertEquals(4096L, profile.availableForModelMb)
        assertEquals(8, profile.processorCount)
        assertEquals("Samsung Galaxy S24", profile.deviceModel)
        assertEquals(34, profile.androidVersion)
    }

    @Test
    fun `DeviceProfile data class equality`() {
        val a = makeProfile()
        val b = makeProfile()
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun `DeviceProfile with different hasVulkan values are not equal`() {
        val withVulkan = makeProfile(hasVulkan = true)
        val withoutVulkan = makeProfile(hasVulkan = false)
        assertNotEquals(withVulkan, withoutVulkan)
    }
}
