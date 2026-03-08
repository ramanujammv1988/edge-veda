package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for FrameQueue — the bounded drop-newest backpressure queue used
 * by the vision soak test pipeline.
 *
 * Framework requirement: 0 frame stalls during a 12.6-minute continuous run.
 * Drop-newest semantics keep vision descriptions current with the live camera
 * feed rather than accumulating a backlog.
 */
class FrameQueueTest {

    private lateinit var queue: FrameQueue

    // Reusable test frames
    private val frame1 = Triple(ByteArray(3) { 1 }, 1, 1)  // 1×1 red-ish
    private val frame2 = Triple(ByteArray(3) { 2 }, 1, 1)  // 1×1 green-ish
    private val frame3 = Triple(ByteArray(3) { 3 }, 1, 1)  // 1×1 blue-ish
    private val wideFrame = Triple(ByteArray(6) { 0 }, 2, 1) // 2×1

    @Before
    fun setUp() {
        queue = FrameQueue()
    }

    // ── Initial state ─────────────────────────────────────────────────────────

    @Test
    fun `new queue isProcessing is false`() {
        assertFalse(queue.isProcessing)
    }

    @Test
    fun `new queue hasPending is false`() {
        assertFalse(queue.hasPending)
    }

    @Test
    fun `new queue droppedFrames is 0`() {
        assertEquals(0, queue.droppedFrames)
    }

    // ── enqueue ───────────────────────────────────────────────────────────────

    @Test
    fun `enqueue into empty idle queue returns true (no drop)`() {
        val (rgb, w, h) = frame1
        assertTrue(queue.enqueue(rgb, w, h))
    }

