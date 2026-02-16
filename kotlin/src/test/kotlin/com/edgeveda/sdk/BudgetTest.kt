package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test
import java.util.Date

/**
 * Tests for EdgeVedaBudget, BudgetProfile, MeasuredBaseline, and BudgetViolation.
 */
class BudgetTest {

    // -------------------------------------------------------------------
    // EdgeVedaBudget Creation
    // -------------------------------------------------------------------

    @Test
    fun `test default budget has all null constraints`() {
        val budget = EdgeVedaBudget()
        assertNull(budget.p95LatencyMs)
        assertNull(budget.batteryDrainPerTenMinutes)
        assertNull(budget.maxThermalLevel)
        assertNull(budget.memoryCeilingMb)
        assertNull(budget.adaptiveProfile)
    }

    @Test
    fun `test custom budget stores all values`() {
        val budget = EdgeVedaBudget(
            p95LatencyMs = 2000,
            batteryDrainPerTenMinutes = 3.0,
            maxThermalLevel = 2,
            memoryCeilingMb = 1200
        )
        assertEquals(2000, budget.p95LatencyMs)
        assertEquals(3.0, budget.batteryDrainPerTenMinutes!!, 0.01)
        assertEquals(2, budget.maxThermalLevel)
        assertEquals(1200, budget.memoryCeilingMb)
    }

    @Test
    fun `test partial budget with only latency`() {
        val budget = EdgeVedaBudget(p95LatencyMs = 1500)
        assertEquals(1500, budget.p95LatencyMs)
        assertNull(budget.batteryDrainPerTenMinutes)
        assertNull(budget.maxThermalLevel)
        assertNull(budget.memoryCeilingMb)
    }

    @Test
    fun `test budget data class equality`() {
        val b1 = EdgeVedaBudget(p95LatencyMs = 2000, maxThermalLevel = 2)
        val b2 = EdgeVedaBudget(p95LatencyMs = 2000, maxThermalLevel = 2)
        assertEquals(b1, b2)
    }

    @Test
    fun `test budget data class inequality`() {
        val b1 = EdgeVedaBudget(p95LatencyMs = 2000)
        val b2 = EdgeVedaBudget(p95LatencyMs = 3000)
        assertNotEquals(b1, b2)
    }

    // -------------------------------------------------------------------
    // Adaptive Budget
    // -------------------------------------------------------------------

    @Test
    fun `test adaptive budget stores profile`() {
        val budget = EdgeVedaBudget.adaptive(BudgetProfile.BALANCED)
        assertEquals(BudgetProfile.BALANCED, budget.adaptiveProfile)
        assertNull(budget.p95LatencyMs)
        assertNull(budget.batteryDrainPerTenMinutes)
        assertNull(budget.maxThermalLevel)
        assertNull(budget.memoryCeilingMb)
    }

    @Test
    fun `test adaptive conservative`() {
        val budget = EdgeVedaBudget.adaptive(BudgetProfile.CONSERVATIVE)
        assertEquals(BudgetProfile.CONSERVATIVE, budget.adaptiveProfile)
    }

    @Test
    fun `test adaptive performance`() {
        val budget = EdgeVedaBudget.adaptive(BudgetProfile.PERFORMANCE)
        assertEquals(BudgetProfile.PERFORMANCE, budget.adaptiveProfile)
    }

    // -------------------------------------------------------------------
    // Budget Resolution
    // -------------------------------------------------------------------

