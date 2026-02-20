package com.edgeveda.example

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.edgeveda.sdk.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Chat screen matching Flutter's ChatScreen exactly.
 *
 * Features: ChatSession streaming, persona chips, metrics bar,
 * context indicator, message bubbles with avatars, benchmark mode.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val vm: ChatViewModel = viewModel(
        factory = ChatViewModel.Factory(context.applicationContext as Application)
    )
    val listState = rememberLazyListState()
    var showModelSheet by remember { mutableStateOf(false) }
    var showBenchmarkDialog by remember { mutableStateOf(false) }
    var showInfoDialog by remember { mutableStateOf(false) }

    // Auto-scroll on new messages
    LaunchedEffect(vm.displayMessages.size, vm.streamingText) {
        if (vm.displayMessages.isNotEmpty() || vm.streamingText.isNotEmpty()) {
            listState.animateScrollToItem(maxOf(0, vm.displayMessages.size - 1))
        }
    }

    Column(modifier = modifier.fillMaxSize().background(AppTheme.background)) {
        // Top bar
        CenterAlignedTopAppBar(
            title = { Text("Veda", color = AppTheme.textPrimary) },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                containerColor = AppTheme.background,
            ),
            actions = {
                if (vm.isInitialized) {
                    IconButton(onClick = vm::resetChat, enabled = !vm.isStreaming && !vm.isLoading) {
                        Icon(Icons.Outlined.AddComment, contentDescription = "New Chat", tint = AppTheme.textSecondary)
                    }
                }
                IconButton(onClick = { showModelSheet = true }) {
                    Icon(Icons.Outlined.Layers, contentDescription = "Models", tint = AppTheme.textSecondary)
                }
                if (vm.isInitialized && !vm.runningBenchmark) {
                    IconButton(onClick = { vm.runBenchmark(); showBenchmarkDialog = true }) {
                        Icon(Icons.Outlined.Assessment, contentDescription = "Benchmark", tint = AppTheme.textSecondary)
                    }
                }
                if (vm.isInitialized) {
                    IconButton(onClick = { showInfoDialog = true }) {
                        Icon(Icons.Outlined.Info, contentDescription = "Info", tint = AppTheme.textSecondary)
                    }
                }
            },
        )

        // Status bar
        StatusBar(vm)

        // Download progress
        if (vm.isDownloading) {
            LinearProgressIndicator(
                progress = vm.downloadProgress.toFloat(),
                modifier = Modifier.fillMaxWidth(),
                color = AppTheme.accent,
                trackColor = AppTheme.surfaceVariant,
            )
        }

        // Metrics bar
        if (vm.isInitialized) {
            MetricsBar(vm)
        }

        // Persona picker or context indicator
        if (vm.isInitialized) {
            if (vm.displayMessages.isEmpty() && !vm.isStreaming) {
                PersonaPicker(vm)
            } else {
                ContextIndicator(vm)
            }
        }

        // Messages list
        Box(modifier = Modifier.weight(1f)) {
            if (vm.displayMessages.isEmpty() && !vm.isStreaming) {
                EmptyState()
            } else {
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(vm.displayMessages) { message ->
                        MessageBubble(message)
                    }
                    if (vm.isStreaming && vm.streamingText.isNotEmpty()) {
                        item {
                            MessageBubble(ChatMessage(ChatRole.ASSISTANT, vm.streamingText))
                        }
                    }
                }
            }
        }

        // Input bar
        InputBar(vm)
    }

    // Model sheet
    if (showModelSheet) {
        ModalBottomSheet(
            onDismissRequest = { showModelSheet = false },
            containerColor = AppTheme.surface,
        ) {
            ModelSelectionSheet()
        }
    }

    // Benchmark dialog
    if (showBenchmarkDialog && vm.benchmarkResultText.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = { showBenchmarkDialog = false },
            title = { Text("Benchmark Results", color = AppTheme.textPrimary) },
            text = { Text(vm.benchmarkResultText, color = AppTheme.textPrimary) },
            confirmButton = {
                TextButton(onClick = { showBenchmarkDialog = false }) {
                    Text("OK", color = AppTheme.accent)
                }
            },
            containerColor = AppTheme.surface,
        )
    }

    // Info dialog
    if (showInfoDialog) {
        AlertDialog(
            onDismissRequest = { showInfoDialog = false },
            title = { Text("Performance Info", color = AppTheme.textPrimary) },
            text = {
                Column {
                    Text("Platform: Android", color = AppTheme.textPrimary, fontSize = 14.sp)
                    Text("Backend: CPU", color = AppTheme.textPrimary, fontSize = 14.sp)
                    Divider(color = AppTheme.border, modifier = Modifier.padding(vertical = 8.dp))
                    Text("Memory: ${vm.memoryText}", color = AppTheme.textPrimary, fontSize = 14.sp)
                    if (vm.tokensPerSecond != null) {
                        Text("Last Speed: ${String.format("%.1f", vm.tokensPerSecond)} tok/s", color = AppTheme.textPrimary, fontSize = 14.sp)
                    }
                    if (vm.timeToFirstTokenMs != null) {
                        Text("Last TTFT: ${vm.timeToFirstTokenMs}ms", color = AppTheme.textPrimary, fontSize = 14.sp)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showInfoDialog = false }) {
                    Text("OK", color = AppTheme.accent)
                }
            },
            containerColor = AppTheme.surface,
        )
    }
}

