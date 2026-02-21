package com.edgeveda.sdk

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for PerfTrace — the JSONL frame-based performance trace logger.
 *
 * Framework requirement: PerfTrace JSONL output feeds tools/analyze_trace.py
 * which computes p50/p95/p99 latency, throughput time series, and thermal
 * overlays from soak test sessions.
 *
 * All tests use the in-memory mode (no file argument) to avoid I/O.
 */
class PerfTraceTest {

    // ── Initial state ─────────────────────────────────────────────────────────

    @Test
    fun `new trace currentFrameId is 0`() {
        val trace = PerfTrace()
        assertEquals(0, trace.currentFrameId())
    }

    @Test
    fun `new trace allRecords is empty`() {
        val trace = PerfTrace()
        assertTrue(trace.allRecords().isEmpty())
    }

    @Test
    fun `new trace exportJSONL returns empty string`() {
        val trace = PerfTrace()
        assertEquals("", trace.exportJSONL())
    }

    // ── record ────────────────────────────────────────────────────────────────

    @Test
    fun `record appends one entry to allRecords`() {
        val trace = PerfTrace()
        trace.record("decode", 12.5)
        assertEquals(1, trace.allRecords().size)
    }

    @Test
    fun `record increments allRecords size with each call`() {
        val trace = PerfTrace()
        trace.record("a", 1.0)
        trace.record("b", 2.0)
        trace.record("c", 3.0)
        assertEquals(3, trace.allRecords().size)
    }

    @Test
    fun `record entry contains frame_id key`() {
        val trace = PerfTrace()
        trace.record("decode", 10.0)
        val entry = trace.allRecords().first()
        assertTrue(entry.containsKey("frame_id"))
    }

    @Test
    fun `record entry contains ts_ms key`() {
        val trace = PerfTrace()
        trace.record("decode", 10.0)
        val entry = trace.allRecords().first()
        assertTrue(entry.containsKey("ts_ms"))
    }

    @Test
    fun `record entry contains stage key with correct value`() {
        val trace = PerfTrace()
        trace.record("vision_preprocess", 5.0)
        val entry = trace.allRecords().first()
        assertEquals("vision_preprocess", entry["stage"])
    }

    @Test
    fun `record entry contains value key with correct value`() {
        val trace = PerfTrace()
        trace.record("decode", 42.0)
        val entry = trace.allRecords().first()
        assertEquals(42.0, entry["value"] as Double, 0.001)
    }

    @Test
    fun `record entry frame_id matches currentFrameId at time of record`() {
        val trace = PerfTrace()
        trace.record("a", 1.0)
        val entry = trace.allRecords().first()
        assertEquals(0, entry["frame_id"] as Int)
    }

    @Test
    fun `record ts_ms is non-negative`() {
        val trace = PerfTrace()
        trace.record("a", 1.0)
        val tsMs = trace.allRecords().first()["ts_ms"] as Double
        assertTrue(tsMs >= 0.0)
    }

    // ── record with extra ─────────────────────────────────────────────────────

    @Test
    fun `record with extra map includes extra keys in entry`() {
        val trace = PerfTrace()
        trace.record("sample", 0.8, mapOf("top_k" to 40, "model" to "llama"))
        val entry = trace.allRecords().first()
        assertTrue(entry.containsKey("top_k"))
        assertTrue(entry.containsKey("model"))
    }

    @Test
    fun `record with extra map preserves standard keys`() {
        val trace = PerfTrace()
        trace.record("sample", 0.8, mapOf("extra_key" to "value"))
        val entry = trace.allRecords().first()
        assertTrue(entry.containsKey("frame_id"))
        assertTrue(entry.containsKey("ts_ms"))
        assertTrue(entry.containsKey("stage"))
        assertTrue(entry.containsKey("value"))
    }

    @Test
    fun `record without extra map does not throw`() {
        val trace = PerfTrace()
        trace.record("decode", 10.0)     // extra defaults to null
        assertEquals(1, trace.allRecords().size)
    }

    // ── nextFrame ─────────────────────────────────────────────────────────────

