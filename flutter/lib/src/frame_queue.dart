/// Bounded frame queue with drop-newest backpressure policy.
///
/// When inference is busy and a new frame arrives, the pending frame is
/// replaced (not accumulated). This ensures vision descriptions stay
/// current with the camera feed rather than falling behind.
///
/// Design decisions:
/// - Drop-newest policy: when processing is busy, new frames REPLACE the
///   pending slot (not queue up)
/// - Only 1 pending slot (capacity 1): at most 1 frame waits while
///   inference runs
/// - [droppedFrames] is cumulative across the session for PerfTrace analysis
/// - [reset] clears frame state but preserves drop counter;
///   [resetCounters] resets the counter
/// - Thread safety is NOT needed because this runs on the main Dart isolate
///   (single-threaded event loop)
///
/// Usage:
/// 1. Camera callback calls [enqueue] with each frame
/// 2. Processing loop calls [dequeue] to get next frame
/// 3. After inference completes, call [markDone]
/// 4. Check [droppedFrames] to track backpressure
library;

import 'dart:typed_data';

/// Bounded frame queue with drop-newest backpressure policy.
///
/// Holds at most one pending frame. When inference is busy and a frame is
/// already pending, new frames replace the pending slot and increment the
/// [droppedFrames] counter.
class FrameQueue {
  Uint8List? _pendingFrame;
  int _pendingWidth = 0;
  int _pendingHeight = 0;
  int _droppedFrames = 0;
  bool _isProcessing = false;

  /// Number of frames dropped due to backpressure (cumulative).
  int get droppedFrames => _droppedFrames;

  /// Whether inference is currently processing a frame.
  bool get isProcessing => _isProcessing;

  /// Whether there is a frame waiting to be processed.
  bool get hasPending => _pendingFrame != null;

  /// Enqueue a frame for processing.
  ///
  /// If inference is busy and a frame is already pending, the old pending
  /// frame is replaced (dropped) and [droppedFrames] is incremented.
  ///
  /// Returns `true` if no frame was dropped, `false` if a pending frame
  /// was replaced.
  bool enqueue(Uint8List rgb, int width, int height) {
    final dropped = _isProcessing && _pendingFrame != null;
    if (dropped) {
      _droppedFrames++;
    }
    _pendingFrame = rgb;
    _pendingWidth = width;
    _pendingHeight = height;
    return !dropped;
  }

  /// Dequeue the next frame for processing.
  ///
  /// Returns `null` if no frame is pending or inference is already running.
  /// Sets [isProcessing] to `true` on success.
  ({Uint8List rgb, int width, int height})? dequeue() {
    if (_pendingFrame == null || _isProcessing) return null;
    final frame = (
      rgb: _pendingFrame!,
      width: _pendingWidth,
      height: _pendingHeight,
    );
    _pendingFrame = null;
    _isProcessing = true;
    return frame;
  }

  /// Mark current inference as done. Allows next [dequeue].
  void markDone() {
    _isProcessing = false;
  }

  /// Reset queue state (e.g., when stopping camera stream).
  ///
  /// Clears the pending frame and processing flag but preserves
  /// [droppedFrames] since it is cumulative for trace analysis.
  void reset() {
    _pendingFrame = null;
    _pendingWidth = 0;
    _pendingHeight = 0;
    _isProcessing = false;
    // Note: droppedFrames is NOT reset - it's cumulative for trace analysis
  }

  /// Reset the dropped frames counter.
  ///
  /// Use at the start of a new soak test session or benchmark run.
  void resetCounters() {
    _droppedFrames = 0;
  }
}
