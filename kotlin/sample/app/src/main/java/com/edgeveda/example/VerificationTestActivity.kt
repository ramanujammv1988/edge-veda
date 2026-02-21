package com.edgeveda.example

import android.os.Bundle
import android.os.Debug
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.edgeveda.sdk.Backend
import com.edgeveda.sdk.EdgeVeda
import com.edgeveda.sdk.EdgeVedaConfig
import com.edgeveda.sdk.GenerateOptions
import com.edgeveda.sdk.ModelManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.system.measureTimeMillis

/**
 * Verification Test Activity for EdgeVeda SDK
 *
 * Tests:
 * 1. Build Verification — ensures native library loads correctly
 * 2. Memory Leak Detection — 100 inferences tracking RSS, native heap, Java heap
 * 3. Latency Benchmark — 50 inferences measuring p50/p95/p99
 */
class VerificationTestActivity : ComponentActivity() {
    private val TAG = "EdgeVedaVerification"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    background = AppTheme.background,
                    surface = AppTheme.surface,
                    primary = AppTheme.accent,
                    onPrimary = AppTheme.background,
                    onSurface = AppTheme.textPrimary,
                    error = AppTheme.danger,
                )
            ) {
                VerificationTestScreen()
            }
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun VerificationTestScreen() {
        val context = this
        val scope = rememberCoroutineScope()
        var testOutput by remember { mutableStateOf("") }
        var isRunning by remember { mutableStateOf(false) }
        // Default empty; auto-populated with first downloaded model if available
        var modelPath by remember { mutableStateOf("") }

        val scrollState = rememberScrollState()

        // Auto-populate model path from ModelManager if any model is already downloaded
        LaunchedEffect(Unit) {
            val mm = ModelManager(context)
            val downloaded = mm.getDownloadedModels()
            if (downloaded.isNotEmpty() && modelPath.isEmpty()) {
                modelPath = mm.getModelPath(downloaded.first())
            }
        }

        Scaffold(
            topBar = {
                TopAppBar(title = { Text("EdgeVeda Verification Tests") })
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp)
            ) {
                OutlinedTextField(
                    value = modelPath,
                    onValueChange = { modelPath = it },
                    label = { Text("Model Path (.gguf / ggml)") },
                    placeholder = { Text("Auto-populated from downloaded models") },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isRunning,
                )

                Spacer(modifier = Modifier.height(16.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Button(
                        onClick = {
                            scope.launch {
                                isRunning = true
                                testOutput = "Starting memory leak test...\n"
                                runMemoryLeakTest(modelPath) { testOutput += it }
                                isRunning = false
                            }
                        },
                        enabled = !isRunning,
                        modifier = Modifier.weight(1f),
                    ) { Text("Memory Test") }

                    Button(
                        onClick = {
                            scope.launch {
                                isRunning = true
                                testOutput = "Starting latency benchmark...\n"
                                runLatencyBenchmark(modelPath) { testOutput += it }
                                isRunning = false
                            }
                        },
                        enabled = !isRunning,
                        modifier = Modifier.weight(1f),
                    ) { Text("Latency Test") }
                }

                Spacer(modifier = Modifier.height(8.dp))

                Button(
                    onClick = {
                        scope.launch {
                            isRunning = true
                            testOutput = "Running all verification tests...\n"
                            runAllTests(modelPath) { testOutput += it }
                            isRunning = false
                        }
                    },
                    enabled = !isRunning,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Run All Tests") }

                Spacer(modifier = Modifier.height(16.dp))

                Card(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    Text(
                        text = testOutput,
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(scrollState)
                            .padding(8.dp),
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                if (isRunning) {
                    Spacer(modifier = Modifier.height(8.dp))
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }

    private suspend fun runMemoryLeakTest(modelPath: String, onOutput: (String) -> Unit) {
        withContext(Dispatchers.Default) {
            try {
                onOutput("=== MEMORY LEAK TEST (100 INFERENCES) ===\n")
                onOutput("Model: $modelPath\n\n")

                if (!File(modelPath).exists()) {
                    onOutput("ERROR: Model file not found at $modelPath\n")
                    onOutput("Download a model via the main app first.\n")
                    return@withContext
                }

                onOutput("Initializing model...\n")
                val edgeVeda = EdgeVeda.create(this@VerificationTestActivity)
                val config = EdgeVedaConfig(
                    backend = Backend.CPU,
                    numThreads = 4,
                    contextSize = 2048,
                    useGpu = false,
                )
                edgeVeda.init(modelPath, config)
                onOutput("Model initialized successfully\n\n")

                val memorySnapshots = mutableListOf<MemorySnapshot>()
                val prompt = "Say hello in 5 words"
                val options = GenerateOptions(maxTokens = 20)

                onOutput("Running 100 inferences...\n")
                onOutput(
                    "%-10s %-15s %-15s %-15s %-15s\n".format(
                        "Iteration", "RSS (MB)", "Native (MB)", "Java (MB)", "Time (ms)"
                    )
                )
                onOutput("${"=".repeat(80)}\n")

                for (i in 1..100) {
                    val inferenceTime = measureTimeMillis { edgeVeda.generate(prompt, options) }
                    System.gc()
                    Thread.sleep(50)

                    val snapshot = getMemorySnapshot()
                    memorySnapshots.add(snapshot)

                    if (i % 10 == 0) {
                        onOutput(
                            "%-10d %-15.2f %-15.2f %-15.2f %-15d\n".format(
                                i,
                                snapshot.rssKB / 1024.0,
                                snapshot.nativeHeapKB / 1024.0,
                                snapshot.javaHeapKB / 1024.0,
                                inferenceTime,
                            )
                        )
                    }
                    Log.d(TAG, "Iteration $i: RSS=${snapshot.rssKB}KB, Time=${inferenceTime}ms")
                }

                onOutput("\n=== MEMORY ANALYSIS ===\n")
                val first = memorySnapshots.first()
                val last = memorySnapshots.last()

                val rssGrowth = last.rssKB - first.rssKB
                val nativeGrowth = last.nativeHeapKB - first.nativeHeapKB
                val javaGrowth = last.javaHeapKB - first.javaHeapKB

                onOutput("Initial RSS: %.2f MB\n".format(first.rssKB / 1024.0))
                onOutput("Final RSS:   %.2f MB\n".format(last.rssKB / 1024.0))
                onOutput(
                    "RSS Growth:  %.2f MB (%.1f%%)\n".format(
                        rssGrowth / 1024.0,
                        if (first.rssKB > 0) (rssGrowth.toDouble() / first.rssKB) * 100 else 0.0,
                    )
                )
                onOutput("\nNative Heap Growth: %.2f MB\n".format(nativeGrowth / 1024.0))
                onOutput("Java Heap Growth:   %.2f MB\n".format(javaGrowth / 1024.0))
                onOutput("\n")

                if ((rssGrowth / 1024.0) > 50.0) {
                    onOutput("WARNING: Potential memory leak — RSS grew >50 MB over 100 inferences.\n")
                } else {
                    onOutput("PASS: No significant memory leak detected.\n")
                }

                edgeVeda.close()
                onOutput("\n=== TEST COMPLETE ===\n")

            } catch (e: Exception) {
                onOutput("\nERROR: ${e.message}\n")
                Log.e(TAG, "Memory leak test failed", e)
            }
        }
    }

    private suspend fun runLatencyBenchmark(modelPath: String, onOutput: (String) -> Unit) {
        withContext(Dispatchers.Default) {
            try {
                onOutput("=== LATENCY BENCHMARK (50 RUNS) ===\n")
                onOutput("Model: $modelPath\n\n")

                if (!File(modelPath).exists()) {
                    onOutput("ERROR: Model file not found at $modelPath\n")
                    return@withContext
                }

                onOutput("Initializing model...\n")
                val edgeVeda = EdgeVeda.create(this@VerificationTestActivity)
                val config = EdgeVedaConfig(
                    backend = Backend.CPU,
                    numThreads = 4,
                    contextSize = 2048,
                    useGpu = false,
                )
                edgeVeda.init(modelPath, config)
                onOutput("Model initialized successfully\n\n")

                val timings = mutableListOf<Long>()
                val prompt = "Tell me a short joke"
                val options = GenerateOptions(maxTokens = 50)

                onOutput("Running 5 warmup inferences...\n")
                repeat(5) { edgeVeda.generate(prompt, options) }
                onOutput("Warmup complete\n\n")

                onOutput("Running 50 benchmark inferences...\n")
                for (i in 1..50) {
                    val time = measureTimeMillis { edgeVeda.generate(prompt, options) }
                    timings.add(time)
                    if (i % 10 == 0) onOutput("Completed $i/50 runs\n")
                }

                timings.sort()
                val lastIdx = timings.lastIndex
                val min = timings.first()
                val max = timings.last()
                val mean = timings.average()
                val p50 = timings[lastIdx / 2]
                // Guard against off-by-one: coerce index to valid range
                val p95 = timings[(lastIdx * 0.95).toInt().coerceAtMost(lastIdx)]
                val p99 = timings[(lastIdx * 0.99).toInt().coerceAtMost(lastIdx)]

                onOutput("\n=== LATENCY RESULTS ===\n")
                onOutput("Min:  %6d ms\n".format(min))
                onOutput("Mean: %6.1f ms\n".format(mean))
                onOutput("P50:  %6d ms\n".format(p50))
                onOutput("P95:  %6d ms\n".format(p95))
                onOutput("P99:  %6d ms\n".format(p99))
                onOutput("Max:  %6d ms\n".format(max))
                onOutput("\n")

                // maxTokens is the ceiling; actual output may be shorter
                onOutput("Throughput (estimated @ ${options.maxTokens} tokens):\n")
                onOutput("P50: %.1f tokens/sec\n".format(options.maxTokens!! * 1000.0 / p50))
                onOutput("P95: %.1f tokens/sec\n".format(options.maxTokens!! * 1000.0 / p95))
                onOutput("\n")

                onOutput("=== DEVICE INFO ===\n")
                onOutput("Device:    ${android.os.Build.MODEL}\n")
                onOutput("Android:   ${android.os.Build.VERSION.RELEASE}\n")
                onOutput("CPU Cores: ${Runtime.getRuntime().availableProcessors()}\n")

                edgeVeda.close()
                onOutput("\n=== TEST COMPLETE ===\n")

            } catch (e: Exception) {
                onOutput("\nERROR: ${e.message}\n")
                Log.e(TAG, "Latency benchmark failed", e)
            }
        }
    }

    private suspend fun runAllTests(modelPath: String, onOutput: (String) -> Unit) {
        onOutput("=== RUNNING ALL VERIFICATION TESTS ===\n\n")

        onOutput("Test 1: Build Verification\n")
        try {
            System.loadLibrary("edgeveda_jni")
            onOutput("PASS: Native library loaded successfully\n\n")
        } catch (e: Exception) {
            onOutput("FAIL: Failed to load native library: ${e.message}\n\n")
            return
        }

        onOutput("Test 2: Memory Leak Detection\n")
        runMemoryLeakTest(modelPath, onOutput)
        onOutput("\n")

        onOutput("Test 3: Latency Benchmark\n")
        runLatencyBenchmark(modelPath, onOutput)

        onOutput("\n=== ALL TESTS COMPLETE ===\n")
    }

    private fun getMemorySnapshot(): MemorySnapshot {
        val rssKB = try {
            File("/proc/self/status").readText()
                .lines()
                .find { it.startsWith("VmRSS:") }
                ?.split(Regex("\\s+"))
                ?.getOrNull(1)
                ?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            0L
        }

        val nativeHeapKB = Debug.getNativeHeapAllocatedSize() / 1024
        val runtime = Runtime.getRuntime()
        val javaHeapKB = (runtime.totalMemory() - runtime.freeMemory()) / 1024

        return MemorySnapshot(rssKB, nativeHeapKB, javaHeapKB)
    }

    data class MemorySnapshot(
        val rssKB: Long,
        val nativeHeapKB: Long,
        val javaHeapKB: Long,
    )
}
