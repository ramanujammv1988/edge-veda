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
 * Unit tests for BatteryDrainTracker (no-context path — pure JVM).
 *
 * Framework requirement (Phase 13): battery drain must stay ≤ 5% per 10 minutes
 * under the Balanced budget. BatteryDrainTracker provides the rolling-window
 * drain-rate reading that feeds the budget enforcement cycle.
 *
 * Tests cover the null-context path which is the only code path exercisable
 * on the JVM without Android instrumentation. Full BatteryManager integration
 * (sliding 10-min window, drain-rate formula) requires Robolectric tests.
 */
class BatteryDrainTrackerTest {

    @Before
    fun setUp() {
        // Suppress android.util.Log calls so they don't throw RuntimeException: Stub!
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
        val tracker = BatteryDrainTracker(context = null)
        assertFalse(tracker.isSupported)
        tracker.destroy()
    }

    // ── currentDrainRate ──────────────────────────────────────────────────────

    @Test
    fun `currentDrainRate returns null when context is null`() = runTest {
        val tracker = BatteryDrainTracker(context = null)
        assertNull(tracker.currentDrainRate())
        tracker.destroy()
    }

    // ── averageDrainRate ──────────────────────────────────────────────────────

    @Test
    fun `averageDrainRate returns null when context is null`() = runTest {
        val tracker = BatteryDrainTracker(context = null)
        assertNull(tracker.averageDrainRate())
        tracker.destroy()
    }

    // ── currentBatteryLevel ───────────────────────────────────────────────────

    @Test
    fun `currentBatteryLevel returns null when context is null`() = runTest {
        val tracker = BatteryDrainTracker(context = null)
        assertNull(tracker.currentBatteryLevel())
        tracker.destroy()
    }

    // ── sampleCount ───────────────────────────────────────────────────────────

    @Test
    fun `sampleCount returns 0 when context is null`() = runTest {
        val tracker = BatteryDrainTracker(context = null)
        assertEquals(0, tracker.sampleCount())
        tracker.destroy()
    }

    // ── reset ─────────────────────────────────────────────────────────────────

    @Test
    fun `reset is safe to call when context is null`() = runTest {
        val tracker = BatteryDrainTracker(context = null)
        tracker.reset()  // should not throw
        assertEquals(0, tracker.sampleCount())
        tracker.destroy()
    }

    @Test
    fun `reset leaves sampleCount at 0 when no samples were taken`() = runTest {
        val tracker = BatteryDrainTracker(context = null)
        tracker.reset()
        assertEquals(0, tracker.sampleCount())
        tracker.destroy()
    }

    // ── destroy ───────────────────────────────────────────────────────────────

    @Test
    fun `destroy is safe to call when context is null`() {
        val tracker = BatteryDrainTracker(context = null)
        tracker.destroy()  // should not throw
    }

    @Test
    fun `destroy is idempotent - calling twice does not throw`() {
        val tracker = BatteryDrainTracker(context = null)
        tracker.destroy()
        tracker.destroy()  // second call should be a no-op
    }

    // ── recordSample ──────────────────────────────────────────────────────────

    @Test
    fun `recordSample is safe when context is null`() = runTest {
        val tracker = BatteryDrainTracker(context = null)
        tracker.recordSample()  // should not throw
        assertEquals(0, tracker.sampleCount())  // no real sample recorded
        tracker.destroy()
    }
}
