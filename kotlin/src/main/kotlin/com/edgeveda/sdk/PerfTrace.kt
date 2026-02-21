package com.edgeveda.sdk

import org.json.JSONObject
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * PerfTrace — JSONL frame-based performance trace logger.
 *
 * Records timestamped stage/value events grouped by frame ID.
 * Output format (one JSON object per line):
 *   {"frame_id": N, "ts_ms": T, "stage": "...", "value": V, ...}
 *
 * Usage:
 *   val trace = PerfTrace(file = File("trace.jsonl"))
 *   trace.record("decode", 12.5)
 *   trace.record("sample", 0.8, mapOf("top_k" to 40))
 *   trace.nextFrame()
 *   trace.close()
 */
class PerfTrace(
    file: File? = null,
) {
    private val frameId = AtomicInteger(0)
    private val closed = AtomicBoolean(false)
    private val epochMs: Double = nowMs()

    private val writer: BufferedWriter? = file?.let {
        it.parentFile?.mkdirs()
        BufferedWriter(FileWriter(it, /* append = */ true))
    }

    private val records = mutableListOf<Map<String, Any>>()
    private val lock = Any()

    // ── Public API ────────────────────────────────────────────────

    /**
     * Record a trace event in the current frame.
     *
     * @param stage Short label, e.g. "decode", "sample", "vision_preprocess".
     * @param value Numeric measurement (latency ms, token count, etc.).
     * @param extra Optional map merged into the JSON line.
     */
    fun record(stage: String, value: Double, extra: Map<String, Any>? = null) {
        if (closed.get()) return

        val entry = mutableMapOf<String, Any>(
            "frame_id" to frameId.get(),
            "ts_ms" to (nowMs() - epochMs),
            "stage" to stage,
            "value" to value,
        )
        extra?.let { entry.putAll(it) }

        synchronized(lock) {
            records.add(entry)
        }
        writeLineToFile(entry)
    }

    /** Advance to the next frame. */
    fun nextFrame() {
        if (closed.get()) return
        frameId.incrementAndGet()
    }

    /** Current frame identifier. */
    fun currentFrameId(): Int = frameId.get()

    /** Return a snapshot of all accumulated records. */
    fun allRecords(): List<Map<String, Any>> {
        synchronized(lock) {
            return records.toList()
        }
    }

    /** Flush and close the trace. No further recording is allowed. */
    fun close() {
        if (!closed.compareAndSet(false, true)) return
        try {
            writer?.flush()
            writer?.close()
        } catch (_: Exception) {
            // best-effort
        }
    }

    /** Export all records as a single JSONL string. */
    fun exportJSONL(): String {
        val snapshot = synchronized(lock) { records.toList() }
        return snapshot.joinToString("\n") { entry ->
            JSONObject(entry).toString()
        }
    }

    // ── Private Helpers ───────────────────────────────────────────

    private fun writeLineToFile(entry: Map<String, Any>) {
        val w = writer ?: return
        try {
            val line = JSONObject(entry).toString()
            synchronized(w) {
                w.write(line)
                w.newLine()
                w.flush()
            }
        } catch (_: Exception) {
            // best-effort — don't crash the caller
        }
    }

    private fun nowMs(): Double = System.currentTimeMillis().toDouble()
}