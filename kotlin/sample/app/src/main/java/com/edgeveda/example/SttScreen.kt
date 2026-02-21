package com.edgeveda.example

import android.Manifest
import android.app.Application
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.google.accompanist.permissions.shouldShowRationale
import com.edgeveda.sdk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Speech-to-Text screen using WhisperSession.
 *
 * Mirrors Flutter's stt_screen.dart. Captures 3-second audio chunks via
 * AudioRecord and feeds them to the Whisper model for transcription.
 *
 * States: notReady → downloading → ready → recording → (segments accumulate)
 */
@OptIn(ExperimentalPermissionsApi::class, ExperimentalMaterial3Api::class)
@Composable
fun SttScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val vm: SttViewModel = viewModel(
        factory = SttViewModel.Factory(context.applicationContext as Application)
    )

    val micPermission = rememberPermissionState(Manifest.permission.RECORD_AUDIO)
    val listState = rememberLazyListState()

    // Auto-scroll as new segments arrive
    LaunchedEffect(vm.segments.size) {
        if (vm.segments.isNotEmpty()) {
            listState.animateScrollToItem(vm.segments.lastIndex)
        }
    }

    Column(modifier = modifier.fillMaxSize().background(AppTheme.background)) {
        CenterAlignedTopAppBar(
            title = { Text("Listen", color = AppTheme.textPrimary) },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppTheme.background),
        )

        when {
            // ── Downloading ──────────────────────────────────────────────────
            vm.isDownloading -> {
                DownloadOverlay(vm.statusMessage, vm.downloadProgress)
            }

            // ── Model not ready ──────────────────────────────────────────────
            !vm.isReady -> {
                NotReadyOverlay(vm.statusMessage)
            }

            // ── Permission denied ────────────────────────────────────────────
            !micPermission.status.isGranted -> {
                PermissionPrompt(
                    shouldShowRationale = micPermission.status.shouldShowRationale,
                    onRequest = { micPermission.launchPermissionRequest() },
                )
            }

            // ── Ready / Recording ────────────────────────────────────────────
            else -> {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(0.dp),
                ) {
                    // Status bar
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(AppTheme.surface)
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (vm.isRecording) {
                            PulsingMic()
                            Spacer(Modifier.width(8.dp))
                        }
                        Text(
                            text = vm.statusMessage,
                            fontSize = 13.sp,
                            color = if (vm.isRecording) AppTheme.danger else AppTheme.textSecondary,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = "Whisper Tiny EN",
                            fontSize = 11.sp,
                            color = AppTheme.textTertiary,
                        )
                    }
                    HorizontalDivider(color = AppTheme.border)

                    // Segments list
                    if (vm.segments.isEmpty()) {
                        Box(
                            modifier = Modifier.weight(1f).fillMaxWidth(),
                            contentAlignment = Alignment.Center,
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(
                                    Icons.Outlined.MicNone,
                                    contentDescription = null,
                                    tint = AppTheme.border,
                                    modifier = Modifier.size(64.dp),
                                )
                                Spacer(Modifier.height(16.dp))
                                Text("Tap the button below to start recording", fontSize = 15.sp, color = AppTheme.textTertiary)
                                Spacer(Modifier.height(6.dp))
                                Text("Transcription appears here in real-time", fontSize = 13.sp, color = AppTheme.textTertiary)
                            }
                        }
                    } else {
                        LazyColumn(
                            state = listState,
                            modifier = Modifier.weight(1f),
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            items(vm.segments) { segment ->
                                SegmentItem(segment)
                            }
                        }
                    }

                    // Record / Stop button
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(AppTheme.background)
                            .padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        FloatingActionButton(
                            onClick = {
                                if (vm.isRecording) vm.stopRecording()
                                else vm.startRecording()
                            },
                            containerColor = if (vm.isRecording) AppTheme.danger else AppTheme.accent,
                            contentColor = AppTheme.background,
                            modifier = Modifier.size(72.dp),
                        ) {
                            Icon(
                                imageVector = if (vm.isRecording) Icons.Filled.Stop else Icons.Filled.Mic,
                                contentDescription = if (vm.isRecording) "Stop" else "Record",
                                modifier = Modifier.size(32.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

// ─── Sub-composables ──────────────────────────────────────────────────────────

@Composable
private fun SegmentItem(segment: SttViewModel.Segment) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppTheme.surface, RoundedCornerShape(12.dp))
            .border(1.dp, AppTheme.border, RoundedCornerShape(12.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = "[${formatMs(segment.startMs)}–${formatMs(segment.endMs)}]",
            fontSize = 11.sp,
            color = AppTheme.textTertiary,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.width(110.dp),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            text = segment.text,
            fontSize = 14.sp,
            color = AppTheme.textPrimary,
            lineHeight = 20.sp,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun PulsingMic() {
    val infiniteTransition = rememberInfiniteTransition(label = "micPulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(700, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "micAlpha",
    )
    Box(
        modifier = Modifier
            .size(10.dp)
            .alpha(alpha)
            .background(AppTheme.danger, CircleShape),
    )
}

@Composable
private fun DownloadOverlay(status: String, progress: Double) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.CloudDownload, contentDescription = null, tint = AppTheme.textSecondary, modifier = Modifier.size(64.dp))
            Spacer(Modifier.height(24.dp))
            LinearProgressIndicator(
                progress = { progress.toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.width(240.dp),
                color = AppTheme.accent,
                trackColor = AppTheme.surfaceVariant,
            )
            Spacer(Modifier.height(16.dp))
            Text(status, color = AppTheme.textPrimary, fontSize = 15.sp)
        }
    }
}

@Composable
private fun NotReadyOverlay(status: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = AppTheme.textSecondary, modifier = Modifier.size(48.dp))
            Spacer(Modifier.height(16.dp))
            Text(status, color = AppTheme.textPrimary, fontSize = 15.sp)
        }
    }
}

