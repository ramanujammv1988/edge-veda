package com.edgeveda.sdk

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Tests for LatencyTracker - sliding window percentile tracking.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LatencyTrackerTest {

    private lateinit var tracker: LatencyTracker

    @Before
    fun setUp() {
        tracker = LatencyTracker()
    }

    // -------------------------------------------------------------------
    // Initial State
    // -------------------------------------------------------------------

    @Test
    fun `test initial state is empty`() = runTest {
        assertEquals(0, tracker.sampleCount())
        assertEquals(0.0, tracker.p50(), 0.001)
        assertEquals(0.0, tracker.p95(), 0.001)
        assertEquals(0.0, tracker.p99(), 0.001)
        assertEquals(0.0, tracker.average(), 0.001)
        assertEquals(0.0, tracker.min(), 0.001)
        assertEquals(0.0, tracker.max(), 0.001)
    }

    // -------------------------------------------------------------------
    // Recording
    // -------------------------------------------------------------------

    @Test
    fun `test record single sample`() = runTest {
        tracker.record(100.0)

        assertEquals(1, tracker.sampleCount())
        assertEquals(100.0, tracker.p50(), 0.01)
        assertEquals(100.0, tracker.average(), 0.01)
        assertEquals(100.0, tracker.min(), 0.01)
        assertEquals(100.0, tracker.max(), 0.01)
    }

    @Test
    fun `test record multiple samples`() = runTest {
        val latencies = listOf(50.0, 100.0, 150.0, 200.0, 250.0)
        for (l in latencies) {
            tracker.record(l)
        }

        assertEquals(5, tracker.sampleCount())
        assertEquals(150.0, tracker.average(), 0.01)
        assertEquals(50.0, tracker.min(), 0.01)
        assertEquals(250.0, tracker.max(), 0.01)
    }

    @Test
    fun `test record zero latency`() = runTest {
        tracker.record(0.0)

        assertEquals(1, tracker.sampleCount())
        assertEquals(0.0, tracker.average(), 0.001)
    }

    // -------------------------------------------------------------------
    // Percentiles
    // -------------------------------------------------------------------

    @Test
    fun `test percentile calculation with 100 samples`() = runTest {
        for (i in 1..100) {
            tracker.record(i.toDouble())
        }

        assertEquals(100, tracker.sampleCount())

        val p50 = tracker.p50()
        val p95 = tracker.p95()
        val p99 = tracker.p99()

        // p50 should be around 50
        assertTrue("p50=$p50 should be near 50", p50 in 49.0..51.0)
        // p95 should be around 95
        assertTrue("p95=$p95 should be near 95", p95 in 94.0..96.0)
        // p99 should be around 99
        assertTrue("p99=$p99 should be near 99", p99 in 98.0..100.0)
    }

    @Test
    fun `test percentiles with few samples`() = runTest {
        tracker.record(10.0)
        tracker.record(20.0)

        val p95 = tracker.p95()
        val p99 = tracker.p99()

        assertTrue("p95 should be > 0", p95 > 0)
        assertTrue("p99 should be > 0", p99 > 0)
    }

    @Test
    fun `test percentiles with identical samples`() = runTest {
        for (i in 1..50) {
            tracker.record(100.0)
        }

        assertEquals(100.0, tracker.p50(), 0.01)
        assertEquals(100.0, tracker.p95(), 0.01)
        assertEquals(100.0, tracker.p99(), 0.01)
        assertEquals(100.0, tracker.average(), 0.01)
        assertEquals(100.0, tracker.min(), 0.01)
        assertEquals(100.0, tracker.max(), 0.01)
    }

    // -------------------------------------------------------------------
    // Sliding Window
    // -------------------------------------------------------------------

    @Test
    fun `test sliding window evicts old samples`() = runTest {
        // Default maxSamples = 100
        for (i in 1..150) {
            tracker.record(i.toDouble())
        }

        // Should only have 100 samples
        assertEquals(100, tracker.sampleCount())

        // Oldest samples (1-50) should have been evicted
        // Min should be 51 (the oldest remaining)
        assertEquals(51.0, tracker.min(), 0.01)
        assertEquals(150.0, tracker.max(), 0.01)
    }

    @Test
    fun `test custom window size`() = runTest {
        val smallTracker = LatencyTracker(maxSamples = 10)

        for (i in 1..20) {
            smallTracker.record(i.toDouble())
        }

        assertEquals(10, smallTracker.sampleCount())
        assertEquals(11.0, smallTracker.min(), 0.01)
        assertEquals(20.0, smallTracker.max(), 0.01)
    }

    // -------------------------------------------------------------------
    // Statistics
    // -------------------------------------------------------------------

    @Test
    fun `test average calculation`() = runTest {
        tracker.record(100.0)
        tracker.record(200.0)
        tracker.record(300.0)

        assertEquals(200.0, tracker.average(), 0.01)
    }

    @Test
    fun `test min and max`() = runTest {
        tracker.record(500.0)
        tracker.record(100.0)
        tracker.record(300.0)
        tracker.record(50.0)
        tracker.record(800.0)

        assertEquals(50.0, tracker.min(), 0.01)
        assertEquals(800.0, tracker.max(), 0.01)
    }

    // -------------------------------------------------------------------
    // Reset
    // -------------------------------------------------------------------

    @Test
    fun `test reset clears all samples`() = runTest {
        for (i in 1..10) {
            tracker.record(i * 10.0)
        }
        assertEquals(10, tracker.sampleCount())

        tracker.reset()

        assertEquals(0, tracker.sampleCount())
        assertEquals(0.0, tracker.average(), 0.001)
        assertEquals(0.0, tracker.p50(), 0.001)
        assertEquals(0.0, tracker.p95(), 0.001)
        assertEquals(0.0, tracker.min(), 0.001)
        assertEquals(0.0, tracker.max(), 0.001)
    }

    @Test
    fun `test record after reset`() = runTest {
        tracker.record(100.0)
        tracker.reset()
        tracker.record(200.0)

        assertEquals(1, tracker.sampleCount())
        assertEquals(200.0, tracker.average(), 0.01)
    }

    // -------------------------------------------------------------------
    // Concurrency
    // -------------------------------------------------------------------

    @Test
    fun `test concurrent recording`() = runTest {
        val jobs = (1..100).map { i ->
            async {
                tracker.record(i.toDouble())
            }
        }
        jobs.awaitAll()

        assertEquals(100, tracker.sampleCount())
    }

    // -------------------------------------------------------------------
    // Edge Cases
    // -------------------------------------------------------------------

    @Test
    fun `test very large latency value`() = runTest {
        tracker.record(1_000_000.0)

        assertEquals(1_000_000.0, tracker.max(), 0.01)
        assertEquals(1, tracker.sampleCount())
    }

    @Test
    fun `test mixed latency range`() = runTest {
        val latencies = listOf(1.0, 10.0, 100.0, 1000.0, 10000.0)
        for (l in latencies) {
            tracker.record(l)
        }

        assertEquals(5, tracker.sampleCount())
        assertEquals(1.0, tracker.min(), 0.01)
        assertEquals(10000.0, tracker.max(), 0.01)
    }

    @Test
    fun `test single sample percentiles are all equal`() = runTest {
        tracker.record(42.0)

        assertEquals(42.0, tracker.p50(), 0.01)
        assertEquals(42.0, tracker.p95(), 0.01)
        assertEquals(42.0, tracker.p99(), 0.01)
    }
}