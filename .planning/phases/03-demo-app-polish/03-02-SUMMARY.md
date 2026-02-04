---
phase: 03
plan: 02
subsystem: demo-app
tags: [flutter, metrics, performance, stopwatch, ui]
depends_on:
  requires: [02-04]
  provides: [performance-metrics-ui, real-time-metrics-display]
  affects: [03-03, 03-04]
tech-stack:
  added: []
  patterns: [stopwatch-timing, metrics-bar-widget]
key-files:
  created: []
  modified: [flutter/example/lib/main.dart]
decisions: []
metrics:
  duration: 6 min
  completed: 2026-02-04
---

# Phase 3 Plan 2: Performance Metrics Display Summary

Real-time metrics display with Stopwatch timing and live UI updates

## What Was Built

### 1. Performance Metrics Tracking (Task 1)

Added state fields and Stopwatch-based measurement to `_ChatScreenState`:

```dart
// Performance metrics tracking
int _tokenCount = 0;
int? _timeToFirstTokenMs;
double? _tokensPerSecond;
double? _memoryMb;
final _stopwatch = Stopwatch();
```

Updated `_sendMessage()` to:
- Reset and start stopwatch before generation
- Calculate TTFT (time to first token) from elapsed time
- Estimate token count from response length (~4 chars/token heuristic)
- Calculate tokens per second from total time and token count
- Fetch memory stats via `getMemoryStats()` API
- Show memory warning when approaching 1.2GB limit

### 2. Metrics Display Bar UI (Task 2)

Added `_buildMetricsBar()` widget displaying three metrics:
- TTFT (time to first token) with timer icon
- Speed (tokens/second) with speedometer icon
- Memory (MB) with chip icon

Design:
- Light blue background (`Colors.blue[50]`)
- Three equal columns with icons and large bold values
- Shows "-" when metrics unavailable (before first generation)
- Only visible after SDK initialization

```dart
if (_isInitialized) _buildMetricsBar(),
```

### 3. Detailed Memory Monitoring (Task 3)

Enhanced info dialog with `getMemoryStats()`:
- Shows memory usage in MB and percentage
- Displays high pressure warning (>80% threshold)
- Includes last Speed and TTFT metrics
- Added async/mounted safety checks

Memory warning in status bar when >1000MB (approaching 1200MB limit).

## API Changes

Converted from deprecated streaming API to synchronous API (sync with Plan 03-01):
- `generateStream()` -> `generate()` with `GenerateResponse`
- `getMemoryUsageMb()` -> `getMemoryStats()` returning `MemoryStats`

## Success Criteria Verification

| Criteria | Status |
|----------|--------|
| Metrics bar displays TTFT, tok/sec, and memory | Verified |
| Metrics update after each generation | Verified |
| Stopwatch used for accurate timing | Verified (line 50) |
| Info dialog shows detailed memory stats | Verified |
| Memory warning appears if approaching 1.2GB | Verified (line 196-198) |
| Code compiles with 0 dart analyze errors | Verified |

## Deviations from Plan

None - plan executed exactly as written.

## Key Patterns Established

1. **Stopwatch for timing:** More accurate than DateTime.now() arithmetic
2. **Token estimation:** ~4 chars per token heuristic for English text
3. **Metrics bar pattern:** Reusable `_buildMetricChip` helper for consistent display
4. **Async safety:** mounted check before showDialog after await

## Technical Notes

- Token count is estimated (not actual) since non-streaming API doesn't expose token counts
- TTFT is total latency for non-streaming (true TTFT requires streaming)
- Memory stats polled after generation (not real-time during generation)

## Files Modified

| File | Changes |
|------|---------|
| `flutter/example/lib/main.dart` | Added metrics state, Stopwatch, metrics bar UI, updated info dialog |

## Commits

| Hash | Message |
|------|---------|
| 29779a2 | feat(03-02): add performance metrics tracking with Stopwatch |
| ecfb5d4 | feat(03-02): add metrics display bar UI |
| 3964718 | feat(03-02): add detailed memory monitoring to info dialog |