@Composable
private fun StatusBar(vm: ChatViewModel) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppTheme.surface)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (vm.isDownloading || vm.isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = AppTheme.accent,
            )
            Spacer(Modifier.width(8.dp))
        }

        Text(
            text = vm.statusMessage,
            fontSize = 12.sp,
            color = if (vm.isInitialized) AppTheme.success else AppTheme.warning,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )

        if (!vm.isInitialized && !vm.isLoading && !vm.isDownloading && vm.modelPath != null) {
            Button(
                onClick = { vm.initialize() },
                colors = ButtonDefaults.buttonColors(
                    containerColor = AppTheme.accent,
                    contentColor = AppTheme.background,
                ),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            ) {
                Text("Initialize", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
    Divider(color = AppTheme.border, thickness = 1.dp)
}

@Composable
private fun MetricsBar(vm: ChatViewModel) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppTheme.surface)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceAround,
    ) {
        MetricChip(icon = Icons.Outlined.Timer, label = "TTFT", value = vm.ttftText)
        MetricChip(icon = Icons.Outlined.Speed, label = "Speed", value = vm.speedText)
        MetricChip(icon = Icons.Outlined.Memory, label = "Memory", value = vm.memoryText)
    }
    Divider(color = AppTheme.border, thickness = 1.dp)
}

@Composable
private fun MetricChip(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(4.dp))
            Text(label, fontSize = 10.sp, fontWeight = FontWeight.Medium, color = AppTheme.textTertiary)
        }
        Spacer(Modifier.height(2.dp))
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = AppTheme.textPrimary)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PersonaPicker(vm: ChatViewModel) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppTheme.surface)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Text("Choose a persona", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AppTheme.textTertiary)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("Assistant" to SystemPromptPreset.Assistant, "Coder" to SystemPromptPreset.Coder, "Creative" to SystemPromptPreset.Creative).forEach { (label, preset) ->
                val isSelected = preset == vm.selectedPreset
                FilterChip(
                    selected = isSelected,
                    onClick = { vm.changePreset(preset) },
                    label = { Text(label, fontSize = 13.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppTheme.accent.copy(alpha = 0.2f),
                        selectedLabelColor = AppTheme.accent,
                        containerColor = AppTheme.surfaceVariant,
                        labelColor = AppTheme.textSecondary,
                    ),
                    border = FilterChipDefaults.filterChipBorder(
                        enabled = true,
                        selected = isSelected,
                        borderColor = if (isSelected) AppTheme.accent else AppTheme.border,
                    ),
                    shape = RoundedCornerShape(20.dp),
                )
            }
        }
    }
    Divider(color = AppTheme.border, thickness = 1.dp)
}

