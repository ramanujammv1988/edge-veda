import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class NativeErrorCodeTests: XCTestCase {

    // MARK: - from(code:) round-trips

    func testFromCodeOk() {
        XCTAssertEqual(NativeErrorCode.from(code: 0), .ok)
    }

    func testFromCodeInvalidParameter() {
        XCTAssertEqual(NativeErrorCode.from(code: -1), .invalidParameter)
    }

    func testFromCodeOutOfMemory() {
        XCTAssertEqual(NativeErrorCode.from(code: -2), .outOfMemory)
    }

    func testFromCodeModelLoadFailed() {
        XCTAssertEqual(NativeErrorCode.from(code: -3), .modelLoadFailed)
    }

    func testFromCodeBackendInitFailed() {
        XCTAssertEqual(NativeErrorCode.from(code: -4), .backendInitFailed)
    }

    func testFromCodeInferenceFailed() {
        XCTAssertEqual(NativeErrorCode.from(code: -5), .inferenceFailed)
    }

    func testFromCodeContextInvalid() {
        XCTAssertEqual(NativeErrorCode.from(code: -6), .contextInvalid)
    }

    func testFromCodeStreamEnded() {
        XCTAssertEqual(NativeErrorCode.from(code: -7), .streamEnded)
    }

    func testFromCodeNotImplemented() {
        XCTAssertEqual(NativeErrorCode.from(code: -8), .notImplemented)
    }

    func testFromCodeMemoryLimitExceeded() {
        XCTAssertEqual(NativeErrorCode.from(code: -9), .memoryLimitExceeded)
    }

    func testFromCodeUnsupportedBackend() {
        XCTAssertEqual(NativeErrorCode.from(code: -10), .unsupportedBackend)
    }

    func testFromCodeUnknown() {
        XCTAssertEqual(NativeErrorCode.from(code: -999), .unknown)
    }

    func testUnrecognisedCodeMapsToUnknown() {
        XCTAssertEqual(NativeErrorCode.from(code: -42), .unknown)
    }

    // MARK: - toEdgeVedaError()

    func testOkProducesNoError() {
        XCTAssertNil(NativeErrorCode.ok.toEdgeVedaError())
    }

    func testStreamEndedProducesNoError() {
        XCTAssertNil(NativeErrorCode.streamEnded.toEdgeVedaError())
    }

    func testInvalidParameterProducesError() {
        XCTAssertNotNil(NativeErrorCode.invalidParameter.toEdgeVedaError())
    }

    func testOutOfMemoryProducesOutOfMemoryError() {
        let error = NativeErrorCode.outOfMemory.toEdgeVedaError()
        XCTAssertNotNil(error)
        if case .outOfMemory = error! {
            // correct
        } else {
            XCTFail("Expected EdgeVedaError.outOfMemory, got \(String(describing: error))")
        }
    }

    func testModelLoadFailedProducesError() {
        XCTAssertNotNil(NativeErrorCode.modelLoadFailed.toEdgeVedaError())
    }

    func testInferenceFailedProducesError() {
        XCTAssertNotNil(NativeErrorCode.inferenceFailed.toEdgeVedaError())
    }

    // MARK: - throwIfError()

    func testOkDoesNotThrow() {
        XCTAssertNoThrow(try NativeErrorCode.ok.throwIfError())
    }

    func testStreamEndedDoesNotThrow() {
        XCTAssertNoThrow(try NativeErrorCode.streamEnded.throwIfError())
    }

    func testInferenceFailedThrows() {
        XCTAssertThrowsError(try NativeErrorCode.inferenceFailed.throwIfError())
    }
}