    @Test
    fun `nextFrame increments currentFrameId by 1`() {
        val trace = PerfTrace()
        trace.nextFrame()
        assertEquals(1, trace.currentFrameId())
    }

    @Test
    fun `nextFrame increments monotonically`() {
        val trace = PerfTrace()
        repeat(5) { trace.nextFrame() }
        assertEquals(5, trace.currentFrameId())
    }

    @Test
    fun `records after nextFrame carry new frame_id`() {
        val trace = PerfTrace()
        trace.record("frame0", 1.0)
        trace.nextFrame()
        trace.record("frame1", 2.0)
        val records = trace.allRecords()
        assertEquals(0, records[0]["frame_id"] as Int)
        assertEquals(1, records[1]["frame_id"] as Int)
    }

    @Test
    fun `multiple records in same frame share the same frame_id`() {
        val trace = PerfTrace()
        trace.record("encode", 5.0)
        trace.record("decode", 10.0)
        val records = trace.allRecords()
        assertEquals(records[0]["frame_id"], records[1]["frame_id"])
    }

    // ── exportJSONL ───────────────────────────────────────────────────────────

    @Test
    fun `exportJSONL returns one line per record`() {
        val trace = PerfTrace()
        trace.record("a", 1.0)
        trace.record("b", 2.0)
        trace.record("c", 3.0)
        val lines = trace.exportJSONL().split("\n")
        assertEquals(3, lines.size)
    }

    @Test
    fun `each exportJSONL line is valid JSON`() {
        val trace = PerfTrace()
        trace.record("decode", 12.5)
        trace.record("sample", 0.9)
        val lines = trace.exportJSONL().split("\n")
        for (line in lines) {
            assertNotNull("Line should parse as JSON: $line", JSONObject(line))
        }
    }

    @Test
    fun `each exportJSONL line contains required keys`() {
        val trace = PerfTrace()
        trace.record("vision", 15.0)
        val line = trace.exportJSONL()
        val json = JSONObject(line)
        assertTrue(json.has("frame_id"))
        assertTrue(json.has("ts_ms"))
        assertTrue(json.has("stage"))
        assertTrue(json.has("value"))
    }

    @Test
    fun `exportJSONL stage value matches recorded stage`() {
        val trace = PerfTrace()
        trace.record("my_stage", 99.0)
        val json = JSONObject(trace.exportJSONL())
        assertEquals("my_stage", json.getString("stage"))
    }

    @Test
    fun `exportJSONL value matches recorded value`() {
        val trace = PerfTrace()
        trace.record("latency", 1412.0)
        val json = JSONObject(trace.exportJSONL())
        assertEquals(1412.0, json.getDouble("value"), 0.001)
    }

    @Test
    fun `exportJSONL includes extra keys`() {
        val trace = PerfTrace()
        trace.record("soak", 1.0, mapOf("thermal" to 2))
        val json = JSONObject(trace.exportJSONL())
        assertTrue(json.has("thermal"))
    }

    // ── allRecords snapshot ───────────────────────────────────────────────────

    @Test
    fun `allRecords returns an immutable snapshot`() {
        val trace = PerfTrace()
        trace.record("a", 1.0)
        val snapshot1 = trace.allRecords()
        trace.record("b", 2.0)
        val snapshot2 = trace.allRecords()
        assertEquals(1, snapshot1.size)
        assertEquals(2, snapshot2.size)
    }

    // ── close ─────────────────────────────────────────────────────────────────

    @Test
    fun `close is idempotent - calling twice does not throw`() {
        val trace = PerfTrace()
        trace.close()
        trace.close()  // second close should be a no-op
    }

    @Test
    fun `record after close is silently ignored`() {
        val trace = PerfTrace()
        trace.record("before", 1.0)
        trace.close()
        trace.record("after", 2.0)  // should be ignored
        assertEquals(1, trace.allRecords().size)
    }

    @Test
    fun `nextFrame after close is silently ignored`() {
        val trace = PerfTrace()
        trace.close()
        trace.nextFrame()
        assertEquals(0, trace.currentFrameId())
    }
}
