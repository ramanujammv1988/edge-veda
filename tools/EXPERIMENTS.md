# Soak Test Experiments

## Run: 20260301_214218_7d54ca2 [Android SD845 CPU-only vision soak]

**Date:** 2026-03-01 | **Git:** `7d54ca2` | **Duration:** 35.0 min | **Frames:** 3

| Hypothesis | Verdict | Evidence |
|:-----------|:-------:|:---------|
| H1: Stability | INCONCLUSIVE | 3 frames, insufficient data |
| H2: Latency | INCONCLUSIVE | insufficient latency data |
| H3: Memory | PASS | slope=0.98 MB/min (R²=0.555) |
| H4: Thermal | FAIL | nominal=0%, fair=0% |
| H5: Battery | FAIL | 7.44%/10min |
| H6: Budget | PASS | memory_degrades=0 |

**Result: 2/6 PASS**

<details><summary>Full Metrics</summary>

```json
{
  "frames": {
    "total": 3,
    "dropped": 0
  },
  "latency": {
    "total_inference": {
      "p50": 64714.0,
      "p95": 65101.0,
      "p99": 65135.4,
      "mean": 63699.3
    }
  },
  "drift": null,
  "throughput": {
    "avg_fpm": 0.1,
    "min_fpm": 0.0,
    "max_fpm": 1.0
  },
  "tokens": {
    "total_generated": 594,
    "tokens_per_sec": 0.0
  },
  "memory": {
    "rss_peak_mb": 1284.9,
    "rss_slope_mb_per_min": 0.98,
    "rss_slope_r_squared": 0.555
  },
  "thermal": {
    "nominal_pct": 0.0,
    "fair_pct": 0.0,
    "serious_pct": 100.0,
    "critical_pct": 0.0,
    "peak_state": 2
  },
  "battery": {
    "start_pct": 96.0,
    "end_pct": 70.0,
    "drain_pct": 26.0,
    "drain_per_10min": 7.44
  },
  "scheduler": {
    "degrade_count": 0,
    "restore_count": 0,
    "degrade_reasons": {},
    "actionable_violations": 0,
    "observe_only_violations": 0,
    "memory_triggered_degrades": 0
  },
  "stability": {
    "gap_count": 2,
    "max_gap_seconds": 665.8,
    "frame_id_breaks": 0,
    "is_stable": false
  }
}
```

</details>

---