@Composable
private fun ContextIndicator(vm: ChatViewModel) {
    val usage = vm.contextUsage
    val isHigh = usage > 0.8
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppTheme.surface)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Outlined.Memory, contentDescription = null,
            tint = if (isHigh) AppTheme.warning else AppTheme.accent,
            modifier = Modifier.size(14.dp),
        )
        Spacer(Modifier.width(4.dp))
        Text(
            "${vm.turnCount} ${if (vm.turnCount == 1) "turn" else "turns"}",
            fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AppTheme.textSecondary,
        )
        Spacer(Modifier.weight(1f))
        Text(
            "${(usage * 100).toInt()}%",
            fontSize = 11.sp, fontWeight = FontWeight.Medium,
            color = if (isHigh) AppTheme.warning else AppTheme.textTertiary,
        )
        Spacer(Modifier.width(6.dp))
        Box(
            modifier = Modifier
                .width(60.dp)
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(AppTheme.surfaceVariant),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(usage.coerceIn(0.0, 1.0).toFloat())
                    .clip(RoundedCornerShape(2.dp))
                    .background(if (isHigh) AppTheme.warning else AppTheme.accent),
            )
        }
    }
    Divider(color = AppTheme.border, thickness = 1.dp)
}

@Composable
private fun EmptyState() {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Outlined.ChatBubbleOutline,
            contentDescription = null,
            tint = AppTheme.border,
            modifier = Modifier.size(64.dp),
        )
        Spacer(Modifier.height(16.dp))
        Text("Start a conversation", fontSize = 16.sp, color = AppTheme.textTertiary)
        Spacer(Modifier.height(8.dp))
        Text("Ask anything. It runs on your device.", fontSize = 13.sp, color = AppTheme.textTertiary)
    }
}

