package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test
import java.util.Date

/**
 * Tests for Telemetry supporting types: LatencyMetric, BudgetViolationRecord,
 * ResourceSnapshot, LatencyStats, BudgetViolationType, ViolationSeverity.
 *
 * NOTE: The Telemetry singleton itself uses android.util.Log and cannot be
 * instantiated in pure JVM tests without Robolectric. These tests cover
 * the pure data classes and enums only.
 */
class TelemetryTest {

    // -------------------------------------------------------------------
    // LatencyMetric
    // -------------------------------------------------------------------

    @Test
    fun `test latency metric creation with all fields`() {
        val start = Date()
        val end = Date(start.time + 150)
        val metric = LatencyMetric(
            requestId = "req-001",
            modelName = "phi-3-mini",
            startTime = start,
            endTime = end,
            latencyMs = 150.0
        )

        assertEquals("req-001", metric.requestId)
        assertEquals("phi-3-mini", metric.modelName)
        assertEquals(start, metric.startTime)
        assertEquals(end, metric.endTime)
        assertEquals(150.0, metric.latencyMs!!, 0.01)
    }

    @Test
    fun `test latency metric with null optional fields`() {
        val metric = LatencyMetric(
            requestId = "req-002",
            modelName = null,
            startTime = null,
            endTime = null,
            latencyMs = null
        )

        assertEquals("req-002", metric.requestId)
        assertNull(metric.modelName)
        assertNull(metric.startTime)
        assertNull(metric.endTime)
        assertNull(metric.latencyMs)
    }

    @Test
    fun `test latency metric equality`() {
        val time = Date()
        val m1 = LatencyMetric("req-1", "model-a", time, null, 42.0)
        val m2 = LatencyMetric("req-1", "model-a", time, null, 42.0)
        assertEquals(m1, m2)
    }

    @Test
    fun `test latency metric inequality`() {
        val time = Date()
        val m1 = LatencyMetric("req-1", "model-a", time, null, 42.0)
        val m2 = LatencyMetric("req-2", "model-a", time, null, 42.0)
        assertNotEquals(m1, m2)
    }

    @Test
    fun `test latency metric copy`() {
        val metric = LatencyMetric("req-1", "model-a", Date(), null, null)
        val updated = metric.copy(latencyMs = 100.0, endTime = Date())

        assertEquals("req-1", updated.requestId)
        assertEquals(100.0, updated.latencyMs!!, 0.01)
        assertNotNull(updated.endTime)
    }

    @Test
    fun `test latency metric hashCode consistent with equals`() {
        val time = Date()
        val m1 = LatencyMetric("req-1", null, time, null, 50.0)
        val m2 = LatencyMetric("req-1", null, time, null, 50.0)
        assertEquals(m1.hashCode(), m2.hashCode())
    }

    // -------------------------------------------------------------------
    // BudgetViolationRecord
    // -------------------------------------------------------------------

    @Test
    fun `test budget violation record creation`() {
        val now = Date()
        val record = BudgetViolationRecord(
            timestamp = now,
            type = BudgetViolationType.LATENCY,
            current = 500.0,
            limit = 400.0,
            severity = ViolationSeverity.WARNING
        )

        assertEquals(now, record.timestamp)
        assertEquals(BudgetViolationType.LATENCY, record.type)
        assertEquals(500.0, record.current, 0.01)
        assertEquals(400.0, record.limit, 0.01)
        assertEquals(ViolationSeverity.WARNING, record.severity)
    }

    @Test
    fun `test budget violation record memory type`() {
        val record = BudgetViolationRecord(
            timestamp = Date(),
            type = BudgetViolationType.MEMORY,
            current = 2048.0,
            limit = 1500.0,
            severity = ViolationSeverity.CRITICAL
        )

        assertEquals(BudgetViolationType.MEMORY, record.type)
        assertEquals(ViolationSeverity.CRITICAL, record.severity)
    }

