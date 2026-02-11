import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class ResourceMonitorTests: XCTestCase {
    
    var monitor: ResourceMonitor!
    
    override func setUp() async throws {
        monitor = ResourceMonitor()
    }
    
    override func tearDown() async throws {
        monitor = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async {
        // ResourceMonitor takes an initial sample on init
        let sampleCount = await monitor.sampleCount
        XCTAssertGreaterThanOrEqual(sampleCount, 1, "Should have at least 1 sample after init")
    }
    
    // MARK: - Current RSS Tests
    
    func testCurrentRssMbReturnsPositiveValue() async {
        let rss = await monitor.currentRssMb
        XCTAssertGreaterThan(rss, 0.0, "Current RSS should be positive for a running process")
    }
    
    func testCurrentRssMbReturnsReasonableValue() async {
        let rss = await monitor.currentRssMb
        // A test process should use between 1MB and 10GB
        XCTAssertGreaterThan(rss, 1.0, "RSS should be at least 1MB")
        XCTAssertLessThan(rss, 10_000.0, "RSS should be less than 10GB")
    }
    
    func testMultipleCurrentRssMbReads() async {
        let rss1 = await monitor.currentRssMb
        let rss2 = await monitor.currentRssMb
        let rss3 = await monitor.currentRssMb
        
        // All should be positive
        XCTAssertGreaterThan(rss1, 0.0)
        XCTAssertGreaterThan(rss2, 0.0)
        XCTAssertGreaterThan(rss3, 0.0)
    }
    
    // MARK: - Peak RSS Tests
    
    func testPeakRssMbIsPositive() async {
        _ = await monitor.currentRssMb // Trigger a sample
        let peak = await monitor.peakRssMb
        XCTAssertGreaterThan(peak, 0.0, "Peak RSS should be positive")
    }
    
    func testPeakRssMbIsGreaterThanOrEqualToAverage() async {
        // Take several samples
        for _ in 0..<5 {
            _ = await monitor.currentRssMb
        }
        
        let peak = await monitor.peakRssMb
        let average = await monitor.averageRssMb
        XCTAssertGreaterThanOrEqual(peak, average, "Peak should be >= average")
    }
    
    func testPeakRssMbNeverDecreases() async {
        _ = await monitor.currentRssMb
        let peak1 = await monitor.peakRssMb
        
        _ = await monitor.currentRssMb
        let peak2 = await monitor.peakRssMb
        
        _ = await monitor.currentRssMb
        let peak3 = await monitor.peakRssMb
        
        XCTAssertGreaterThanOrEqual(peak2, peak1, "Peak should never decrease")
        XCTAssertGreaterThanOrEqual(peak3, peak2, "Peak should never decrease")
    }
    
    // MARK: - Average RSS Tests
    
    func testAverageRssMbReturnsPositiveValue() async {
        _ = await monitor.currentRssMb
        let average = await monitor.averageRssMb
        XCTAssertGreaterThan(average, 0.0, "Average RSS should be positive")
    }
    
    func testAverageRssMbWithMultipleSamples() async {
        // Take multiple samples
        for _ in 0..<10 {
            await monitor.sample()
        }
        
        let average = await monitor.averageRssMb
        let peak = await monitor.peakRssMb
        
        XCTAssertGreaterThan(average, 0.0)
        XCTAssertLessThanOrEqual(average, peak, "Average should be <= peak")
    }
    
    // MARK: - Sample Count Tests
    
    func testSampleCountIncrements() async {
        let initialCount = await monitor.sampleCount
        
        await monitor.sample()
        let count1 = await monitor.sampleCount
        XCTAssertEqual(count1, initialCount + 1)
        
        await monitor.sample()
        let count2 = await monitor.sampleCount
        XCTAssertEqual(count2, initialCount + 2)
    }
    
    func testSampleCountCapsAtMaxSamples() async {
        // Take more than maxSamples (100) samples
        for _ in 0..<120 {
            await monitor.sample()
        }
        
        let count = await monitor.sampleCount
        // Should be capped at maxSamples (100) due to sliding window
        XCTAssertLessThanOrEqual(count, 100, "Sample count should be capped at maxSamples")
    }
    
    // MARK: - Manual Sample Tests
    
    func testManualSampleRecords() async {
        let countBefore = await monitor.sampleCount
        await monitor.sample()
        let countAfter = await monitor.sampleCount
        
        XCTAssertEqual(countAfter, countBefore + 1, "Manual sample should increment count")
    }
    
    func testMultipleManualSamples() async {
        let countBefore = await monitor.sampleCount
        
        for _ in 0..<5 {
            await monitor.sample()
        }
        
        let countAfter = await monitor.sampleCount
        XCTAssertEqual(countAfter, countBefore + 5)
    }
    
    // MARK: - Reset Tests
    
    func testResetClearsSamples() async {
        // Take some samples
        for _ in 0..<5 {
            await monitor.sample()
        }
        
        let countBefore = await monitor.sampleCount
        XCTAssertGreaterThan(countBefore, 0)
        
        await monitor.reset()
        
        let countAfter = await monitor.sampleCount
        XCTAssertEqual(countAfter, 0, "Reset should clear all samples")
    }
    
    func testResetClearsPeakRss() async {
        _ = await monitor.currentRssMb
        let peakBefore = await monitor.peakRssMb
        XCTAssertGreaterThan(peakBefore, 0.0)
        
        await monitor.reset()
        
        let peakAfter = await monitor.peakRssMb
        XCTAssertEqual(peakAfter, 0.0, "Reset should clear peak RSS")
    }
    
    func testResetClearsAverage() async {
        for _ in 0..<5 {
            await monitor.sample()
        }
        
        await monitor.reset()
        
        let average = await monitor.averageRssMb
        XCTAssertEqual(average, 0.0, "Reset should result in 0 average (no samples)")
    }
    
    func testSamplingAfterReset() async {
        // Take samples, reset, then take more
        for _ in 0..<5 {
            await monitor.sample()
        }
        
        await monitor.reset()
        
        await monitor.sample()
        let count = await monitor.sampleCount
        XCTAssertEqual(count, 1, "Should have 1 sample after reset + 1 sample")
        
        let rss = await monitor.currentRssMb
        XCTAssertGreaterThan(rss, 0.0, "Should still get valid RSS after reset")
    }
    
    // MARK: - Sliding Window Tests
    
    func testSlidingWindowMaintainsMaxSamples() async {
        // Fill beyond max
        for _ in 0..<150 {
            await monitor.sample()
        }
        
        let count = await monitor.sampleCount
        XCTAssertLessThanOrEqual(count, 100, "Sliding window should cap at maxSamples")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentSampling() async {
        // Actor isolation should handle concurrent access safely
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await self.monitor.sample()
                }
            }
        }
        
        let count = await monitor.sampleCount
        // Initial sample + 20 concurrent samples
        XCTAssertGreaterThanOrEqual(count, 20, "All concurrent samples should be recorded")
    }
    
    func testConcurrentReadsAndWrites() async {
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for _ in 0..<10 {
                group.addTask {
                    await self.monitor.sample()
                }
            }
            // Readers
            for _ in 0..<10 {
                group.addTask {
                    _ = await self.monitor.currentRssMb
                    _ = await self.monitor.peakRssMb
                    _ = await self.monitor.averageRssMb
                }
            }
        }
        
        // Should complete without crashes
        let count = await monitor.sampleCount
        XCTAssertGreaterThan(count, 0)
    }
    
    // MARK: - Performance Tests
    
    func testSamplingPerformance() {
        measure {
            let expectation = self.expectation(description: "sampling")
            Task {
                for _ in 0..<100 {
                    await self.monitor.sample()
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
}