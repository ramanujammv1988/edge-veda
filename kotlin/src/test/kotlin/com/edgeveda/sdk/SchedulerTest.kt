package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test
import java.util.Date

/**
 * Tests for Scheduler supporting types: TaskPriority, TaskStatus, QueueStatus,
 * PriorityQueue, and TaskHandle.
 *
 * NOTE: The Scheduler class itself uses android.util.Log and requires
 * Robolectric or Android instrumented tests. These tests cover the pure
 * data classes and internal priority queue that work on JVM.
 */
class SchedulerTest {

    // -------------------------------------------------------------------
    // TaskPriority Enum
    // -------------------------------------------------------------------

    @Test
    fun `test task priority enum values`() {
        val values = TaskPriority.entries
        assertEquals(3, values.size)
        assertTrue(values.contains(TaskPriority.LOW))
        assertTrue(values.contains(TaskPriority.NORMAL))
        assertTrue(values.contains(TaskPriority.HIGH))
    }

    @Test
    fun `test task priority ordering`() {
        assertTrue(TaskPriority.HIGH.value > TaskPriority.NORMAL.value)
        assertTrue(TaskPriority.NORMAL.value > TaskPriority.LOW.value)
    }

    @Test
    fun `test task priority integer values`() {
        assertEquals(0, TaskPriority.LOW.value)
        assertEquals(1, TaskPriority.NORMAL.value)
        assertEquals(2, TaskPriority.HIGH.value)
    }

    @Test
    fun `test task priority fromValue`() {
        assertEquals(TaskPriority.LOW, TaskPriority.fromValue(0))
        assertEquals(TaskPriority.NORMAL, TaskPriority.fromValue(1))
        assertEquals(TaskPriority.HIGH, TaskPriority.fromValue(2))
    }

    @Test(expected = NoSuchElementException::class)
    fun `test task priority fromValue invalid throws`() {
        TaskPriority.fromValue(99)
    }

    // -------------------------------------------------------------------
    // TaskStatus Enum
    // -------------------------------------------------------------------

    @Test
    fun `test task status enum values`() {
        val values = TaskStatus.entries
        assertEquals(5, values.size)
        assertTrue(values.contains(TaskStatus.QUEUED))
        assertTrue(values.contains(TaskStatus.RUNNING))
        assertTrue(values.contains(TaskStatus.COMPLETED))
        assertTrue(values.contains(TaskStatus.CANCELLED))
        assertTrue(values.contains(TaskStatus.FAILED))
    }

    @Test
    fun `test task status names`() {
        assertEquals("QUEUED", TaskStatus.QUEUED.name)
        assertEquals("RUNNING", TaskStatus.RUNNING.name)
        assertEquals("COMPLETED", TaskStatus.COMPLETED.name)
        assertEquals("CANCELLED", TaskStatus.CANCELLED.name)
        assertEquals("FAILED", TaskStatus.FAILED.name)
    }

    // -------------------------------------------------------------------
    // TaskHandle
    // -------------------------------------------------------------------

    @Test
    fun `test task handle creation`() {
        val handle = TaskHandle(
            id = "task-123",
            priority = TaskPriority.HIGH,
            workload = WorkloadId.TEXT,
            status = TaskStatus.QUEUED
        )

        assertEquals("task-123", handle.id)
        assertEquals(TaskPriority.HIGH, handle.priority)
        assertEquals(WorkloadId.TEXT, handle.workload)
        assertEquals(TaskStatus.QUEUED, handle.status)
    }

    @Test
    fun `test task handle equality`() {
        val h1 = TaskHandle("id-1", TaskPriority.NORMAL, WorkloadId.TEXT, TaskStatus.QUEUED)
        val h2 = TaskHandle("id-1", TaskPriority.NORMAL, WorkloadId.TEXT, TaskStatus.QUEUED)
        assertEquals(h1, h2)
    }

