# EdgeVeda Kotlin SDK - Quick Start Guide

## Basic Usage Example

```kotlin
import com.edgeveda.sdk.*
import kotlinx.coroutines.flow.collect

// 1. Create SDK instance
val edgeVeda = EdgeVeda.create()

// 2. Configure for your use case
val config = EdgeVedaConfig.mobile() // or .highQuality() or .fast()

// 3. Initialize with your model
edgeVeda.init("/sdcard/models/llama-7b-q4.gguf", config)

// 4. Generate text (blocking)
val response = edgeVeda.generate("What is quantum computing?")
println(response)

// 5. Or use streaming for better UX
edgeVeda.generateStream("Explain AI in simple terms")
    .collect { token ->
        print(token) // Update UI as tokens arrive
    }

// 6. Clean up when done
edgeVeda.close()
```

## Using with Android Activity

```kotlin
class MainActivity : AppCompatActivity() {
    private lateinit var edgeVeda: EdgeVeda

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize SDK
        edgeVeda = EdgeVeda.create()

        lifecycleScope.launch {
            try {
                // Load model
                val modelPath = getModelPath() // Copy model to app storage
                edgeVeda.init(modelPath, EdgeVedaConfig.mobile())

                // Generate
                val response = edgeVeda.generate("Hello!")
                textView.text = response

            } catch (e: EdgeVedaException) {
                Log.e(TAG, "Error: ${e.message}", e)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        edgeVeda.close()
    }

    private fun getModelPath(): String {
        // Copy model from assets or download
        val modelFile = File(filesDir, "model.gguf")
        if (!modelFile.exists()) {
            assets.open("model.gguf").use { input ->
                modelFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }
        return modelFile.absolutePath
    }
}
```

## Streaming to UI with Flow

```kotlin
class ChatViewModel : ViewModel() {
    private val edgeVeda = EdgeVeda.create()
    private val _response = MutableStateFlow("")
    val response: StateFlow<String> = _response.asStateFlow()

    suspend fun initModel(modelPath: String) {
        edgeVeda.init(modelPath, EdgeVedaConfig.mobile())
    }

    fun generateResponse(prompt: String) {
        viewModelScope.launch {
            _response.value = ""
            edgeVeda.generateStream(prompt)
                .collect { token ->
                    _response.value += token
                }
        }
    }

    override fun onCleared() {
        super.onCleared()
        edgeVeda.close()
    }
}
```

## Compose Integration

```kotlin
@Composable
fun ChatScreen(viewModel: ChatViewModel = viewModel()) {
    val response by viewModel.response.collectAsState()
    var prompt by remember { mutableStateOf("") }

    Column(modifier = Modifier.padding(16.dp)) {
        OutlinedTextField(
            value = prompt,
            onValueChange = { prompt = it },
            label = { Text("Ask a question") },
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = { viewModel.generateResponse(prompt) },
            modifier = Modifier.padding(top = 8.dp)
        ) {
            Text("Generate")
        }

        Text(
            text = response,
            modifier = Modifier.padding(top = 16.dp)
        )
    }
}
```

## Configuration Examples

### Mobile Device (Default)
```kotlin
val config = EdgeVedaConfig.mobile()
// 4 threads, 256 max tokens, 1024 context, GPU enabled
```

### High Quality Output
```kotlin
val config = EdgeVedaConfig.highQuality()
// More tokens, larger context, higher quality sampling
```

### Fast Response
```kotlin
val config = EdgeVedaConfig.fast()
// 2 threads, 128 max tokens, optimized for speed
```

### Custom Configuration
```kotlin
val config = EdgeVedaConfig(
    backend = Backend.VULKAN,      // Use Vulkan GPU
    numThreads = 6,                 // 6 CPU threads
    maxTokens = 512,                // Generate up to 512 tokens
    contextSize = 2048,             // 2K context window
    temperature = 0.8f,             // More creative (0.0-2.0)
    topP = 0.95f,                   // Nucleus sampling
    topK = 50,                      // Top-k sampling
    useGpu = true                   // Enable GPU
)
```

