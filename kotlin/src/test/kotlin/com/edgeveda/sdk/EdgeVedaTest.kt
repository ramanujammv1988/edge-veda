package com.edgeveda.sdk

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import kotlin.time.Duration.Companion.seconds

/**
 * Unit tests for EdgeVeda SDK.
 *
 * Note: These tests assume the native library is available.
 * In a real CI/CD environment, you would use mocking or
 * provide a test implementation of the native layer.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class EdgeVedaTest {

    private lateinit var edgeVeda: EdgeVeda

    @Before
    fun setUp() {
        // Create a new instance for each test
        edgeVeda = EdgeVeda.create()
    }

    @After
    fun tearDown() {
        // Clean up after each test
        try {
            edgeVeda.close()
        } catch (e: Exception) {
            // Ignore cleanup errors in tests
        }
    }

    @Test
    fun `test SDK version is valid`() {
        val version = EdgeVeda.getVersion()
        assertNotNull("Version should not be null", version)
        assertTrue("Version should not be empty", version.isNotEmpty())
        assertTrue("Version should match semver pattern", version.matches(Regex("\\d+\\.\\d+\\.\\d+")))
    }

    @Test
    fun `test create returns non-null instance`() {
        val instance = EdgeVeda.create()
        assertNotNull("EdgeVeda instance should not be null", instance)
        instance.close()
    }

    @Test
    fun `test init with default config`() = runTest(timeout = 30.seconds) {
        // Note: This test will fail without a real model file
        // In a real test, you would use a mock or test model
        try {
            val config = EdgeVedaConfig()
            // This would need a valid model path
            // edgeVeda.init("/path/to/test/model.gguf", config)

            // For now, we just test that config creation works
            assertNotNull("Config should not be null", config)
            assertEquals("Default backend should be AUTO", Backend.AUTO, config.backend)
            assertEquals("Default max tokens should be 512", 512, config.maxTokens)
        } catch (e: EdgeVedaException.ModelLoadError) {
            // Expected without a real model file
        }
    }

    @Test
    fun `test mobile config preset`() {
        val config = EdgeVedaConfig.mobile()

        assertEquals("Mobile backend should be AUTO", Backend.AUTO, config.backend)
        assertEquals("Mobile should use 4 threads", 4, config.numThreads)
        assertEquals("Mobile max tokens should be 256", 256, config.maxTokens)
        assertEquals("Mobile context size should be 1024", 1024, config.contextSize)
        assertTrue("Mobile should use GPU", config.useGpu)
        assertTrue("Mobile should use mmap", config.useMmap)
        assertFalse("Mobile should not use mlock", config.useMlock)
    }

    @Test
    fun `test high quality config preset`() {
        val config = EdgeVedaConfig.highQuality()

        assertEquals("High quality max tokens should be 1024", 1024, config.maxTokens)
        assertEquals("High quality context size should be 4096", 4096, config.contextSize)
        assertTrue("High quality should use mlock", config.useMlock)
    }

    @Test
    fun `test fast config preset`() {
        val config = EdgeVedaConfig.fast()

        assertEquals("Fast should use 2 threads", 2, config.numThreads)
        assertEquals("Fast max tokens should be 128", 128, config.maxTokens)
        assertEquals("Fast context size should be 512", 512, config.contextSize)
    }

    @Test
    fun `test config builder pattern`() {
        val config = EdgeVedaConfig()
            .withBackend(Backend.CPU)
            .withNumThreads(8)
            .withMaxTokens(1024)
            .withTemperature(0.8f)

        assertEquals("Backend should be CPU", Backend.CPU, config.backend)
        assertEquals("Threads should be 8", 8, config.numThreads)
        assertEquals("Max tokens should be 1024", 1024, config.maxTokens)
        assertEquals("Temperature should be 0.8", 0.8f, config.temperature, 0.001f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test config validation - negative threads`() {
        EdgeVedaConfig(numThreads = -1)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test config validation - zero max tokens`() {
        EdgeVedaConfig(maxTokens = 0)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test config validation - invalid temperature`() {
        EdgeVedaConfig(temperature = -0.5f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test config validation - topP out of range`() {
        EdgeVedaConfig(topP = 1.5f)
    }

    @Test
    fun `test backend enum values`() {
        assertEquals("CPU backend value should be 0", 0, Backend.CPU.toNativeValue())
        assertEquals("VULKAN backend value should be 1", 1, Backend.VULKAN.toNativeValue())
        assertEquals("NNAPI backend value should be 2", 2, Backend.NNAPI.toNativeValue())
        assertEquals("AUTO backend value should be 3", 3, Backend.AUTO.toNativeValue())
    }

    @Test
    fun `test backend from native value`() {
        assertEquals("Native 0 should map to CPU", Backend.CPU, Backend.fromNativeValue(0))
        assertEquals("Native 1 should map to VULKAN", Backend.VULKAN, Backend.fromNativeValue(1))
        assertEquals("Native 2 should map to NNAPI", Backend.NNAPI, Backend.fromNativeValue(2))
        assertEquals("Native 3 should map to AUTO", Backend.AUTO, Backend.fromNativeValue(3))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test backend from invalid native value`() {
        Backend.fromNativeValue(99)
    }

    @Test
    fun `test generate options defaults`() {
        val options = GenerateOptions()

        assertNull("Default max tokens should be null", options.maxTokens)
        assertNull("Default temperature should be null", options.temperature)
        assertNull("Default topP should be null", options.topP)
        assertNull("Default topK should be null", options.topK)
        assertTrue("Default stop sequences should be empty", options.stopSequences.isEmpty())
    }

    @Test
    fun `test generate options presets`() {
        val creative = GenerateOptions.creative()
        assertEquals("Creative temperature should be 1.0", 1.0f, creative.temperature, 0.001f)

        val deterministic = GenerateOptions.deterministic()
        assertEquals("Deterministic temperature should be 0.3", 0.3f, deterministic.temperature, 0.001f)

        val balanced = GenerateOptions.balanced()
        assertEquals("Balanced temperature should be 0.7", 0.7f, balanced.temperature, 0.001f)
    }

    @Test
    fun `test generate options with custom values`() {
        val options = GenerateOptions(
            maxTokens = 100,
            temperature = 0.9f,
            topP = 0.95f,
            topK = 50,
            stopSequences = listOf("END", "STOP")
        )

        assertEquals("Max tokens should be 100", 100, options.maxTokens)
        assertEquals("Temperature should be 0.9", 0.9f, options.temperature, 0.001f)
        assertEquals("TopP should be 0.95", 0.95f, options.topP, 0.001f)
        assertEquals("TopK should be 50", 50, options.topK)
        assertEquals("Stop sequences should have 2 items", 2, options.stopSequences.size)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test generate options validation - invalid max tokens`() {
        GenerateOptions(maxTokens = -1)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `test generate options validation - invalid temperature`() {
        GenerateOptions(temperature = -0.5f)
    }

    @Test(expected = IllegalStateException::class)
    fun `test generate before init throws exception`() = runTest {
        edgeVeda.generate("test prompt")
    }

    @Test(expected = IllegalStateException::class)
    fun `test generateStream before init throws exception`() = runTest {
        edgeVeda.generateStream("test prompt").toList()
    }

    @Test
    fun `test memory usage before init returns -1`() {
        assertEquals("Memory usage should be -1 before init", -1L, edgeVeda.memoryUsage)
    }

    @Test(expected = IllegalStateException::class)
    fun `test unload before init throws exception`() = runTest {
        edgeVeda.unloadModel()
    }

    @Test
    fun `test close is idempotent`() {
        edgeVeda.close()
        edgeVeda.close() // Should not throw
    }

    @Test(expected = IllegalStateException::class)
    fun `test operations after close throw exception`() = runTest {
        edgeVeda.close()
        edgeVeda.generate("test prompt")
    }

    @Test
    fun `test EdgeVedaException types`() {
        val modelLoadError = EdgeVedaException.ModelLoadError("test")
        assertTrue("Should be ModelLoadError", modelLoadError is EdgeVedaException.ModelLoadError)

        val generationError = EdgeVedaException.GenerationError("test")
        assertTrue("Should be GenerationError", generationError is EdgeVedaException.GenerationError)

        val invalidConfig = EdgeVedaException.InvalidConfiguration("test")
        assertTrue("Should be InvalidConfiguration", invalidConfig is EdgeVedaException.InvalidConfiguration)

        val nativeError = EdgeVedaException.NativeError("test")
        assertTrue("Should be NativeError", nativeError is EdgeVedaException.NativeError)
    }

    @Test
    fun `test exception messages`() {
        val message = "Test error message"
        val exception = EdgeVedaException.ModelLoadError(message)

        assertEquals("Exception message should match", message, exception.message)
    }

    @Test
    fun `test exception with cause`() {
        val cause = RuntimeException("Root cause")
        val exception = EdgeVedaException.GenerationError("Wrapper error", cause)

        assertEquals("Exception should have cause", cause, exception.cause)
    }

    @Test
    fun `test finish reason enum`() {
        val reasons = FinishReason.values()

        assertTrue("Should have MAX_TOKENS", reasons.contains(FinishReason.MAX_TOKENS))
        assertTrue("Should have EOS_TOKEN", reasons.contains(FinishReason.EOS_TOKEN))
        assertTrue("Should have STOP_SEQUENCE", reasons.contains(FinishReason.STOP_SEQUENCE))
        assertTrue("Should have CANCELLED", reasons.contains(FinishReason.CANCELLED))
        assertTrue("Should have ERROR", reasons.contains(FinishReason.ERROR))
    }

    @Test
    fun `test data class equality`() {
        val config1 = EdgeVedaConfig(maxTokens = 100)
        val config2 = EdgeVedaConfig(maxTokens = 100)
        val config3 = EdgeVedaConfig(maxTokens = 200)

        assertEquals("Configs with same values should be equal", config1, config2)
        assertNotEquals("Configs with different values should not be equal", config1, config3)
    }

    @Test
    fun `test data class copy`() {
        val original = EdgeVedaConfig(maxTokens = 100, temperature = 0.5f)
        val copy = original.copy(temperature = 0.8f)

        assertEquals("Max tokens should be same", original.maxTokens, copy.maxTokens)
        assertNotEquals("Temperature should be different", original.temperature, copy.temperature)
        assertEquals("Copy temperature should be 0.8", 0.8f, copy.temperature, 0.001f)
    }
}
