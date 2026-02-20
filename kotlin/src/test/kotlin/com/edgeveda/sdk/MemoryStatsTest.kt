package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for MemoryStats and MemoryPressureEvent data classes.
 *
 * Verifies the computed properties: usagePercent, isHighPressure, isCritical.
 * Mirrors the Flutter gold standard's DownloadProgress percentage tests pattern.
 */
class MemoryStatsTest {

    // ── usagePercent ──────────────────────────────────────────────────────────

    @Test
    fun `usagePercent is zero when limitBytes is zero`() {
        val stats = MemoryStats(
            currentBytes = 500_000_000L,
            peakBytes = 500_000_000L,
            limitBytes = 0L,
            modelBytes = 400_000_000L,
            contextBytes = 100_000_000L
        )
        assertEquals(0.0, stats.usagePercent, 0.0001)
    }

    @Test
    fun `usagePercent is 0_5 when current is half of limit`() {
        val stats = MemoryStats(
            currentBytes = 500_000_000L,
            peakBytes = 500_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 400_000_000L,
            contextBytes = 100_000_000L
        )
        assertEquals(0.5, stats.usagePercent, 0.0001)
    }

    @Test
    fun `usagePercent is 1_0 when current equals limit`() {
        val stats = MemoryStats(
            currentBytes = 1_000_000_000L,
            peakBytes = 1_000_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 800_000_000L,
            contextBytes = 200_000_000L
        )
        assertEquals(1.0, stats.usagePercent, 0.0001)
    }

    @Test
    fun `usagePercent exceeds 1_0 when current is greater than limit`() {
        val stats = MemoryStats(
            currentBytes = 1_100_000_000L,
            peakBytes = 1_100_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 1_000_000_000L,
            contextBytes = 100_000_000L
        )
        assertTrue("usagePercent should be > 1.0 on overflow", stats.usagePercent > 1.0)
    }

    @Test
    fun `usagePercent is 0_0 when currentBytes is zero`() {
        val stats = MemoryStats(
            currentBytes = 0L,
            peakBytes = 0L,
            limitBytes = 1_000_000_000L,
            modelBytes = 0L,
            contextBytes = 0L
        )
        assertEquals(0.0, stats.usagePercent, 0.0001)
    }

    @Test
    fun `usagePercent calculation uses currentBytes divided by limitBytes`() {
        val current = 750_000_000L
        val limit = 1_000_000_000L
        val stats = MemoryStats(
            currentBytes = current,
            peakBytes = current,
            limitBytes = limit,
            modelBytes = 600_000_000L,
            contextBytes = 150_000_000L
        )
        val expected = current.toDouble() / limit.toDouble()
        assertEquals(expected, stats.usagePercent, 0.0001)
    }

    // ── isHighPressure ────────────────────────────────────────────────────────

    @Test
    fun `isHighPressure is false when usage is below 80 percent`() {
        val stats = MemoryStats(
            currentBytes = 799_999_999L,
            peakBytes = 800_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 700_000_000L,
            contextBytes = 99_999_999L
        )
        assertFalse(stats.isHighPressure)
    }

    @Test
    fun `isHighPressure is false when usage is exactly 80 percent`() {
        val stats = MemoryStats(
            currentBytes = 800_000_000L,
            peakBytes = 800_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 700_000_000L,
            contextBytes = 100_000_000L
        )
        // usagePercent = 0.8 which is NOT > 0.8, so isHighPressure should be false
        assertFalse(stats.isHighPressure)
    }

    @Test
    fun `isHighPressure is true when usage exceeds 80 percent`() {
        val stats = MemoryStats(
            currentBytes = 850_000_000L,
            peakBytes = 850_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 750_000_000L,
            contextBytes = 100_000_000L
        )
        assertTrue(stats.isHighPressure)
    }

    @Test
    fun `isHighPressure is false when limitBytes is zero`() {
        val stats = MemoryStats(
            currentBytes = 999_999_999L,
            peakBytes = 999_999_999L,
            limitBytes = 0L,
            modelBytes = 800_000_000L,
            contextBytes = 199_999_999L
        )
        // usagePercent = 0.0 when limitBytes = 0, so never high pressure
        assertFalse(stats.isHighPressure)
    }

