import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class VersionTests: XCTestCase {

    func testVersionIsNonEmpty() {
        XCTAssertFalse(EdgeVedaVersion.version.isEmpty)
    }

    func testVersionContainsDot() {
        XCTAssertTrue(EdgeVedaVersion.version.contains("."))
    }

    func testGetVersionMatchesVersionConstant() {
        XCTAssertEqual(EdgeVeda.getVersion(), EdgeVedaVersion.version)
    }
}
