package com.edgeveda.example

import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.edgeveda.sdk.*
import kotlinx.coroutines.launch

/**
 * Vision screen with continuous camera scanning and description overlay.
 *
 * Matches Flutter's VisionScreen: full-screen camera preview,
 * AR-style description overlay at bottom with pulsing dot,
 * and model download overlay on first launch.
 */
@Composable
fun VisionScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    var isVisionReady by remember { mutableStateOf(false) }
    var isDownloading by remember { mutableStateOf(false) }
    var isProcessing by remember { mutableStateOf(false) }
    var downloadProgress by remember { mutableDoubleStateOf(0.0) }
    var statusMessage by remember { mutableStateOf("Preparing vision...") }
    var description by remember { mutableStateOf<String?>(null) }

    val visionWorker = remember { VisionWorker() }
    val frameQueue = remember { FrameQueue() }
    val modelManager = remember { ModelManager(context) }

    // Initialize vision pipeline
    LaunchedEffect(Unit) {
        try {
            // Download models
            val model = ModelRegistry.smolvlm2_500m
            val mmproj = ModelRegistry.smolvlm2_500m_mmproj

            val modelDownloaded = modelManager.isModelDownloaded(model.id)
            val mmprojDownloaded = modelManager.isModelDownloaded(mmproj.id)

            var modelPath: String
            var mmprojPath: String

            if (!modelDownloaded || !mmprojDownloaded) {
                isDownloading = true
                statusMessage = "Downloading vision model..."

                modelPath = if (!modelDownloaded) {
                    modelManager.downloadModel(model, onProgress = { progress ->
                        downloadProgress = progress.progress
                        statusMessage = "Downloading: ${progress.progressPercent}%"
                    })
                } else {
                    modelManager.getModelPath(model.id)
                }

                mmprojPath = if (!mmprojDownloaded) {
                    modelManager.downloadModel(mmproj, onProgress = { progress ->
                        downloadProgress = progress.progress
                    })
                } else {
                    modelManager.getModelPath(mmproj.id)
                }

                isDownloading = false
            } else {
                modelPath = modelManager.getModelPath(model.id)
                mmprojPath = modelManager.getModelPath(mmproj.id)
            }

            // Initialize vision worker
            statusMessage = "Loading vision model..."
            visionWorker.initialize(VisionConfig(
                modelPath = modelPath,
                mmprojPath = mmprojPath,
                numThreads = 4,
                contextSize = 4096,
            ))

            isVisionReady = true
            statusMessage = "Vision ready"
        } catch (e: Exception) {
            statusMessage = "Error: ${e.message}"
            isDownloading = false
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            scope.launch { visionWorker.cleanup() }
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        // Camera preview
        if (isVisionReady) {
            AndroidView(
                factory = { ctx ->
                    val previewView = PreviewView(ctx)
                    val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                    cameraProviderFuture.addListener({
                        val cameraProvider = cameraProviderFuture.get()
                        val preview = Preview.Builder().build().also {
                            it.setSurfaceProvider(previewView.surfaceProvider)
                        }

                        val imageAnalysis = ImageAnalysis.Builder()
                            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                            .build()
                            .also { analysis ->
                                analysis.setAnalyzer(java.util.concurrent.Executors.newSingleThreadExecutor()) { imageProxy ->
                                    if (!isVisionReady) {
                                        imageProxy.close()
                                        return@setAnalyzer
                                    }

                                    val yBuffer = imageProxy.planes[0].buffer
                                    val uBuffer = imageProxy.planes[1].buffer
                                    val vBuffer = imageProxy.planes[2].buffer
                                    val yBytes = ByteArray(yBuffer.remaining()).also { yBuffer.get(it) }
                                    val uBytes = ByteArray(uBuffer.remaining()).also { uBuffer.get(it) }
                                    val vBytes = ByteArray(vBuffer.remaining()).also { vBuffer.get(it) }
                                    val width = imageProxy.width
                                    val height = imageProxy.height
                                    imageProxy.close()
                                    val rgb = CameraUtils.convertYuv420ToRgb(yBytes, uBytes, vBytes, width, height)

                                    frameQueue.enqueue(rgb, width, height)

                                    scope.launch {
                                        val frame = frameQueue.dequeue() ?: return@launch
                                        isProcessing = true
                                        try {
                                            val result = visionWorker.describeFrame(
                                                frame.rgb, frame.width, frame.height,
                                                "Describe what you see in this image in one sentence.",
                                                VisionGenerationParams(maxTokens = 100),
                                            )
                                            description = result.description
                                        } catch (e: Exception) {
                                            // Log error
                                        }
                                        frameQueue.markDone()
                                        isProcessing = false
                                    }
                                }
                            }

                        cameraProvider.unbindAll()
                        cameraProvider.bindToLifecycle(
                            lifecycleOwner,
                            CameraSelector.DEFAULT_BACK_CAMERA,
                            preview,
                            imageAnalysis,
                        )
                    }, java.util.concurrent.Executors.newSingleThreadExecutor())
                    previewView
                },
                modifier = Modifier.fillMaxSize(),
            )
        }

        // Description overlay at bottom (AR-style)
        if (description != null && description!!.isNotEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Bottom,
            ) {
                Row(
                    modifier = Modifier
                        .padding(16.dp)
                        .fillMaxWidth()
                        .background(
                            AppTheme.surface.copy(alpha = 0.9f),
                            RoundedCornerShape(16.dp),
                        )
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (isProcessing) {
                        PulsingDot()
                        Spacer(Modifier.width(12.dp))
                    }
                    Text(
                        text = description!!,
                        color = AppTheme.textPrimary,
                        fontSize = 16.sp,
                        lineHeight = 22.sp,
                    )
                }
            }
        }

        // Loading/download overlay
        if (isDownloading || !isVisionReady) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(AppTheme.background.copy(alpha = 0.87f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (isDownloading) {
                        Icon(
                            Icons.Outlined.CloudDownload,
                            contentDescription = null,
                            tint = AppTheme.textSecondary,
                            modifier = Modifier.size(64.dp),
                        )
                        Spacer(Modifier.height(24.dp))
                        LinearProgressIndicator(
                            progress = if (downloadProgress > 0) downloadProgress.toFloat() else 0f,
                            modifier = Modifier.width(240.dp),
                            color = AppTheme.accent,
                            trackColor = AppTheme.surfaceVariant,
                        )
                    } else {
                        CircularProgressIndicator(
                            color = AppTheme.textSecondary,
                            modifier = Modifier.size(48.dp),
                        )
                    }
                    Spacer(Modifier.height(16.dp))
                    Text(statusMessage, color = AppTheme.textPrimary, fontSize = 16.sp)
                }
            }
        }
    }
}

@Composable
private fun PulsingDot() {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseAlpha",
    )

    Box(
        modifier = Modifier
            .size(10.dp)
            .alpha(alpha)
            .background(AppTheme.accent, CircleShape),
    )
}