    // ── isCritical ────────────────────────────────────────────────────────────

    @Test
    fun `isCritical is false when usage is below 90 percent`() {
        val stats = MemoryStats(
            currentBytes = 899_999_999L,
            peakBytes = 900_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 800_000_000L,
            contextBytes = 99_999_999L
        )
        assertFalse(stats.isCritical)
    }

    @Test
    fun `isCritical is false when usage is exactly 90 percent`() {
        val stats = MemoryStats(
            currentBytes = 900_000_000L,
            peakBytes = 900_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 800_000_000L,
            contextBytes = 100_000_000L
        )
        // usagePercent = 0.9 which is NOT > 0.9, so isCritical should be false
        assertFalse(stats.isCritical)
    }

    @Test
    fun `isCritical is true when usage exceeds 90 percent`() {
        val stats = MemoryStats(
            currentBytes = 950_000_000L,
            peakBytes = 950_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 850_000_000L,
            contextBytes = 100_000_000L
        )
        assertTrue(stats.isCritical)
    }

    @Test
    fun `isCritical is false when limitBytes is zero`() {
        val stats = MemoryStats(
            currentBytes = 999_999_999L,
            peakBytes = 999_999_999L,
            limitBytes = 0L,
            modelBytes = 900_000_000L,
            contextBytes = 99_999_999L
        )
        assertFalse(stats.isCritical)
    }

    // ── isHighPressure and isCritical consistency ─────────────────────────────

    @Test
    fun `isCritical implies isHighPressure`() {
        val stats = MemoryStats(
            currentBytes = 950_000_000L,
            peakBytes = 950_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 850_000_000L,
            contextBytes = 100_000_000L
        )
        // If it's critical (>90%) it must also be high pressure (>80%)
        assertTrue(stats.isCritical)
        assertTrue(stats.isHighPressure)
    }

    @Test
    fun `can be high pressure without being critical`() {
        val stats = MemoryStats(
            currentBytes = 850_000_000L,
            peakBytes = 850_000_000L,
            limitBytes = 1_000_000_000L,
            modelBytes = 750_000_000L,
            contextBytes = 100_000_000L
        )
        assertTrue(stats.isHighPressure)
        assertFalse(stats.isCritical)
    }

    // ── MemoryStats data class equality ───────────────────────────────────────

    @Test
    fun `two MemoryStats with same values are equal`() {
        val a = MemoryStats(100L, 200L, 1000L, 80L, 20L)
        val b = MemoryStats(100L, 200L, 1000L, 80L, 20L)
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun `two MemoryStats with different currentBytes are not equal`() {
        val a = MemoryStats(100L, 200L, 1000L, 80L, 20L)
        val b = MemoryStats(200L, 200L, 1000L, 80L, 20L)
        assertNotEquals(a, b)
    }

    // ── MemoryPressureEvent ───────────────────────────────────────────────────

    @Test
    fun `MemoryPressureEvent stores fields correctly`() {
        val event = MemoryPressureEvent(
            currentBytes = 900_000_000L,
            limitBytes = 1_000_000_000L,
            pressureRatio = 0.9,
            timestampMs = 1_700_000_000_000L
        )
        assertEquals(900_000_000L, event.currentBytes)
        assertEquals(1_000_000_000L, event.limitBytes)
        assertEquals(0.9, event.pressureRatio, 0.0001)
        assertEquals(1_700_000_000_000L, event.timestampMs)
    }

    @Test
    fun `MemoryPressureEvent timestampMs defaults to current time`() {
        val before = System.currentTimeMillis()
        val event = MemoryPressureEvent(
            currentBytes = 100L,
            limitBytes = 1000L,
            pressureRatio = 0.1
        )
        val after = System.currentTimeMillis()
        assertTrue(event.timestampMs in before..after)
    }

    @Test
    fun `two MemoryPressureEvents with same values are equal`() {
        val a = MemoryPressureEvent(100L, 1000L, 0.1, 12345L)
        val b = MemoryPressureEvent(100L, 1000L, 0.1, 12345L)
        assertEquals(a, b)
    }
}
