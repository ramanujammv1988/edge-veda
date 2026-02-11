/**
 * PerfTrace — JSONL frame-based performance trace logger.
 *
 * Records timestamped stage/value events grouped by frame ID.
 * Output format (one JSON object per line):
 *   {"frame_id": N, "ts_ms": T, "stage": "...", "value": V, ...}
 *
 * Usage:
 *   let trace = PerfTrace(fileURL: url)
 *   trace.record(stage: "decode", value: 12.5)
 *   trace.record(stage: "sample", value: 0.8, extra: ["top_k": 40])
 *   trace.nextFrame()
 *   trace.close()
 */

import Foundation

@available(iOS 15.0, macOS 12.0, *)
public actor PerfTrace {

    // MARK: - Properties

    private var frameId: Int = 0
    private let fileHandle: FileHandle?
    private let fileURL: URL?
    private var records: [[String: Any]] = []
    private var closed: Bool = false

    /// Session-level start time used to compute relative `ts_ms`.
    private let epochMs: Double

    // MARK: - Init

    /// Create a trace that writes JSONL to the given file URL.
    /// If `fileURL` is nil the trace accumulates records in memory
    /// (retrieve via `allRecords()`).
    public init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL
        self.epochMs = Self.nowMs()

        if let url = fileURL {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            self.fileHandle = try FileHandle(forWritingTo: url)
            self.fileHandle?.seekToEndOfFile()
        } else {
            self.fileHandle = nil
        }
    }

    // MARK: - Public API

    /// Record a trace event in the current frame.
    ///
    /// - Parameters:
    ///   - stage: Short label, e.g. "decode", "sample", "vision_preprocess".
    ///   - value: Numeric measurement (latency ms, token count, etc.).
    ///   - extra: Optional dictionary merged into the JSON line.
    public func record(stage: String, value: Double, extra: [String: Any]? = nil) {
        guard !closed else { return }

        var entry: [String: Any] = [
            "frame_id": frameId,
            "ts_ms": Self.nowMs() - epochMs,
            "stage": stage,
            "value": value,
        ]

        if let extra = extra {
            for (k, v) in extra {
                entry[k] = v
            }
        }

        records.append(entry)
        writeLineToFile(entry)
    }

    /// Advance to the next frame.
    public func nextFrame() {
        guard !closed else { return }
        frameId += 1
    }

    /// Current frame identifier.
    public func currentFrameId() -> Int {
        return frameId
    }

    /// Return all accumulated records (useful when no file URL was provided).
    public func allRecords() -> [[String: Any]] {
        return records
    }

    /// Flush and close the trace. No further recording is allowed.
    public func close() {
        guard !closed else { return }
        closed = true
        fileHandle?.closeFile()
    }

    /// Export all records as a single JSONL string.
    public func exportJSONL() -> String {
        return records.compactMap { entry in
            guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8) else {
                return nil
            }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func writeLineToFile(_ entry: [String: Any]) {
        guard let fh = fileHandle else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")
        if let lineData = line.data(using: .utf8) {
            fh.write(lineData)
        }
    }

    private static func nowMs() -> Double {
        return Date().timeIntervalSince1970 * 1000.0
    }
}