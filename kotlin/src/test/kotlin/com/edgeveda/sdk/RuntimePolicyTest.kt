package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for RuntimePolicy, RuntimePolicyOptions, and ThrottleRecommendation.
 *
 * NOTE: RuntimePolicyEnforcer and RuntimeCapabilities.detect() use Android APIs
 * (android.util.Log, android.os.Build, Context) and require Robolectric or
 * instrumented tests. These tests cover the pure data classes that work on JVM.
 */
class RuntimePolicyTest {

    // -------------------------------------------------------------------
    // RuntimePolicy Presets
    // -------------------------------------------------------------------

    @Test
    fun `test conservative policy`() {
        val policy = RuntimePolicy.CONSERVATIVE
        assertTrue(policy.throttleOnBattery)
        assertTrue(policy.adaptiveMemory)
        assertTrue(policy.thermalAware)
        assertTrue(policy.backgroundOptimization)
    }

    @Test
    fun `test balanced policy`() {
        val policy = RuntimePolicy.BALANCED
        assertTrue(policy.throttleOnBattery)
        assertTrue(policy.adaptiveMemory)
        assertTrue(policy.thermalAware)
        assertFalse(policy.backgroundOptimization)
    }

    @Test
    fun `test performance policy`() {
        val policy = RuntimePolicy.PERFORMANCE
        assertFalse(policy.throttleOnBattery)
        assertFalse(policy.adaptiveMemory)
        assertFalse(policy.thermalAware)
        assertFalse(policy.backgroundOptimization)
    }

    @Test
    fun `test default policy is balanced`() {
        val policy = RuntimePolicy.DEFAULT
        assertEquals(RuntimePolicy.BALANCED, policy)
        assertTrue(policy.throttleOnBattery)
        assertTrue(policy.adaptiveMemory)
        assertTrue(policy.thermalAware)
        assertFalse(policy.backgroundOptimization)
    }

    // -------------------------------------------------------------------
    // Custom Policy
    // -------------------------------------------------------------------

    @Test
    fun `test custom policy all false`() {
        val policy = RuntimePolicy(
            throttleOnBattery = false,
            adaptiveMemory = false,
            thermalAware = false,
            backgroundOptimization = false
        )
        assertFalse(policy.throttleOnBattery)
        assertFalse(policy.adaptiveMemory)
        assertFalse(policy.thermalAware)
        assertFalse(policy.backgroundOptimization)
    }

    @Test
    fun `test custom policy all true`() {
        val policy = RuntimePolicy(
            throttleOnBattery = true,
            adaptiveMemory = true,
            thermalAware = true,
            backgroundOptimization = true
        )
        assertTrue(policy.throttleOnBattery)
        assertTrue(policy.adaptiveMemory)
        assertTrue(policy.thermalAware)
        assertTrue(policy.backgroundOptimization)
    }

    @Test
    fun `test custom policy with default options`() {
        val policy = RuntimePolicy(throttleOnBattery = true)
        assertNotNull(policy.options)
        assertTrue(policy.options.thermalStateMonitoring)
        assertFalse(policy.options.backgroundTaskSupport)
        assertTrue(policy.options.performanceObserver)
        assertTrue(policy.options.workerPooling)
    }

    @Test
    fun `test custom policy with custom options`() {
        val options = RuntimePolicyOptions(
            thermalStateMonitoring = false,
            backgroundTaskSupport = true,
            performanceObserver = false,
            workerPooling = false
        )
        val policy = RuntimePolicy(
            throttleOnBattery = true,
            options = options
        )
        assertFalse(policy.options.thermalStateMonitoring)
        assertTrue(policy.options.backgroundTaskSupport)
        assertFalse(policy.options.performanceObserver)
        assertFalse(policy.options.workerPooling)
    }

    // -------------------------------------------------------------------
    // Policy Equality
    // -------------------------------------------------------------------