@Composable
private fun MessageBubble(message: ChatMessage) {
    if (message.role == ChatRole.SYSTEM) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.Center,
        ) {
            Text(
                text = message.content,
                fontSize = 12.sp,
                color = AppTheme.textSecondary,
                modifier = Modifier
                    .background(AppTheme.surfaceVariant, RoundedCornerShape(12.dp))
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
    } else {
        val isUser = message.role == ChatRole.USER
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
            verticalAlignment = Alignment.Bottom,
        ) {
            if (!isUser) {
                // Assistant avatar
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(AppTheme.surfaceVariant),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(8.dp))
            }

            Box(
                modifier = Modifier
                    .widthIn(max = 280.dp)
                    .shadow(8.dp, RoundedCornerShape(20.dp))
                    .background(
                        if (isUser) AppTheme.userBubble else AppTheme.assistantBubble,
                        RoundedCornerShape(20.dp),
                    )
                    .then(
                        if (!isUser) Modifier.border(1.dp, AppTheme.border, RoundedCornerShape(20.dp))
                        else Modifier
                    )
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Text(
                    text = message.content,
                    color = AppTheme.textPrimary,
                    lineHeight = 22.sp,
                )
            }

            if (isUser) {
                Spacer(Modifier.width(8.dp))
                // User avatar
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(AppTheme.surfaceVariant),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.Person, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

@Composable
private fun InputBar(vm: ChatViewModel) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(8.dp)
            .background(AppTheme.background)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = vm.promptText,
            onValueChange = { vm.promptText = it },
            placeholder = { Text("Message...", color = AppTheme.textTertiary) },
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(24.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = AppTheme.accent,
                unfocusedBorderColor = AppTheme.border,
                focusedContainerColor = AppTheme.surfaceVariant,
                unfocusedContainerColor = AppTheme.surfaceVariant,
                focusedTextColor = AppTheme.textPrimary,
                unfocusedTextColor = AppTheme.textPrimary,
                cursorColor = AppTheme.accent,
            ),
            enabled = vm.isInitialized && !vm.isLoading && !vm.isStreaming,
            singleLine = false,
            maxLines = 4,
        )

        Spacer(Modifier.width(8.dp))

        // Send/Stop button
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(if (vm.isStreaming) AppTheme.danger else AppTheme.accent)
                .clickable(enabled = vm.isStreaming || (vm.isInitialized && !vm.isLoading)) {
                    if (vm.isStreaming) vm.cancelGeneration() else vm.sendMessage()
                },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = if (vm.isStreaming) Icons.Default.Stop else Icons.Default.ArrowUpward,
                contentDescription = if (vm.isStreaming) "Stop" else "Send",
                tint = if (vm.isStreaming) AppTheme.textPrimary else AppTheme.background,
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

// MARK: - ViewModel

class ChatViewModel(application: Application) : AndroidViewModel(application) {
    private var edgeVeda: EdgeVeda? = null
    private var session: ChatSession? = null
    private val modelManager = ModelManager(application)

    var isInitialized by mutableStateOf(false); private set
    var isLoading by mutableStateOf(false); private set
    var isStreaming by mutableStateOf(false); private set
    var isDownloading by mutableStateOf(false); private set
    var runningBenchmark by mutableStateOf(false); private set
    var downloadProgress by mutableDoubleStateOf(0.0); private set
    var modelPath by mutableStateOf<String?>(null); private set
    var statusMessage by mutableStateOf("Ready to initialize"); private set
    var promptText by mutableStateOf("")
    var streamingText by mutableStateOf(""); private set
    var selectedPreset by mutableStateOf<SystemPromptPreset>(SystemPromptPreset.Assistant); private set
    var benchmarkResultText by mutableStateOf(""); private set

    var timeToFirstTokenMs by mutableStateOf<Int?>(null); private set
    var tokensPerSecond by mutableStateOf<Double?>(null); private set
    var memoryMb by mutableStateOf<Double?>(null); private set

    val ttftText: String get() = timeToFirstTokenMs?.let { "${it}ms" } ?: "-"
    val speedText: String get() = tokensPerSecond?.let { "${String.format("%.1f", it)} tok/s" } ?: "-"
    val memoryText: String get() = memoryMb?.let { "${String.format("%.0f", it)} MB" } ?: "-"

    val displayMessages: List<ChatMessage> get() = session?.allMessages ?: emptyList()
    val turnCount: Int get() = session?.turnCount ?: 0
    val contextUsage: Double get() = session?.contextUsage ?: 0.0

    init {
        viewModelScope.launch { checkAndDownloadModel() }
    }

    private suspend fun checkAndDownloadModel() {
        isDownloading = true
        statusMessage = "Checking for model..."
        try {
            val model = ModelRegistry.llama32_1b
            val downloaded = modelManager.isModelDownloaded(model.id)
            if (!downloaded) {
                statusMessage = "Downloading model (${model.name})..."
                modelPath = modelManager.downloadModel(model, onProgress = { progress ->
                    downloadProgress = progress.progress
                    statusMessage = "Downloading: ${progress.progressPercent}%"
                })
            } else {
                modelPath = modelManager.getModelPath(model.id)
            }
            isDownloading = false
            statusMessage = "Model ready. Tap \"Initialize\" to start."
        } catch (e: Exception) {
            isDownloading = false
            statusMessage = "Error: ${e.message}"
        }
    }

    fun initialize() {
        viewModelScope.launch {
            val path = modelPath ?: return@launch
            isLoading = true
            statusMessage = "Initializing Veda..."
            try {
                val ev = EdgeVeda.create(getApplication())
                ev.init(path, EdgeVedaConfig(backend = Backend.AUTO, numThreads = 4, contextSize = 2048))
                edgeVeda = ev
                session = ChatSession(ev, selectedPreset)
                isInitialized = true
                isLoading = false
                statusMessage = "Ready to chat!"
            } catch (e: Exception) {
                isLoading = false
                statusMessage = "Initialization failed: ${e.message}"
                android.util.Log.e("ChatViewModel", "Initialization failed", e)
            }
        }
    }

    fun sendMessage() {
        val prompt = promptText.trim()
        if (prompt.isEmpty() || !isInitialized || isStreaming) return
        promptText = ""
        viewModelScope.launch {
            isStreaming = true
            isLoading = true
            streamingText = ""
            timeToFirstTokenMs = null
            tokensPerSecond = null

            val start = System.currentTimeMillis()
            var receivedFirst = false
            var tokenCount = 0

            try {
                val stream = session!!.sendStream(prompt, GenerateOptions(maxTokens = 256, temperature = 0.7f, topP = 0.9f))
                statusMessage = "Streaming..."
                stream.collect { token ->
                    if (!receivedFirst) {
                        timeToFirstTokenMs = (System.currentTimeMillis() - start).toInt()
                        receivedFirst = true
                    }
                    streamingText += token
                    tokenCount++
                    if (tokenCount % 3 == 0) {
                        statusMessage = "Streaming... ($tokenCount tokens)"
                    }
                }

                val elapsed = (System.currentTimeMillis() - start) / 1000.0
                tokensPerSecond = if (tokenCount > 0) tokenCount / elapsed else 0.0
                statusMessage = "Complete ($tokenCount tokens, ${String.format("%.1f", tokensPerSecond)} tok/s)"

                memoryMb = edgeVeda?.memoryUsage?.toDouble()?.div(1024 * 1024)
                streamingText = ""
            } catch (e: Exception) {
                statusMessage = "Stream error"
                streamingText = ""
            }

            isStreaming = false
            isLoading = false
        }
    }

    fun cancelGeneration() {
        viewModelScope.launch {
            try { edgeVeda?.cancelGeneration() } catch (_: Exception) {}
            isStreaming = false
            isLoading = false
            statusMessage = "Cancelled"
        }
    }

    fun resetChat() {
        viewModelScope.launch { session?.reset() }
        streamingText = ""
        timeToFirstTokenMs = null
        tokensPerSecond = null
        memoryMb = null
        statusMessage = "Ready to chat!"
    }

    fun changePreset(preset: SystemPromptPreset) {
        if (preset == selectedPreset && session != null) return
        selectedPreset = preset
        if (isInitialized) {
            edgeVeda?.let { ev ->
                session = ChatSession(ev, preset)
                streamingText = ""
                statusMessage = "Ready to chat!"
            }
        }
    }

    fun runBenchmark() {
        if (!isInitialized) return
        runningBenchmark = true
        statusMessage = "Running benchmark (10 tests)..."

        val prompts = listOf(
            "What is the capital of France?",
            "Explain quantum computing in simple terms.",
            "Write a haiku about nature.",
            "What are the benefits of exercise?",
            "Describe the solar system.",
            "What is machine learning?",
            "Tell me about the ocean.",
            "Explain photosynthesis.",
            "What is artificial intelligence?",
            "Describe the water cycle.",
        )

        viewModelScope.launch {
            val tokenRates = mutableListOf<Double>()
            var peakMemory = 0.0

            for (i in 0 until 10) {
                statusMessage = "Benchmark ${i + 1}/10..."
                val start = System.currentTimeMillis()
                try {
                    val response = edgeVeda!!.generate(prompts[i], GenerateOptions(maxTokens = 100, temperature = 0.7f))
                    val elapsed = (System.currentTimeMillis() - start) / 1000.0
                    // Approximation: chars ÷ 4 ≈ tokens (good enough for a demo benchmark)
                    val tokens = response.length / 4.0
                    tokenRates.add(tokens / elapsed)

                    val mem = edgeVeda!!.memoryUsage.toDouble() / (1024 * 1024)
                    peakMemory = maxOf(peakMemory, mem)

                    delay(500)
                } catch (_: Exception) { break }
            }

            val avg = tokenRates.average()
            val min = tokenRates.minOrNull() ?: 0.0
            val max = tokenRates.maxOrNull() ?: 0.0

            benchmarkResultText = buildString {
                appendLine("Avg Speed: ${String.format("%.1f", avg)} tok/s")
                appendLine("Range: ${String.format("%.1f", min)} - ${String.format("%.1f", max)} tok/s")
                appendLine("Peak Memory: ${String.format("%.0f", peakMemory)} MB")
                appendLine(if (avg >= 15) "✅ Meets >15 tok/s target" else "⚠️ Below 15 tok/s target")
            }

            runningBenchmark = false
            statusMessage = "Benchmark complete"
        }
    }

    override fun onCleared() {
        super.onCleared()
        edgeVeda?.close()
    }

    class Factory(private val application: Application) : androidx.lifecycle.ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
            return ChatViewModel(application) as T
        }
    }
}
