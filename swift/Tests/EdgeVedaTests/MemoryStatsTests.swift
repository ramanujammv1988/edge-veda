import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class MemoryStatsTests: XCTestCase {

    // MARK: - MemoryStats.usagePercent

    func testUsagePercentCalculation() {
        let stats = MemoryStats(
            currentBytes: 500_000_000,
            peakBytes: 0,
            limitBytes: 1_000_000_000,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertEqual(stats.usagePercent, 0.5, accuracy: 0.001)
    }

    func testZeroLimitReturnsZeroUsagePercent() {
        let stats = MemoryStats(
            currentBytes: 500_000_000,
            peakBytes: 0,
            limitBytes: 0,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertEqual(stats.usagePercent, 0.0, accuracy: 0.001)
    }

    func testFullUsageReturnsOne() {
        let stats = MemoryStats(
            currentBytes: 1_000_000_000,
            peakBytes: 0,
            limitBytes: 1_000_000_000,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertEqual(stats.usagePercent, 1.0, accuracy: 0.001)
    }

    func testOverLimitUsageExceedsOne() {
        let stats = MemoryStats(
            currentBytes: 1_200_000_000,
            peakBytes: 0,
            limitBytes: 1_000_000_000,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertGreaterThan(stats.usagePercent, 1.0)
    }

    // MARK: - MemoryStats.isHighPressure

    func testIsHighPressureFalseBelowThreshold() {
        let stats = MemoryStats(
            currentBytes: 700_000_000,
            peakBytes: 0,
            limitBytes: 1_000_000_000,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertFalse(stats.isHighPressure)
    }

    func testIsHighPressureTrueAboveThreshold() {
        let stats = MemoryStats(
            currentBytes: 850_000_000,
            peakBytes: 0,
            limitBytes: 1_000_000_000,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertTrue(stats.isHighPressure)
        XCTAssertFalse(stats.isCritical)
    }

    // MARK: - MemoryStats.isCritical

    func testIsCriticalFalseBelowThreshold() {
        let stats = MemoryStats(
            currentBytes: 850_000_000,
            peakBytes: 0,
            limitBytes: 1_000_000_000,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertFalse(stats.isCritical)
    }

    func testIsCriticalTrueAboveThreshold() {
        let stats = MemoryStats(
            currentBytes: 950_000_000,
            peakBytes: 0,
            limitBytes: 1_000_000_000,
            modelBytes: 0,
            contextBytes: 0
        )
        XCTAssertTrue(stats.isCritical)
        XCTAssertTrue(stats.isHighPressure)
    }

    // MARK: - MemoryStats stored properties

    func testStoredProperties() {
        let stats = MemoryStats(
            currentBytes: 100,
            peakBytes: 200,
            limitBytes: 1000,
            modelBytes: 80,
            contextBytes: 20
        )
        XCTAssertEqual(stats.currentBytes, 100)
        XCTAssertEqual(stats.peakBytes, 200)
        XCTAssertEqual(stats.limitBytes, 1000)
        XCTAssertEqual(stats.modelBytes, 80)
        XCTAssertEqual(stats.contextBytes, 20)
    }

    // MARK: - MemoryPressureEvent

    func testMemoryPressureEventStoredProperties() {
        let timestamp = Date()
        let event = MemoryPressureEvent(
            currentBytes: 800_000_000,
            limitBytes: 1_000_000_000,
            pressureRatio: 0.8,
            timestamp: timestamp
        )
        XCTAssertEqual(event.currentBytes, 800_000_000)
        XCTAssertEqual(event.limitBytes, 1_000_000_000)
        XCTAssertEqual(event.pressureRatio, 0.8, accuracy: 0.001)
        XCTAssertEqual(event.timestamp, timestamp)
    }

    func testMemoryPressureEventHighRatio() {
        let event = MemoryPressureEvent(
            currentBytes: 950_000_000,
            limitBytes: 1_000_000_000,
            pressureRatio: 0.95,
            timestamp: Date()
        )
        XCTAssertGreaterThan(event.pressureRatio, 0.9)
    }
}
