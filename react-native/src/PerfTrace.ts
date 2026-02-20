/**
 * PerfTrace — JSONL frame-based trace logger for React Native
 *
 * Records performance trace events with frame IDs, timestamps, stages, and values.
 * Stores records in-memory and supports JSON/JSONL export.
 *
 * Output format per record:
 *   {"frame_id": N, "ts_ms": T, "stage": "...", "value": V, ...extra}
 */

/** A single trace record */
export interface TraceRecord {
  frame_id: number;
  ts_ms: number;
  stage: string;
  value: number;
  [key: string]: unknown;
}

export class PerfTrace {
  private readonly _records: TraceRecord[] = [];
  private _frameId = 0;
  private _closed = false;
  private readonly _epochMs: number;

  /**
   * Create a new PerfTrace instance.
   * @param label Optional label stored in every record under the "trace" key.
   */
  constructor(private readonly label?: string) {
    this._epochMs = Date.now();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /**
   * Record a trace event in the current frame.
   *
   * @param stage  Short identifier for the pipeline stage (e.g. "tokenize", "decode").
   * @param value  Numeric measurement (latency ms, token count, memory bytes, …).
   * @param extra  Optional additional key-value pairs merged into the record.
   */
  record(stage: string, value: number, extra?: Record<string, unknown>): void {
    if (this._closed) return;

    const rec: TraceRecord = {
      frame_id: this._frameId,
      ts_ms: Date.now() - this._epochMs,
      stage,
      value,
    };

    if (this.label !== undefined) {
      rec.trace = this.label;
    }

    if (extra) {
      for (const [k, v] of Object.entries(extra)) {
        rec[k] = v;
      }
    }

    this._records.push(rec);
  }

  /**
   * Advance to the next frame. Subsequent records will carry the new frame_id.
   */
  nextFrame(): void {
    if (this._closed) return;
    this._frameId += 1;
  }

  /**
   * Close the trace. No further records will be accepted.
   */
  close(): void {
    this._closed = true;
  }

  /**
   * Export all recorded events as a JSONL string (one JSON object per line).
   */
  exportJSONL(): string {
    return this._records.map((r) => JSON.stringify(r)).join('\n');
  }

  /**
   * Return a shallow copy of all recorded trace events.
   */
  allRecords(): ReadonlyArray<TraceRecord> {
    return [...this._records];
  }

  /**
   * Return the current frame ID (0-based).
   */
  currentFrameId(): number {
    return this._frameId;
  }

  /**
   * Whether the trace has been closed.
   */
  get isClosed(): boolean {
    return this._closed;
  }

  /**
   * Number of recorded events.
   */
  get recordCount(): number {
    return this._records.length;
  }
}