@Composable
private fun PermissionPrompt(shouldShowRationale: Boolean, onRequest: () -> Unit) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(Icons.Outlined.MicNone, contentDescription = null, tint = AppTheme.accent, modifier = Modifier.size(64.dp))
            Spacer(Modifier.height(16.dp))
            Text(
                text = if (shouldShowRationale)
                    "Microphone access is required to transcribe speech. Please grant permission."
                else
                    "Microphone permission is needed for speech-to-text.",
                fontSize = 15.sp,
                color = AppTheme.textPrimary,
                lineHeight = 22.sp,
            )
            Spacer(Modifier.height(24.dp))
            Button(
                onClick = onRequest,
                colors = ButtonDefaults.buttonColors(containerColor = AppTheme.accent, contentColor = AppTheme.background),
            ) {
                Text("Grant Permission", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

private fun formatMs(ms: Long): String {
    val seconds = ms / 1000.0
    return String.format("%.1fs", seconds)
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

class SttViewModel(application: Application) : AndroidViewModel(application) {

    data class Segment(val text: String, val startMs: Long, val endMs: Long)

    private val modelManager = ModelManager(application)
    private val session = WhisperSession()

    var isReady by mutableStateOf(false); private set
    var isDownloading by mutableStateOf(false); private set
    var isRecording by mutableStateOf(false); private set
    var downloadProgress by mutableDoubleStateOf(0.0); private set
    var statusMessage by mutableStateOf("Preparing Whisper model…"); private set
    val segments = mutableStateListOf<Segment>()

    /** AudioRecord sample rate. Whisper requires 16 kHz mono. */
    private val sampleRate = 16_000

    /** Capture ~3 seconds per chunk (PCM float = 4 bytes per sample). */
    private val chunkSamples = sampleRate * 3

    init {
        viewModelScope.launch { prepareModel() }
    }

    private suspend fun prepareModel() {
        try {
            val model = ModelRegistry.whisperTinyEn
            val downloaded = modelManager.isModelDownloaded(model.id)
            val modelPath = if (!downloaded) {
                isDownloading = true
                statusMessage = "Downloading ${model.name}…"
                modelManager.downloadModel(model, onProgress = { p ->
                    downloadProgress = p.progress
                    statusMessage = "Downloading: ${p.progressPercent}%"
                }).also { isDownloading = false }
            } else {
                modelManager.getModelPath(model.id)
            }

            statusMessage = "Loading Whisper model…"
            session.initialize(WhisperConfig(modelPath = modelPath, numThreads = 4, useGpu = false))
            isReady = true
            statusMessage = "Ready to record"
        } catch (e: Exception) {
            isDownloading = false
            statusMessage = "Error: ${e.message}"
        }
    }

    fun startRecording() {
        if (!isReady || isRecording) return
        isRecording = true
        statusMessage = "Recording…"

        viewModelScope.launch(Dispatchers.IO) {
            val minBufSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_FLOAT,
            )
            val bufSize = maxOf(minBufSize, chunkSamples * 4)

            val recorder = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_FLOAT,
                bufSize,
            )

            try {
                recorder.startRecording()
                val buffer = FloatArray(chunkSamples)

                while (isRecording && isActive) {
                    var offset = 0
                    // Fill one chunk (~3 s)
                    while (offset < chunkSamples && isRecording && isActive) {
                        val read = recorder.read(buffer, offset, chunkSamples - offset, AudioRecord.READ_BLOCKING)
                        if (read > 0) offset += read else break
                    }
                    if (offset == 0) continue

                    // Trim to actual read length
                    val pcm = if (offset == chunkSamples) buffer else buffer.copyOf(offset)

                    // Transcribe on Default dispatcher
                    withContext(Dispatchers.Default) {
                        try {
                            val result = session.transcribe(pcm, WhisperTranscribeParams(language = "en"))
                            result.segments.forEach { seg ->
                                segments.add(Segment(seg.text.trim(), seg.startMs, seg.endMs))
                            }
                        } catch (_: Exception) {
                            // Continue recording even if a single chunk fails
                        }
                    }
                }
            } finally {
                recorder.stop()
                recorder.release()
            }
        }
    }

    fun stopRecording() {
        isRecording = false
        statusMessage = "Ready to record"
    }

    override fun onCleared() {
        super.onCleared()
        isRecording = false
        viewModelScope.launch { try { session.cleanup() } catch (_: Exception) {} }
    }

    class Factory(private val application: Application) : androidx.lifecycle.ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            SttViewModel(application) as T
    }
}