    @Test
    fun `test policy equality`() {
        val p1 = RuntimePolicy(throttleOnBattery = true, adaptiveMemory = false)
        val p2 = RuntimePolicy(throttleOnBattery = true, adaptiveMemory = false)
        assertEquals(p1, p2)
    }

    @Test
    fun `test policy inequality`() {
        val p1 = RuntimePolicy(throttleOnBattery = true)
        val p2 = RuntimePolicy(throttleOnBattery = false)
        assertNotEquals(p1, p2)
    }

    @Test
    fun `test policy copy`() {
        val original = RuntimePolicy.BALANCED
        val copy = original.copy(backgroundOptimization = true)
        assertFalse(original.backgroundOptimization)
        assertTrue(copy.backgroundOptimization)
        assertEquals(original.throttleOnBattery, copy.throttleOnBattery)
    }

    // -------------------------------------------------------------------
    // Policy toString
    // -------------------------------------------------------------------

    @Test
    fun `test policy toString contains fields`() {
        val policy = RuntimePolicy.BALANCED
        val str = policy.toString()
        assertTrue(str.contains("throttleOnBattery=true"))
        assertTrue(str.contains("adaptiveMemory=true"))
        assertTrue(str.contains("thermalAware=true"))
        assertTrue(str.contains("backgroundOptimization=false"))
    }

    // -------------------------------------------------------------------
    // RuntimePolicyOptions
    // -------------------------------------------------------------------

    @Test
    fun `test default policy options`() {
        val options = RuntimePolicyOptions()
        assertTrue(options.thermalStateMonitoring)
        assertFalse(options.backgroundTaskSupport)
        assertTrue(options.performanceObserver)
        assertTrue(options.workerPooling)
    }

    @Test
    fun `test custom policy options`() {
        val options = RuntimePolicyOptions(
            thermalStateMonitoring = false,
            backgroundTaskSupport = true,
            performanceObserver = false,
            workerPooling = false
        )
        assertFalse(options.thermalStateMonitoring)
        assertTrue(options.backgroundTaskSupport)
        assertFalse(options.performanceObserver)
        assertFalse(options.workerPooling)
    }

    @Test
    fun `test policy options equality`() {
        val o1 = RuntimePolicyOptions()
        val o2 = RuntimePolicyOptions()
        assertEquals(o1, o2)
    }

    @Test
    fun `test policy options inequality`() {
        val o1 = RuntimePolicyOptions(workerPooling = true)
        val o2 = RuntimePolicyOptions(workerPooling = false)
        assertNotEquals(o1, o2)
    }

    // -------------------------------------------------------------------
    // ThrottleRecommendation
    // -------------------------------------------------------------------

    @Test
    fun `test no throttle recommendation`() {
        val rec = ThrottleRecommendation(
            shouldThrottle = false,
            throttleFactor = 1.0,
            reasons = emptyList()
        )
        assertFalse(rec.shouldThrottle)
        assertEquals(1.0, rec.throttleFactor, 0.001)
        assertTrue(rec.reasons.isEmpty())
    }

    @Test
    fun `test throttle recommendation with single reason`() {
        val rec = ThrottleRecommendation(
            shouldThrottle = true,
            throttleFactor = 0.5,
            reasons = listOf("Thermal pressure (level 2)")
        )
        assertTrue(rec.shouldThrottle)
        assertEquals(0.5, rec.throttleFactor, 0.001)
        assertEquals(1, rec.reasons.size)
        assertEquals("Thermal pressure (level 2)", rec.reasons[0])
    }

    @Test
    fun `test throttle recommendation with multiple reasons`() {
        val rec = ThrottleRecommendation(
            shouldThrottle = true,
            throttleFactor = 0.3,
            reasons = listOf(
                "Thermal pressure (level 2)",
                "Low battery (15%)",
                "High memory usage (800MB)"
            )
        )
        assertTrue(rec.shouldThrottle)
        assertEquals(3, rec.reasons.size)
        assertEquals(0.3, rec.throttleFactor, 0.001)
    }