    @Test
    fun `test budget violation record battery type`() {
        val record = BudgetViolationRecord(
            timestamp = Date(),
            type = BudgetViolationType.BATTERY,
            current = 5.0,
            limit = 3.0,
            severity = ViolationSeverity.INFO
        )

        assertEquals(BudgetViolationType.BATTERY, record.type)
        assertEquals(ViolationSeverity.INFO, record.severity)
    }

    @Test
    fun `test budget violation record thermal type`() {
        val record = BudgetViolationRecord(
            timestamp = Date(),
            type = BudgetViolationType.THERMAL,
            current = 3.0,
            limit = 1.0,
            severity = ViolationSeverity.CRITICAL
        )

        assertEquals(BudgetViolationType.THERMAL, record.type)
    }

    @Test
    fun `test budget violation record equality`() {
        val time = Date()
        val r1 = BudgetViolationRecord(time, BudgetViolationType.LATENCY, 50.0, 40.0, ViolationSeverity.WARNING)
        val r2 = BudgetViolationRecord(time, BudgetViolationType.LATENCY, 50.0, 40.0, ViolationSeverity.WARNING)
        assertEquals(r1, r2)
    }

    @Test
    fun `test budget violation record inequality by type`() {
        val time = Date()
        val r1 = BudgetViolationRecord(time, BudgetViolationType.LATENCY, 50.0, 40.0, ViolationSeverity.WARNING)
        val r2 = BudgetViolationRecord(time, BudgetViolationType.MEMORY, 50.0, 40.0, ViolationSeverity.WARNING)
        assertNotEquals(r1, r2)
    }

    @Test
    fun `test budget violation record copy`() {
        val original = BudgetViolationRecord(
            timestamp = Date(),
            type = BudgetViolationType.LATENCY,
            current = 100.0,
            limit = 80.0,
            severity = ViolationSeverity.INFO
        )
        val escalated = original.copy(severity = ViolationSeverity.CRITICAL)

        assertEquals(BudgetViolationType.LATENCY, escalated.type)
        assertEquals(ViolationSeverity.CRITICAL, escalated.severity)
        assertEquals(100.0, escalated.current, 0.01)
    }

    // -------------------------------------------------------------------
    // ResourceSnapshot
    // -------------------------------------------------------------------

    @Test
    fun `test resource snapshot creation with all fields`() {
        val now = Date()
        val snapshot = ResourceSnapshot(
            timestamp = now,
            memoryMb = 512.0,
            batteryLevel = 0.85,
            thermalLevel = 1
        )

        assertEquals(now, snapshot.timestamp)
        assertEquals(512.0, snapshot.memoryMb, 0.01)
        assertEquals(0.85, snapshot.batteryLevel!!, 0.01)
        assertEquals(1, snapshot.thermalLevel)
    }

    @Test
    fun `test resource snapshot with null battery`() {
        val snapshot = ResourceSnapshot(
            timestamp = Date(),
            memoryMb = 256.0,
            batteryLevel = null,
            thermalLevel = 0
        )

        assertNull(snapshot.batteryLevel)
    }

    @Test
    fun `test resource snapshot equality`() {
        val time = Date()
        val s1 = ResourceSnapshot(time, 512.0, 0.9, 1)
        val s2 = ResourceSnapshot(time, 512.0, 0.9, 1)
        assertEquals(s1, s2)
    }

    @Test
    fun `test resource snapshot inequality`() {
        val time = Date()
        val s1 = ResourceSnapshot(time, 512.0, 0.9, 1)
        val s2 = ResourceSnapshot(time, 1024.0, 0.9, 1)
        assertNotEquals(s1, s2)
    }

    @Test
    fun `test resource snapshot copy`() {
        val snapshot = ResourceSnapshot(Date(), 512.0, 0.8, 0)
        val updated = snapshot.copy(thermalLevel = 2, memoryMb = 700.0)

        assertEquals(2, updated.thermalLevel)
        assertEquals(700.0, updated.memoryMb, 0.01)
        assertEquals(0.8, updated.batteryLevel!!, 0.01)
    }

