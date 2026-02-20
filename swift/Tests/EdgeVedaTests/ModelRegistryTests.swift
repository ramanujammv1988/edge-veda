import XCTest
@testable import EdgeVeda

private extension Array where Element: Hashable {
    func asSet() -> Set<Element> { Set(self) }
}

@available(iOS 15.0, macOS 12.0, *)
final class ModelRegistryTests: XCTestCase {

    // MARK: - Model counts (Flutter parity)

    func testGetAllModelsReturnsFiveTextModels() {
        XCTAssertEqual(ModelRegistry.getAllModels().count, 5)
    }

    func testGetVisionModelsReturnsOne() {
        XCTAssertEqual(ModelRegistry.getVisionModels().count, 1)
    }

    func testGetWhisperModelsReturnsTwo() {
        XCTAssertEqual(ModelRegistry.getWhisperModels().count, 2)
    }

    func testGetEmbeddingModelsReturnsOne() {
        XCTAssertEqual(ModelRegistry.getEmbeddingModels().count, 1)
    }

    func testTotalModelCountIsTen() {
        let total = ModelRegistry.getAllModels().count
            + ModelRegistry.getVisionModels().count
            + 1 // smolvlm2_500m_mmproj is a separate static, not in getVisionModels()
            + ModelRegistry.getWhisperModels().count
            + ModelRegistry.getEmbeddingModels().count
        XCTAssertEqual(total, 10)
    }

    // MARK: - getModelById (Flutter parity)

    func testGetModelByIdFindsLlama() {
        XCTAssertNotNil(ModelRegistry.getModelById("llama-3.2-1b-instruct-q4"))
    }

    func testGetModelByIdLlamaNameContainsLlama() {
        let model = ModelRegistry.getModelById("llama-3.2-1b-instruct-q4")
        XCTAssertTrue(model?.name.contains("Llama") == true)
    }

    func testGetModelByIdReturnsNilForUnknown() {
        XCTAssertNil(ModelRegistry.getModelById("does-not-exist"))
    }

    // MARK: - getMmprojForModel

    func testGetMmprojForSmolvlmIsNonNil() {
        XCTAssertNotNil(ModelRegistry.getMmprojForModel("smolvlm2-500m-video-instruct-q8"))
    }

    func testGetMmprojForTextModelIsNil() {
        XCTAssertNil(ModelRegistry.getMmprojForModel("llama-3.2-1b-instruct-q4"))
    }

    // MARK: - Model types (only for explicitly typed models)

    func testQwen3ModelTypeIsText() {
        XCTAssertEqual(ModelRegistry.qwen3_06b.modelType, .text)
    }

    func testWhisperTinyEnModelTypeIsWhisper() {
        XCTAssertEqual(ModelRegistry.whisperTinyEn.modelType, .whisper)
    }

    func testWhisperBaseEnModelTypeIsWhisper() {
        XCTAssertEqual(ModelRegistry.whisperBaseEn.modelType, .whisper)
    }

    func testAllMiniLmModelTypeIsEmbedding() {
        XCTAssertEqual(ModelRegistry.allMiniLmL6V2.modelType, .embedding)
    }

    // MARK: - Data integrity

    func testAllModelIdsAreUnique() {
        let all = ModelRegistry.getAllModels()
            + ModelRegistry.getVisionModels()
            + [ModelRegistry.smolvlm2_500m_mmproj]
            + ModelRegistry.getWhisperModels()
            + ModelRegistry.getEmbeddingModels()
        XCTAssertEqual(all.count, all.map(\.id).asSet().count,
                       "Duplicate model IDs detected")
    }

    func testAllModelsHaveNonEmptyId() {
        let all = ModelRegistry.getAllModels()
            + ModelRegistry.getVisionModels()
            + [ModelRegistry.smolvlm2_500m_mmproj]
            + ModelRegistry.getWhisperModels()
            + ModelRegistry.getEmbeddingModels()
        for model in all {
            XCTAssertFalse(model.id.isEmpty, "Model '\(model.name)' has empty id")
        }
    }

    func testAllModelsHaveNonEmptyName() {
        let all = ModelRegistry.getAllModels()
            + ModelRegistry.getVisionModels()
            + [ModelRegistry.smolvlm2_500m_mmproj]
            + ModelRegistry.getWhisperModels()
            + ModelRegistry.getEmbeddingModels()
        for model in all {
            XCTAssertFalse(model.name.isEmpty, "Model '\(model.id)' has empty name")
        }
    }

    func testAllModelsHavePositiveSizeBytes() {
        let all = ModelRegistry.getAllModels()
            + ModelRegistry.getVisionModels()
            + [ModelRegistry.smolvlm2_500m_mmproj]
            + ModelRegistry.getWhisperModels()
            + ModelRegistry.getEmbeddingModels()
        for model in all {
            XCTAssertGreaterThan(model.sizeBytes, 0,
                                 "Model '\(model.id)' has non-positive sizeBytes")
        }
    }

    func testAllModelsHaveHttpsDownloadUrl() {
        let all = ModelRegistry.getAllModels()
            + ModelRegistry.getVisionModels()
            + [ModelRegistry.smolvlm2_500m_mmproj]
            + ModelRegistry.getWhisperModels()
            + ModelRegistry.getEmbeddingModels()
        for model in all {
            XCTAssertTrue(model.downloadUrl.hasPrefix("https://"),
                          "Model '\(model.id)' download URL does not start with https://")
        }
    }

    // MARK: - getModelsWithinBudget

    func testBudgetZeroReturnsEmpty() {
        XCTAssertTrue(ModelRegistry.getModelsWithinBudget(0).isEmpty)
    }

    func testBudgetMaxReturnsAllTextModels() {
        XCTAssertEqual(ModelRegistry.getModelsWithinBudget(Int64.max).count, 5)
    }

    func testBudgetResultIsSortedAscending() {
        let models = ModelRegistry.getModelsWithinBudget(Int64.max)
        let sizes = models.map(\.sizeBytes)
        XCTAssertEqual(sizes, sizes.sorted(),
                       "getModelsWithinBudget result should be sorted by sizeBytes ascending")
    }

    // MARK: - getRecommendedModel

    func testRecommendedModelIsInTextModelList() {
        let recommended = ModelRegistry.getRecommendedModel()
        let textModels = ModelRegistry.getAllModels()
        XCTAssertTrue(textModels.contains { $0.id == recommended.id },
                      "Recommended model '\(recommended.id)' is not in text model list")
    }
}