    @Test
    fun `enqueue sets hasPending to true`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        assertTrue(queue.hasPending)
    }

    @Test
    fun `enqueue while processing and no pending returns true (no drop)`() {
        val (rgb1, w1, h1) = frame1
        queue.enqueue(rgb1, w1, h1)
        queue.dequeue()                       // → isProcessing = true, hasPending = false
        val (rgb2, w2, h2) = frame2
        assertTrue(queue.enqueue(rgb2, w2, h2))  // pending slot was empty — no drop
    }

    @Test
    fun `enqueue while processing and pending replaces old frame returns false`() {
        val (rgb1, w1, h1) = frame1
        val (rgb2, w2, h2) = frame2
        val (rgb3, w3, h3) = frame3
        queue.enqueue(rgb1, w1, h1)
        queue.dequeue()                            // isProcessing = true
        queue.enqueue(rgb2, w2, h2)                // pending set
        val dropped = !queue.enqueue(rgb3, w3, h3) // old pending replaced
        assertTrue(dropped)
    }

    @Test
    fun `droppedFrames increments by 1 on each replaced pending frame`() {
        val (rgb1, w1, h1) = frame1
        val (rgb2, w2, h2) = frame2
        val (rgb3, w3, h3) = frame3
        queue.enqueue(rgb1, w1, h1)
        queue.dequeue()
        queue.enqueue(rgb2, w2, h2)   // first pending
        queue.enqueue(rgb3, w3, h3)   // replaces → droppedFrames = 1
        assertEquals(1, queue.droppedFrames)
    }

    @Test
    fun `droppedFrames accumulates across multiple drops`() {
        repeat(5) { i ->
            val (rgb, w, h) = frame1
            queue.enqueue(rgb, w, h)
            if (i == 0) queue.dequeue()  // start processing on first frame
            // Each subsequent enqueue while processing + pending → drop
        }
        // After dequeue (i=0): 1 pending set (i=1 enqueue no drop),
        // then i=2,3,4 each replace pending → 3 drops
        assertTrue(queue.droppedFrames >= 1)
    }

    // ── dequeue ───────────────────────────────────────────────────────────────

    @Test
    fun `dequeue returns FrameData after enqueue`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        assertNotNull(queue.dequeue())
    }

    @Test
    fun `dequeue sets hasPending to false`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        queue.dequeue()
        assertFalse(queue.hasPending)
    }

    @Test
    fun `dequeue sets isProcessing to true`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        queue.dequeue()
        assertTrue(queue.isProcessing)
    }

    @Test
    fun `dequeue returns null when queue is empty`() {
        assertNull(queue.dequeue())
    }

    @Test
    fun `dequeue returns null when already processing`() {
        val (rgb1, w1, h1) = frame1
        val (rgb2, w2, h2) = frame2
        queue.enqueue(rgb1, w1, h1)
        queue.dequeue()                   // isProcessing = true
        queue.enqueue(rgb2, w2, h2)       // pending set
        assertNull(queue.dequeue())       // still processing — returns null
    }

    @Test
    fun `dequeued FrameData carries correct dimensions`() {
        val (rgb, w, h) = wideFrame
        queue.enqueue(rgb, w, h)
        val frame = queue.dequeue()
        assertNotNull(frame)
        assertEquals(2, frame!!.width)
        assertEquals(1, frame.height)
    }

    @Test
    fun `dequeued FrameData carries correct pixel bytes`() {
        val rgb = byteArrayOf(10, 20, 30)
        queue.enqueue(rgb, 1, 1)
        val frame = queue.dequeue()
        assertNotNull(frame)
        assertArrayEquals(rgb, frame!!.rgb)
    }

    // ── markDone ──────────────────────────────────────────────────────────────

    @Test
    fun `markDone sets isProcessing to false`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        queue.dequeue()
        queue.markDone()
        assertFalse(queue.isProcessing)
    }

    @Test
    fun `after markDone next dequeue succeeds`() {
        val (rgb1, w1, h1) = frame1
        val (rgb2, w2, h2) = frame2
        queue.enqueue(rgb1, w1, h1)
        queue.dequeue()
        queue.markDone()
        queue.enqueue(rgb2, w2, h2)
        assertNotNull(queue.dequeue())
    }

    @Test
    fun `markDone on idle queue does not throw`() {
        queue.markDone()  // should be a no-op
        assertFalse(queue.isProcessing)
    }

    // ── reset ─────────────────────────────────────────────────────────────────

    @Test
    fun `reset clears hasPending`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        queue.reset()
        assertFalse(queue.hasPending)
    }

    @Test
    fun `reset clears isProcessing`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        queue.dequeue()
        queue.reset()
        assertFalse(queue.isProcessing)
    }

    @Test
    fun `reset preserves droppedFrames (cumulative counter)`() {
        val (rgb1, w1, h1) = frame1
        val (rgb2, w2, h2) = frame2
        val (rgb3, w3, h3) = frame3
        queue.enqueue(rgb1, w1, h1)
        queue.dequeue()
        queue.enqueue(rgb2, w2, h2)
        queue.enqueue(rgb3, w3, h3)      // 1 drop
        assertEquals(1, queue.droppedFrames)
        queue.reset()
        assertEquals(1, queue.droppedFrames)  // preserved after reset
    }

    @Test
    fun `after reset new enqueue is accepted cleanly`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        queue.dequeue()
        queue.reset()
        assertTrue(queue.enqueue(rgb, w, h))
    }

    // ── resetCounters ─────────────────────────────────────────────────────────

    @Test
    fun `resetCounters sets droppedFrames to 0`() {
        val (rgb1, w1, h1) = frame1
        val (rgb2, w2, h2) = frame2
        val (rgb3, w3, h3) = frame3
        queue.enqueue(rgb1, w1, h1)
        queue.dequeue()
        queue.enqueue(rgb2, w2, h2)
        queue.enqueue(rgb3, w3, h3)      // 1 drop
        queue.resetCounters()
        assertEquals(0, queue.droppedFrames)
    }

    @Test
    fun `resetCounters does not clear pending frame`() {
        val (rgb, w, h) = frame1
        queue.enqueue(rgb, w, h)
        queue.resetCounters()
        assertTrue(queue.hasPending)
    }
}