    @Test
    fun `test resource snapshot zero memory`() {
        val snapshot = ResourceSnapshot(Date(), 0.0, 1.0, 0)
        assertEquals(0.0, snapshot.memoryMb, 0.001)
    }

    @Test
    fun `test resource snapshot high thermal level`() {
        val snapshot = ResourceSnapshot(Date(), 1024.0, 0.1, 3)
        assertEquals(3, snapshot.thermalLevel)
    }

    // -------------------------------------------------------------------
    // LatencyStats
    // -------------------------------------------------------------------

    @Test
    fun `test latency stats creation`() {
        val stats = LatencyStats(
            count = 100,
            min = 10.0,
            max = 500.0,
            mean = 150.0,
            p50 = 120.0,
            p95 = 400.0,
            p99 = 480.0
        )

        assertEquals(100, stats.count)
        assertEquals(10.0, stats.min, 0.01)
        assertEquals(500.0, stats.max, 0.01)
        assertEquals(150.0, stats.mean, 0.01)
        assertEquals(120.0, stats.p50, 0.01)
        assertEquals(400.0, stats.p95, 0.01)
        assertEquals(480.0, stats.p99, 0.01)
    }

    @Test
    fun `test latency stats toString format`() {
        val stats = LatencyStats(
            count = 50,
            min = 10.5,
            max = 200.75,
            mean = 100.333,
            p50 = 95.0,
            p95 = 185.5,
            p99 = 198.2
        )

        val str = stats.toString()
        assertTrue(str.contains("count=50"))
        assertTrue(str.contains("min=10.50ms"))
        assertTrue(str.contains("max=200.75ms"))
        assertTrue(str.contains("mean=100.33ms"))
        assertTrue(str.contains("p50=95.00ms"))
        assertTrue(str.contains("p95=185.50ms"))
        assertTrue(str.contains("p99=198.20ms"))
    }

    @Test
    fun `test latency stats toString with whole numbers`() {
        val stats = LatencyStats(
            count = 10,
            min = 100.0,
            max = 200.0,
            mean = 150.0,
            p50 = 140.0,
            p95 = 190.0,
            p99 = 199.0
        )

        val str = stats.toString()
        assertTrue(str.contains("min=100.00ms"))
        assertTrue(str.contains("max=200.00ms"))
    }

    @Test
    fun `test latency stats equality`() {
        val s1 = LatencyStats(10, 1.0, 100.0, 50.0, 45.0, 90.0, 98.0)
        val s2 = LatencyStats(10, 1.0, 100.0, 50.0, 45.0, 90.0, 98.0)
        assertEquals(s1, s2)
    }

    @Test
    fun `test latency stats inequality`() {
        val s1 = LatencyStats(10, 1.0, 100.0, 50.0, 45.0, 90.0, 98.0)
        val s2 = LatencyStats(20, 1.0, 100.0, 50.0, 45.0, 90.0, 98.0)
        assertNotEquals(s1, s2)
    }

    @Test
    fun `test latency stats copy`() {
        val original = LatencyStats(10, 1.0, 100.0, 50.0, 45.0, 90.0, 98.0)
        val updated = original.copy(count = 20, mean = 55.0)

        assertEquals(20, updated.count)
        assertEquals(55.0, updated.mean, 0.01)
        assertEquals(1.0, updated.min, 0.01) // unchanged
    }

    @Test
    fun `test latency stats single sample`() {
        val stats = LatencyStats(
            count = 1,
            min = 42.0,
            max = 42.0,
            mean = 42.0,
            p50 = 42.0,
            p95 = 42.0,
            p99 = 42.0
        )

        assertEquals(stats.min, stats.max, 0.01)
        assertEquals(stats.p50, stats.p99, 0.01)
    }

