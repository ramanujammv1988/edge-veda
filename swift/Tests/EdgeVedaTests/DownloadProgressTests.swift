import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class DownloadProgressTests: XCTestCase {

    // MARK: - DownloadProgress computed properties

    func testProgressFraction() {
        let p = DownloadProgress(totalBytes: 1000, downloadedBytes: 500)
        XCTAssertEqual(p.progress, 0.5, accuracy: 0.001)
    }

    func testProgressPercent() {
        let p = DownloadProgress(totalBytes: 1000, downloadedBytes: 500)
        XCTAssertEqual(p.progressPercent, 50)
    }

    func testZeroTotalBytesReturnsZeroProgress() {
        let p = DownloadProgress(totalBytes: 0, downloadedBytes: 0)
        XCTAssertEqual(p.progress, 0.0, accuracy: 0.001)
    }

    func testZeroTotalBytesReturnsZeroProgressPercent() {
        let p = DownloadProgress(totalBytes: 0, downloadedBytes: 0)
        XCTAssertEqual(p.progressPercent, 0)
    }

    func testCompleteDownloadProgressIsOne() {
        let p = DownloadProgress(totalBytes: 1000, downloadedBytes: 1000)
        XCTAssertEqual(p.progress, 1.0, accuracy: 0.001)
    }

    func testCompleteDownloadProgressPercentIs100() {
        let p = DownloadProgress(totalBytes: 1000, downloadedBytes: 1000)
        XCTAssertEqual(p.progressPercent, 100)
    }

    func testProgressIsWithinRangeForNormalDownload() {
        let p = DownloadProgress(totalBytes: 1000, downloadedBytes: 750)
        XCTAssertGreaterThanOrEqual(p.progress, 0.0)
        XCTAssertLessThanOrEqual(p.progress, 1.0)
    }

    // MARK: - DownloadableModelInfo fields (Flutter parity)

    func testLlama32IdContainsLlama() {
        XCTAssertTrue(ModelRegistry.llama32_1b.id.contains("llama"))
    }

    func testLlama32SizeBytesIsPositive() {
        XCTAssertGreaterThan(ModelRegistry.llama32_1b.sizeBytes, 0)
    }

    func testLlama32DownloadUrlStartsWithHttps() {
        XCTAssertTrue(ModelRegistry.llama32_1b.downloadUrl.hasPrefix("https://"))
    }

    func testSmolvlm2MmprojFormatIsGGUF() {
        XCTAssertEqual(ModelRegistry.smolvlm2_500m_mmproj.format, "GGUF")
    }

    func testWhisperTinyEnModelTypeIsWhisper() {
        XCTAssertEqual(ModelRegistry.whisperTinyEn.modelType, .whisper)
    }
}
