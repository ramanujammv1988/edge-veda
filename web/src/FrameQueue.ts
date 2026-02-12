/**
 * FrameQueue - Drop-newest backpressure queue for vision frame processing
 * 
 * Manages frame backpressure with a capacity of 1. When a frame is enqueued
 * while processing is active and a frame is already pending, the new frame
 * replaces the pending frame (drop-newest policy).
 */

import type { FrameData } from './types';

export class FrameQueue {
  private pendingFrame: FrameData | null = null;
  private isProcessing = false;
  private droppedFrames = 0;

  /**
   * Enqueue a frame for processing
   * 
   * If currently processing and a frame is already pending,
   * the new frame replaces the pending frame and dropCount increments.
   * 
   * @param rgb RGB888 pixel data
   * @param width Frame width
   * @param height Frame height
   */
  enqueue(rgb: Uint8Array, width: number, height: number): void {
    const frame: FrameData = { rgb, width, height };

    if (this.isProcessing && this.pendingFrame !== null) {
      // Drop the current pending frame and replace with new one
      this.droppedFrames++;
      this.pendingFrame = frame;
    } else {
      // No frame pending or not processing, just set it
      this.pendingFrame = frame;
    }
  }

  /**
   * Dequeue the next frame for processing
   * 
   * Marks the queue as processing and returns the pending frame.
   * Returns null if no frame is pending.
   * 
   * @returns The pending frame or null
   */
  dequeue(): FrameData | null {
    if (this.pendingFrame === null) {
      return null;
    }

    this.isProcessing = true;
    const frame = this.pendingFrame;
    this.pendingFrame = null;
    return frame;
  }

  /**
   * Mark the current processing as done
   * 
   * Clears the processing flag. Call this after inference completes.
   */
  markDone(): void {
    this.isProcessing = false;
  }

  /**
   * Reset the queue state
   * 
   * Clears pending frame and processing flag, but preserves drop count.
   */
  reset(): void {
    this.pendingFrame = null;
    this.isProcessing = false;
  }

  /**
   * Reset drop counters
   * 
   * Resets the cumulative dropped frame count.
   */
  resetCounters(): void {
    this.droppedFrames = 0;
  }

  /**
   * Get cumulative dropped frame count
   */
  getDroppedFrames(): number {
    return this.droppedFrames;
  }

  /**
   * Check if currently processing a frame
   */
  getIsProcessing(): boolean {
    return this.isProcessing;
  }

  /**
   * Check if a frame is pending
   */
  hasPending(): boolean {
    return this.pendingFrame !== null;
  }
}