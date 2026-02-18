import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class LatencyTrackerTests: XCTestCase {
    
    var tracker: LatencyTracker!
    
    override func setUp() async throws {
        try await super.setUp()
        tracker = LatencyTracker()
    }
    
    override func tearDown() async throws {
        tracker = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() async {
        let stats = await tracker.getStatistics()
        
        XCTAssertEqual(stats.count, 0)
        XCTAssertEqual(stats.mean, 0)
        XCTAssertEqual(stats.median, 0)
        XCTAssertEqual(stats.p50, 0)
        XCTAssertEqual(stats.p95, 0)
        XCTAssertEqual(stats.p99, 0)
        XCTAssertEqual(stats.min, 0)
        XCTAssertEqual(stats.max, 0)
        XCTAssertEqual(stats.stdDev, 0)
    }
    
    // MARK: - Recording Tests
    
    func testRecordSingleLatency() async {
        await tracker.recordLatency(100.0)
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.mean, 100.0, accuracy: 0.01)
        XCTAssertEqual(stats.median, 100.0, accuracy: 0.01)
        XCTAssertEqual(stats.min, 100.0, accuracy: 0.01)
        XCTAssertEqual(stats.max, 100.0, accuracy: 0.01)
    }
    
    func testRecordMultipleLatencies() async {
        let latencies: [TimeInterval] = [50.0, 100.0, 150.0, 200.0, 250.0]
        
        for latency in latencies {
            await tracker.recordLatency(latency)
        }
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 5)
        XCTAssertEqual(stats.mean, 150.0, accuracy: 0.01)
        XCTAssertEqual(stats.median, 150.0, accuracy: 0.01)
        XCTAssertEqual(stats.min, 50.0, accuracy: 0.01)
        XCTAssertEqual(stats.max, 250.0, accuracy: 0.01)
    }
    
    func testRecordZeroLatency() async {
        await tracker.recordLatency(0.0)
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.mean, 0.0)
    }
    
    func testRecordNegativeLatencyIgnored() async {
        await tracker.recordLatency(-50.0)
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 0)
    }
    
    // MARK: - Percentile Tests
    
    func testPercentileCalculation() async {
        // Add 100 samples from 1ms to 100ms
        for i in 1...100 {
            await tracker.recordLatency(Double(i))
        }
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.p50, 50.0, accuracy: 1.0)
        XCTAssertEqual(stats.p95, 95.0, accuracy: 1.0)
        XCTAssertEqual(stats.p99, 99.0, accuracy: 1.0)
    }
    
    func testPercentileWithFewSamples() async {
        await tracker.recordLatency(10.0)
        await tracker.recordLatency(20.0)
        
        let stats = await tracker.getStatistics()
        XCTAssertGreaterThan(stats.p95, 0)
        XCTAssertGreaterThan(stats.p99, 0)
    }
    
    // MARK: - Warm-up Tests
    
    func testWarmupPeriod() async {
        // Should not be warmed up initially
        var isWarmedUp = await tracker.isWarmedUp()
        XCTAssertFalse(isWarmedUp)
        
        // Add 20 samples (warm-up threshold is typically 20)
        for i in 1...20 {
            await tracker.recordLatency(Double(i) * 10.0)
        }
        
        isWarmedUp = await tracker.isWarmedUp()
        XCTAssertTrue(isWarmedUp)
    }
    
    func testBaselineAfterWarmup() async {
        // Add samples to reach warm-up
        for i in 1...25 {
            await tracker.recordLatency(100.0 + Double(i))
        }
        
        let baseline = await tracker.getBaseline()
        XCTAssertNotNil(baseline)
        XCTAssertGreaterThan(baseline!.p95, 0)
        XCTAssertGreaterThan(baseline!.mean, 0)
    }
    
    // MARK: - Reset Tests
    
    func testReset() async {
        // Add some samples
        for i in 1...10 {
            await tracker.recordLatency(Double(i) * 10.0)
        }
        
        var stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 10)
        
        // Reset
        await tracker.reset()
        
        stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 0)
        XCTAssertEqual(stats.mean, 0)
        
        let isWarmedUp = await tracker.isWarmedUp()
        XCTAssertFalse(isWarmedUp)
    }
    
    // MARK: - Window Size Tests
    
    func testWindowSizeLimit() async {
        // Add more samples than the window size (typically 1000)
        for i in 1...1500 {
            await tracker.recordLatency(Double(i))
        }
        
        let stats = await tracker.getStatistics()
        // Should keep only the most recent samples
        XCTAssertLessThanOrEqual(stats.count, 1000)
    }
    
    // MARK: - Standard Deviation Tests
    
    func testStandardDeviationCalculation() async {
        // Add samples with known distribution
        let samples: [TimeInterval] = [100, 100, 100, 200, 200, 200]
        
        for sample in samples {
            await tracker.recordLatency(sample)
        }
        
        let stats = await tracker.getStatistics()
        XCTAssertGreaterThan(stats.stdDev, 0)
        // Mean should be 150
        XCTAssertEqual(stats.mean, 150.0, accuracy: 0.01)
    }
    
    // MARK: - Edge Cases
    
    func testVeryLargeLatency() async {
        await tracker.recordLatency(1000000.0) // 1000 seconds
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.max, 1000000.0)
    }
    
    func testMixedLatencyValues() async {
        let latencies: [TimeInterval] = [1.0, 10.0, 100.0, 1000.0, 10000.0]
        
        for latency in latencies {
            await tracker.recordLatency(latency)
        }
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 5)
        XCTAssertEqual(stats.min, 1.0)
        XCTAssertEqual(stats.max, 10000.0)
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentRecording() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 1...100 {
                group.addTask {
                    await self.tracker.recordLatency(Double(i))
                }
            }
        }
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.count, 100)
    }
    
    // MARK: - Performance Tests
    
    func testRecordingPerformance() {
        measure {
            Task {
                for i in 1...1000 {
                    await tracker.recordLatency(Double(i))
                }
            }
        }
    }
    
    func testStatisticsCalculationPerformance() async {
        // Add many samples first
        for i in 1...1000 {
            await tracker.recordLatency(Double(i))
        }
        
        measure {
            Task {
                _ = await tracker.getStatistics()
            }
        }
    }
}