    @Test
    fun `test throttle recommendation toString no throttle`() {
        val rec = ThrottleRecommendation(
            shouldThrottle = false,
            throttleFactor = 1.0,
            reasons = emptyList()
        )
        val str = rec.toString()
        assertTrue(str.contains("No throttling needed"))
    }

    @Test
    fun `test throttle recommendation toString with throttle`() {
        val rec = ThrottleRecommendation(
            shouldThrottle = true,
            throttleFactor = 0.5,
            reasons = listOf("Thermal pressure")
        )
        val str = rec.toString()
        assertTrue(str.contains("Throttle by"))
        assertTrue(str.contains("50%"))
        assertTrue(str.contains("Thermal pressure"))
    }

    @Test
    fun `test throttle recommendation equality`() {
        val r1 = ThrottleRecommendation(true, 0.5, listOf("reason"))
        val r2 = ThrottleRecommendation(true, 0.5, listOf("reason"))
        assertEquals(r1, r2)
    }

    @Test
    fun `test throttle recommendation inequality`() {
        val r1 = ThrottleRecommendation(true, 0.5, listOf("reason"))
        val r2 = ThrottleRecommendation(false, 1.0, emptyList())
        assertNotEquals(r1, r2)
    }

    // -------------------------------------------------------------------
    // RuntimeCapabilities (data class only, not detect())
    // -------------------------------------------------------------------

    @Test
    fun `test runtime capabilities creation`() {
        val caps = RuntimeCapabilities(
            hasThermalMonitoring = true,
            hasBatteryMonitoring = true,
            hasMemoryMonitoring = true,
            hasBackgroundTasks = true,
            platform = "Android",
            osVersion = "Android 14 (API 34)",
            deviceModel = "Google Pixel 8"
        )
        assertTrue(caps.hasThermalMonitoring)
        assertTrue(caps.hasBatteryMonitoring)
        assertTrue(caps.hasMemoryMonitoring)
        assertTrue(caps.hasBackgroundTasks)
        assertEquals("Android", caps.platform)
        assertEquals("Android 14 (API 34)", caps.osVersion)
        assertEquals("Google Pixel 8", caps.deviceModel)
    }

    @Test
    fun `test runtime capabilities limited device`() {
        val caps = RuntimeCapabilities(
            hasThermalMonitoring = false,
            hasBatteryMonitoring = false,
            hasMemoryMonitoring = true,
            hasBackgroundTasks = true,
            platform = "Android",
            osVersion = "Android 9 (API 28)",
            deviceModel = "Generic"
        )
        assertFalse(caps.hasThermalMonitoring)
        assertFalse(caps.hasBatteryMonitoring)
    }

    @Test
    fun `test runtime capabilities equality`() {
        val c1 = RuntimeCapabilities(true, true, true, true, "Android", "14", "Pixel")
        val c2 = RuntimeCapabilities(true, true, true, true, "Android", "14", "Pixel")
        assertEquals(c1, c2)
    }

    // -------------------------------------------------------------------
    // Edge Cases
    // -------------------------------------------------------------------

    @Test
    fun `test throttle factor zero`() {
        val rec = ThrottleRecommendation(
            shouldThrottle = true,
            throttleFactor = 0.0,
            reasons = listOf("Complete throttle")
        )
        assertEquals(0.0, rec.throttleFactor, 0.001)
        assertTrue(rec.toString().contains("100%"))
    }

    @Test
    fun `test throttle factor exactly one`() {
        val rec = ThrottleRecommendation(
            shouldThrottle = true,
            throttleFactor = 1.0,
            reasons = listOf("Minimal")
        )
        assertEquals(1.0, rec.throttleFactor, 0.001)
        assertTrue(rec.toString().contains("0%"))
    }

    @Test
    fun `test policy defaults via no-arg constructor`() {
        val policy = RuntimePolicy()
        assertTrue(policy.throttleOnBattery)
        assertTrue(policy.adaptiveMemory)
        assertTrue(policy.thermalAware)
        assertFalse(policy.backgroundOptimization)
    }
}