## Generation Options

### Default Generation
```kotlin
val response = edgeVeda.generate("What is AI?")
```

### Creative Generation
```kotlin
val response = edgeVeda.generate(
    prompt = "Write a poem",
    options = GenerateOptions.creative()
)
```

### Factual Generation
```kotlin
val response = edgeVeda.generate(
    prompt = "What is 2+2?",
    options = GenerateOptions.deterministic()
)
```

### Custom Options
```kotlin
val response = edgeVeda.generate(
    prompt = "Explain...",
    options = GenerateOptions(
        maxTokens = 200,
        temperature = 0.9f,
        stopSequences = listOf("\n\n", "END")
    )
)
```

## Error Handling

```kotlin
suspend fun safeGenerate(prompt: String): String {
    return try {
        edgeVeda.generate(prompt)
    } catch (e: EdgeVedaException.ModelLoadError) {
        "Failed to load model: ${e.message}"
    } catch (e: EdgeVedaException.GenerationError) {
        "Generation failed: ${e.message}"
    } catch (e: EdgeVedaException.OutOfMemoryError) {
        "Out of memory. Try a smaller model."
    } catch (e: EdgeVedaException) {
        "SDK error: ${e.message}"
    }
}
```

## Memory Management

```kotlin
// Check available memory before loading
val runtime = Runtime.getRuntime()
val availableMB = runtime.maxMemory() / (1024 * 1024)

if (availableMB < 1024) {
    // Use smaller model or lighter config
    config = EdgeVedaConfig.fast()
}

// Monitor memory usage
lifecycleScope.launch {
    while (true) {
        val usageMB = edgeVeda.memoryUsage / (1024 * 1024)
        Log.d(TAG, "Model using: $usageMB MB")
        delay(5000) // Check every 5 seconds
    }
}
```

## Best Practices

1. **Initialize once** - Create EdgeVeda instance and reuse it
2. **Use lifecycle-aware components** - Clean up in onDestroy()
3. **Handle errors gracefully** - Wrap calls in try-catch
4. **Use streaming for UX** - Better user experience than blocking
5. **Monitor memory** - Check memoryUsage property
6. **Choose right backend** - Use AUTO for automatic selection
7. **Test on real devices** - Emulators may not support GPU
8. **Optimize config** - Balance quality vs. performance
9. **Cache models locally** - Don't download on every launch
10. **Use coroutines** - All heavy operations are suspend functions

## Common Issues

### Native library not found
```kotlin
if (!EdgeVeda.isNativeLibraryAvailable()) {
    // Handle missing native library
    Log.e(TAG, "Native library not available")
}
```

### Model fails to load
- Check model file exists and is readable
- Ensure model format is compatible (GGUF recommended)
- Verify sufficient memory available
- Try smaller model or lighter quantization

### Slow generation
- Reduce `maxTokens` in config
- Use `Backend.VULKAN` or `Backend.NNAPI` for GPU
- Increase `numThreads` (but not too many)
- Use smaller model or higher quantization
- Try `EdgeVedaConfig.fast()` preset

### Out of memory
- Use smaller model (e.g., 3B instead of 7B parameters)
- Enable `useMmap = true` for memory mapping
- Reduce `contextSize` and `batchSize`
- Disable `useMlock` to allow swapping
- Close unused instances

## Performance Tips

1. **Prefer streaming** - `generateStream()` over `generate()`
2. **Warm up model** - Generate dummy text after init
3. **Reuse instance** - Don't create multiple EdgeVeda instances
4. **Profile on target device** - Test with actual hardware
5. **Use appropriate quantization** - Q4_0 is good balance
6. **Monitor battery** - LLM inference is power-intensive

## Next Steps

- Read full documentation in README.md
- Check example app (coming soon)
- Review API documentation
- Join community Discord
- Report issues on GitHub
