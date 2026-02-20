package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for ModelRegistry.
 *
 * Verifies model counts, query functions, ModelType assignments, and ID uniqueness.
 * Mirrors the Flutter gold standard ModelRegistry group in edge_veda_test.dart.
 */
class ModelRegistryTest {

    // ── Model counts ──────────────────────────────────────────────────────────

    @Test
    fun `getAllTextModels returns 5 models`() =
        assertEquals(5, ModelRegistry.getAllTextModels().size)

    @Test
    fun `getVisionModels returns 1 model`() =
        assertEquals(1, ModelRegistry.getVisionModels().size)

    @Test
    fun `getWhisperModels returns 2 models`() =
        assertEquals(2, ModelRegistry.getWhisperModels().size)

    @Test
    fun `getEmbeddingModels returns 1 model`() =
        assertEquals(1, ModelRegistry.getEmbeddingModels().size)

    @Test
    fun `total model count across all categories is 10`() {
        val all = ModelRegistry.getAllTextModels() +
                  ModelRegistry.getVisionModels() +
                  listOf(ModelRegistry.smolvlm2_500m_mmproj) +
                  ModelRegistry.getWhisperModels() +
                  ModelRegistry.getEmbeddingModels()
        assertEquals(10, all.size)
    }

    // ── getModelById ──────────────────────────────────────────────────────────

    @Test
    fun `getModelById returns model for known text model id`() {
        val model = ModelRegistry.getModelById("llama-3.2-1b-instruct-q4")
        assertNotNull(model)
        assertEquals("Llama 3.2 1B Instruct", model!!.name)
    }

    @Test
    fun `getModelById returns model for known whisper model id`() {
        val model = ModelRegistry.getModelById("whisper-tiny-en")
        assertNotNull(model)
        assertEquals(ModelType.WHISPER, model!!.modelType)
    }

    @Test
    fun `getModelById returns model for vision model id`() {
        val model = ModelRegistry.getModelById("smolvlm2-500m-video-instruct-q8")
        assertNotNull(model)
        assertEquals(ModelType.VISION, model!!.modelType)
    }

    @Test
    fun `getModelById returns model for mmproj id`() {
        val model = ModelRegistry.getModelById("smolvlm2-500m-mmproj-f16")
        assertNotNull(model)
        assertEquals(ModelType.MMPROJ, model!!.modelType)
    }

    @Test
    fun `getModelById returns model for embedding model id`() {
        val model = ModelRegistry.getModelById("all-minilm-l6-v2-f16")
        assertNotNull(model)
        assertEquals(ModelType.EMBEDDING, model!!.modelType)
    }

    @Test
    fun `getModelById returns null for unknown id`() =
        assertNull(ModelRegistry.getModelById("does-not-exist"))

    @Test
    fun `getModelById returns null for empty string`() =
        assertNull(ModelRegistry.getModelById(""))

    // ── getMmprojForModel ─────────────────────────────────────────────────────

    @Test
    fun `getMmprojForModel returns projector for smolvlm2_500m`() {
        val mmproj = ModelRegistry.getMmprojForModel(ModelRegistry.smolvlm2_500m.id)
        assertNotNull(mmproj)
        assertEquals(ModelType.MMPROJ, mmproj!!.modelType)
    }

    @Test
    fun `getMmprojForModel returns null for text model`() {
        val mmproj = ModelRegistry.getMmprojForModel(ModelRegistry.llama32_1b.id)
        assertNull(mmproj)
    }

    @Test
    fun `getMmprojForModel returns null for unknown id`() =
        assertNull(ModelRegistry.getMmprojForModel("unknown-model-id"))

    // ── ModelType assignments ─────────────────────────────────────────────────

    @Test
    fun `llama32_1b has TEXT model type`() =
        assertEquals(ModelType.TEXT, ModelRegistry.llama32_1b.modelType)

    @Test
    fun `phi35_mini has TEXT model type`() =
        assertEquals(ModelType.TEXT, ModelRegistry.phi35_mini.modelType)

    @Test
    fun `gemma2_2b has TEXT model type`() =
        assertEquals(ModelType.TEXT, ModelRegistry.gemma2_2b.modelType)

    @Test
    fun `tinyLlama has TEXT model type`() =
        assertEquals(ModelType.TEXT, ModelRegistry.tinyLlama.modelType)

    @Test
    fun `qwen3_06b has TEXT model type`() =
        assertEquals(ModelType.TEXT, ModelRegistry.qwen3_06b.modelType)

    @Test
    fun `smolvlm2_500m has VISION model type`() =
        assertEquals(ModelType.VISION, ModelRegistry.smolvlm2_500m.modelType)

