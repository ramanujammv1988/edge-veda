package com.edgeveda.example

import android.app.ActivityManager
import android.content.Context
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
import com.edgeveda.sdk.EdgeVeda
import com.edgeveda.sdk.EdgeVedaConfig
import com.edgeveda.sdk.GenerateOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.system.measureTimeMillis

/**
 * Verification Test Activity for EdgeVeda SDK
 * 
 * Tests:
 * 1. Memory Leak Detection - Run 100 inferences and track RSS
 * 2. Latency Benchmarks - Measure p50/p95 latency on physical device
 * 3. Build Verification - Ensure native library loads correctly
 */
class VerificationTestActivity : ComponentActivity() {
    private val TAG = "EdgeVedaVerification"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        setContent {
            EdgeVedaTheme {
                VerificationTestScreen()
            }
        }
    }
    
    @Composable
    fun VerificationTestScreen() {
        val scope = rememberCoroutineScope()
        var testOutput by remember { mutableStateOf("") }
        var isRunning by remember { mutableStateOf(false) }
        var modelPath by remember { mutableStateOf("/sdcard/Download/phi-3-mini-4k-instruct.Q4_K_M.gguf") }
        
        val scrollState = rememberScrollState()
        
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("EdgeVeda Verification Tests") }
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp)
            ) {
                // Model Path Input
                OutlinedTextField(
                    value = modelPath,
                    onValueChange = { modelPath = it },
                    label = { Text("Model Path") },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isRunning
                )
                
                Spacer(modifier = Modifier.height(16.dp))
                
                // Test Buttons
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = {
                            scope.launch {
                                isRunning = true
                                testOutput = "Starting memory leak test...\n"
                                runMemoryLeakTest(modelPath) { output ->
                                    testOutput += output
                                }
                                isRunning = false
                            }
                        },
                        enabled = !isRunning,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Memory Test")
                    }
                    
                    Button(
                        onClick = {
                            scope.launch {
                                isRunning = true
                                testOutput = "Starting latency benchmark...\n"
                                runLatencyBenchmark(modelPath) { output ->
                                    testOutput += output
                                }
                                isRunning = false
                            }
                        },
                        enabled = !isRunning,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Latency Test")
                    }
                }
                
                Spacer(modifier = Modifier.height(8.dp))
                
                Button(
                    onClick = {
                        scope.launch {
                            isRunning = true
                            testOutput = "Running all verification tests...\n"
                            runAllTests(modelPath) { output ->
                                testOutput += output
                            }
                            isRunning = false
                        }
                    },
                    enabled = !isRunning,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Run All Tests")
                }
                
                Spacer(modifier = Modifier.height(16.dp))
                
                // Output Display
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                ) {
                    Text(
                        text = testOutput,
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(scrollState)
                            .padding(8.dp),
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall
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
                
                // Check if model exists
                if (!File(modelPath).exists()) {
                    onOutput("ERROR: Model file not found at $modelPath\n")
                    onOutput("Please download a GGUF model and update the path.\n")
                    return@withContext
                }
                
                // Initialize model
                onOutput("Initializing model...\n")
                val edgeVeda = EdgeVeda(this@VerificationTestActivity)
                val config = EdgeVedaConfig(
                    backend = EdgeVedaConfig.Backend.CPU,
                    numThreads = 4,
                    contextSize = 2048,
                    useGpu = false
                )
                
                edgeVeda.initModel(modelPath, config)
                onOutput("Model initialized successfully\n\n")
                
                val memorySnapshots = mutableListOf<MemorySnapshot>()
                val prompt = "Say hello in 5 words"
                val options = GenerateOptions(maxTokens = 20)
                
                // Run 100 inferences
                onOutput("Running 100 inferences...\n")
                onOutput("%-10s %-15s %-15s %-15s %-15s\n".format(
                    "Iteration", "RSS (MB)", "Native (MB)", "Java (MB)", "Time (ms)"
                ))
                onOutput("${"=".repeat(80)}\n")
                
                for (i in 1..100) {
                    // Run inference
                    val inferenceTime = measureTimeMillis {
                        edgeVeda.generate(prompt, options)
                    }
                    
                    // Force GC to get stable memory reading
                    System.gc()
                    Thread.sleep(50)
                    
                    // Collect memory snapshot
                    val snapshot = getMemorySnapshot()
                    memorySnapshots.add(snapshot)
                    
                    if (i % 10 == 0) {
                        onOutput("%-10d %-15.2f %-15.2f %-15.2f %-15d\n".format(
                            i,
                            snapshot.rssKB / 1024.0,
                            snapshot.nativeHeapKB / 1024.0,
                            snapshot.javaHeapKB / 1024.0,
                            inferenceTime
                        ))
                    }
                    
                    Log.d(TAG, "Iteration $i: RSS=${snapshot.rssKB}KB, Time=${inferenceTime}ms")
                }
                
                // Analyze results
                onOutput("\n=== MEMORY ANALYSIS ===\n")
                val firstSnapshot = memorySnapshots.first()
                val lastSnapshot = memorySnapshots.last()
                
                val rssGrowth = lastSnapshot.rssKB - firstSnapshot.rssKB
                val nativeGrowth = lastSnapshot.nativeHeapKB - firstSnapshot.nativeHeapKB
                val javaGrowth = lastSnapshot.javaHeapKB - firstSnapshot.javaHeapKB
                
                onOutput("Initial RSS: %.2f MB\n".format(firstSnapshot.rssKB / 1024.0))
                onOutput("Final RSS: %.2f MB\n".format(lastSnapshot.rssKB / 1024.0))
                onOutput("RSS Growth: %.2f MB (%.1f%%)\n".format(
                    rssGrowth / 1024.0,
                    (rssGrowth.toDouble() / firstSnapshot.rssKB) * 100
                ))
                onOutput("\n")
                onOutput("Native Heap Growth: %.2f MB\n".format(nativeGrowth / 1024.0))
                onOutput("Java Heap Growth: %.2f MB\n".format(javaGrowth / 1024.0))
                onOutput("\n")
                
                // Verdict
                val leakThresholdMB = 50.0
                val hasLeak = (rssGrowth / 1024.0) > leakThresholdMB
                
                if (hasLeak) {
                    onOutput("⚠️  WARNING: Potential memory leak detected!\n")
                    onOutput("RSS grew by more than ${leakThresholdMB}MB over 100 inferences.\n")
                } else {
                    onOutput("✅ PASS: No significant memory leak detected.\n")
                    onOutput("RSS growth is within acceptable range.\n")
                }
                
                // Cleanup
                edgeVeda.dispose()
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
                
                // Check if model exists
                if (!File(modelPath).exists()) {
                    onOutput("ERROR: Model file not found at $modelPath\n")
                    return@withContext
                }
                
                // Initialize model
                onOutput("Initializing model...\n")
                val edgeVeda = EdgeVeda(this@VerificationTestActivity)
                val config = EdgeVedaConfig(
                    backend = EdgeVedaConfig.Backend.CPU,
                    numThreads = 4,
                    contextSize = 2048,
                    useGpu = false
                )
                
                edgeVeda.initModel(modelPath, config)
                onOutput("Model initialized successfully\n\n")
                
                val timings = mutableListOf<Long>()
                val prompt = "Tell me a short joke"
                val options = GenerateOptions(maxTokens = 50)
                
                // Warmup runs
                onOutput("Running 5 warmup inferences...\n")
                repeat(5) {
                    edgeVeda.generate(prompt, options)
                }
                onOutput("Warmup complete\n\n")
                
                // Benchmark runs
                onOutput("Running 50 benchmark inferences...\n")
                for (i in 1..50) {
                    val time = measureTimeMillis {
                        edgeVeda.generate(prompt, options)
                    }
                    timings.add(time)
                    
                    if (i % 10 == 0) {
                        onOutput("Completed $i/50 runs\n")
                    }
                }
                
                // Calculate statistics
                timings.sort()
                val min = timings.first()
                val max = timings.last()
                val mean = timings.average()
                val p50 = timings[timings.size / 2]
                val p95 = timings[(timings.size * 0.95).toInt()]
                val p99 = timings[(timings.size * 0.99).toInt()]
                
                onOutput("\n=== LATENCY RESULTS ===\n")
                onOutput("Min:  %6d ms\n".format(min))
                onOutput("Mean: %6.1f ms\n".format(mean))
                onOutput("P50:  %6d ms\n".format(p50))
                onOutput("P95:  %6d ms\n".format(p95))
                onOutput("P99:  %6d ms\n".format(p99))
                onOutput("Max:  %6d ms\n".format(max))
                onOutput("\n")
                
                // Tokens per second estimate (assuming ~50 tokens generated)
                val tokensGenerated = 50
                val tokensPerSecP50 = (tokensGenerated * 1000.0) / p50
                val tokensPerSecP95 = (tokensGenerated * 1000.0) / p95
                
                onOutput("Throughput (estimated @ 50 tokens):\n")
                onOutput("P50: %.1f tokens/sec\n".format(tokensPerSecP50))
                onOutput("P95: %.1f tokens/sec\n".format(tokensPerSecP95))
                onOutput("\n")
                
                // Device info
                onOutput("=== DEVICE INFO ===\n")
                onOutput("Device: ${android.os.Build.MODEL}\n")
                onOutput("Android: ${android.os.Build.VERSION.RELEASE}\n")
                onOutput("CPU Cores: ${Runtime.getRuntime().availableProcessors()}\n")
                
                // Cleanup
                edgeVeda.dispose()
                onOutput("\n=== TEST COMPLETE ===\n")
                
            } catch (e: Exception) {
                onOutput("\nERROR: ${e.message}\n")
                Log.e(TAG, "Latency benchmark failed", e)
            }
        }
    }
    
    private suspend fun runAllTests(modelPath: String, onOutput: (String) -> Unit) {
        onOutput("=== RUNNING ALL VERIFICATION TESTS ===\n\n")
        
        // Test 1: Build verification
        onOutput("Test 1: Build Verification\n")
        onOutput("Checking if native library loads...\n")
        try {
            System.loadLibrary("edgeveda_jni")
            onOutput("✅ Native library loaded successfully\n\n")
        } catch (e: Exception) {
            onOutput("❌ Failed to load native library: ${e.message}\n\n")
            return
        }
        
        // Test 2: Memory leak test
        onOutput("Test 2: Memory Leak Detection\n")
        runMemoryLeakTest(modelPath, onOutput)
        onOutput("\n")
        
        // Test 3: Latency benchmark
        onOutput("Test 3: Latency Benchmark\n")
        runLatencyBenchmark(modelPath, onOutput)
        
        onOutput("\n=== ALL TESTS COMPLETE ===\n")
    }
    
    private fun getMemorySnapshot(): MemorySnapshot {
        // Get RSS from /proc/self/status
        val rssKB = try {
            File("/proc/self/status").readText()
                .lines()
                .find { it.startsWith("VmRSS:") }
                ?.split(Regex("\\s+"))
                ?.get(1)
                ?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            0L
        }
        
        // Get native heap info
        val nativeHeapKB = Debug.getNativeHeapAllocatedSize() / 1024
        
        // Get Java heap info
        val runtime = Runtime.getRuntime()
        val javaHeapKB = (runtime.totalMemory() - runtime.freeMemory()) / 1024
        
        return MemorySnapshot(rssKB, nativeHeapKB, javaHeapKB)
    }
    
    data class MemorySnapshot(
        val rssKB: Long,
        val nativeHeapKB: Long,
        val javaHeapKB: Long
    )
}