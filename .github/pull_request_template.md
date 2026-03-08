## What does this PR do?

<!-- Brief description of the change -->

## Issue

<!-- Link the issue this PR addresses. Use "Closes" to auto-close on merge -->
Closes #

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Tests
- [ ] CI/CD
- [ ] Refactoring (no functional change)

## Testing checklist

### Gate 1: Unit tests (required for all code PRs)
- [ ] `flutter test` — all tests pass
- [ ] `flutter analyze` — no issues
- [ ] Added new tests for new functionality (if applicable)

### Gate 2: 30-minute soak test (required for inference/vision/scheduler/memory changes)
- [ ] Ran 30-minute soak test with vision enabled
- [ ] 0 crashes, 0 model reloads
- [ ] Thermal recovered (not stuck at critical)
- [ ] Memory (RSS) stable — no sustained upward drift
- [ ] N/A — change does not affect inference pipeline

### Gate 3: Benchmark update (required for performance-impacting changes)
- [ ] Exported JSONL telemetry trace
- [ ] Derived p95/p99 using `python3 tools/analyze_trace.py <trace>.jsonl`
- [ ] Updated `BENCHMARKS.md` with new numbers (if changed)
- [ ] Added entry to `tools/experiments.json`
- [ ] Attached trace file to PR
- [ ] N/A — change does not affect performance

## Screenshots / Logs (if applicable)

<!-- Add screenshots for UI changes, soak test dashboard, or relevant log output -->
