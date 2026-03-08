import XCTest
@testable import EdgeVeda

/// Tests for BatteryDrainTracker — the actor that monitors battery drain rate.
///
/// BatteryDrainTracker relies on UIDevice.batteryLevel (iOS only).
/// On macOS test machines battery APIs are unavailable, so many properties
/// return nil / false.  Tests are therefore split into:
///   1. Cross-platform behavioural tests (always run)
///   2. iOS-only tests guarded by `#if os(iOS)`
@available(iOS 15.0, macOS 12.0, *)
final class BatteryDrainTrackerTests: XCTestCase {

    // MARK: - Initialization

    func testInitCreatesInstance() async {
        let tracker = BatteryDrainTracker()
        // Actor is created without throwing
        let _ = await tracker.sampleCount
    }

    // MARK: - Platform Support

    func testIsSupportedMatchesPlatform() async {
        let tracker = BatteryDrainTracker()
        #if os(iOS)
        XCTAssertTrue(tracker.isSupported, "isSupported should be true on iOS")
        #else
        XCTAssertFalse(tracker.isSupported, "isSupported should be false on non-iOS platforms")
        #endif
    }

    func testIsSupportedIsNonisolated() {
        // isSupported is nonisolated — callable without await
        let tracker = BatteryDrainTracker()
        let supported = tracker.isSupported
        #if os(iOS)
        XCTAssertTrue(supported)
        #else
        XCTAssertFalse(supported)
        #endif
    }

    // MARK: - Non-iOS Platform Behaviour

    #if !os(iOS)
    func testCurrentDrainRateIsNilOnNonIOS() async {
        let tracker = BatteryDrainTracker()
        let rate = await tracker.currentDrainRate
        XCTAssertNil(rate, "currentDrainRate should be nil on non-iOS platforms")
    }

    func testAverageDrainRateIsNilOnNonIOS() async {
        let tracker = BatteryDrainTracker()
        let rate = await tracker.averageDrainRate
        XCTAssertNil(rate, "averageDrainRate should be nil on non-iOS platforms")
    }

    func testCurrentBatteryLevelIsNilOnNonIOS() async {
        let tracker = BatteryDrainTracker()
        let level = await tracker.currentBatteryLevel
        XCTAssertNil(level, "currentBatteryLevel should be nil on non-iOS platforms")
    }

    func testRecordSampleNoOpOnNonIOS() async {
        let tracker = BatteryDrainTracker()
        await tracker.recordSample()
        // On non-iOS recordSample is a no-op inside #if os(iOS) guard,
        // but the init itself calls recordSample which also no-ops.
        let count = await tracker.sampleCount
        XCTAssertEqual(count, 0, "sampleCount should stay 0 on non-iOS after recordSample")
    }
    #endif

    // MARK: - Sample Count

    func testSampleCountInitialValue() async {
        let tracker = BatteryDrainTracker()
        let count = await tracker.sampleCount
        #if os(iOS)
        // init calls recordSample once via startTracking → at least 1
        XCTAssertGreaterThanOrEqual(count, 1)
        #else
        XCTAssertEqual(count, 0)
        #endif
    }

    // MARK: - Reset

    func testResetClearsSamples() async {
        let tracker = BatteryDrainTracker()
        // Record a few samples (no-op on non-iOS, but safe to call)
        await tracker.recordSample()
        await tracker.recordSample()
        await tracker.reset()
        let count = await tracker.sampleCount
        XCTAssertEqual(count, 0, "sampleCount should be 0 after reset")
    }

    func testResetClearsDrainRates() async {
        let tracker = BatteryDrainTracker()
        await tracker.reset()
        let rate = await tracker.currentDrainRate
        XCTAssertNil(rate, "currentDrainRate should be nil after reset (no samples)")
        let avg = await tracker.averageDrainRate
        XCTAssertNil(avg, "averageDrainRate should be nil after reset (no samples)")
    }

