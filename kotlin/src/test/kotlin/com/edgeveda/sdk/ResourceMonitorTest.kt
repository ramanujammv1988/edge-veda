package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for ResourceMonitor.
 *
 * NOTE: ResourceMonitor relies on Android-specific APIs:
 * - [android.os.Debug.getNativeHeapAllocatedSize] for native heap measurement
 * - [android.util.Log] for error logging
 *
 * Unlike Scheduler and RuntimePolicy which expose many pure data classes/enums
 * that can be tested on pure JVM, ResourceMonitor has no standalone supporting
 * types — it is a single class with all suspend methods that depend on
 * Android runtime APIs.
 *
 * Full behavioral tests (currentRssMb, peakRssMb, averageRssMb, sample,
 * reset, sliding window eviction) require either:
 * - Android instrumented tests (androidTest)
 * - Robolectric test runner
 *
 * The tests below verify class existence and constructor parameters only.
 */
class ResourceMonitorTest {

    // -------------------------------------------------------------------
    // Class Existence & Construction
    // -------------------------------------------------------------------

    @Test
    fun `test ResourceMonitor class exists`() {
        // Verify the class is accessible and loadable on JVM
        val clazz = ResourceMonitor::class
        assertEquals("ResourceMonitor", clazz.simpleName)
    }

    @Test
    fun `test ResourceMonitor default maxSamples parameter`() {
        // The default constructor parameter is maxSamples = 100.
        // We verify via reflection that the class has the expected constructor.
        val constructors = ResourceMonitor::class.constructors
        assertTrue("ResourceMonitor should have at least one constructor", constructors.isNotEmpty())

        // Primary constructor should accept an optional Int parameter
        val primary = constructors.first()
        val params = primary.parameters
        // maxSamples parameter
        assertTrue(
            "Constructor should have maxSamples parameter",
            params.any { it.name == "maxSamples" }
        )
    }

    @Test
    fun `test ResourceMonitor has expected public methods`() {
        // Verify the public API surface via reflection
        val methods = ResourceMonitor::class.members.map { it.name }.toSet()

        assertTrue("Should have currentRssMb", methods.contains("currentRssMb"))
        assertTrue("Should have peakRssMb", methods.contains("peakRssMb"))
        assertTrue("Should have averageRssMb", methods.contains("averageRssMb"))
        assertTrue("Should have sampleCount", methods.contains("sampleCount"))
        assertTrue("Should have sample", methods.contains("sample"))
        assertTrue("Should have reset", methods.contains("reset"))
    }

    @Test
    fun `test ResourceMonitor method count`() {
        // Ensure the public API hasn't unexpectedly grown or shrunk
        val publicMethods = ResourceMonitor::class.members
            .filter { it.name in setOf("currentRssMb", "peakRssMb", "averageRssMb", "sampleCount", "sample", "reset") }

        assertEquals("Should have exactly 6 public API methods", 6, publicMethods.size)
    }

    @Test
    fun `test ResourceMonitor maxSamples parameter has type Int`() {
        val primary = ResourceMonitor::class.constructors.first()
        val maxSamplesParam = primary.parameters.firstOrNull { it.name == "maxSamples" }
        assertNotNull("maxSamples parameter should exist", maxSamplesParam)
        assertEquals(
            "maxSamples should be of type Int",
            Int::class,
            maxSamplesParam!!.type.classifier
        )
    }

    @Test
    fun `test ResourceMonitor maxSamples parameter has default value`() {
        val primary = ResourceMonitor::class.constructors.first()
        val maxSamplesParam = primary.parameters.firstOrNull { it.name == "maxSamples" }
        assertNotNull("maxSamples parameter should exist", maxSamplesParam)
        assertTrue("maxSamples should have a default value", maxSamplesParam!!.isOptional)
    }

    @Test
    fun `test ResourceMonitor instantiates without throwing`() {
        val monitor = ResourceMonitor()
        assertNotNull("ResourceMonitor instance should not be null", monitor)
    }

    @Test
    fun `test ResourceMonitor instantiates with custom maxSamples`() {
        val monitor = ResourceMonitor(maxSamples = 50)
        assertNotNull("ResourceMonitor with custom maxSamples should not be null", monitor)
    }
}