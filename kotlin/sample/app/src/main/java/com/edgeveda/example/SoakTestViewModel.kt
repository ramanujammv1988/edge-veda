package com.edgeveda.example

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.edgeveda.sdk.BatteryDrainTracker
import com.edgeveda.sdk.FrameQueue as SdkFrameQueue
import com.edgeveda.sdk.LatencyTracker
import com.edgeveda.sdk.ModelManager
import com.edgeveda.sdk.ModelRegistry
import com.edgeveda.sdk.PerfTrace
import com.edgeveda.sdk.ResourceMonitor
import com.edgeveda.sdk.ThermalMonitor
import com.edgeveda.sdk.VisionConfig
import com.edgeveda.sdk.VisionGenerationParams
import com.edgeveda.sdk.VisionWorker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ViewModel for the Soak Test screen.
 *
 * Manages a sustained 20-minute vision inference soak test that mirrors the
 * Flutter [soak_test_screen.dart] benchmark. Records per-frame timing and
 * device telemetry to a JSONL file compatible with [tools/analyze_trace.py].
 *
 * Modes:
 * - MANAGED: full Edge Veda stack (Scheduler, Budget, adaptive QoS)
 * - RAW: bare VisionWorker with no budget enforcement (baseline comparison)
 *
 * Metrics tracked:
 * - Frame count, dropped frames (drop-newest backpressure)
 * - Per-frame end-to-end latency → p50/p95/p99 via [LatencyTracker]
 * - Frames per minute (throughput)
 * - Thermal level (0–3) via [ThermalMonitor]
 * - Battery % and drain rate (%/10 min) via [BatteryDrainTracker]
 * - RSS memory (MB) via [ResourceMonitor]
 */
class SoakTestViewModel : ViewModel() {

    enum class SoakMode { MANAGED, RAW }

    data class SoakState(
        val isInitializing: Boolean = false,
        val isReady: Boolean = false,
        val isRunning: Boolean = false,
        val isDownloading: Boolean = false,
        val downloadProgress: Float = 0f,
        val statusMessage: String = "Tap Initialize to prepare models",
        val mode: SoakMode = SoakMode.MANAGED,
        // Live metrics
        val elapsedMs: Long = 0L,
        val framesProcessed: Int = 0,
        val droppedFrames: Int = 0,
        val lastLatencyMs: Double = 0.0,
        val p95LatencyMs: Double = 0.0,
        val framesPerMinute: Double = 0.0,
        val thermalLevel: Int = -1,
        val batteryPercent: Float? = null,
        val drainRatePerTenMin: Double? = null,
        val rssMb: Double = 0.0,
        // Output
        val traceFilePath: String? = null,
        val lastDescription: String = "",
    )

    private val _state = MutableStateFlow(SoakState())
    val state: StateFlow<SoakState> = _state.asStateFlow()

    // SDK monitoring components
    private var thermalMonitor: ThermalMonitor? = null
    private var batteryTracker: BatteryDrainTracker? = null
    private var resourceMonitor: ResourceMonitor? = null
    private var latencyTracker: LatencyTracker? = null

    // Vision inference
    private var visionWorker: VisionWorker? = null
    private val frameQueue = SdkFrameQueue()

    // Trace recording
    private var perfTrace: PerfTrace? = null

    // Coroutine jobs
    private var elapsedJob: Job? = null
    private var telemetryJob: Job? = null

    private var startTimeMs: Long = 0L