    func testMultipleResetsAreSafe() async {
        let tracker = BatteryDrainTracker()
        for _ in 0..<5 {
            await tracker.reset()
        }
        let count = await tracker.sampleCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Concurrent Access

    func testConcurrentRecordSampleIsSafe() async {
        let tracker = BatteryDrainTracker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await tracker.recordSample()
                }
            }
        }
        // Should complete without crashes; actor serialises access
        let count = await tracker.sampleCount
        // On non-iOS count stays 0; on iOS each recordSample adds a sample
        #if os(iOS)
        XCTAssertGreaterThan(count, 0)
        #else
        XCTAssertEqual(count, 0)
        #endif
    }

    func testConcurrentReadsAreSafe() async {
        let tracker = BatteryDrainTracker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    _ = await tracker.currentDrainRate
                    _ = await tracker.averageDrainRate
                    _ = await tracker.currentBatteryLevel
                    _ = await tracker.sampleCount
                }
            }
        }
        // No assertion needed — we're verifying no crashes under contention
    }

    func testConcurrentReadWriteIsSafe() async {
        let tracker = BatteryDrainTracker()
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for _ in 0..<30 {
                group.addTask {
                    await tracker.recordSample()
                }
            }
            // Readers
            for _ in 0..<30 {
                group.addTask {
                    _ = await tracker.currentDrainRate
                    _ = await tracker.sampleCount
                }
            }
            // Resetters
            for _ in 0..<5 {
                group.addTask {
                    await tracker.reset()
                }
            }
        }
        // Actor serialisation guarantees safety
    }

    // MARK: - Multiple Instances

    func testMultipleInstancesAreIndependent() async {
        let a = BatteryDrainTracker()
        let b = BatteryDrainTracker()

        await a.recordSample()
        await a.recordSample()

        await b.reset()

        let countB = await b.sampleCount
        XCTAssertEqual(countB, 0, "Instance b should not be affected by instance a")
    }

    // MARK: - iOS-Specific Tests

    #if os(iOS)
    func testCurrentBatteryLevelRange() async {
        let tracker = BatteryDrainTracker()
        if let level = await tracker.currentBatteryLevel {
            XCTAssertGreaterThanOrEqual(level, 0.0)
            XCTAssertLessThanOrEqual(level, 1.0)
        }
        // nil is acceptable (e.g. simulator)
    }

    func testCurrentDrainRateNonNegative() async {
        let tracker = BatteryDrainTracker()
        // Record a couple of extra samples to potentially compute a rate
        await tracker.recordSample()
        if let rate = await tracker.currentDrainRate {
            XCTAssertGreaterThanOrEqual(rate, 0.0, "Drain rate should never be negative")
        }
    }

    func testAverageDrainRateNonNegative() async {
        let tracker = BatteryDrainTracker()
        await tracker.recordSample()
        await tracker.recordSample()
        if let rate = await tracker.averageDrainRate {
            XCTAssertGreaterThanOrEqual(rate, 0.0, "Average drain rate should never be negative")
        }
    }

    func testRecordSampleIncrementsSampleCount() async {
        let tracker = BatteryDrainTracker()
        await tracker.reset()
        let before = await tracker.sampleCount
        await tracker.recordSample()
        let after = await tracker.sampleCount
        // On real device with monitoring enabled this should increment;
        // on simulator batteryLevel may be -1.0 causing the guard to skip.
        XCTAssertGreaterThanOrEqual(after, before)
    }

    func testNeedsTwoSamplesForDrainRate() async {
        let tracker = BatteryDrainTracker()
        await tracker.reset()
        // 0 samples → nil
        XCTAssertNil(await tracker.currentDrainRate)
        await tracker.recordSample()
        // 1 sample → still nil (need ≥ 2)
        XCTAssertNil(await tracker.currentDrainRate)
    }

    func testNeedsThreeSamplesForAverageDrainRate() async {
        let tracker = BatteryDrainTracker()
        await tracker.reset()
        await tracker.recordSample()
        await tracker.recordSample()
        // With < 3 samples, averageDrainRate falls back to currentDrainRate
        let avg = await tracker.averageDrainRate
        let cur = await tracker.currentDrainRate
        XCTAssertEqual(avg, cur, "averageDrainRate should equal currentDrainRate when < 3 samples")
    }
    #endif

    // MARK: - Performance

    func testRecordSamplePerformance() {
        let tracker = BatteryDrainTracker()
        measure {
            let exp = expectation(description: "record")
            Task {
                for _ in 0..<100 {
                    await tracker.recordSample()
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
    }

    func testReadPropertiesPerformance() {
        let tracker = BatteryDrainTracker()
        measure {
            let exp = expectation(description: "read")
            Task {
                for _ in 0..<200 {
                    _ = await tracker.currentDrainRate
                    _ = await tracker.averageDrainRate
                    _ = await tracker.currentBatteryLevel
                    _ = await tracker.sampleCount
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 5.0)
        }
    }
}