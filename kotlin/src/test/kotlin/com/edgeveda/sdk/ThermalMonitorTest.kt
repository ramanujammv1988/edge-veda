package com.edgeveda.sdk

import android.util.Log
import io.mockk.every
import io.mockk.mockkStatic
import io.mockk.unmockkAll
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for ThermalMonitor (no-context path — pure JVM).
 *
 * Framework requirement (BENCHMARKS.md): 4-level QoS adaptation —
 *   0 = nominal, 1 = light, 2 = moderate (shouldThrottle), 3 = critical
 * Phase 13 budget default: thermal ≤ level 2 before enforcement kicks in.
 *
 * Tests cover the null-context path. Full PowerManager integration
 * (OnThermalStatusChangedListener, getThermalHeadroom) requires Robolectric.
 */
class ThermalMonitorTest {

    @Before
    fun setUp() {
        mockkStatic(Log::class)
        every { Log.i(any(), any<String>()) } returns 0
        every { Log.d(any(), any<String>()) } returns 0
        every { Log.e(any(), any<String>()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.v(any(), any<String>()) } returns 0
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ── isSupported ───────────────────────────────────────────────────────────

    @Test
    fun `isSupported is false when context is null`() {
        val monitor = ThermalMonitor(context = null)
        assertFalse(monitor.isSupported)
        monitor.destroy()
    }

    // ── currentLevel ─────────────────────────────────────────────────────────

    @Test
    fun `currentLevel returns -1 when context is null`() = runTest {
        val monitor = ThermalMonitor(context = null)
        assertEquals(-1, monitor.currentLevel())
        monitor.destroy()
    }

    // ── currentStateName ─────────────────────────────────────────────────────

    @Test
    fun `currentStateName returns non-empty string when context is null`() = runTest {
        val monitor = ThermalMonitor(context = null)
        val name = monitor.currentStateName()
        assertTrue("Expected non-empty state name, got: '$name'", name.isNotEmpty())
        monitor.destroy()
    }

    // ── shouldThrottle ────────────────────────────────────────────────────────

    @Test
    fun `shouldThrottle returns false when context is null (level is -1 below threshold 2)`() = runTest {
        val monitor = ThermalMonitor(context = null)
        assertFalse(monitor.shouldThrottle())
        monitor.destroy()
    }

    // ── isCritical ────────────────────────────────────────────────────────────

    @Test
    fun `isCritical returns false when context is null (level is -1 below threshold 3)`() = runTest {
        val monitor = ThermalMonitor(context = null)
        assertFalse(monitor.isCritical())
        monitor.destroy()
    }

    // ── logical implication ───────────────────────────────────────────────────

    @Test
    fun `isCritical false implies shouldThrottle can be false (null context)`() = runTest {
        val monitor = ThermalMonitor(context = null)
        val critical = monitor.isCritical()
        val throttle = monitor.shouldThrottle()
        // When critical is true, throttle must also be true (level 3 >= 2)
        // Here both are false — verify consistency
        if (critical) assertTrue("isCritical implies shouldThrottle", throttle)
        monitor.destroy()
    }

    // ── removeListener ────────────────────────────────────────────────────────

    @Test
    fun `removeListener with unknown id does not throw`() = runTest {
        val monitor = ThermalMonitor(context = null)
        monitor.removeListener("nonexistent-id")  // should be a no-op
        monitor.destroy()
    }

    @Test
    fun `removeListener with empty string id does not throw`() = runTest {
        val monitor = ThermalMonitor(context = null)
        monitor.removeListener("")
        monitor.destroy()
    }

    // ── destroy ───────────────────────────────────────────────────────────────

    @Test
    fun `destroy is safe to call when context is null`() {
        val monitor = ThermalMonitor(context = null)
        monitor.destroy()  // should not throw
    }

    @Test
    fun `destroy is idempotent - calling twice does not throw`() {
        val monitor = ThermalMonitor(context = null)
        monitor.destroy()
        monitor.destroy()  // second call should be a no-op
    }
}