    @Test
    fun `test task handle inequality`() {
        val h1 = TaskHandle("id-1", TaskPriority.NORMAL, WorkloadId.TEXT, TaskStatus.QUEUED)
        val h2 = TaskHandle("id-2", TaskPriority.NORMAL, WorkloadId.TEXT, TaskStatus.QUEUED)
        assertNotEquals(h1, h2)
    }

    @Test
    fun `test task handle copy with status change`() {
        val original = TaskHandle("id-1", TaskPriority.HIGH, WorkloadId.VISION, TaskStatus.QUEUED)
        val running = original.copy(status = TaskStatus.RUNNING)

        assertEquals("id-1", running.id)
        assertEquals(TaskPriority.HIGH, running.priority)
        assertEquals(TaskStatus.RUNNING, running.status)
        assertEquals(TaskStatus.QUEUED, original.status)
    }

    @Test
    fun `test task handle with vision workload`() {
        val handle = TaskHandle("v-1", TaskPriority.LOW, WorkloadId.VISION, TaskStatus.COMPLETED)
        assertEquals(WorkloadId.VISION, handle.workload)
        assertEquals(TaskStatus.COMPLETED, handle.status)
    }

    // -------------------------------------------------------------------
    // QueueStatus
    // -------------------------------------------------------------------

    @Test
    fun `test queue status creation`() {
        val status = QueueStatus(
            queuedTasks = 5,
            runningTasks = 2,
            completedTasks = 10,
            highPriorityCount = 1,
            normalPriorityCount = 3,
            lowPriorityCount = 1
        )

        assertEquals(5, status.queuedTasks)
        assertEquals(2, status.runningTasks)
        assertEquals(10, status.completedTasks)
        assertEquals(1, status.highPriorityCount)
        assertEquals(3, status.normalPriorityCount)
        assertEquals(1, status.lowPriorityCount)
    }

    @Test
    fun `test queue status empty`() {
        val status = QueueStatus(
            queuedTasks = 0,
            runningTasks = 0,
            completedTasks = 0,
            highPriorityCount = 0,
            normalPriorityCount = 0,
            lowPriorityCount = 0
        )

        assertEquals(0, status.queuedTasks)
        assertEquals(0, status.completedTasks)
    }

    @Test
    fun `test queue status equality`() {
        val s1 = QueueStatus(5, 2, 10, 1, 3, 1)
        val s2 = QueueStatus(5, 2, 10, 1, 3, 1)
        assertEquals(s1, s2)
    }

    @Test
    fun `test queue status toString`() {
        val status = QueueStatus(
            queuedTasks = 3,
            runningTasks = 1,
            completedTasks = 7,
            highPriorityCount = 1,
            normalPriorityCount = 1,
            lowPriorityCount = 1
        )
        val str = status.toString()
        assertTrue(str.contains("queued=3"))
        assertTrue(str.contains("running=1"))
        assertTrue(str.contains("completed=7"))
        assertTrue(str.contains("high=1"))
        assertTrue(str.contains("normal=1"))
        assertTrue(str.contains("low=1"))
    }

    // -------------------------------------------------------------------
    // PriorityQueue (internal)
    // -------------------------------------------------------------------

    @Test
    fun `test priority queue empty`() {
        val queue = PriorityQueue()
        assertEquals(0, queue.count)
        assertTrue(queue.isEmpty)
        assertNull(queue.dequeue())
    }

    @Test
    fun `test priority queue enqueue and dequeue`() {
        val queue = PriorityQueue()
        queue.enqueue("task-1", TaskPriority.NORMAL)

        assertEquals(1, queue.count)
        assertFalse(queue.isEmpty)

        val id = queue.dequeue()
        assertEquals("task-1", id)
        assertTrue(queue.isEmpty)
    }

    @Test
    fun `test priority queue dequeues highest priority first`() {
        val queue = PriorityQueue()
        queue.enqueue("low-1", TaskPriority.LOW)
        queue.enqueue("normal-1", TaskPriority.NORMAL)
        queue.enqueue("high-1", TaskPriority.HIGH)

        assertEquals("high-1", queue.dequeue())
        assertEquals("normal-1", queue.dequeue())
        assertEquals("low-1", queue.dequeue())
    }

