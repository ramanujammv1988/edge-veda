import 'dart:convert';
import 'dart:io';

/// JSONL performance trace logger for vision inference benchmarking.
///
/// Each line in the output file is a JSON object with fields:
/// - `frame_id`: int (sequential frame counter)
/// - `ts_ms`: int (milliseconds since epoch)
/// - `stage`: String (e.g., 'image_encode', 'prompt_eval', 'decode', 'total_inference')
/// - `value`: double (measurement value, typically milliseconds)
/// - Additional fields from [extra] map
///
/// Usage:
/// ```dart
/// final trace = PerfTrace(File('/path/to/trace.jsonl'));
/// trace.record(stage: 'image_encode', value: 142.5);
/// trace.record(stage: 'decode', value: 830.2);
/// trace.nextFrame();
/// await trace.close();
/// ```
class PerfTrace {
  final IOSink _sink;
  int _frameId = 0;

  /// Create a PerfTrace that writes to the given file (append mode).
  PerfTrace(File traceFile)
      : _sink = traceFile.openWrite(mode: FileMode.append);

  /// Current frame ID (zero-based, incremented by [nextFrame]).
  int get frameId => _frameId;

  /// Record a single trace entry for the current frame.
  ///
  /// [stage] identifies the measurement (e.g., 'image_encode', 'prompt_eval',
  /// 'decode', 'total_inference', 'rss_bytes', 'thermal_state').
  ///
  /// [value] is the measured value (typically milliseconds for timing stages).
  ///
  /// [extra] is an optional map of additional key-value pairs to include in
  /// the JSON entry (e.g., prompt_tokens, generated_tokens).
  void record({
    required String stage,
    required double value,
    Map<String, dynamic>? extra,
  }) {
    final entry = <String, dynamic>{
      'frame_id': _frameId,
      'ts_ms': DateTime.now().millisecondsSinceEpoch,
      'stage': stage,
      'value': value,
    };
    if (extra != null) {
      entry.addAll(extra);
    }
    _sink.writeln(jsonEncode(entry));
  }

  /// Advance to next frame. Call after recording all stages for the
  /// current frame.
  void nextFrame() => _frameId++;

  /// Flush and close the trace file.
  ///
  /// After calling this method, no further [record] calls should be made.
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}
