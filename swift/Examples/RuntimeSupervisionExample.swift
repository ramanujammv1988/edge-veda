import Foundation
import EdgeVeda

/// Phase 4 — Runtime Supervision demo.
///
/// Demonstrates the declarative budget system, adaptive profiles, runtime
/// policies, scheduler priority queues, latency tracking, resource monitoring,
/// thermal monitoring, battery drain tracking, and telemetry.
///
/// Run:
/// ```bash
/// swift run RuntimeSupervisionExample
/// ```
@available(iOS 15.0, macOS 12.0, *)
@main
struct RuntimeSupervisionExample {
    static func main() async throws {
        print("EdgeVeda Swift SDK — Runtime Supervision (Phase 4)")
        print("===================================================\n")

        // ─────────────────────────────────────────────────────
        // 1. Declarative Compute Budgets
        // ─────────────────────────────────────────────────────
        print("1. Declarative Compute Budgets")
        print("───────────────────────────────")

        // Explicit budget with hard limits
        let explicitBudget = EdgeVedaBudget(
            p95LatencyMs: 2000,
            batteryDrainPerTenMinutes: 3.0,
            maxThermalLevel: 2,
            memoryCeilingMb: 1200
        )
        print("Explicit budget:  \(explicitBudget)")

        // Validate — will warn about memory ceiling
        let warnings = explicitBudget.validate()
        if !warnings.isEmpty {
            print("Warnings:")
            for w in warnings { print("  ⚠️  \(w)") }
        }
        print()

        // ─────────────────────────────────────────────────────
        // 2. Adaptive Budget Profiles
        // ─────────────────────────────────────────────────────
        print("2. Adaptive Budget Profiles")
        print("───────────────────────────")
        for profile in BudgetProfile.allCases {
            let budget = EdgeVedaBudget.adaptive(profile)
            print("  .\(profile.rawValue)  →  \(budget)")
        }
        print()

        // Resolve a profile against a simulated baseline
        let baseline = MeasuredBaseline(
            measuredP95Ms: 1500,
            measuredDrainPerTenMin: 2.0,
            currentThermalState: 0,
            currentRssMb: 1800,
            sampleCount: 25,
            measuredAt: Date()
        )
        print("Measured baseline:  \(baseline)")

        for profile in BudgetProfile.allCases {
            let resolved = EdgeVedaBudget.resolve(profile: profile, baseline: baseline)
            print("  .\(profile.rawValue) resolved →  \(resolved)")
        }
        print()

        // ─────────────────────────────────────────────────────
        // 3. Budget Violations
        // ─────────────────────────────────────────────────────
        print("3. Budget Violation Events")
        print("──────────────────────────")

        let violation = BudgetViolation(
            constraint: .p95Latency,
            currentValue: 2500,
            budgetValue: 2000,
            mitigation: "Reduced vision FPS 30→15",
            timestamp: Date(),
            mitigated: true
        )
        print("  \(violation)")

        let memViolation = BudgetViolation(
            constraint: .memoryCeiling,
            currentValue: 2100,
            budgetValue: 1200,
            mitigation: "Observe-only: QoS cannot reduce model RSS",
            timestamp: Date(),
            mitigated: false,
            observeOnly: true
        )
        print("  \(memViolation)")
        print()

        // ─────────────────────────────────────────────────────
        // 4. Runtime Policy
        // ─────────────────────────────────────────────────────
        print("4. Runtime Policy")
        print("─────────────────")

        let policies: [RuntimePolicy] = [.standard, .lowPower, .aggressive]
        for policy in policies {
            print("  \(policy.name): \(policy)")
        }
        print()

        // Custom policy
        let customPolicy = RuntimePolicy(
            name: "background-sync",
            options: [.throttleOnBattery, .adaptiveMemory, .backgroundOptimization]
        )
        print("  Custom: \(customPolicy)")
        print()

        // ─────────────────────────────────────────────────────
        // 5. Latency Tracker
        // ─────────────────────────────────────────────────────
        print("5. Latency Tracker")
        print("──────────────────")

        let latencyTracker = LatencyTracker()

        // Simulate 30 inference latency samples
        let sampleLatencies: [Double] = (0..<30).map { _ in
            Double.random(in: 800...2200)
        }
        for lat in sampleLatencies {
            await latencyTracker.record(lat)
        }

        let count = await latencyTracker.sampleCount
        let p50 = await latencyTracker.percentile(0.50) ?? 0
        let p95 = await latencyTracker.percentile(0.95) ?? 0
        let p99 = await latencyTracker.percentile(0.99) ?? 0
        let isWarmedUp = await latencyTracker.isWarmedUp

        print("  Samples: \(count), warmed-up: \(isWarmedUp)")
        print("  p50=\(String(format: "%.0f", p50))ms  p95=\(String(format: "%.0f", p95))ms  p99=\(String(format: "%.0f", p99))ms")
        print()

        // ─────────────────────────────────────────────────────
        // 6. Resource Monitor
        // ─────────────────────────────────────────────────────
        print("6. Resource Monitor (Memory RSS)")
        print("────────────────────────────────")

        let resourceMonitor = ResourceMonitor()
        for _ in 0..<5 {
            await resourceMonitor.sample()
        }

        let currentRss = await resourceMonitor.currentRssMb
        let peakRss = await resourceMonitor.peakRssMb
        let avgRss = await resourceMonitor.averageRssMb
        let rssSamples = await resourceMonitor.sampleCount

        print("  Current RSS: \(String(format: "%.1f", currentRss)) MB")
        print("  Peak RSS:    \(String(format: "%.1f", peakRss)) MB")
        print("  Average RSS: \(String(format: "%.1f", avgRss)) MB")
        print("  Samples:     \(rssSamples)")
        print()

        // ─────────────────────────────────────────────────────
        // 7. Thermal Monitor
        // ─────────────────────────────────────────────────────
        print("7. Thermal Monitor")
        print("──────────────────")

        let thermalMonitor = ThermalMonitor()
        let thermalLevel = await thermalMonitor.currentLevel
        let thermalName = await thermalMonitor.currentStateName
        let shouldThrottle = await thermalMonitor.shouldThrottle
        let isCritical = await thermalMonitor.isCritical

        print("  Level: \(thermalLevel) (\(thermalName))")
        print("  Should throttle: \(shouldThrottle)")
        print("  Is critical:     \(isCritical)")

        // Register a thermal listener
        let listenerId = await thermalMonitor.addListener { level in
            print("  🌡️  Thermal state changed → level \(level)")
        }
        print("  Listener registered: \(listenerId.uuidString.prefix(8))…")
        await thermalMonitor.removeListener(id: listenerId)
        print()

        // ─────────────────────────────────────────────────────
        // 8. Battery Drain Tracker
        // ─────────────────────────────────────────────────────
        print("8. Battery Drain Tracker")
        print("────────────────────────")

        let batteryTracker = BatteryDrainTracker()
        let supported = batteryTracker.isSupported

        print("  Supported: \(supported)")
        if supported {
            if let level = await batteryTracker.currentBatteryLevel {
                print("  Battery level: \(String(format: "%.0f", level * 100))%")
            }
            if let drain = await batteryTracker.currentDrainRate {
                print("  Drain rate: \(String(format: "%.2f", drain))% / 10 min")
            } else {
                print("  Drain rate: accumulating samples…")
            }
        } else {
            print("  (Battery monitoring unavailable on this platform)")
        }
        print()

        // ─────────────────────────────────────────────────────
        // 9. Scheduler (priority queue)
        // ─────────────────────────────────────────────────────
        print("9. Scheduler — Priority Task Queue")
        print("───────────────────────────────────")

        let scheduler = Scheduler()

        // Schedule tasks at different priorities
        let highResult = await scheduler.schedule(priority: .high) {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return "high-priority result"
        }

        let normalResult = await scheduler.schedule(priority: .normal) {
            return "normal-priority result"
        }

        let lowResult = await scheduler.schedule(priority: .low) {
            return "low-priority result"
        }

        print("  HIGH   → \(highResult ?? "nil")")
        print("  NORMAL → \(normalResult ?? "nil")")
        print("  LOW    → \(lowResult ?? "nil")")

        let stats = await scheduler.stats
        print("  Stats: submitted=\(stats.submitted), completed=\(stats.completed), cancelled=\(stats.cancelled)")
        print()

        // ─────────────────────────────────────────────────────
        // 10. Telemetry
        // ─────────────────────────────────────────────────────
        print("10. Telemetry — Structured Logging & Metrics")
        print("─────────────────────────────────────────────")

        let telemetry = Telemetry()

        await telemetry.log(.info, "Runtime supervision example started")
        await telemetry.log(.debug, "Latency tracker warmed up with \(count) samples")
        await telemetry.recordMetric(name: "inference.p95", value: p95)
        await telemetry.recordMetric(name: "memory.rss_mb", value: currentRss)
        await telemetry.recordMetric(name: "thermal.level", value: Double(thermalLevel))

        let metrics = await telemetry.recentMetrics(limit: 5)
        print("  Recent metrics:")
        for m in metrics {
            print("    \(m.name) = \(String(format: "%.1f", m.value))")
        }

        let logCount = await telemetry.logCount
        print("  Log entries: \(logCount)")
        print()

        // ─────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────
        print("===================================================")
        print("Phase 4 Runtime Supervision — all components active")
        print("  ✅ ComputeBudget (declarative + adaptive)")
        print("  ✅ BudgetProfile (conservative / balanced / performance)")
        print("  ✅ MeasuredBaseline + budget resolution")
        print("  ✅ BudgetViolation events")
        print("  ✅ RuntimePolicy (standard / lowPower / aggressive / custom)")
        print("  ✅ LatencyTracker (percentiles, warm-up)")
        print("  ✅ ResourceMonitor (RSS, peak, average)")
        print("  ✅ ThermalMonitor (level, listeners)")
        print("  ✅ BatteryDrainTracker (drain rate, platform-aware)")
        print("  ✅ Scheduler (priority queue, stats)")
        print("  ✅ Telemetry (structured logs, metrics)")
        print("===================================================")
    }
}