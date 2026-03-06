package com.edgeveda.example

import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * Soak Test screen — sustained 20-minute vision inference benchmark.
 *
 * Mirrors [flutter/example/lib/soak_test_screen.dart].
 * Records per-frame JSONL traces compatible with [tools/analyze_trace.py].
 *
 * Layout (top → bottom):
 *   ┌─────────────────────────────────┐
 *   │  Top bar: title + elapsed time  │
 *   ├─────────────────────────────────┤
 *   │  Camera preview (~180dp)        │
 *   ├─────────────────────────────────┤
 *   │  Last description (1 line)      │
 *   ├─────────────────────────────────┤
 *   │  Metrics grid (2 × 4)           │
 *   ├─────────────────────────────────┤
 *   │  Mode selector (Managed | Raw)  │
 *   ├─────────────────────────────────┤
 *   │  Initialize / Start / Stop btn  │
 *   ├─────────────────────────────────┤
 *   │  Trace file path (when saved)   │
 *   └─────────────────────────────────┘
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SoakTestScreen(modifier: Modifier = Modifier) {
    val vm = viewModel<SoakTestViewModel>()
    val state by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    // Single-thread executor for CameraX image analysis
    val cameraExecutor = remember { Executors.newSingleThreadExecutor() }
    DisposableEffect(Unit) {
        onDispose { cameraExecutor.shutdown() }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(AppTheme.background),
    ) {
        // ── Top bar ──────────────────────────────────────────────────────────
        CenterAlignedTopAppBar(
            title = {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "Soak Test",
                        color = AppTheme.textPrimary,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (state.isRunning || state.elapsedMs > 0) {
                        Text(
                            text = formatElapsed(state.elapsedMs),
                            color = if (state.isRunning) AppTheme.accent else AppTheme.textSecondary,
                            fontSize = 12.sp,
                        )
                    }
                }
            },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                containerColor = AppTheme.background,
            ),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── Camera preview ────────────────────────────────────────────────
            if (state.isReady) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(180.dp)
                        .background(AppTheme.surface, RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    AndroidView(
                        factory = { ctx ->
                            val previewView = PreviewView(ctx)
                            val future = ProcessCameraProvider.getInstance(ctx)
                            future.addListener({
                                val provider = future.get()
                                val preview = Preview.Builder().build().also {
                                    it.setSurfaceProvider(previewView.surfaceProvider)
                                }
                                val analysis = ImageAnalysis.Builder()
                                    .setBackpressureStrategy(
                                        ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST
                                    )
                                    .build()
                                    .also { ia ->
                                        ia.setAnalyzer(cameraExecutor) { imageProxy ->
                                            val yBuf = imageProxy.planes[0].buffer
                                            val uBuf = imageProxy.planes[1].buffer
                                            val vBuf = imageProxy.planes[2].buffer
                                            val yBytes =
                                                ByteArray(yBuf.remaining()).also { yBuf.get(it) }
                                            val uBytes =
                                                ByteArray(uBuf.remaining()).also { uBuf.get(it) }
                                            val vBytes =
                                                ByteArray(vBuf.remaining()).also { vBuf.get(it) }
                                            val w = imageProxy.width
                                            val h = imageProxy.height
                                            imageProxy.close()
                                            val rgb = CameraUtils.convertYuv420ToRgb(
                                                yBytes, uBytes, vBytes, w, h
                                            )
                                            vm.onCameraFrame(rgb, w, h)
                                        }
                                    }
                                provider.unbindAll()
                                provider.bindToLifecycle(
                                    lifecycleOwner,
                                    CameraSelector.DEFAULT_BACK_CAMERA,
                                    preview,
                                    analysis,
                                )
                            }, cameraExecutor)
                            previewView
                        },
                        modifier = Modifier.fillMaxSize(),
                    )

                    // "Running" indicator overlay
                    if (state.isRunning) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(8.dp)
                                .background(AppTheme.accent.copy(alpha = 0.85f), RoundedCornerShape(8.dp))
                                .padding(horizontal = 8.dp, vertical = 4.dp),
                        ) {
                            Text("● REC", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            } else {
                // Placeholder while not ready
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(180.dp)
                        .background(AppTheme.surface, RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = state.statusMessage,
                        color = AppTheme.textSecondary,
                        fontSize = 14.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(16.dp),
                    )
                }
            }

            // Download progress bar (shown during model download)
            if (state.isDownloading) {
                LinearProgressIndicator(
                    progress = { state.downloadProgress },
                    modifier = Modifier.fillMaxWidth(),
                    color = AppTheme.accent,
                    trackColor = AppTheme.surfaceVariant,
                )
            }

            // ── Last description ──────────────────────────────────────────────
            if (state.lastDescription.isNotEmpty()) {
                Text(
                    text = state.lastDescription,
                    color = AppTheme.textSecondary,
                    fontSize = 13.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(AppTheme.surface, RoundedCornerShape(8.dp))
                        .padding(12.dp),
                )
            }

            // ── Metrics grid ──────────────────────────────────────────────────
            if (state.isRunning || state.framesProcessed > 0) {
                SoakMetricsGrid(state = state)
            }

            // ── Mode selector ──────────────────────────────────────────────────
            if (!state.isRunning) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SoakModeButton(
                        label = "Managed",
                        description = "Scheduler + Budget",
                        selected = state.mode == SoakTestViewModel.SoakMode.MANAGED,
                        enabled = !state.isRunning,
                        modifier = Modifier.weight(1f),
                        onClick = { vm.setMode(SoakTestViewModel.SoakMode.MANAGED) },
                    )
                    SoakModeButton(
                        label = "Raw",
                        description = "Bare VisionWorker",
                        selected = state.mode == SoakTestViewModel.SoakMode.RAW,
                        enabled = !state.isRunning,
                        modifier = Modifier.weight(1f),
                        onClick = { vm.setMode(SoakTestViewModel.SoakMode.RAW) },
                    )
                }
            }

            // ── Action button ─────────────────────────────────────────────────
            when {
                !state.isReady && !state.isInitializing -> {
                    Button(
                        onClick = { vm.initialize(context) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = AppTheme.accent),
                    ) {
                        Text("Initialize", color = AppTheme.background, fontWeight = FontWeight.Bold)
                    }
                }

                state.isInitializing -> {
                    Button(
                        onClick = {},
                        enabled = false,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = AppTheme.surfaceVariant),
                    ) {
                        CircularProgressIndicator(
                            color = AppTheme.accent,
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(state.statusMessage, color = AppTheme.textSecondary)
                    }
                }

                state.isRunning -> {
                    Button(
                        onClick = { vm.stopSoak() },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = AppTheme.danger),
                    ) {
                        Text("Stop Soak", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }

                else -> {
                    Button(
                        onClick = { vm.startSoak(context) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = AppTheme.accent),
                    ) {
                        Text("Start 20-min Soak", color = AppTheme.background, fontWeight = FontWeight.Bold)
                    }
                }
            }

            // ── Trace file path ───────────────────────────────────────────────
            state.traceFilePath?.let { path ->
                if (!state.isRunning) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(AppTheme.surface, RoundedCornerShape(8.dp))
                            .padding(12.dp),
                    ) {
                        Text(
                            text = "Trace saved",
                            color = AppTheme.accent,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = path,
                            color = AppTheme.textSecondary,
                            fontSize = 11.sp,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Pull with: adb pull $path",
                            color = AppTheme.textTertiary,
                            fontSize = 11.sp,
                        )
                        Text(
                            text = "Analyze: python3 tools/analyze_trace.py <file>",
                            color = AppTheme.textTertiary,
                            fontSize = 11.sp,
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }
}

// ── Metrics grid ──────────────────────────────────────────────────────────────

@Composable
private fun SoakMetricsGrid(state: SoakTestViewModel.SoakState) {
    val thermalName = when (state.thermalLevel) {
        0 -> "nominal"
        1 -> "fair"
        2 -> "serious"
        3 -> "critical"
        else -> "n/a"
    }
    val thermalColor = when (state.thermalLevel) {
        0 -> AppTheme.success
        1 -> AppTheme.warning
        2, 3 -> AppTheme.danger
        else -> AppTheme.textSecondary
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppTheme.surface, RoundedCornerShape(12.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = "Live Metrics",
            color = AppTheme.textSecondary,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            MetricItem("Frames", "${state.framesProcessed}", AppTheme.accent)
            MetricItem("Dropped", "${state.droppedFrames}",
                if (state.droppedFrames > 0) AppTheme.warning else AppTheme.textSecondary)
            MetricItem("FPS avg", String.format("%.1f/min", state.framesPerMinute), AppTheme.textPrimary)
            MetricItem("Last ms", String.format("%.0f", state.lastLatencyMs), AppTheme.textPrimary)
        }

        HorizontalDivider(color = AppTheme.border, thickness = 0.5.dp)

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            MetricItem("p95 ms", String.format("%.0f", state.p95LatencyMs),
                if (state.p95LatencyMs in 1.0..3000.0) AppTheme.success
                else if (state.p95LatencyMs > 3000.0) AppTheme.danger
                else AppTheme.textSecondary)
            MetricItem("Thermal", thermalName, thermalColor)
            MetricItem("Battery",
                state.batteryPercent?.let { String.format("%.0f%%", it) } ?: "n/a",
                AppTheme.textPrimary)
            MetricItem("RSS MB", String.format("%.0f", state.rssMb),
                if (state.rssMb > 2500) AppTheme.danger
                else if (state.rssMb > 1500) AppTheme.warning
                else AppTheme.textSecondary)
        }

        // Battery drain rate (only meaningful after ~1 minute)
        state.drainRatePerTenMin?.let { drain ->
            HorizontalDivider(color = AppTheme.border, thickness = 0.5.dp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "Drain: ",
                    color = AppTheme.textSecondary,
                    fontSize = 12.sp,
                )
                Text(
                    text = String.format("%.2f%%/10 min", drain),
                    color = if (drain > 5.0) AppTheme.danger
                            else if (drain > 3.0) AppTheme.warning
                            else AppTheme.success,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "  (target ≤ 5%/10 min)",
                    color = AppTheme.textTertiary,
                    fontSize = 11.sp,
                )
            }
        }
    }
}

@Composable
private fun MetricItem(label: String, value: String, valueColor: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            color = valueColor,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = label,
            color = AppTheme.textTertiary,
            fontSize = 10.sp,
        )
    }
}

@Composable
private fun SoakModeButton(
    label: String,
    description: String,
    selected: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val containerColor = if (selected) AppTheme.accent.copy(alpha = 0.15f) else AppTheme.surface
    val borderColor = if (selected) AppTheme.accent else AppTheme.border

    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        colors = ButtonDefaults.outlinedButtonColors(containerColor = containerColor),
        border = androidx.compose.foundation.BorderStroke(
            width = if (selected) 1.5.dp else 0.5.dp,
            color = borderColor,
        ),
        shape = RoundedCornerShape(10.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = label,
                color = if (selected) AppTheme.accent else AppTheme.textPrimary,
                fontSize = 14.sp,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
            )
            Text(
                text = description,
                color = AppTheme.textTertiary,
                fontSize = 10.sp,
            )
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private fun formatElapsed(ms: Long): String {
    val totalSec = ms / 1000
    val min = totalSec / 60
    val sec = totalSec % 60
    return String.format("%02d:%02d / 20:00", min, sec)
}
