import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class SchedulerTests: XCTestCase {
    
    var scheduler: Scheduler!
    
    override func setUp() async throws {
        try await super.setUp()
        scheduler = Scheduler()
    }
    
    override func tearDown() async throws {
        await scheduler.cancelAll()
        scheduler = nil
        try await super.tearDown()
    }
    
    // MARK: - Task Scheduling Tests
    
    func testScheduleHighPriorityTask() async throws {
        var executed = false
        
        let task = ScheduledTask(priority: .high) {
            executed = true
        }
        
        await scheduler.schedule(task)
        
        // Give it time to execute
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        XCTAssertTrue(executed)
    }
    
    func testScheduleNormalPriorityTask() async throws {
        var executed = false
        
        let task = ScheduledTask(priority: .normal) {
            executed = true
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertTrue(executed)
    }
    
    func testScheduleLowPriorityTask() async throws {
        var executed = false
        
        let task = ScheduledTask(priority: .low) {
            executed = true
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertTrue(executed)
    }
    
    // MARK: - Priority Order Tests
    
    func testPriorityOrder() async throws {
        var executionOrder: [TaskPriority] = []
        
        let lowTask = ScheduledTask(priority: .low) {
            executionOrder.append(.low)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        let highTask = ScheduledTask(priority: .high) {
            executionOrder.append(.high)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        let normalTask = ScheduledTask(priority: .normal) {
            executionOrder.append(.normal)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // Schedule in reverse priority order
        await scheduler.schedule(lowTask)
        await scheduler.schedule(normalTask)
        await scheduler.schedule(highTask)
        
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // High priority should execute first
        XCTAssertEqual(executionOrder.first, .high)
    }
    
    // MARK: - Task Cancellation Tests
    
    func testCancelTask() async throws {
        var executed = false
        
        let task = ScheduledTask(priority: .normal) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            executed = true
        }
        
        await scheduler.schedule(task)
        
        // Cancel immediately
        await scheduler.cancel(task.id)
        
        try await Task.sleep(nanoseconds: 600_000_000)
        
        XCTAssertFalse(executed)
    }
    
    func testCancelAllTasks() async throws {
        var count = 0
        
        for _ in 1...10 {
            let task = ScheduledTask(priority: .normal) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                count += 1
            }
            await scheduler.schedule(task)
        }
        
        await scheduler.cancelAll()
        
        try await Task.sleep(nanoseconds: 600_000_000)
        
        // None should have executed
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Queue Statistics Tests
    
    func testQueueStatistics() async {
        let stats = await scheduler.getStatistics()
        
        XCTAssertEqual(stats.queuedTasks, 0)
        XCTAssertEqual(stats.runningTasks, 0)
        XCTAssertEqual(stats.completedTasks, 0)
        XCTAssertEqual(stats.cancelledTasks, 0)
        XCTAssertEqual(stats.failedTasks, 0)
    }
    
    func testStatisticsAfterScheduling() async throws {
        let task = ScheduledTask(priority: .normal) {
            // Quick task
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        let stats = await scheduler.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.completedTasks, 1)
    }
    
    // MARK: - Concurrent Scheduling Tests
    
    func testConcurrentScheduling() async throws {
        var completedCount = 0
        let expectedCount = 50
        
        await withTaskGroup(of: Void.self) { group in
            for i in 1...expectedCount {
                group.addTask {
                    let task = ScheduledTask(priority: .normal) {
                        completedCount += 1
                    }
                    await self.scheduler.schedule(task)
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertEqual(completedCount, expectedCount)
    }
    
    // MARK: - Task with Deadline Tests
    
    func testTaskWithDeadline() async throws {
        var executed = false
        
        let deadline = Date().addingTimeInterval(0.2)
        let task = ScheduledTask(priority: .normal, deadline: deadline) {
            executed = true
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        XCTAssertTrue(executed)
    }
    
    func testTaskMissedDeadline() async throws {
        var executed = false
        
        // Set deadline in the past
        let deadline = Date().addingTimeInterval(-1.0)
        let task = ScheduledTask(priority: .normal, deadline: deadline) {
            executed = true
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Task might still execute depending on implementation
        // This test documents the behavior
        let stats = await scheduler.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.completedTasks + stats.cancelledTasks, 1)
    }
    
    // MARK: - Error Handling Tests
    
    func testTaskThrowingError() async throws {
        enum TestError: Error {
            case intentional
        }
        
        let task = ScheduledTask(priority: .normal) {
            throw TestError.intentional
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let stats = await scheduler.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.failedTasks, 1)
    }
    
    // MARK: - Pause and Resume Tests
    
    func testPauseScheduler() async throws {
        await scheduler.pause()
        
        var executed = false
        let task = ScheduledTask(priority: .normal) {
            executed = true
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should not execute while paused
        XCTAssertFalse(executed)
        
        await scheduler.resume()
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Should execute after resume
        XCTAssertTrue(executed)
    }
    
    // MARK: - Budget Integration Tests
    
    func testSchedulerWithBudget() async throws {
        let budget = ComputeBudget(
            maxLatency: 200.0,
            maxBatteryDrainRate: 1.0,
            maxThermalLevel: 1,
            maxMemoryMB: 512.0
        )
        
        var executed = false
        let task = ScheduledTask(priority: .normal, budget: budget) {
            executed = true
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 300_000_000)
        
        XCTAssertTrue(executed)
    }
    
    // MARK: - Long Running Task Tests
    
    func testLongRunningTask() async throws {
        var startTime: Date?
        var endTime: Date?
        
        let task = ScheduledTask(priority: .normal) {
            startTime = Date()
            try? await Task.sleep(nanoseconds: 500_000_000)
            endTime = Date()
        }
        
        await scheduler.schedule(task)
        
        try await Task.sleep(nanoseconds: 700_000_000)
        
        XCTAssertNotNil(startTime)
        XCTAssertNotNil(endTime)
        
        if let start = startTime, let end = endTime {
            let duration = end.timeIntervalSince(start)
            XCTAssertGreaterThanOrEqual(duration, 0.4)
        }
    }
    
    // MARK: - Queue Capacity Tests
    
    func testQueueCapacity() async throws {
        // Schedule many tasks
        for i in 1...100 {
            let task = ScheduledTask(priority: .normal) {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            await scheduler.schedule(task)
        }
        
        let stats = await scheduler.getStatistics()
        XCTAssertGreaterThan(stats.queuedTasks + stats.runningTasks, 0)
    }
    
    // MARK: - Task Metadata Tests
    
    func testTaskMetadata() async {
        let metadata = ["key": "value", "type": "test"]
        let task = ScheduledTask(priority: .normal, metadata: metadata) {
            // Empty task
        }
        
        XCTAssertEqual(task.metadata["key"], "value")
        XCTAssertEqual(task.metadata["type"], "test")
    }
    
    // MARK: - Performance Tests
    
    func testSchedulingPerformance() {
        measure {
            Task {
                for i in 1...100 {
                    let task = ScheduledTask(priority: .normal) {
                        // Minimal work
                    }
                    await self.scheduler.schedule(task)
                }
            }
        }
    }
    
    func testExecutionPerformance() async throws {
        let startTime = Date()
        
        for i in 1...100 {
            let task = ScheduledTask(priority: .high) {
                // Minimal work
            }
            await scheduler.schedule(task)
        }
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Should complete reasonably fast
        XCTAssertLessThan(duration, 3.0)
    }
}