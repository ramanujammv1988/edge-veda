import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class BudgetTests: XCTestCase {
    
    // MARK: - ComputeBudget Tests
    
    func testDefaultBudget() {
        let budget = ComputeBudget.default
        
        XCTAssertEqual(budget.maxLatency, 500.0, accuracy: 0.01)
        XCTAssertEqual(budget.maxBatteryDrainRate, 1.0, accuracy: 0.01)
        XCTAssertEqual(budget.maxThermalLevel, 1)
        XCTAssertEqual(budget.maxMemoryMB, 1024.0, accuracy: 0.01)
    }
    
    func testConservativeBudget() {
        let budget = ComputeBudget.conservative
        
        // Conservative should have stricter limits
        XCTAssertLessThan(budget.maxLatency, ComputeBudget.default.maxLatency * 1.5)
        XCTAssertLessThan(budget.maxBatteryDrainRate, ComputeBudget.default.maxBatteryDrainRate)
        XCTAssertLessThanOrEqual(budget.maxThermalLevel, 1)
    }
    
    func testBalancedBudget() {
        let budget = ComputeBudget.balanced
        
        XCTAssertGreaterThan(budget.maxLatency, 0)
        XCTAssertGreaterThan(budget.maxBatteryDrainRate, 0)
        XCTAssertGreaterThan(budget.maxThermalLevel, 0)
        XCTAssertGreaterThan(budget.maxMemoryMB, 0)
    }
    
    func testPerformanceBudget() {
        let budget = ComputeBudget.performance
        
        // Performance should have more relaxed limits
        XCTAssertGreaterThan(budget.maxBatteryDrainRate, ComputeBudget.balanced.maxBatteryDrainRate)
        XCTAssertGreaterThanOrEqual(budget.maxThermalLevel, ComputeBudget.balanced.maxThermalLevel)
    }
    
    func testCustomBudget() {
        let budget = ComputeBudget(
            maxLatency: 300.0,
            maxBatteryDrainRate: 0.8,
            maxThermalLevel: 2,
            maxMemoryMB: 768.0
        )
        
        XCTAssertEqual(budget.maxLatency, 300.0, accuracy: 0.01)
        XCTAssertEqual(budget.maxBatteryDrainRate, 0.8, accuracy: 0.01)
        XCTAssertEqual(budget.maxThermalLevel, 2)
        XCTAssertEqual(budget.maxMemoryMB, 768.0, accuracy: 0.01)
    }
    
    // MARK: - BudgetProfile Tests
    
    func testConservativeProfile() {
        let profile = BudgetProfile.conservative
        
        XCTAssertEqual(profile.latencyMultiplier, 2.0, accuracy: 0.01)
        XCTAssertEqual(profile.batteryMultiplier, 0.6, accuracy: 0.01)
        XCTAssertEqual(profile.thermalLevel, 1)
        XCTAssertEqual(profile.memoryMultiplier, 0.8, accuracy: 0.01)
    }
    
    func testBalancedProfile() {
        let profile = BudgetProfile.balanced
        
        XCTAssertEqual(profile.latencyMultiplier, 1.5, accuracy: 0.01)
        XCTAssertEqual(profile.batteryMultiplier, 1.0, accuracy: 0.01)
        XCTAssertEqual(profile.thermalLevel, 1)
        XCTAssertEqual(profile.memoryMultiplier, 1.0, accuracy: 0.01)
    }
    
    func testPerformanceProfile() {
        let profile = BudgetProfile.performance
        
        XCTAssertEqual(profile.latencyMultiplier, 1.1, accuracy: 0.01)
        XCTAssertEqual(profile.batteryMultiplier, 1.5, accuracy: 0.01)
        XCTAssertEqual(profile.thermalLevel, 3)
        XCTAssertEqual(profile.memoryMultiplier, 1.2, accuracy: 0.01)
    }
    
    func testApplyProfileToBudget() async {
        let baseline = MeasuredBaseline(
            p95Latency: 200.0,
            meanBatteryDrain: 1.0,
            typicalMemoryMB: 512.0,
            thermalLevel: 0
        )
        
        let profile = BudgetProfile.balanced
        let budget = await profile.apply(to: baseline)
        
        // Should multiply baseline by profile factors
        XCTAssertEqual(budget.maxLatency, baseline.p95Latency * profile.latencyMultiplier, accuracy: 0.01)
        XCTAssertEqual(budget.maxBatteryDrainRate, baseline.meanBatteryDrain * profile.batteryMultiplier, accuracy: 0.01)
        XCTAssertEqual(budget.maxMemoryMB, baseline.typicalMemoryMB * profile.memoryMultiplier, accuracy: 0.01)
        XCTAssertEqual(budget.maxThermalLevel, profile.thermalLevel)
    }
    
    // MARK: - MeasuredBaseline Tests
    
    func testMeasuredBaseline() {
        let baseline = MeasuredBaseline(
            p95Latency: 250.0,
            meanBatteryDrain: 1.2,
            typicalMemoryMB: 600.0,
            thermalLevel: 1
        )
        
        XCTAssertEqual(baseline.p95Latency, 250.0, accuracy: 0.01)
        XCTAssertEqual(baseline.meanBatteryDrain, 1.2, accuracy: 0.01)
        XCTAssertEqual(baseline.typicalMemoryMB, 600.0, accuracy: 0.01)
        XCTAssertEqual(baseline.thermalLevel, 1)
    }
    
    // MARK: - BudgetViolation Tests
    
    func testBudgetViolationLatency() {
        let violation = BudgetViolation(
            type: .latency,
            severity: .high,
            measuredValue: 600.0,
            budgetLimit: 500.0,
            timestamp: Date()
        )
        
        XCTAssertEqual(violation.type, .latency)
        XCTAssertEqual(violation.severity, .high)
        XCTAssertEqual(violation.measuredValue, 600.0, accuracy: 0.01)
        XCTAssertEqual(violation.budgetLimit, 500.0, accuracy: 0.01)
    }
    
    func testBudgetViolationBattery() {
        let violation = BudgetViolation(
            type: .battery,
            severity: .medium,
            measuredValue: 1.5,
            budgetLimit: 1.0,
            timestamp: Date()
        )
        
        XCTAssertEqual(violation.type, .battery)
        XCTAssertEqual(violation.severity, .medium)
    }
    
    func testBudgetViolationThermal() {
        let violation = BudgetViolation(
            type: .thermal,
            severity: .critical,
            measuredValue: 3.0,
            budgetLimit: 1.0,
            timestamp: Date()
        )
        
        XCTAssertEqual(violation.type, .thermal)
        XCTAssertEqual(violation.severity, .critical)
    }
    
    func testBudgetViolationMemory() {
        let violation = BudgetViolation(
            type: .memory,
            severity: .low,
            measuredValue: 550.0,
            budgetLimit: 512.0,
            timestamp: Date()
        )
        
        XCTAssertEqual(violation.type, .memory)
        XCTAssertEqual(violation.severity, .low)
    }
    
    // MARK: - Violation Severity Tests
    
    func testViolationSeverityOrdering() {
        XCTAssertTrue(ViolationSeverity.low.rawValue < ViolationSeverity.medium.rawValue)
        XCTAssertTrue(ViolationSeverity.medium.rawValue < ViolationSeverity.high.rawValue)
        XCTAssertTrue(ViolationSeverity.high.rawValue < ViolationSeverity.critical.rawValue)
    }
    
    // MARK: - Budget Validation Tests
    
    func testIsWithinBudgetLatency() async {
        let budget = ComputeBudget(
            maxLatency: 500.0,
            maxBatteryDrainRate: 1.0,
            maxThermalLevel: 1,
            maxMemoryMB: 1024.0
        )
        
        // Within budget
        XCTAssertLessThanOrEqual(400.0, budget.maxLatency)
        
        // Exceeds budget
        XCTAssertGreaterThan(600.0, budget.maxLatency)
    }
    
    func testIsWithinBudgetBattery() async {
        let budget = ComputeBudget.default
        
        XCTAssertLessThanOrEqual(0.8, budget.maxBatteryDrainRate)
        XCTAssertGreaterThan(1.5, budget.maxBatteryDrainRate)
    }
    
    func testIsWithinBudgetThermal() async {
        let budget = ComputeBudget.default
        
        XCTAssertLessThanOrEqual(0, budget.maxThermalLevel)
        XCTAssertLessThanOrEqual(1, budget.maxThermalLevel)
        XCTAssertGreaterThan(2, budget.maxThermalLevel)
    }
    
    func testIsWithinBudgetMemory() async {
        let budget = ComputeBudget.default
        
        XCTAssertLessThanOrEqual(800.0, budget.maxMemoryMB)
        XCTAssertGreaterThan(1500.0, budget.maxMemoryMB)
    }
    
    // MARK: - Edge Cases
    
    func testZeroBudgetValues() {
        let budget = ComputeBudget(
            maxLatency: 0.0,
            maxBatteryDrainRate: 0.0,
            maxThermalLevel: 0,
            maxMemoryMB: 0.0
        )
        
        XCTAssertEqual(budget.maxLatency, 0.0)
        XCTAssertEqual(budget.maxBatteryDrainRate, 0.0)
        XCTAssertEqual(budget.maxThermalLevel, 0)
        XCTAssertEqual(budget.maxMemoryMB, 0.0)
    }
    
    func testNegativeBudgetValues() {
        let budget = ComputeBudget(
            maxLatency: -100.0,
            maxBatteryDrainRate: -1.0,
            maxThermalLevel: -1,
            maxMemoryMB: -512.0
        )
        
        // Should accept negative values (implementation may clamp)
        XCTAssertEqual(budget.maxLatency, -100.0)
        XCTAssertEqual(budget.maxBatteryDrainRate, -1.0)
    }
    
    func testVeryLargeBudgetValues() {
        let budget = ComputeBudget(
            maxLatency: 1_000_000.0,
            maxBatteryDrainRate: 1000.0,
            maxThermalLevel: 100,
            maxMemoryMB: 100_000.0
        )
        
        XCTAssertEqual(budget.maxLatency, 1_000_000.0)
        XCTAssertEqual(budget.maxBatteryDrainRate, 1000.0)
        XCTAssertEqual(budget.maxThermalLevel, 100)
        XCTAssertEqual(budget.maxMemoryMB, 100_000.0)
    }
    
    // MARK: - Budget Comparison Tests
    
    func testCompareBudgets() {
        let budget1 = ComputeBudget.conservative
        let budget2 = ComputeBudget.performance
        
        // Conservative should be stricter than performance
        XCTAssertLessThan(budget1.maxBatteryDrainRate, budget2.maxBatteryDrainRate)
        XCTAssertLessThan(budget1.maxThermalLevel, budget2.maxThermalLevel)
    }
    
    // MARK: - Profile Application Tests
    
    func testApplyConservativeProfile() async {
        let baseline = MeasuredBaseline(
            p95Latency: 100.0,
            meanBatteryDrain: 1.0,
            typicalMemoryMB: 500.0,
            thermalLevel: 0
        )
        
        let budget = await BudgetProfile.conservative.apply(to: baseline)
        
        // Conservative should multiply by 2.0 for latency
        XCTAssertEqual(budget.maxLatency, 200.0, accuracy: 0.01)
        
        // And reduce battery by 0.6
        XCTAssertEqual(budget.maxBatteryDrainRate, 0.6, accuracy: 0.01)
    }
    
    func testApplyPerformanceProfile() async {
        let baseline = MeasuredBaseline(
            p95Latency: 100.0,
            meanBatteryDrain: 1.0,
            typicalMemoryMB: 500.0,
            thermalLevel: 0
        )
        
        let budget = await BudgetProfile.performance.apply(to: baseline)
        
        // Performance should multiply by 1.1 for latency
        XCTAssertEqual(budget.maxLatency, 110.0, accuracy: 0.01)
        
        // And increase battery by 1.5
        XCTAssertEqual(budget.maxBatteryDrainRate, 1.5, accuracy: 0.01)
        
        // Thermal level should be 3
        XCTAssertEqual(budget.maxThermalLevel, 3)
    }
    
    // MARK: - Performance Tests
    
    func testBudgetCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = ComputeBudget.default
                _ = ComputeBudget.conservative
                _ = ComputeBudget.balanced
                _ = ComputeBudget.performance
            }
        }
    }
    
    func testProfileApplicationPerformance() {
        let baseline = MeasuredBaseline(
            p95Latency: 100.0,
            meanBatteryDrain: 1.0,
            typicalMemoryMB: 500.0,
            thermalLevel: 0
        )
        
        measure {
            Task {
                for _ in 0..<100 {
                    _ = await BudgetProfile.balanced.apply(to: baseline)
                }
            }
        }
    }
}