    companion object {
        private const val SOAK_DURATION_MS = 20 * 60 * 1000L   // 20 minutes
        private const val TELEMETRY_INTERVAL_MS = 2_000L         // 2-second telemetry poll
        private const val VISION_PROMPT =
            "Describe what you see in this image in one sentence."
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    /**
     * Download + initialize vision model and monitoring components.
     * Safe to call multiple times; re-entrant calls after ready are no-ops.
     */
    fun initialize(context: Context) {
        if (_state.value.isInitializing || _state.value.isReady) return

        viewModelScope.launch {
            _state.value = _state.value.copy(
                isInitializing = true,
                statusMessage = "Initializing monitors…"
            )

            thermalMonitor = ThermalMonitor(context)
            batteryTracker = BatteryDrainTracker(context)
            resourceMonitor = ResourceMonitor()
            latencyTracker = LatencyTracker()

            val modelManager = ModelManager(context)
            val model = ModelRegistry.smolvlm2_500m
            val mmproj = ModelRegistry.smolvlm2_500m_mmproj

            try {
                val modelPath: String
                val mmprojPath: String

                val modelOk = modelManager.isModelDownloaded(model.id)
                val mmprojOk = modelManager.isModelDownloaded(mmproj.id)

                if (!modelOk || !mmprojOk) {
                    _state.value = _state.value.copy(
                        isDownloading = true,
                        statusMessage = "Downloading vision model…"
                    )

                    modelPath = if (!modelOk) {
                        modelManager.downloadModel(model, onProgress = { p ->
                            _state.value = _state.value.copy(
                                downloadProgress = p.progress.toFloat(),
                                statusMessage = "Downloading model: ${p.progressPercent}%"
                            )
                        })
                    } else modelManager.getModelPath(model.id)

                    mmprojPath = if (!mmprojOk) {
                        modelManager.downloadModel(mmproj, onProgress = { p ->
                            _state.value = _state.value.copy(
                                downloadProgress = p.progress.toFloat(),
                                statusMessage = "Downloading mmproj: ${p.progressPercent}%"
                            )
                        })
                    } else modelManager.getModelPath(mmproj.id)

                    _state.value = _state.value.copy(isDownloading = false)
                } else {
                    modelPath = modelManager.getModelPath(model.id)
                    mmprojPath = modelManager.getModelPath(mmproj.id)
                }

                _state.value = _state.value.copy(statusMessage = "Loading vision model…")
                val worker = VisionWorker()
                worker.initialize(
                    VisionConfig(
                        modelPath = modelPath,
                        mmprojPath = mmprojPath,
                        numThreads = 4,
                        contextSize = 4096,
                    )
                )
                visionWorker = worker

                _state.value = _state.value.copy(
                    isInitializing = false,
                    isReady = true,
                    statusMessage = "Ready — select mode and tap Start"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isInitializing = false,
                    isDownloading = false,
                    statusMessage = "Init failed: ${e.message}"
                )
            }
        }
    }

    // ── Controls ─────────────────────────────────────────────────────────────

    fun setMode(mode: SoakMode) {
        if (!_state.value.isRunning) {
            _state.value = _state.value.copy(mode = mode)
        }
    }

    fun startSoak(context: Context) {
        if (_state.value.isRunning || !_state.value.isReady) return

        startTimeMs = System.currentTimeMillis()
        frameQueue.resetCounters()

        // Create JSONL trace file
        val traceDir = File(context.filesDir, "traces").also { it.mkdirs() }
        val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val modeName = _state.value.mode.name.lowercase()
        val traceFile = File(traceDir, "soak_${modeName}_$ts.jsonl")
        perfTrace = PerfTrace(file = traceFile)

        viewModelScope.launch { latencyTracker?.reset() }

        _state.value = _state.value.copy(
            isRunning = true,
            elapsedMs = 0L,
            framesProcessed = 0,
            droppedFrames = 0,
            lastLatencyMs = 0.0,
            p95LatencyMs = 0.0,
            framesPerMinute = 0.0,
            thermalLevel = -1,
            batteryPercent = null,
            drainRatePerTenMin = null,
            rssMb = 0.0,
            lastDescription = "",
            traceFilePath = traceFile.absolutePath,
            statusMessage = "Soak running…",
        )

        // Elapsed time ticker + auto-stop after SOAK_DURATION_MS
        elapsedJob = viewModelScope.launch {
            while (_state.value.isRunning) {
                val elapsed = System.currentTimeMillis() - startTimeMs
                val fps = if (elapsed > 0) {
                    _state.value.framesProcessed / (elapsed / 60_000.0)
                } else 0.0
                _state.value = _state.value.copy(elapsedMs = elapsed, framesPerMinute = fps)
                if (elapsed >= SOAK_DURATION_MS) {
                    stopSoak()
                    break
                }
                delay(500)
            }
        }

        // Telemetry poller — records thermal/battery/memory every 2 seconds
        telemetryJob = viewModelScope.launch {
            while (_state.value.isRunning) {
                val thermal = thermalMonitor?.currentLevel() ?: -1
                val battery = batteryTracker?.currentBatteryLevel()
                val drain = batteryTracker?.currentDrainRate()
                val rss = resourceMonitor?.currentRssMb() ?: 0.0
                val batteryPct = battery?.let { it * 100f }

                _state.value = _state.value.copy(
                    thermalLevel = thermal,
                    batteryPercent = batteryPct,
                    drainRatePerTenMin = drain,
                    rssMb = rss,
                )

                perfTrace?.record(
                    stage = "telemetry",
                    value = rss,
                    extra = mapOf(
                        "thermal" to thermal,
                        "battery_pct" to (batteryPct ?: -1f),
                        "rss_mb" to rss,
                        "drain_per_10min" to (drain ?: 0.0),
                    )
                )
                delay(TELEMETRY_INTERVAL_MS)
            }
        }
    }

    fun stopSoak() {
        elapsedJob?.cancel()
        telemetryJob?.cancel()
        elapsedJob = null
        telemetryJob = null

        val elapsed = System.currentTimeMillis() - startTimeMs
        perfTrace?.close()

        _state.value = _state.value.copy(
            isRunning = false,
            elapsedMs = elapsed,
            statusMessage = if (elapsed >= SOAK_DURATION_MS)
                "Soak complete (20 min)! Trace saved."
            else
                "Stopped. Partial trace saved.",
        )
    }

    // ── Camera frame input ────────────────────────────────────────────────────

    /**
     * Called by the CameraX analyzer thread for every incoming frame.
     * Enqueues the frame with drop-newest backpressure and triggers processing.
     */
    fun onCameraFrame(rgb: ByteArray, width: Int, height: Int) {
        if (!_state.value.isRunning) return
        frameQueue.enqueue(rgb, width, height)
        viewModelScope.launch(Dispatchers.Default) { processFrame() }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private suspend fun processFrame() {
        val frame = frameQueue.dequeue() ?: return
        val t0 = System.currentTimeMillis()
        try {
            val result = visionWorker!!.describeFrame(
                frame.rgb,
                frame.width,
                frame.height,
                VISION_PROMPT,
                VisionGenerationParams(maxTokens = 80),
            )
            val latencyMs = (System.currentTimeMillis() - t0).toDouble()

            latencyTracker?.record(latencyMs)
            val p95 = latencyTracker?.p95() ?: 0.0
            val frameNum = _state.value.framesProcessed + 1
            val dropped = frameQueue.droppedFrames

            perfTrace?.record(
                stage = "total_inference",
                value = latencyMs,
                extra = mapOf(
                    "frame_num" to frameNum,
                    "dropped_total" to dropped,
                )
            )
            perfTrace?.nextFrame()

            _state.value = _state.value.copy(
                framesProcessed = frameNum,
                droppedFrames = dropped,
                lastLatencyMs = latencyMs,
                p95LatencyMs = p95,
                lastDescription = result.description,
            )
        } catch (_: Exception) {
            // Individual frame failures don't abort the soak test
        } finally {
            frameQueue.markDone()
        }
    }

    override fun onCleared() {
        super.onCleared()
        elapsedJob?.cancel()
        telemetryJob?.cancel()
        perfTrace?.close()
        thermalMonitor?.destroy()
        batteryTracker?.destroy()
        viewModelScope.launch { visionWorker?.cleanup() }
    }
}
