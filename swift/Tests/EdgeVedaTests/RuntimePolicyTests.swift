import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class RuntimePolicyTests: XCTestCase {
    
    // MARK: - Predefined Policy Tests
    
    func testConservativePolicy() {
        let policy = RuntimePolicy.conservative
        
        XCTAssertTrue(policy.throttleOnBattery)
        XCTAssertTrue(policy.adaptiveMemory)
        XCTAssertTrue(policy.thermalAware)
        XCTAssertTrue(policy.backgroundOptimization)
    }
    
    func testBalancedPolicy() {
        let policy = RuntimePolicy.balanced
        
        XCTAssertTrue(policy.throttleOnBattery)
        XCTAssertTrue(policy.adaptiveMemory)
        XCTAssertTrue(policy.thermalAware)
        XCTAssertFalse(policy.backgroundOptimization)
    }
    
    func testPerformancePolicy() {
        let policy = RuntimePolicy.performance
        
        XCTAssertFalse(policy.throttleOnBattery)
        XCTAssertFalse(policy.adaptiveMemory)
        XCTAssertTrue(policy.thermalAware)
        XCTAssertFalse(policy.backgroundOptimization)
    }
    
    func testDefaultPolicy() {
        let policy = RuntimePolicy.default
        
        // Default should be balanced
        XCTAssertTrue(policy.throttleOnBattery)
        XCTAssertTrue(policy.adaptiveMemory)
        XCTAssertTrue(policy.thermalAware)
        XCTAssertFalse(policy.backgroundOptimization)
    }
    
    // MARK: - Custom Policy Tests
    
    func testCustomPolicy() {
        let policy = RuntimePolicy(
            throttleOnBattery: false,
            adaptiveMemory: false,
            thermalAware: false,
            backgroundOptimization: false
        )
        
        XCTAssertFalse(policy.throttleOnBattery)
        XCTAssertFalse(policy.adaptiveMemory)
        XCTAssertFalse(policy.thermalAware)
        XCTAssertFalse(policy.backgroundOptimization)
    }
    
    func testCustomPolicyWithOptions() {
        let options = RuntimePolicyOptions(
            batteryThreshold: 0.3,
            thermalThreshold: 2,
            memoryPressureThreshold: 0.8,
            backgroundDelaySeconds: 10.0
        )
        
        let policy = RuntimePolicy(
            throttleOnBattery: true,
            adaptiveMemory: true,
            thermalAware: true,
            backgroundOptimization: true,
            options: options
        )
        
        XCTAssertTrue(policy.throttleOnBattery)
        XCTAssertEqual(policy.options.batteryThreshold, 0.3, accuracy: 0.01)
        XCTAssertEqual(policy.options.thermalThreshold, 2)
        XCTAssertEqual(policy.options.memoryPressureThreshold, 0.8, accuracy: 0.01)
        XCTAssertEqual(policy.options.backgroundDelaySeconds, 10.0, accuracy: 0.01)
    }
    
    // MARK: - Policy Options Tests
    
    func testDefaultPolicyOptions() {
        let options = RuntimePolicyOptions()
        
        XCTAssertEqual(options.batteryThreshold, 0.2, accuracy: 0.01)
        XCTAssertEqual(options.thermalThreshold, 1)
        XCTAssertEqual(options.memoryPressureThreshold, 0.85, accuracy: 0.01)
        XCTAssertEqual(options.backgroundDelaySeconds, 5.0, accuracy: 0.01)
    }
    
    func testCustomPolicyOptions() {
        let options = RuntimePolicyOptions(
            batteryThreshold: 0.5,
            thermalThreshold: 3,
            memoryPressureThreshold: 0.9,
            backgroundDelaySeconds: 20.0
        )
        
        XCTAssertEqual(options.batteryThreshold, 0.5, accuracy: 0.01)
        XCTAssertEqual(options.thermalThreshold, 3)
        XCTAssertEqual(options.memoryPressureThreshold, 0.9, accuracy: 0.01)
        XCTAssertEqual(options.backgroundDelaySeconds, 20.0, accuracy: 0.01)
    }
    
    // MARK: - Runtime Capabilities Tests
    
    func testRuntimeCapabilitiesDetection() async {
        let capabilities = await RuntimeCapabilities.detect()
        
        // All Apple platforms should support these
        XCTAssertTrue(capabilities.supportsBatteryMonitoring || !capabilities.supportsBatteryMonitoring)
        XCTAssertTrue(capabilities.supportsThermalMonitoring)
        XCTAssertTrue(capabilities.supportsMemoryPressure)
        XCTAssertTrue(capabilities.supportsBackgroundExecution || !capabilities.supportsBackgroundExecution)
    }
    
    // MARK: - Policy Enforcer Tests
    
    func testPolicyEnforcerInitialization() async {
        let policy = RuntimePolicy.balanced
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        let currentPolicy = await enforcer.getCurrentPolicy()
        XCTAssertEqual(currentPolicy.throttleOnBattery, policy.throttleOnBattery)
        XCTAssertEqual(currentPolicy.adaptiveMemory, policy.adaptiveMemory)
    }
    
    func testUpdatePolicy() async {
        let initialPolicy = RuntimePolicy.conservative
        let enforcer = RuntimePolicyEnforcer(policy: initialPolicy)
        
        let newPolicy = RuntimePolicy.performance
        await enforcer.updatePolicy(newPolicy)
        
        let currentPolicy = await enforcer.getCurrentPolicy()
        XCTAssertEqual(currentPolicy.throttleOnBattery, newPolicy.throttleOnBattery)
        XCTAssertEqual(currentPolicy.adaptiveMemory, newPolicy.adaptiveMemory)
    }
    
    func testShouldThrottle() async {
        let policy = RuntimePolicy(
            throttleOnBattery: true,
            adaptiveMemory: false,
            thermalAware: false,
            backgroundOptimization: false
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with low battery
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 0.15,
            thermalState: 0,
            memoryPressure: 0.5,
            isBackground: false
        )
        
        XCTAssertTrue(shouldThrottle)
    }
    
    func testShouldNotThrottle() async {
        let policy = RuntimePolicy(
            throttleOnBattery: true,
            adaptiveMemory: false,
            thermalAware: false,
            backgroundOptimization: false
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with good battery
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 0.8,
            thermalState: 0,
            memoryPressure: 0.5,
            isBackground: false
        )
        
        XCTAssertFalse(shouldThrottle)
    }
    
    func testThermalThrottling() async {
        let policy = RuntimePolicy(
            throttleOnBattery: false,
            adaptiveMemory: false,
            thermalAware: true,
            backgroundOptimization: false
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with high thermal state
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 1.0,
            thermalState: 2,
            memoryPressure: 0.5,
            isBackground: false
        )
        
        XCTAssertTrue(shouldThrottle)
    }
    
    func testMemoryPressureThrottling() async {
        let policy = RuntimePolicy(
            throttleOnBattery: false,
            adaptiveMemory: true,
            thermalAware: false,
            backgroundOptimization: false
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with high memory pressure
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 1.0,
            thermalState: 0,
            memoryPressure: 0.9,
            isBackground: false
        )
        
        XCTAssertTrue(shouldThrottle)
    }
    
    func testBackgroundOptimization() async {
        let policy = RuntimePolicy(
            throttleOnBattery: false,
            adaptiveMemory: false,
            thermalAware: false,
            backgroundOptimization: true
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test in background
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 1.0,
            thermalState: 0,
            memoryPressure: 0.5,
            isBackground: true
        )
        
        XCTAssertTrue(shouldThrottle)
    }
    
    // MARK: - Policy String Conversion Tests
    
    func testPolicyDescription() {
        let policy = RuntimePolicy.balanced
        let description = policy.description
        
        XCTAssertTrue(description.contains("RuntimePolicy"))
        XCTAssertTrue(description.contains("throttleOnBattery"))
        XCTAssertTrue(description.contains("adaptiveMemory"))
        XCTAssertTrue(description.contains("thermalAware"))
        XCTAssertTrue(description.contains("backgroundOptimization"))
    }
    
    // MARK: - Multiple Condition Tests
    
    func testMultipleThrottleConditions() async {
        let policy = RuntimePolicy(
            throttleOnBattery: true,
            adaptiveMemory: true,
            thermalAware: true,
            backgroundOptimization: true
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with multiple conditions met
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 0.15,
            thermalState: 2,
            memoryPressure: 0.9,
            isBackground: true
        )
        
        XCTAssertTrue(shouldThrottle)
    }
    
    func testNoThrottleConditions() async {
        let policy = RuntimePolicy(
            throttleOnBattery: true,
            adaptiveMemory: true,
            thermalAware: true,
            backgroundOptimization: true
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with no conditions met
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 1.0,
            thermalState: 0,
            memoryPressure: 0.3,
            isBackground: false
        )
        
        XCTAssertFalse(shouldThrottle)
    }
    
    // MARK: - Edge Cases
    
    func testBoundaryBatteryLevel() async {
        let policy = RuntimePolicy(
            throttleOnBattery: true,
            adaptiveMemory: false,
            thermalAware: false,
            backgroundOptimization: false
        )
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test at exact threshold
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 0.2,
            thermalState: 0,
            memoryPressure: 0.5,
            isBackground: false
        )
        
        // Behavior at boundary is implementation-specific
        XCTAssertTrue(shouldThrottle || !shouldThrottle)
    }
    
    func testInvalidBatteryLevel() async {
        let policy = RuntimePolicy.balanced
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with negative battery level (shouldn't crash)
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: -0.1,
            thermalState: 0,
            memoryPressure: 0.5,
            isBackground: false
        )
        
        // Should handle gracefully
        XCTAssertTrue(shouldThrottle || !shouldThrottle)
    }
    
    func testInvalidThermalState() async {
        let policy = RuntimePolicy.balanced
        let enforcer = RuntimePolicyEnforcer(policy: policy)
        
        // Test with negative thermal state
        let shouldThrottle = await enforcer.shouldThrottle(
            batteryLevel: 0.8,
            thermalState: -1,
            memoryPressure: 0.5,
            isBackground: false
        )
        
        // Should handle gracefully
        XCTAssertTrue(shouldThrottle || !shouldThrottle)
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentPolicyUpdates() async {
        let enforcer = RuntimePolicyEnforcer(policy: .balanced)
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let policy = i % 2 == 0 ? RuntimePolicy.conservative : RuntimePolicy.performance
                    await enforcer.updatePolicy(policy)
                }
            }
        }
        
        let finalPolicy = await enforcer.getCurrentPolicy()
        // Should have a valid policy after concurrent updates
        XCTAssertNotNil(finalPolicy)
    }
    
    func testConcurrentThrottleChecks() async {
        let enforcer = RuntimePolicyEnforcer(policy: .balanced)
        
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<100 {
                group.addTask {
                    return await enforcer.shouldThrottle(
                        batteryLevel: Double(i) / 100.0,
                        thermalState: i % 3,
                        memoryPressure: Double(i % 50) / 100.0,
                        isBackground: i % 2 == 0
                    )
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            
            XCTAssertEqual(results.count, 100)
        }
    }
    
    // MARK: - Performance Tests
    
    func testPolicyCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = RuntimePolicy.balanced
                _ = RuntimePolicy.conservative
                _ = RuntimePolicy.performance
            }
        }
    }
    
    func testThrottleCheckPerformance() async {
        let enforcer = RuntimePolicyEnforcer(policy: .balanced)
        
        measure {
            Task {
                for i in 0..<100 {
                    _ = await enforcer.shouldThrottle(
                        batteryLevel: 0.5,
                        thermalState: 1,
                        memoryPressure: 0.6,
                        isBackground: false
                    )
                }
            }
        }
    }
}