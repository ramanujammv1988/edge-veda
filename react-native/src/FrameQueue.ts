/**
 * Bounded frame queue with drop-newest backpressure policy.
 *
 * When inference is busy and a new frame arrives, the pending frame is
 * replaced (not accumulated). This ensures vision descriptions stay
 * current with the camera feed rather than falling behind.
 *
 * Design decisions:
 * - Drop-newest policy: when processing is busy, new frames REPLACE the
 *   pending slot (not queue up)
 * - Only 1 pending slot (capacity 1): at most 1 frame waits while
 *   inference runs
 * - droppedFrames is cumulative across the session for analysis
 * - reset() clears frame state but preserves drop counter;
 *   resetCounters() resets the counter
 *
 * Usage:
 * 1. Camera callback calls enqueue() with each frame
 * 2. Processing loop calls dequeue() to get next frame
 * 3. After inference completes, call markDone()
 * 4. Check droppedFrames to track backpressure
 */

import type { FrameData } from './types';

/**
 * Bounded frame queue with drop-newest backpressure policy.
 *
 * Holds at most one pending frame. When inference is busy and a frame is
 * already pending, new frames replace the pending slot and increment the
 * droppedFrames counter.
 */
export class FrameQueue {
  private _pendingFrame: FrameData | null = null;
  private _droppedFrames = 0;
  private _isProcessing = false;

  /**
   * Number of frames dropped due to backpressure (cumulative).
   */
  get droppedFrames(): number {
    return this._droppedFrames;
  }

  /**
   * Whether inference is currently processing a frame.
   */
  get isProcessing(): boolean {
    return this._isProcessing;
  }

  /**
   * Whether there is a frame waiting to be processed.
   */
  get hasPending(): boolean {
    return this._pendingFrame !== null;
  }

  /**
   * Enqueue a frame for processing.
   *
   * If inference is busy and a frame is already pending, the old pending
   * frame is replaced (dropped) and droppedFrames is incremented.
   *
   * Returns true if no frame was dropped, false if a pending frame
   * was replaced.
   */
  enqueue(rgb: Uint8Array, width: number, height: number): boolean {
    const dropped = this._isProcessing && this._pendingFrame !== null;
    if (dropped) {
      this._droppedFrames++;
    }
    this._pendingFrame = { rgb, width, height };
    return !dropped;
  }

  /**
   * Dequeue the next frame for processing.
   *
   * Returns null if no frame is pending or inference is already running.
   * Sets isProcessing to true on success.
   */
  dequeue(): FrameData | null {
    if (this._pendingFrame === null || this._isProcessing) {
      return null;
    }
    const frame = this._pendingFrame;
    this._pendingFrame = null;
    this._isProcessing = true;
    return frame;
  }

  /**
   * Mark current inference as done. Allows next dequeue().
   */
  markDone(): void {
    this._isProcessing = false;
  }

  /**
   * Reset queue state (e.g., when stopping camera stream).
   *
   * Clears the pending frame and processing flag but preserves
   * droppedFrames since it is cumulative for analysis.
   */
  reset(): void {
    this._pendingFrame = null;
    this._isProcessing = false;
    // Note: droppedFrames is NOT reset - it's cumulative for analysis
  }

  /**
   * Reset the dropped frames counter.
   *
   * Use at the start of a new test session or benchmark run.
   */
  resetCounters(): void {
    this._droppedFrames = 0;
  }
}