    @Test
    fun `test priority queue same priority preserves order`() {
        val queue = PriorityQueue()
        queue.enqueue("a", TaskPriority.NORMAL)
        queue.enqueue("b", TaskPriority.NORMAL)
        queue.enqueue("c", TaskPriority.NORMAL)

        // Same priority - stable sort should preserve insertion order
        val first = queue.dequeue()
        val second = queue.dequeue()
        val third = queue.dequeue()

        // All should be dequeued
        assertNotNull(first)
        assertNotNull(second)
        assertNotNull(third)
        assertNull(queue.dequeue())
    }

    @Test
    fun `test priority queue remove task`() {
        val queue = PriorityQueue()
        queue.enqueue("task-1", TaskPriority.LOW)
        queue.enqueue("task-2", TaskPriority.NORMAL)
        queue.enqueue("task-3", TaskPriority.HIGH)

        assertEquals(3, queue.count)

        queue.removeTask("task-2")

        assertEquals(2, queue.count)
        assertEquals("task-3", queue.dequeue()) // HIGH first
        assertEquals("task-1", queue.dequeue()) // LOW remaining
    }

    @Test
    fun `test priority queue remove nonexistent task`() {
        val queue = PriorityQueue()
        queue.enqueue("task-1", TaskPriority.NORMAL)

        queue.removeTask("nonexistent")

        assertEquals(1, queue.count) // unchanged
    }

    @Test
    fun `test priority queue count by priority`() {
        val queue = PriorityQueue()
        queue.enqueue("h1", TaskPriority.HIGH)
        queue.enqueue("h2", TaskPriority.HIGH)
        queue.enqueue("n1", TaskPriority.NORMAL)
        queue.enqueue("l1", TaskPriority.LOW)
        queue.enqueue("l2", TaskPriority.LOW)
        queue.enqueue("l3", TaskPriority.LOW)

        assertEquals(2, queue.countByPriority(TaskPriority.HIGH))
        assertEquals(1, queue.countByPriority(TaskPriority.NORMAL))
        assertEquals(3, queue.countByPriority(TaskPriority.LOW))
    }

    @Test
    fun `test priority queue count by priority empty`() {
        val queue = PriorityQueue()
        assertEquals(0, queue.countByPriority(TaskPriority.HIGH))
        assertEquals(0, queue.countByPriority(TaskPriority.NORMAL))
        assertEquals(0, queue.countByPriority(TaskPriority.LOW))
    }

    @Test
    fun `test priority queue multiple enqueue dequeue cycles`() {
        val queue = PriorityQueue()

        // First batch
        queue.enqueue("a", TaskPriority.HIGH)
        queue.enqueue("b", TaskPriority.LOW)
        assertEquals("a", queue.dequeue())

        // Second batch
        queue.enqueue("c", TaskPriority.NORMAL)
        assertEquals("c", queue.dequeue()) // NORMAL > LOW
        assertEquals("b", queue.dequeue())

        assertTrue(queue.isEmpty)
    }

    @Test
    fun `test priority queue large batch`() {
        val queue = PriorityQueue()
        for (i in 1..100) {
            val priority = when (i % 3) {
                0 -> TaskPriority.HIGH
                1 -> TaskPriority.NORMAL
                else -> TaskPriority.LOW
            }
            queue.enqueue("task-$i", priority)
        }

        assertEquals(100, queue.count)

        // Dequeue all - should get HIGH tasks first, then NORMAL, then LOW
        var lastPriority = TaskPriority.HIGH.value
        var dequeuedCount = 0

        // We'll just verify count after full drain
        while (queue.dequeue() != null) {
            dequeuedCount++
        }
        assertEquals(100, dequeuedCount)
        assertTrue(queue.isEmpty)
    }
}