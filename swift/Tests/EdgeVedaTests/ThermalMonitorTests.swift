import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class ThermalMonitorTests: XCTestCase {
    
    var monitor: ThermalMonitor!
    
    override func setUp() async throws {
        monitor = ThermalMonitor()
    }
    
    override func tearDown() async throws {
        monitor = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async {
        // Monitor should initialize without crashing
        let level = await monitor.currentLevel
        // Level should be 0-3 on iOS/macOS, -1 on unsupported
        XCTAssertGreaterThanOrEqual(level, -1, "Thermal level should be >= -1")
        XCTAssertLessThanOrEqual(level, 3, "Thermal level should be <= 3")
    }
    
    // MARK: - Current Level Tests
    
    func testCurrentLevelReturnsValidRange() async {
        let level = await monitor.currentLevel
        let validLevels = Set([-1, 0, 1, 2, 3])
        XCTAssertTrue(validLevels.contains(level), "Thermal level \(level) should be in valid range [-1, 0, 1, 2, 3]")
    }
    
    func testCurrentLevelConsistentOnMultipleReads() async {
        let level1 = await monitor.currentLevel
        let level2 = await monitor.currentLevel
        let level3 = await monitor.currentLevel
        
        // Under normal test conditions, thermal state shouldn't change rapidly
        // All reads should return valid values
        for level in [level1, level2, level3] {
            XCTAssertGreaterThanOrEqual(level, -1)
            XCTAssertLessThanOrEqual(level, 3)
        }
    }
    
    // MARK: - State Name Tests
    
    func testCurrentStateNameReturnsValidString() async {
        let name = await monitor.currentStateName
        let validNames = Set(["nominal", "fair", "serious", "critical", "unavailable", "unknown"])
        XCTAssertTrue(validNames.contains(name), "State name '\(name)' should be a valid thermal state name")
    }
    
    func testStateNameCorrespondsToLevel() async {
        let level = await monitor.currentLevel
        let name = await monitor.currentStateName
        
        #if os(iOS) || os(macOS)
        switch level {
        case 0:
            XCTAssertEqual(name, "nominal")
        case 1:
            XCTAssertEqual(name, "fair")
        case 2:
            XCTAssertEqual(name, "serious")
        case 3:
            XCTAssertEqual(name, "critical")
        default:
            XCTAssertEqual(name, "unknown")
        }
        #else
        XCTAssertEqual(name, "unavailable")
        #endif
    }
    
    // MARK: - Platform Support Tests
    
    func testIsSupportedMatchesPlatform() {
        let supported = monitor.isSupported
        
        #if os(iOS) || os(macOS)
        XCTAssertTrue(supported, "Thermal monitoring should be supported on iOS/macOS")
        #else
        XCTAssertFalse(supported, "Thermal monitoring should not be supported on this platform")
        #endif
    }
    
    func testIsSupportedIsNonisolated() {
        // isSupported is nonisolated, should be callable without await
        let supported = monitor.isSupported
        XCTAssertNotNil(supported as Any)
    }
    
    // MARK: - Throttle Tests
    
    func testShouldThrottleReturnsBool() async {
        let shouldThrottle = await monitor.shouldThrottle
        // Under normal test conditions, should not be throttling
        // But we just verify it returns a valid bool
        XCTAssertNotNil(shouldThrottle as Any)
    }
    
    func testShouldThrottleConsistentWithLevel() async {
        let level = await monitor.currentLevel
        let shouldThrottle = await monitor.shouldThrottle
        
        if level >= 2 {
            XCTAssertTrue(shouldThrottle, "Should throttle when thermal level >= 2")
        } else {
            XCTAssertFalse(shouldThrottle, "Should not throttle when thermal level < 2")
        }
    }
    
    func testIsCriticalConsistentWithLevel() async {
        let level = await monitor.currentLevel
        let isCritical = await monitor.isCritical
        
        if level >= 3 {
            XCTAssertTrue(isCritical, "Should be critical when thermal level >= 3")
        } else {
            XCTAssertFalse(isCritical, "Should not be critical when thermal level < 3")
        }
    }
    
    func testNominalStateDoesNotThrottle() async {
        // On most test machines, thermal state is nominal
        let level = await monitor.currentLevel
        if level == 0 {
            let shouldThrottle = await monitor.shouldThrottle
            let isCritical = await monitor.isCritical
            
            XCTAssertFalse(shouldThrottle, "Nominal state should not throttle")
            XCTAssertFalse(isCritical, "Nominal state should not be critical")
        }
    }
    
    // MARK: - Listener Tests
    
    func testRegisterListener() async {
        let id = await monitor.onThermalStateChange { _ in
            // No-op listener
        }
        
        XCTAssertNotNil(id, "Should return a valid listener UUID")
    }
    
    func testRemoveListener() async {
        let id = await monitor.onThermalStateChange { _ in
            // No-op listener
        }
        
        // Should not crash when removing
        await monitor.removeListener(id)
    }
    
    func testRemoveNonexistentListener() async {
        let randomId = UUID()
        // Should not crash when removing a listener that doesn't exist
        await monitor.removeListener(randomId)
    }
    
    func testMultipleListeners() async {
        var ids: [UUID] = []
        
        for _ in 0..<5 {
            let id = await monitor.onThermalStateChange { _ in }
            ids.append(id)
        }
        
        XCTAssertEqual(ids.count, 5, "Should register 5 listeners")
        
        // All IDs should be unique
        let uniqueIds = Set(ids)
        XCTAssertEqual(uniqueIds.count, 5, "All listener IDs should be unique")
        
        // Remove all
        for id in ids {
            await monitor.removeListener(id)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentLevelReads() async {
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    return await self.monitor.currentLevel
                }
            }
            
            for await level in group {
                XCTAssertGreaterThanOrEqual(level, -1)
                XCTAssertLessThanOrEqual(level, 3)
            }
        }
    }
    
    func testConcurrentListenerRegistration() async {
        var allIds: [UUID] = []
        
        await withTaskGroup(of: UUID.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    return await self.monitor.onThermalStateChange { _ in }
                }
            }
            
            for await id in group {
                allIds.append(id)
            }
        }
        
        XCTAssertEqual(allIds.count, 10, "All concurrent listener registrations should succeed")
        
        // Clean up
        for id in allIds {
            await monitor.removeListener(id)
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testMultipleMonitorInstances() async {
        let monitor2 = ThermalMonitor()
        let monitor3 = ThermalMonitor()
        
        let level1 = await monitor.currentLevel
        let level2 = await monitor2.currentLevel
        let level3 = await monitor3.currentLevel
        
        // All should report the same thermal level (same device)
        XCTAssertEqual(level1, level2, "Multiple monitors should report same level")
        XCTAssertEqual(level2, level3, "Multiple monitors should report same level")
    }
    
    // MARK: - Performance Tests
    
    func testLevelReadPerformance() {
        measure {
            let expectation = self.expectation(description: "level reads")
            Task {
                for _ in 0..<100 {
                    _ = await self.monitor.currentLevel
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
}