    @Test
    fun `smolvlm2_500m_mmproj has MMPROJ model type`() =
        assertEquals(ModelType.MMPROJ, ModelRegistry.smolvlm2_500m_mmproj.modelType)

    @Test
    fun `whisperTinyEn has WHISPER model type`() =
        assertEquals(ModelType.WHISPER, ModelRegistry.whisperTinyEn.modelType)

    @Test
    fun `whisperBaseEn has WHISPER model type`() =
        assertEquals(ModelType.WHISPER, ModelRegistry.whisperBaseEn.modelType)

    @Test
    fun `allMiniLmL6V2 has EMBEDDING model type`() =
        assertEquals(ModelType.EMBEDDING, ModelRegistry.allMiniLmL6V2.modelType)

    // ── Model descriptor invariants ───────────────────────────────────────────

    @Test
    fun `all models have non-empty ids`() {
        val all = ModelRegistry.getAllTextModels() +
                  ModelRegistry.getVisionModels() +
                  listOf(ModelRegistry.smolvlm2_500m_mmproj) +
                  ModelRegistry.getWhisperModels() +
                  ModelRegistry.getEmbeddingModels()
        all.forEach { model ->
            assertTrue("Model '${model.name}' has empty id", model.id.isNotEmpty())
        }
    }

    @Test
    fun `all models have non-empty names`() {
        val all = ModelRegistry.getAllTextModels() +
                  ModelRegistry.getVisionModels() +
                  listOf(ModelRegistry.smolvlm2_500m_mmproj) +
                  ModelRegistry.getWhisperModels() +
                  ModelRegistry.getEmbeddingModels()
        all.forEach { model ->
            assertTrue("Model '${model.id}' has empty name", model.name.isNotEmpty())
        }
    }

    @Test
    fun `all models have positive sizeBytes`() {
        val all = ModelRegistry.getAllTextModels() +
                  ModelRegistry.getVisionModels() +
                  listOf(ModelRegistry.smolvlm2_500m_mmproj) +
                  ModelRegistry.getWhisperModels() +
                  ModelRegistry.getEmbeddingModels()
        all.forEach { model ->
            assertTrue("Model '${model.id}' sizeBytes must be > 0", model.sizeBytes > 0)
        }
    }

    @Test
    fun `all models have non-empty downloadUrl`() {
        val all = ModelRegistry.getAllTextModels() +
                  ModelRegistry.getVisionModels() +
                  listOf(ModelRegistry.smolvlm2_500m_mmproj) +
                  ModelRegistry.getWhisperModels() +
                  ModelRegistry.getEmbeddingModels()
        all.forEach { model ->
            assertTrue("Model '${model.id}' has empty downloadUrl", model.downloadUrl.isNotEmpty())
        }
    }

    @Test
    fun `all model ids are unique`() {
        val all = ModelRegistry.getAllTextModels() +
                  ModelRegistry.getVisionModels() +
                  listOf(ModelRegistry.smolvlm2_500m_mmproj) +
                  ModelRegistry.getWhisperModels() +
                  ModelRegistry.getEmbeddingModels()
        val uniqueIds = all.map { it.id }.toSet()
        assertEquals(
            "Duplicate model IDs found",
            all.size,
            uniqueIds.size
        )
    }

    @Test
    fun `all text models are not included in whisper or embedding query results`() {
        val textIds = ModelRegistry.getAllTextModels().map { it.id }.toSet()
        val whisperIds = ModelRegistry.getWhisperModels().map { it.id }.toSet()
        val embeddingIds = ModelRegistry.getEmbeddingModels().map { it.id }.toSet()
        assertTrue((textIds intersect whisperIds).isEmpty())
        assertTrue((textIds intersect embeddingIds).isEmpty())
    }

    // ── Registry model identity ────────────────────────────────────────────────

    @Test
    fun `llama32_1b id matches expected string`() =
        assertEquals("llama-3.2-1b-instruct-q4", ModelRegistry.llama32_1b.id)

    @Test
    fun `whisperTinyEn id matches expected string`() =
        assertEquals("whisper-tiny-en", ModelRegistry.whisperTinyEn.id)

    @Test
    fun `whisperBaseEn id matches expected string`() =
        assertEquals("whisper-base-en", ModelRegistry.whisperBaseEn.id)

    @Test
    fun `smolvlm2_500m id matches expected string`() =
        assertEquals("smolvlm2-500m-video-instruct-q8", ModelRegistry.smolvlm2_500m.id)

    @Test
    fun `allMiniLmL6V2 id matches expected string`() =
        assertEquals("all-minilm-l6-v2-f16", ModelRegistry.allMiniLmL6V2.id)
}