    @Test
    fun `test latency stats zero values`() {
        val stats = LatencyStats(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        assertEquals(0, stats.count)
        assertTrue(stats.toString().contains("count=0"))
    }

    // -------------------------------------------------------------------
    // BudgetViolationType Enum
    // -------------------------------------------------------------------

    @Test
    fun `test budget violation type has four values`() {
        val values = BudgetViolationType.entries
        assertEquals(4, values.size)
    }

    @Test
    fun `test budget violation type LATENCY value`() {
        assertEquals("latency", BudgetViolationType.LATENCY.value)
    }

    @Test
    fun `test budget violation type MEMORY value`() {
        assertEquals("memory", BudgetViolationType.MEMORY.value)
    }

    @Test
    fun `test budget violation type BATTERY value`() {
        assertEquals("battery", BudgetViolationType.BATTERY.value)
    }

    @Test
    fun `test budget violation type THERMAL value`() {
        assertEquals("thermal", BudgetViolationType.THERMAL.value)
    }

    @Test
    fun `test budget violation type all entries`() {
        val expected = setOf(
            BudgetViolationType.LATENCY,
            BudgetViolationType.MEMORY,
            BudgetViolationType.BATTERY,
            BudgetViolationType.THERMAL
        )
        assertEquals(expected, BudgetViolationType.entries.toSet())
    }

    // -------------------------------------------------------------------
    // ViolationSeverity Enum
    // -------------------------------------------------------------------

    @Test
    fun `test violation severity has three values`() {
        val values = ViolationSeverity.entries
        assertEquals(3, values.size)
    }

    @Test
    fun `test violation severity INFO value`() {
        assertEquals("info", ViolationSeverity.INFO.value)
    }

    @Test
    fun `test violation severity WARNING value`() {
        assertEquals("warning", ViolationSeverity.WARNING.value)
    }

    @Test
    fun `test violation severity CRITICAL value`() {
        assertEquals("critical", ViolationSeverity.CRITICAL.value)
    }

    @Test
    fun `test violation severity all entries`() {
        val expected = setOf(
            ViolationSeverity.INFO,
            ViolationSeverity.WARNING,
            ViolationSeverity.CRITICAL
        )
        assertEquals(expected, ViolationSeverity.entries.toSet())
    }

    @Test
    fun `test violation severity ordinal order`() {
        assertTrue(ViolationSeverity.INFO.ordinal < ViolationSeverity.WARNING.ordinal)
        assertTrue(ViolationSeverity.WARNING.ordinal < ViolationSeverity.CRITICAL.ordinal)
    }

    // -------------------------------------------------------------------
    // Cross-Type Integration (data class interop)
    // -------------------------------------------------------------------

    @Test
    fun `test violation record with all violation types and severities`() {
        for (type in BudgetViolationType.entries) {
            for (severity in ViolationSeverity.entries) {
                val record = BudgetViolationRecord(
                    timestamp = Date(),
                    type = type,
                    current = 100.0,
                    limit = 50.0,
                    severity = severity
                )
                assertEquals(type, record.type)
                assertEquals(severity, record.severity)
            }
        }
    }

    @Test
    fun `test latency metric in map keyed by requestId`() {
        val metrics = mutableMapOf<String, LatencyMetric>()
        val m1 = LatencyMetric("req-1", "model-a", Date(), null, null)
        val m2 = LatencyMetric("req-2", "model-b", Date(), null, null)

        metrics[m1.requestId] = m1
        metrics[m2.requestId] = m2

        assertEquals(2, metrics.size)
        assertEquals("model-a", metrics["req-1"]?.modelName)
        assertEquals("model-b", metrics["req-2"]?.modelName)
    }

    @Test
    fun `test resource snapshots in sorted list by timestamp`() {
        val t1 = Date(1000)
        val t2 = Date(2000)
        val t3 = Date(3000)

        val snapshots = listOf(
            ResourceSnapshot(t3, 300.0, null, 2),
            ResourceSnapshot(t1, 100.0, null, 0),
            ResourceSnapshot(t2, 200.0, null, 1)
        ).sortedBy { it.timestamp }

        assertEquals(t1, snapshots[0].timestamp)
        assertEquals(t2, snapshots[1].timestamp)
        assertEquals(t3, snapshots[2].timestamp)
    }
}