    @Test
    fun `test resolve conservative profile`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 100.0,
            measuredDrainPerTenMin = 1.0,
            currentThermalState = 0,
            currentRssMb = 500.0,
            sampleCount = 25,
            measuredAt = Date()
        )

        val resolved = EdgeVedaBudget.resolve(BudgetProfile.CONSERVATIVE, baseline)

        // p95 * 2.0
        assertEquals(200, resolved.p95LatencyMs)
        // drain * 0.6
        assertEquals(0.6, resolved.batteryDrainPerTenMinutes!!, 0.01)
        // thermal: max(1, currentThermalState) since current < 1 → 1
        assertEquals(1, resolved.maxThermalLevel)
        // memory is always null (observe-only)
        assertNull(resolved.memoryCeilingMb)
    }

    @Test
    fun `test resolve balanced profile`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 200.0,
            measuredDrainPerTenMin = 2.0,
            currentThermalState = 0,
            currentRssMb = 600.0,
            sampleCount = 30,
            measuredAt = Date()
        )

        val resolved = EdgeVedaBudget.resolve(BudgetProfile.BALANCED, baseline)

        // p95 * 1.5
        assertEquals(300, resolved.p95LatencyMs)
        // drain * 1.0
        assertEquals(2.0, resolved.batteryDrainPerTenMinutes!!, 0.01)
        // thermal = 1
        assertEquals(1, resolved.maxThermalLevel)
        assertNull(resolved.memoryCeilingMb)
    }

    @Test
    fun `test resolve performance profile`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 100.0,
            measuredDrainPerTenMin = 1.0,
            currentThermalState = 1,
            currentRssMb = 800.0,
            sampleCount = 20,
            measuredAt = Date()
        )

        val resolved = EdgeVedaBudget.resolve(BudgetProfile.PERFORMANCE, baseline)

        // p95 * 1.1
        assertEquals(110, resolved.p95LatencyMs)
        // drain * 1.5
        assertEquals(1.5, resolved.batteryDrainPerTenMinutes!!, 0.01)
        // thermal = 3
        assertEquals(3, resolved.maxThermalLevel)
        assertNull(resolved.memoryCeilingMb)
    }

    @Test
    fun `test resolve with null drain`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 150.0,
            measuredDrainPerTenMin = null,
            currentThermalState = 0,
            currentRssMb = 400.0,
            sampleCount = 25,
            measuredAt = Date()
        )

        val resolved = EdgeVedaBudget.resolve(BudgetProfile.BALANCED, baseline)

        assertEquals(225, resolved.p95LatencyMs) // 150 * 1.5
        assertNull(resolved.batteryDrainPerTenMinutes) // null * anything = null
    }

    @Test
    fun `test resolve conservative with high thermal preserves state`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 100.0,
            measuredDrainPerTenMin = 1.0,
            currentThermalState = 2,
            currentRssMb = 500.0,
            sampleCount = 25,
            measuredAt = Date()
        )

        val resolved = EdgeVedaBudget.resolve(BudgetProfile.CONSERVATIVE, baseline)

        // When currentThermalState >= 1, conservative keeps it
        assertEquals(2, resolved.maxThermalLevel)
    }

    // -------------------------------------------------------------------
    // Budget Validation
    // -------------------------------------------------------------------

    @Test
    fun `test validate realistic budget returns no warnings`() {
        val budget = EdgeVedaBudget(
            p95LatencyMs = 2000,
            batteryDrainPerTenMinutes = 3.0,
            maxThermalLevel = 2,
            memoryCeilingMb = 2500
        )
        val warnings = budget.validate()
        assertTrue(warnings.isEmpty())
    }

    @Test
    fun `test validate warns on low latency`() {
        val budget = EdgeVedaBudget(p95LatencyMs = 100)
        val warnings = budget.validate()
        assertEquals(1, warnings.size)
        assertTrue(warnings[0].contains("p95LatencyMs=100"))
    }

    @Test
    fun `test validate warns on low battery drain`() {
        val budget = EdgeVedaBudget(batteryDrainPerTenMinutes = 0.1)
        val warnings = budget.validate()
        assertEquals(1, warnings.size)
        assertTrue(warnings[0].contains("batteryDrainPerTenMinutes"))
    }

    @Test
    fun `test validate warns on low memory ceiling`() {
        val budget = EdgeVedaBudget(memoryCeilingMb = 500)
        val warnings = budget.validate()
        assertEquals(1, warnings.size)
        assertTrue(warnings[0].contains("memoryCeilingMb=500"))
    }

    @Test
    fun `test validate multiple warnings`() {
        val budget = EdgeVedaBudget(
            p95LatencyMs = 100,
            batteryDrainPerTenMinutes = 0.1,
            memoryCeilingMb = 500
        )
        val warnings = budget.validate()
        assertEquals(3, warnings.size)
    }

    @Test
    fun `test validate null constraints no warnings`() {
        val budget = EdgeVedaBudget()
        val warnings = budget.validate()
        assertTrue(warnings.isEmpty())
    }

    // -------------------------------------------------------------------
    // Budget toString
    // -------------------------------------------------------------------

    @Test
    fun `test explicit budget toString`() {
        val budget = EdgeVedaBudget(p95LatencyMs = 2000, maxThermalLevel = 2)
        val str = budget.toString()
        assertTrue(str.contains("p95LatencyMs=2000"))
        assertTrue(str.contains("maxThermalLevel=2"))
    }

    @Test
    fun `test adaptive budget toString`() {
        val budget = EdgeVedaBudget.adaptive(BudgetProfile.BALANCED)
        val str = budget.toString()
        assertTrue(str.contains("adaptive"))
        assertTrue(str.contains("balanced"))
    }

    // -------------------------------------------------------------------
    // MeasuredBaseline
    // -------------------------------------------------------------------

    @Test
    fun `test measured baseline stores values`() {
        val now = Date()
        val baseline = MeasuredBaseline(
            measuredP95Ms = 250.0,
            measuredDrainPerTenMin = 1.2,
            currentThermalState = 1,
            currentRssMb = 600.0,
            sampleCount = 30,
            measuredAt = now
        )

        assertEquals(250.0, baseline.measuredP95Ms, 0.01)
        assertEquals(1.2, baseline.measuredDrainPerTenMin!!, 0.01)
        assertEquals(1, baseline.currentThermalState)
        assertEquals(600.0, baseline.currentRssMb, 0.01)
        assertEquals(30, baseline.sampleCount)
        assertEquals(now, baseline.measuredAt)
    }

    @Test
    fun `test measured baseline toString`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 250.0,
            measuredDrainPerTenMin = 1.2,
            currentThermalState = 1,
            currentRssMb = 600.0,
            sampleCount = 30,
            measuredAt = Date()
        )
        val str = baseline.toString()
        assertTrue(str.contains("p95=250ms"))
        assertTrue(str.contains("drain=1.2%"))
        assertTrue(str.contains("thermal=1"))
        assertTrue(str.contains("rss=600MB"))
        assertTrue(str.contains("samples=30"))
    }

    @Test
    fun `test measured baseline with null drain`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 100.0,
            measuredDrainPerTenMin = null,
            currentThermalState = 0,
            currentRssMb = 400.0,
            sampleCount = 20,
            measuredAt = Date()
        )
        assertNull(baseline.measuredDrainPerTenMin)
        assertTrue(baseline.toString().contains("drain=n/a"))
    }

    // -------------------------------------------------------------------
    // BudgetViolation
    // -------------------------------------------------------------------

    @Test
    fun `test budget violation latency`() {
        val violation = BudgetViolation(
            constraint = BudgetConstraint.P95_LATENCY,
            currentValue = 600.0,
            budgetValue = 500.0,
            mitigation = "Reduce inference frequency",
            timestamp = Date(),
            mitigated = false
        )

        assertEquals(BudgetConstraint.P95_LATENCY, violation.constraint)
        assertEquals(600.0, violation.currentValue, 0.01)
        assertEquals(500.0, violation.budgetValue, 0.01)
        assertFalse(violation.mitigated)
        assertFalse(violation.observeOnly)
    }

    @Test
    fun `test budget violation battery`() {
        val violation = BudgetViolation(
            constraint = BudgetConstraint.BATTERY_DRAIN,
            currentValue = 5.0,
            budgetValue = 3.0,
            mitigation = "Lower model quality",
            timestamp = Date(),
            mitigated = true
        )

        assertEquals(BudgetConstraint.BATTERY_DRAIN, violation.constraint)
        assertTrue(violation.mitigated)
    }

    @Test
    fun `test budget violation memory is observe only`() {
        val violation = BudgetViolation(
            constraint = BudgetConstraint.MEMORY_CEILING,
            currentValue = 1500.0,
            budgetValue = 1200.0,
            mitigation = "Observe only",
            timestamp = Date(),
            mitigated = false,
            observeOnly = true
        )

        assertTrue(violation.observeOnly)
        assertTrue(violation.toString().contains("observeOnly=true"))
    }

    @Test
    fun `test budget violation thermal`() {
        val violation = BudgetViolation(
            constraint = BudgetConstraint.THERMAL_LEVEL,
            currentValue = 3.0,
            budgetValue = 1.0,
            mitigation = "Pause high-priority workloads",
            timestamp = Date(),
            mitigated = false
        )

        assertEquals(BudgetConstraint.THERMAL_LEVEL, violation.constraint)
    }

    // -------------------------------------------------------------------
    // BudgetConstraint Enum
    // -------------------------------------------------------------------

    @Test
    fun `test budget constraint enum values`() {
        val values = BudgetConstraint.entries
        assertEquals(4, values.size)
        assertTrue(values.contains(BudgetConstraint.P95_LATENCY))
        assertTrue(values.contains(BudgetConstraint.BATTERY_DRAIN))
        assertTrue(values.contains(BudgetConstraint.THERMAL_LEVEL))
        assertTrue(values.contains(BudgetConstraint.MEMORY_CEILING))
    }

    // -------------------------------------------------------------------
    // BudgetProfile Enum
    // -------------------------------------------------------------------

    @Test
    fun `test budget profile enum values`() {
        val values = BudgetProfile.entries
        assertEquals(3, values.size)
        assertTrue(values.contains(BudgetProfile.CONSERVATIVE))
        assertTrue(values.contains(BudgetProfile.BALANCED))
        assertTrue(values.contains(BudgetProfile.PERFORMANCE))
    }

    // -------------------------------------------------------------------
    // WorkloadPriority and WorkloadId
    // -------------------------------------------------------------------

    @Test
    fun `test workload priority enum`() {
        assertEquals(2, WorkloadPriority.entries.size)
        assertTrue(WorkloadPriority.entries.contains(WorkloadPriority.LOW))
        assertTrue(WorkloadPriority.entries.contains(WorkloadPriority.HIGH))
    }

    @Test
    fun `test workload id enum`() {
        assertEquals(2, WorkloadId.entries.size)
        assertTrue(WorkloadId.entries.contains(WorkloadId.VISION))
        assertTrue(WorkloadId.entries.contains(WorkloadId.TEXT))
    }

    // -------------------------------------------------------------------
    // Edge Cases
    // -------------------------------------------------------------------

    @Test
    fun `test budget with zero values`() {
        val budget = EdgeVedaBudget(
            p95LatencyMs = 0,
            batteryDrainPerTenMinutes = 0.0,
            maxThermalLevel = 0,
            memoryCeilingMb = 0
        )
        assertEquals(0, budget.p95LatencyMs)
        assertEquals(0.0, budget.batteryDrainPerTenMinutes!!, 0.001)
    }

    @Test
    fun `test resolve with zero baseline p95`() {
        val baseline = MeasuredBaseline(
            measuredP95Ms = 0.0,
            measuredDrainPerTenMin = 0.0,
            currentThermalState = 0,
            currentRssMb = 0.0,
            sampleCount = 20,
            measuredAt = Date()
        )

        val resolved = EdgeVedaBudget.resolve(BudgetProfile.BALANCED, baseline)
        assertEquals(0, resolved.p95LatencyMs) // 0 * 1.5 = 0
    }
}