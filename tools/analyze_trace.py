#!/usr/bin/env python3
"""Analyze PerfTrace JSONL files from Edge Veda soak tests.

Reads JSONL trace files produced by PerfTrace (flutter/lib/src/perf_trace.dart)
and outputs latency statistics, throughput metrics, and generates charts.

Each JSONL line has:
  - frame_id: int (sequential frame counter)
  - ts_ms: int (milliseconds since epoch)
  - stage: str (image_encode | prompt_eval | decode | total_inference |
                rss_bytes | thermal_state | battery_level | available_memory)
  - value: float (measurement value)
  - Optional: prompt_tokens, generated_tokens (on total_inference entries)

Usage:
  python3 tools/analyze_trace.py path/to/soak_test.jsonl [--output-dir ./charts]
  python3 tools/analyze_trace.py path/to/trace.jsonl --experiment --tag "baseline"
  python3 tools/analyze_trace.py --list
  python3 tools/analyze_trace.py --compare [ID1] [ID2]
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

try:
    import numpy as np

    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

try:
    import matplotlib

    matplotlib.use("Agg")  # Non-interactive backend for PNG output
    import matplotlib.pyplot as plt

    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False


# ── Data Loading ─────────────────────────────────────────────────────────────


def load_trace(path: str) -> List[Dict[str, Any]]:
    """Read a JSONL trace file and return a list of entry dicts.

    Each line is parsed as JSON. Blank lines and lines that fail to parse
    are silently skipped.
    """
    entries = []
    with open(path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                print(
                    "Warning: skipping malformed JSON on line %d" % line_num,
                    file=sys.stderr,
                )
    return entries


# ── Statistics ───────────────────────────────────────────────────────────────


def compute_stats(entries: List[Dict[str, Any]], stage: str) -> Dict[str, Any]:
    """Compute p50/p95/p99 and basic stats for entries matching *stage*.

    Returns a dict with count, min, max, mean, std, p50, p95, p99.
    If no entries match, returns {'count': 0}.
    """
    values = [e["value"] for e in entries if e.get("stage") == stage]
    if not values:
        return {"count": 0}

    if HAS_NUMPY:
        arr = np.array(values, dtype=np.float64)
        return {
            "count": len(values),
            "min": float(np.min(arr)),
            "max": float(np.max(arr)),
            "mean": float(np.mean(arr)),
            "std": float(np.std(arr)),
            "p50": float(np.percentile(arr, 50)),
            "p95": float(np.percentile(arr, 95)),
            "p99": float(np.percentile(arr, 99)),
        }
    else:
        # Fallback: pure Python (no percentile)
        sorted_vals = sorted(values)
        n = len(sorted_vals)
        mean = sum(sorted_vals) / n
        var = sum((x - mean) ** 2 for x in sorted_vals) / n
        return {
            "count": n,
            "min": sorted_vals[0],
            "max": sorted_vals[-1],
            "mean": mean,
            "std": var ** 0.5,
            "p50": sorted_vals[n // 2],
            "p95": sorted_vals[int(n * 0.95)],
            "p99": sorted_vals[int(n * 0.99)],
        }


# ── Throughput ───────────────────────────────────────────────────────────────


def compute_throughput(entries: List[Dict[str, Any]]) -> List[Tuple[float, float]]:
    """Compute frames-per-minute in 1-minute sliding windows.

    Groups total_inference entries by frame_id to identify unique frames,
    then counts completions per 1-minute window.

    Returns list of (minute, frames_per_minute) tuples.
    """
    # Collect one timestamp per unique frame_id from total_inference entries
    frame_timestamps = {}
    for e in entries:
        if e.get("stage") == "total_inference":
            fid = e.get("frame_id", -1)
            if fid not in frame_timestamps:
                frame_timestamps[fid] = e["ts_ms"]

    if not frame_timestamps:
        return []

    timestamps_ms = sorted(frame_timestamps.values())
    t0 = timestamps_ms[0]

    # Convert to relative minutes
    rel_minutes = [(t - t0) / 60000.0 for t in timestamps_ms]

    if not rel_minutes:
        return []

    # 1-minute sliding windows, stepping by 0.5 minutes
    max_minute = rel_minutes[-1]
    window_size = 1.0
    step = 0.5
    results = []

    window_start = 0.0
    while window_start <= max_minute:
        window_end = window_start + window_size
        count = sum(1 for m in rel_minutes if window_start <= m < window_end)
        # Normalize to full minute rate
        results.append((window_start + window_size / 2.0, float(count)))
        window_start += step

    return results


# ── Time Series Extraction ───────────────────────────────────────────────────


def extract_time_series(
    entries: List[Dict[str, Any]], stage: str
) -> Tuple[List[float], List[float]]:
    """Extract (timestamps_relative_seconds, values) for a given stage.

    Timestamps are relative to the first entry in the entire trace.
    """
    # Find global t0
    all_ts = [e["ts_ms"] for e in entries if "ts_ms" in e]
    if not all_ts:
        return ([], [])
    t0 = min(all_ts)

    filtered = [e for e in entries if e.get("stage") == stage]
    timestamps = [(e["ts_ms"] - t0) / 1000.0 for e in filtered]
    values = [e["value"] for e in filtered]
    return (timestamps, values)


# ── Token Metrics ────────────────────────────────────────────────────────────


def _compute_token_metrics(
    entries: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Extract total tokens generated and tokens/sec from total_inference entries."""
    total_tokens = 0
    total_decode_ms = 0.0
    count = 0

    for e in entries:
        if e.get("stage") == "total_inference":
            gen = e.get("generated_tokens", 0)
            total_tokens += gen
            count += 1

    # Use decode stage for tokens/sec (decode is where token generation happens)
    decode_entries = [e for e in entries if e.get("stage") == "decode"]
    total_decode_ms = sum(e["value"] for e in decode_entries)

    tokens_per_sec = 0.0
    if total_decode_ms > 0:
        tokens_per_sec = total_tokens / (total_decode_ms / 1000.0)

    return {
        "total_generated": total_tokens,
        "tokens_per_sec": tokens_per_sec,
    }


# ── Experiment Metrics ───────────────────────────────────────────────────────


def compute_rss_slope(
    entries: List[Dict[str, Any]], warmup_seconds: float = 60.0
) -> Optional[Dict[str, Any]]:
    """Compute RSS memory slope (MB/min) after warmup period.

    Uses numpy.polyfit(degree=1) on (relative_minutes, rss_mb).
    Returns {slope_mb_per_min, r_squared, sample_count} or None.
    """
    if not HAS_NUMPY:
        return None

    rss_entries = [e for e in entries if e.get("stage") == "rss_bytes"]
    if len(rss_entries) < 5:
        return None

    all_ts = [e["ts_ms"] for e in entries if "ts_ms" in e]
    if not all_ts:
        return None
    t0 = min(all_ts)

    # Filter out warmup period
    filtered = [
        e for e in rss_entries
        if (e["ts_ms"] - t0) / 1000.0 >= warmup_seconds
    ]
    if len(filtered) < 5:
        return None

    rel_minutes = np.array([(e["ts_ms"] - t0) / 60000.0 for e in filtered])
    rss_mb = np.array([e["value"] / (1024 * 1024) for e in filtered])

    coeffs = np.polyfit(rel_minutes, rss_mb, 1)
    slope = float(coeffs[0])

    # R-squared
    predicted = np.polyval(coeffs, rel_minutes)
    ss_res = np.sum((rss_mb - predicted) ** 2)
    ss_tot = np.sum((rss_mb - np.mean(rss_mb)) ** 2)
    r_squared = float(1.0 - ss_res / ss_tot) if ss_tot > 0 else 0.0

    return {
        "slope_mb_per_min": round(slope, 2),
        "r_squared": round(r_squared, 3),
        "sample_count": len(filtered),
    }


def compute_latency_drift(entries: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Compute latency drift between first and second half of the run.

    Splits total_inference entries at the temporal midpoint, computes p95
    for each half, and returns the drift.
    """
    inference = [e for e in entries if e.get("stage") == "total_inference"]
    if len(inference) < 20:
        return None

    # Sort by timestamp
    inference.sort(key=lambda e: e["ts_ms"])
    t_start = inference[0]["ts_ms"]
    t_end = inference[-1]["ts_ms"]
    t_mid = (t_start + t_end) / 2.0

    first_half = [e["value"] for e in inference if e["ts_ms"] < t_mid]
    second_half = [e["value"] for e in inference if e["ts_ms"] >= t_mid]

    if len(first_half) < 5 or len(second_half) < 5:
        return None

    if HAS_NUMPY:
        p95_first = float(np.percentile(first_half, 95))
        p95_second = float(np.percentile(second_half, 95))
    else:
        first_sorted = sorted(first_half)
        second_sorted = sorted(second_half)
        p95_first = first_sorted[int(len(first_sorted) * 0.95)]
        p95_second = second_sorted[int(len(second_sorted) * 0.95)]

    drift_ms = p95_second - p95_first
    drift_pct = (drift_ms / p95_first * 100.0) if p95_first > 0 else 0.0

    return {
        "first_half_p95": round(p95_first, 1),
        "second_half_p95": round(p95_second, 1),
        "drift_ms": round(drift_ms, 1),
        "drift_pct": round(drift_pct, 1),
    }


def compute_thermal_distribution(
    entries: List[Dict[str, Any]],
) -> Optional[Dict[str, Any]]:
    """Compute time-weighted thermal state distribution.

    Treats thermal_state as a step function: each sample's state is held
    until the next sample.
    """
    thermal = [e for e in entries if e.get("stage") == "thermal_state"]
    if not thermal:
        return None

    thermal.sort(key=lambda e: e["ts_ms"])

    # Time-weighted distribution
    state_time = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}
    peak_state = 0

    for i in range(len(thermal)):
        state = int(thermal[i]["value"])
        peak_state = max(peak_state, state)

        if i + 1 < len(thermal):
            duration = (thermal[i + 1]["ts_ms"] - thermal[i]["ts_ms"]) / 1000.0
        else:
            duration = 1.0  # Last sample: assume 1 second

        if state in state_time:
            state_time[state] += duration

    total_time = sum(state_time.values())
    if total_time <= 0:
        return None

    return {
        "nominal_pct": round(state_time[0] / total_time * 100, 1),
        "fair_pct": round(state_time[1] / total_time * 100, 1),
        "serious_pct": round(state_time[2] / total_time * 100, 1),
        "critical_pct": round(state_time[3] / total_time * 100, 1),
        "peak_state": peak_state,
    }


def compute_scheduler_actions(
    entries: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Count scheduler decisions and budget violations from trace entries.

    PerfTrace merges extra map into entry, so fields like 'action',
    'reason', 'constraint', 'observe_only' are top-level.
    """
    degrade_count = 0
    restore_count = 0
    degrade_reasons = defaultdict(int)  # type: Dict[str, int]
    actionable_violations = 0
    observe_only_violations = 0
    memory_triggered_degrades = 0

    for e in entries:
        stage = e.get("stage")

        if stage == "scheduler_decision":
            action = e.get("action", "")
            if action == "degrade":
                degrade_count += 1
                reason = e.get("reason", "unknown")
                degrade_reasons[reason] += 1
                if reason == "memoryCeiling":
                    memory_triggered_degrades += 1
            elif action == "restore":
                restore_count += 1

        elif stage == "budget_violation":
            if e.get("observe_only", False):
                observe_only_violations += 1
            else:
                actionable_violations += 1

    return {
        "degrade_count": degrade_count,
        "restore_count": restore_count,
        "degrade_reasons": dict(degrade_reasons),
        "actionable_violations": actionable_violations,
        "observe_only_violations": observe_only_violations,
        "memory_triggered_degrades": memory_triggered_degrades,
    }


def compute_stability_metrics(
    entries: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Scan for gaps > 30s between inference frames and non-monotonic frame_id."""
    inference = [e for e in entries if e.get("stage") == "total_inference"]
    if not inference:
        return {"gap_count": 0, "max_gap_seconds": 0.0, "frame_id_breaks": 0, "is_stable": True}

    inference.sort(key=lambda e: e["ts_ms"])

    gap_count = 0
    max_gap = 0.0
    frame_id_breaks = 0
    prev_ts = inference[0]["ts_ms"]
    prev_fid = inference[0].get("frame_id", -1)

    for e in inference[1:]:
        gap = (e["ts_ms"] - prev_ts) / 1000.0
        if gap > max_gap:
            max_gap = gap
        if gap > 30.0:
            gap_count += 1

        fid = e.get("frame_id", -1)
        if fid != -1 and prev_fid != -1 and fid <= prev_fid:
            frame_id_breaks += 1
        prev_ts = e["ts_ms"]
        prev_fid = fid

    return {
        "gap_count": gap_count,
        "max_gap_seconds": round(max_gap, 1),
        "frame_id_breaks": frame_id_breaks,
        "is_stable": gap_count == 0 and frame_id_breaks == 0,
    }


# ── Hypothesis Evaluation ────────────────────────────────────────────────────

DEFAULT_THRESHOLDS = {
    "min_duration_min": 10.0,
    "max_gap_seconds": 30.0,
    "p95_latency_ms": 3000.0,
    "max_drift_pct": 20.0,
    "max_rss_slope_mb_per_min": 5.0,
    "max_thermal_serious_pct": 10.0,
    "max_drain_per_10min": 5.0,
    "max_memory_triggered_degrades": 0,
}


def evaluate_hypotheses(
    duration_min: float,
    total_frames: int,
    latency_stats: Dict[str, Any],
    stability: Dict[str, Any],
    drift: Optional[Dict[str, Any]],
    rss_slope: Optional[Dict[str, Any]],
    thermal_dist: Optional[Dict[str, Any]],
    battery_drain_per_10min: Optional[float],
    scheduler: Dict[str, Any],
    thresholds: Optional[Dict[str, Any]] = None,
) -> Dict[str, Dict[str, str]]:
    """Evaluate all 6 hypotheses against metrics.

    Returns {H1_stability: {verdict, criteria, evidence}, ...}.
    Verdict is PASS, FAIL, or INCONCLUSIVE.
    """
    t = dict(DEFAULT_THRESHOLDS)
    if thresholds:
        t.update(thresholds)

    results = {}

    # H1: Stability
    criteria = "duration >= %.0f min, 0 gaps > %.0fs, 0 frame_id breaks" % (
        t["min_duration_min"], t["max_gap_seconds"]
    )
    if total_frames < 10:
        results["H1_stability"] = {
            "verdict": "INCONCLUSIVE",
            "criteria": criteria,
            "evidence": "%d frames, insufficient data" % total_frames,
        }
    else:
        h1_pass = (
            duration_min >= t["min_duration_min"]
            and stability["gap_count"] == 0
            and stability["frame_id_breaks"] == 0
        )
        evidence = "%d frames, %.1f min, %d gaps, %d breaks" % (
            total_frames, duration_min,
            stability["gap_count"], stability["frame_id_breaks"],
        )
        results["H1_stability"] = {
            "verdict": "PASS" if h1_pass else "FAIL",
            "criteria": criteria,
            "evidence": evidence,
        }

    # H2: Latency consistency
    criteria = "p95 < %.0fms AND drift < %.0f%%" % (
        t["p95_latency_ms"], t["max_drift_pct"]
    )
    p95 = latency_stats.get("p95")
    if p95 is None or latency_stats.get("count", 0) < 20:
        results["H2_latency"] = {
            "verdict": "INCONCLUSIVE",
            "criteria": criteria,
            "evidence": "insufficient latency data",
        }
    elif drift is None:
        h2_pass = p95 < t["p95_latency_ms"]
        results["H2_latency"] = {
            "verdict": "PASS" if h2_pass else "FAIL",
            "criteria": criteria,
            "evidence": "p95=%.0fms, drift=N/A" % p95,
        }
    else:
        h2_pass = (
            p95 < t["p95_latency_ms"]
            and abs(drift["drift_pct"]) < t["max_drift_pct"]
        )
        results["H2_latency"] = {
            "verdict": "PASS" if h2_pass else "FAIL",
            "criteria": criteria,
            "evidence": "p95=%.0fms, drift=%.1f%%" % (p95, drift["drift_pct"]),
        }

    # H3: Memory discipline
    criteria = "RSS slope < %.1f MB/min after 60s warmup" % t["max_rss_slope_mb_per_min"]
    if rss_slope is None:
        results["H3_memory"] = {
            "verdict": "INCONCLUSIVE",
            "criteria": criteria,
            "evidence": "no RSS slope data (numpy required)",
        }
    else:
        h3_pass = rss_slope["slope_mb_per_min"] < t["max_rss_slope_mb_per_min"]
        results["H3_memory"] = {
            "verdict": "PASS" if h3_pass else "FAIL",
            "criteria": criteria,
            "evidence": "slope=%.2f MB/min (R\u00b2=%.3f)" % (
                rss_slope["slope_mb_per_min"], rss_slope["r_squared"]
            ),
        }

    # H4: Thermal safety
    criteria = "fair(1) or below for > 90%% of run time"
    if thermal_dist is None:
        results["H4_thermal"] = {
            "verdict": "INCONCLUSIVE",
            "criteria": criteria,
            "evidence": "no thermal data",
        }
    else:
        safe_pct = thermal_dist["nominal_pct"] + thermal_dist["fair_pct"]
        h4_pass = safe_pct > 90.0
        results["H4_thermal"] = {
            "verdict": "PASS" if h4_pass else "FAIL",
            "criteria": criteria,
            "evidence": "nominal=%.0f%%, fair=%.0f%%" % (
                thermal_dist["nominal_pct"], thermal_dist["fair_pct"]
            ),
        }

    # H5: Battery respect
    criteria = "drain < %.1f%% per 10 min" % t["max_drain_per_10min"]
    if battery_drain_per_10min is None:
        results["H5_battery"] = {
            "verdict": "INCONCLUSIVE",
            "criteria": criteria,
            "evidence": "no battery data",
        }
    else:
        h5_pass = battery_drain_per_10min < t["max_drain_per_10min"]
        results["H5_battery"] = {
            "verdict": "PASS" if h5_pass else "FAIL",
            "criteria": criteria,
            "evidence": "%.2f%%/10min" % battery_drain_per_10min,
        }

    # H6: Budget enforcement
    criteria = "0 degrades triggered by memoryCeiling"
    h6_pass = scheduler["memory_triggered_degrades"] <= t["max_memory_triggered_degrades"]
    results["H6_budget"] = {
        "verdict": "PASS" if h6_pass else "FAIL",
        "criteria": criteria,
        "evidence": "memory_degrades=%d" % scheduler["memory_triggered_degrades"],
    }

    return results


# ── Experiment Recording ─────────────────────────────────────────────────────


def _get_git_hash() -> Optional[str]:
    """Return short git hash of HEAD, or None on failure."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def _generate_experiment_id(git_hash: Optional[str]) -> str:
    """Generate experiment ID as YYYYMMDD_HHMMSS_{hash}."""
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    if git_hash:
        return "%s_%s" % (ts, git_hash)
    return ts


def build_experiment_record(
    experiment_id: str,
    tag: str,
    trace_path: str,
    entries: List[Dict[str, Any]],
    device_model: Optional[str],
    device_os: Optional[str],
    thresholds: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    """Assemble a full experiment record from trace entries."""
    git_hash = _get_git_hash()

    # Duration
    all_ts = [e["ts_ms"] for e in entries if "ts_ms" in e]
    if len(all_ts) >= 2:
        duration_min = (max(all_ts) - min(all_ts)) / 60000.0
    else:
        duration_min = 0.0

    # Frame count
    frame_ids = set(
        e.get("frame_id", -1) for e in entries if e.get("stage") == "total_inference"
    )
    frame_ids.discard(-1)
    total_frames = len(frame_ids)

    # Dropped frames
    dropped_stats = compute_stats(entries, "dropped_frames")
    dropped_count = int(dropped_stats.get("max", 0)) if dropped_stats["count"] > 0 else 0

    # Existing metrics
    latency_stats = compute_stats(entries, "total_inference")
    throughput = compute_throughput(entries)
    token_metrics = _compute_token_metrics(entries)

    # Throughput summary
    if throughput:
        fpm_values = [fpm for _, fpm in throughput]
        throughput_summary = {
            "avg_fpm": round(sum(fpm_values) / len(fpm_values), 1),
            "min_fpm": round(min(fpm_values), 1),
            "max_fpm": round(max(fpm_values), 1),
        }
    else:
        throughput_summary = {"avg_fpm": 0.0, "min_fpm": 0.0, "max_fpm": 0.0}

    # New metrics
    rss_slope = compute_rss_slope(entries)
    drift = compute_latency_drift(entries)
    thermal_dist = compute_thermal_distribution(entries)
    scheduler = compute_scheduler_actions(entries)
    stability = compute_stability_metrics(entries)

    # RSS peak
    rss_values = [e["value"] for e in entries if e.get("stage") == "rss_bytes"]
    rss_peak_mb = round(max(rss_values) / (1024 * 1024), 1) if rss_values else 0.0

    # Battery
    battery_values = [e["value"] for e in entries if e.get("stage") == "battery_level"]
    battery_metrics = {}
    battery_drain_per_10min = None
    if len(battery_values) >= 2:
        start_pct = battery_values[0] * 100.0
        end_pct = battery_values[-1] * 100.0
        drain_pct = start_pct - end_pct
        if duration_min > 0:
            battery_drain_per_10min = drain_pct / duration_min * 10.0
        battery_metrics = {
            "start_pct": round(start_pct, 1),
            "end_pct": round(end_pct, 1),
            "drain_pct": round(drain_pct, 1),
            "drain_per_10min": round(battery_drain_per_10min, 2) if battery_drain_per_10min else None,
        }

    # Evaluate hypotheses
    hypotheses = evaluate_hypotheses(
        duration_min=duration_min,
        total_frames=total_frames,
        latency_stats=latency_stats,
        stability=stability,
        drift=drift,
        rss_slope=rss_slope,
        thermal_dist=thermal_dist,
        battery_drain_per_10min=battery_drain_per_10min,
        scheduler=scheduler,
        thresholds=thresholds,
    )

    # Summary
    pass_count = sum(1 for h in hypotheses.values() if h["verdict"] == "PASS")
    total_count = len(hypotheses)
    summary = "%d/%d PASS" % (pass_count, total_count)

    # Build latency sub-dict
    latency_dict = {}
    if latency_stats.get("count", 0) > 0:
        latency_dict["total_inference"] = {
            "p50": round(latency_stats["p50"], 1),
            "p95": round(latency_stats["p95"], 1),
            "p99": round(latency_stats["p99"], 1),
            "mean": round(latency_stats["mean"], 1),
        }

    # Memory sub-dict
    memory_dict = {"rss_peak_mb": rss_peak_mb}
    if rss_slope:
        memory_dict["rss_slope_mb_per_min"] = rss_slope["slope_mb_per_min"]
        memory_dict["rss_slope_r_squared"] = rss_slope["r_squared"]

    # Build record
    record = {
        "id": experiment_id,
        "tag": tag,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_hash": git_hash,
        "trace_file": os.path.basename(trace_path),
        "device": {
            "model": device_model or "unknown",
            "os_version": device_os or "unknown",
        },
        "duration": {
            "actual_min": round(duration_min, 1),
        },
        "metrics": {
            "frames": {"total": total_frames, "dropped": dropped_count},
            "latency": latency_dict,
            "drift": drift,
            "throughput": throughput_summary,
            "tokens": token_metrics,
            "memory": memory_dict,
            "thermal": thermal_dist,
            "battery": battery_metrics,
            "scheduler": scheduler,
            "stability": stability,
        },
        "hypotheses": hypotheses,
        "summary": summary,
    }

    return record


def append_to_experiments_json(
    record: Dict[str, Any], db_path: str
) -> None:
    """Load/create experiments.json array, append record, write back."""
    experiments = []
    if os.path.isfile(db_path):
        with open(db_path, "r", encoding="utf-8") as f:
            try:
                experiments = json.load(f)
            except json.JSONDecodeError:
                experiments = []

    experiments.append(record)

    with open(db_path, "w", encoding="utf-8") as f:
        json.dump(experiments, f, indent=2)
        f.write("\n")

    print("Saved to %s" % db_path)


def append_to_experiments_md(
    record: Dict[str, Any], md_path: str
) -> None:
    """Format experiment as markdown section and append to EXPERIMENTS.md."""
    lines = []

    tag_suffix = " [%s]" % record["tag"] if record["tag"] else ""
    lines.append("## Run: %s%s\n" % (record["id"], tag_suffix))

    git_str = "`%s`" % record["git_hash"] if record["git_hash"] else "N/A"
    lines.append(
        "**Date:** %s | **Git:** %s | **Duration:** %.1f min | **Frames:** %d\n"
        % (
            record["timestamp"][:10],
            git_str,
            record["duration"]["actual_min"],
            record["metrics"]["frames"]["total"],
        )
    )

    # Hypothesis table
    lines.append("| Hypothesis | Verdict | Evidence |")
    lines.append("|:-----------|:-------:|:---------|")

    h_labels = {
        "H1_stability": "H1: Stability",
        "H2_latency": "H2: Latency",
        "H3_memory": "H3: Memory",
        "H4_thermal": "H4: Thermal",
        "H5_battery": "H5: Battery",
        "H6_budget": "H6: Budget",
    }

    for key, label in h_labels.items():
        h = record["hypotheses"].get(key)
        if h:
            lines.append("| %s | %s | %s |" % (label, h["verdict"], h["evidence"]))

    lines.append("")
    lines.append("**Result: %s**\n" % record["summary"])

    # Full metrics in details block
    lines.append("<details><summary>Full Metrics</summary>\n")
    lines.append("```json")
    lines.append(json.dumps(record["metrics"], indent=2))
    lines.append("```\n")
    lines.append("</details>\n")
    lines.append("---\n")

    content = "\n".join(lines)

    # Create or append
    if not os.path.isfile(md_path):
        with open(md_path, "w", encoding="utf-8") as f:
            f.write("# Soak Test Experiments\n\n")
            f.write(content)
    else:
        with open(md_path, "a", encoding="utf-8") as f:
            f.write(content)

    print("Saved to %s" % md_path)


# ── Experiment Comparison & Listing ──────────────────────────────────────────


def _load_experiments(db_path: str) -> List[Dict[str, Any]]:
    """Load experiments from JSON file."""
    if not os.path.isfile(db_path):
        print("No experiments file found at %s" % db_path, file=sys.stderr)
        return []
    with open(db_path, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            print("Error: malformed experiments.json", file=sys.stderr)
            return []


def _find_experiment(experiments: List[Dict[str, Any]], exp_id: str) -> Optional[Dict[str, Any]]:
    """Find experiment by ID (prefix match allowed)."""
    for exp in experiments:
        if exp["id"] == exp_id or exp["id"].startswith(exp_id):
            return exp
    return None


def list_experiments(db_path: str) -> None:
    """Print summary table of all recorded experiments."""
    experiments = _load_experiments(db_path)
    if not experiments:
        print("No experiments recorded.")
        return

    # Header
    print("%-28s %-14s %8s %6s %8s  %s" % (
        "ID", "Tag", "Duration", "Frames", "p95(ms)", "Result",
    ))
    print("-" * 80)

    for exp in experiments:
        tag = exp.get("tag", "")[:14]
        dur = exp.get("duration", {}).get("actual_min", 0)
        frames = exp.get("metrics", {}).get("frames", {}).get("total", 0)

        latency = exp.get("metrics", {}).get("latency", {}).get("total_inference", {})
        p95 = latency.get("p95", 0)

        summary = exp.get("summary", "N/A")

        print("%-28s %-14s %7.1fm %6d %8.0f  %s" % (
            exp["id"], tag, dur, frames, p95, summary,
        ))


def compare_experiments(
    id1: Optional[str], id2: Optional[str], db_path: str
) -> None:
    """Compare two experiments side-by-side with delta annotations."""
    experiments = _load_experiments(db_path)
    if not experiments:
        return

    if id1 is None and len(experiments) >= 2:
        # Compare last two
        exp_a = experiments[-2]
        exp_b = experiments[-1]
    elif id1 is not None and id2 is None:
        # Compare id1 against most recent
        exp_a = _find_experiment(experiments, id1)
        exp_b = experiments[-1]
        if exp_a is None:
            print("Experiment not found: %s" % id1, file=sys.stderr)
            return
    elif id1 is not None and id2 is not None:
        exp_a = _find_experiment(experiments, id1)
        exp_b = _find_experiment(experiments, id2)
        if exp_a is None:
            print("Experiment not found: %s" % id1, file=sys.stderr)
            return
        if exp_b is None:
            print("Experiment not found: %s" % id2, file=sys.stderr)
            return
    else:
        print("Need at least 2 experiments to compare.", file=sys.stderr)
        return

    print("=== Experiment Comparison ===\n")
    print("  A: %s [%s]" % (exp_a["id"], exp_a.get("tag", "")))
    print("  B: %s [%s]" % (exp_b["id"], exp_b.get("tag", "")))
    print()

    # Compare key metrics
    _compare_metric("Duration (min)",
                    exp_a.get("duration", {}).get("actual_min"),
                    exp_b.get("duration", {}).get("actual_min"),
                    higher_is_better=True)

    _compare_metric("Frames",
                    exp_a.get("metrics", {}).get("frames", {}).get("total"),
                    exp_b.get("metrics", {}).get("frames", {}).get("total"),
                    higher_is_better=True)

    lat_a = exp_a.get("metrics", {}).get("latency", {}).get("total_inference", {})
    lat_b = exp_b.get("metrics", {}).get("latency", {}).get("total_inference", {})
    _compare_metric("p50 latency (ms)", lat_a.get("p50"), lat_b.get("p50"),
                    higher_is_better=False)
    _compare_metric("p95 latency (ms)", lat_a.get("p95"), lat_b.get("p95"),
                    higher_is_better=False)

    drift_a = exp_a.get("metrics", {}).get("drift") or {}
    drift_b = exp_b.get("metrics", {}).get("drift") or {}
    _compare_metric("Drift (%)", drift_a.get("drift_pct"), drift_b.get("drift_pct"),
                    higher_is_better=False)

    mem_a = exp_a.get("metrics", {}).get("memory", {})
    mem_b = exp_b.get("metrics", {}).get("memory", {})
    _compare_metric("RSS peak (MB)", mem_a.get("rss_peak_mb"), mem_b.get("rss_peak_mb"),
                    higher_is_better=False)
    _compare_metric("RSS slope (MB/min)",
                    mem_a.get("rss_slope_mb_per_min"),
                    mem_b.get("rss_slope_mb_per_min"),
                    higher_is_better=False)

    bat_a = exp_a.get("metrics", {}).get("battery", {})
    bat_b = exp_b.get("metrics", {}).get("battery", {})
    _compare_metric("Battery drain/10min",
                    bat_a.get("drain_per_10min"),
                    bat_b.get("drain_per_10min"),
                    higher_is_better=False)

    sched_a = exp_a.get("metrics", {}).get("scheduler", {})
    sched_b = exp_b.get("metrics", {}).get("scheduler", {})
    _compare_metric("Memory degrades",
                    sched_a.get("memory_triggered_degrades"),
                    sched_b.get("memory_triggered_degrades"),
                    higher_is_better=False)

    # Hypothesis comparison
    print()
    print("%-16s %12s %12s" % ("Hypothesis", "A", "B"))
    print("-" * 42)
    h_keys = ["H1_stability", "H2_latency", "H3_memory", "H4_thermal", "H5_battery", "H6_budget"]
    for key in h_keys:
        va = exp_a.get("hypotheses", {}).get(key, {}).get("verdict", "N/A")
        vb = exp_b.get("hypotheses", {}).get(key, {}).get("verdict", "N/A")
        print("%-16s %12s %12s" % (key, va, vb))

    print()
    print("Summary:  A=%s  B=%s" % (exp_a.get("summary", "N/A"), exp_b.get("summary", "N/A")))


def _compare_metric(
    label: str,
    val_a: Optional[float],
    val_b: Optional[float],
    higher_is_better: bool,
) -> None:
    """Print one comparison row with delta and IMPROVED/REGRESSED annotation."""
    if val_a is None and val_b is None:
        return

    a_str = "%.1f" % val_a if val_a is not None else "N/A"
    b_str = "%.1f" % val_b if val_b is not None else "N/A"

    if val_a is not None and val_b is not None:
        delta = val_b - val_a
        if abs(delta) < 0.01:
            annotation = ""
        elif (delta > 0) == higher_is_better:
            annotation = "IMPROVED"
        else:
            annotation = "REGRESSED"
        delta_str = "%+.1f" % delta
    else:
        delta_str = ""
        annotation = ""

    print("  %-24s %10s %10s %10s  %s" % (label, a_str, b_str, delta_str, annotation))


# ── Console Output ───────────────────────────────────────────────────────────


def _thermal_label(value: float) -> str:
    """Convert numeric thermal state to human label."""
    labels = {0: "nominal", 1: "fair", 2: "serious", 3: "critical"}
    return labels.get(int(value), "unknown(%d)" % int(value))


def print_stats(entries: List[Dict[str, Any]]) -> None:
    """Print formatted statistics to console."""
    if not entries:
        print("No trace entries found.")
        return

    # Duration
    all_ts = [e["ts_ms"] for e in entries if "ts_ms" in e]
    if len(all_ts) < 2:
        duration_min = 0.0
    else:
        duration_min = (max(all_ts) - min(all_ts)) / 60000.0

    # Frame count
    frame_ids = set(
        e.get("frame_id", -1) for e in entries if e.get("stage") == "total_inference"
    )
    frame_ids.discard(-1)
    total_frames = len(frame_ids)

    # Dropped frames (if recorded)
    dropped_stats = compute_stats(entries, "dropped_frames")
    dropped_count = int(dropped_stats.get("max", 0)) if dropped_stats["count"] > 0 else 0

    print("=== Edge Veda Soak Test Analysis ===")
    print("Duration: %.1f minutes" % duration_min)
    print("Total frames: %d" % total_frames)
    print("Dropped frames: %d" % dropped_count)

    # Latency stats
    latency_stages = ["image_encode", "prompt_eval", "decode", "total_inference"]
    print()
    print("Latency (ms):")
    for stage in latency_stages:
        stats = compute_stats(entries, stage)
        if stats["count"] == 0:
            print("  %-18s (no data)" % (stage + ":"))
        else:
            print(
                "  %-18s p50=%-8.1f p95=%-8.1f p99=%-8.1f mean=%.1f"
                % (
                    stage + ":",
                    stats["p50"],
                    stats["p95"],
                    stats["p99"],
                    stats["mean"],
                )
            )

    # Throughput
    throughput = compute_throughput(entries)
    if throughput:
        fpm_values = [fpm for _, fpm in throughput]
        avg_fpm = sum(fpm_values) / len(fpm_values)
        min_fpm = min(fpm_values)
        max_fpm = max(fpm_values)
    else:
        avg_fpm = min_fpm = max_fpm = 0.0

    print()
    print("Throughput:")
    print("  Avg frames/min: %.1f" % avg_fpm)
    print("  Min frames/min: %.1f" % min_fpm)
    print("  Max frames/min: %.1f" % max_fpm)

    # Tokens
    token_metrics = _compute_token_metrics(entries)
    print()
    print("Tokens:")
    print("  Total generated: %d" % token_metrics["total_generated"])
    print("  Avg tokens/sec: %.1f" % token_metrics["tokens_per_sec"])

    # System metrics
    thermal_stats = compute_stats(entries, "thermal_state")
    battery_values = [
        e["value"] for e in entries if e.get("stage") == "battery_level"
    ]
    rss_values = [e["value"] for e in entries if e.get("stage") == "rss_bytes"]

    print()
    print("System:")

    if thermal_stats["count"] > 0:
        peak_thermal = int(thermal_stats["max"])
        print("  Thermal peak: %d (%s)" % (peak_thermal, _thermal_label(peak_thermal)))
    else:
        print("  Thermal peak: (no data)")

    if len(battery_values) >= 2:
        start_battery = battery_values[0] * 100.0
        end_battery = battery_values[-1] * 100.0
        drain = start_battery - end_battery
        print(
            "  Battery drain: %.1f%% (%.0f%% -> %.0f%%)"
            % (drain, start_battery, end_battery)
        )
    else:
        print("  Battery drain: (no data)")

    if rss_values:
        peak_rss_mb = max(rss_values) / (1024 * 1024)
        print("  RSS peak: %.0f MB" % peak_rss_mb)
    else:
        print("  RSS peak: (no data)")


# ── Chart Generation ─────────────────────────────────────────────────────────


def generate_charts(entries: List[Dict[str, Any]], output_dir: str) -> List[str]:
    """Generate PNG charts from trace data. Returns list of output file paths.

    Gracefully returns empty list if matplotlib is not available.
    """
    if not HAS_MATPLOTLIB:
        print("Matplotlib not available, skipping charts.")
        return []

    if not entries:
        print("No entries to chart.")
        return []

    os.makedirs(output_dir, exist_ok=True)
    generated = []

    # Chart 1: Latency time series
    path = _chart_latency_timeseries(entries, output_dir)
    if path:
        generated.append(path)

    # Chart 2: Throughput time series
    path = _chart_throughput_timeseries(entries, output_dir)
    if path:
        generated.append(path)

    # Chart 3: Thermal + battery overlay
    path = _chart_thermal_battery_overlay(entries, output_dir)
    if path:
        generated.append(path)

    # Chart 4: Latency distribution
    path = _chart_latency_distribution(entries, output_dir)
    if path:
        generated.append(path)

    return generated


def _chart_latency_timeseries(
    entries: List[Dict[str, Any]], output_dir: str
) -> Optional[str]:
    """Line chart of total_inference latency over time."""
    ts, vals = extract_time_series(entries, "total_inference")
    if not ts:
        return None

    fig, ax = plt.subplots(figsize=(12, 5))
    # Convert seconds to minutes for x-axis
    ts_min = [t / 60.0 for t in ts]
    ax.plot(ts_min, vals, linewidth=0.8, color="#00BCD4", alpha=0.8)
    ax.set_xlabel("Time (minutes)")
    ax.set_ylabel("Latency (ms)")
    ax.set_title("Total Inference Latency Over Time")
    ax.grid(True, alpha=0.3)

    # Add p50/p95 reference lines
    if HAS_NUMPY and vals:
        arr = np.array(vals)
        p50 = np.percentile(arr, 50)
        p95 = np.percentile(arr, 95)
        ax.axhline(y=p50, color="#4CAF50", linestyle="--", alpha=0.7, label="p50=%.0f ms" % p50)
        ax.axhline(y=p95, color="#FF9800", linestyle="--", alpha=0.7, label="p95=%.0f ms" % p95)
        ax.legend()

    fig.tight_layout()
    out_path = os.path.join(output_dir, "latency_timeseries.png")
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


def _chart_throughput_timeseries(
    entries: List[Dict[str, Any]], output_dir: str
) -> Optional[str]:
    """Frames-per-minute over time."""
    throughput = compute_throughput(entries)
    if not throughput:
        return None

    minutes = [t for t, _ in throughput]
    fpm = [f for _, f in throughput]

    fig, ax = plt.subplots(figsize=(12, 5))
    ax.plot(minutes, fpm, linewidth=1.2, color="#00BCD4", marker="o", markersize=3)
    ax.fill_between(minutes, fpm, alpha=0.15, color="#00BCD4")
    ax.set_xlabel("Time (minutes)")
    ax.set_ylabel("Frames per Minute")
    ax.set_title("Throughput Over Time")
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    out_path = os.path.join(output_dir, "throughput_timeseries.png")
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


def _chart_thermal_battery_overlay(
    entries: List[Dict[str, Any]], output_dir: str
) -> Optional[str]:
    """Dual-axis chart: thermal state (left, step) and battery level (right, line)."""
    ts_thermal, vals_thermal = extract_time_series(entries, "thermal_state")
    ts_battery, vals_battery = extract_time_series(entries, "battery_level")

    if not ts_thermal and not ts_battery:
        return None

    fig, ax1 = plt.subplots(figsize=(12, 5))

    if ts_thermal:
        ts_thermal_min = [t / 60.0 for t in ts_thermal]
        ax1.step(
            ts_thermal_min,
            vals_thermal,
            where="post",
            linewidth=1.5,
            color="#FF5722",
            label="Thermal State",
        )
        ax1.set_ylabel("Thermal State (0-3)", color="#FF5722")
        ax1.set_ylim(-0.5, 3.5)
        ax1.set_yticks([0, 1, 2, 3])
        ax1.set_yticklabels(["Nominal", "Fair", "Serious", "Critical"])
        ax1.tick_params(axis="y", labelcolor="#FF5722")

    ax1.set_xlabel("Time (minutes)")

    if ts_battery:
        ax2 = ax1.twinx()
        ts_battery_min = [t / 60.0 for t in ts_battery]
        battery_pct = [v * 100.0 for v in vals_battery]
        ax2.plot(
            ts_battery_min,
            battery_pct,
            linewidth=1.5,
            color="#4CAF50",
            label="Battery Level",
        )
        ax2.set_ylabel("Battery Level (%)", color="#4CAF50")
        ax2.set_ylim(0, 105)
        ax2.tick_params(axis="y", labelcolor="#4CAF50")

    ax1.set_title("Thermal State & Battery Level Over Time")
    ax1.grid(True, alpha=0.3)

    # Combined legend
    lines1, labels1 = ax1.get_legend_handles_labels()
    if ts_battery:
        lines2, labels2 = ax2.get_legend_handles_labels()
        ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper right")
    else:
        ax1.legend(loc="upper right")

    fig.tight_layout()
    out_path = os.path.join(output_dir, "thermal_battery_overlay.png")
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


def _chart_latency_distribution(
    entries: List[Dict[str, Any]], output_dir: str
) -> Optional[str]:
    """Box plot of latency by stage."""
    stages = ["image_encode", "prompt_eval", "decode", "total_inference"]
    data = []
    labels = []
    for stage in stages:
        vals = [e["value"] for e in entries if e.get("stage") == stage]
        if vals:
            data.append(vals)
            labels.append(stage.replace("_", "\n"))

    if not data:
        return None

    fig, ax = plt.subplots(figsize=(10, 6))
    bp = ax.boxplot(
        data,
        labels=labels,
        patch_artist=True,
        showfliers=True,
        flierprops={"marker": ".", "markersize": 3, "alpha": 0.4},
    )

    colors = ["#00BCD4", "#FF9800", "#4CAF50", "#E91E63"]
    for patch, color in zip(bp["boxes"], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.6)

    ax.set_ylabel("Latency (ms)")
    ax.set_title("Latency Distribution by Stage")
    ax.grid(True, axis="y", alpha=0.3)

    fig.tight_layout()
    out_path = os.path.join(output_dir, "latency_distribution.png")
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


# ── Main ─────────────────────────────────────────────────────────────────────


def _parse_args(argv: List[str]) -> Dict[str, Any]:
    """Parse CLI arguments manually (consistent with existing style)."""
    args = {
        "trace_path": None,
        "output_dir": None,
        "experiment": False,
        "tag": "",
        "device_model": None,
        "device_os": None,
        "thresholds_file": None,
        "compare": False,
        "compare_ids": [],
        "list": False,
        "help": False,
    }

    i = 1
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            args["help"] = True
        elif arg == "--list":
            args["list"] = True
        elif arg == "--compare":
            args["compare"] = True
            # Collect up to 2 IDs that follow (non-flag arguments)
            while i + 1 < len(argv) and not argv[i + 1].startswith("-"):
                i += 1
                args["compare_ids"].append(argv[i])
                if len(args["compare_ids"]) >= 2:
                    break
        elif arg == "--output-dir" and i + 1 < len(argv):
            i += 1
            args["output_dir"] = argv[i]
        elif arg == "--experiment":
            args["experiment"] = True
        elif arg == "--tag" and i + 1 < len(argv):
            i += 1
            args["tag"] = argv[i]
        elif arg == "--device-model" and i + 1 < len(argv):
            i += 1
            args["device_model"] = argv[i]
        elif arg == "--device-os" and i + 1 < len(argv):
            i += 1
            args["device_os"] = argv[i]
        elif arg == "--thresholds" and i + 1 < len(argv):
            i += 1
            args["thresholds_file"] = argv[i]
        elif not arg.startswith("-") and args["trace_path"] is None:
            args["trace_path"] = arg
        i += 1

    return args


def _print_help() -> None:
    """Print usage information."""
    print("Usage: analyze_trace.py <trace.jsonl> [options]")
    print("       analyze_trace.py --list")
    print("       analyze_trace.py --compare [ID1] [ID2]")
    print()
    print("Analyze PerfTrace JSONL files from Edge Veda soak tests.")
    print()
    print("Arguments:")
    print("  trace.jsonl             Path to JSONL trace file")
    print()
    print("Options:")
    print("  --output-dir DIR        Directory for chart PNGs (default: same as JSONL)")
    print("  --experiment            Record as versioned experiment")
    print("  --tag TAG               Human label (e.g., 'baseline', 'after-fix')")
    print("  --device-model MODEL    Device name (e.g., 'iPhone 16 Pro')")
    print("  --device-os VERSION     OS version (e.g., 'iOS 26.2.1')")
    print("  --thresholds FILE       Custom hypothesis thresholds JSON")
    print("  --compare [ID] [ID2]    Compare two runs (or latest two)")
    print("  --list                  List all recorded experiments")


def _print_verdicts(hypotheses: Dict[str, Dict[str, str]]) -> None:
    """Print hypothesis verdicts to console."""
    print()
    print("=== Hypothesis Verdicts ===")
    print()

    h_labels = {
        "H1_stability": "H1: Stability",
        "H2_latency": "H2: Latency consistency",
        "H3_memory": "H3: Memory discipline",
        "H4_thermal": "H4: Thermal safety",
        "H5_battery": "H5: Battery respect",
        "H6_budget": "H6: Budget enforcement",
    }

    pass_count = 0
    total = 0
    for key, label in h_labels.items():
        h = hypotheses.get(key)
        if not h:
            continue
        total += 1
        verdict = h["verdict"]
        if verdict == "PASS":
            pass_count += 1
            marker = "+"
        elif verdict == "FAIL":
            marker = "X"
        else:
            marker = "?"
        print("  [%s] %-28s %s" % (marker, label, h["evidence"]))

    print()
    print("Result: %d/%d PASS" % (pass_count, total))


def main() -> None:
    """CLI entry point: parse args, load trace, print stats, generate charts."""
    args = _parse_args(sys.argv)

    if args["help"] or (
        not args["list"]
        and not args["compare"]
        and args["trace_path"] is None
    ):
        _print_help()
        sys.exit(0 if args["help"] else 1)

    # Resolve paths for experiment files
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    db_path = os.path.join(tools_dir, "experiments.json")
    md_path = os.path.join(tools_dir, "EXPERIMENTS.md")

    # --list mode
    if args["list"]:
        list_experiments(db_path)
        return

    # --compare mode
    if args["compare"]:
        ids = args["compare_ids"]
        id1 = ids[0] if len(ids) >= 1 else None
        id2 = ids[1] if len(ids) >= 2 else None
        compare_experiments(id1, id2, db_path)
        return

    # Normal trace analysis
    trace_path = args["trace_path"]
    output_dir = args["output_dir"]
    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(trace_path))

    if not os.path.isfile(trace_path):
        print("Error: file not found: %s" % trace_path, file=sys.stderr)
        sys.exit(1)

    # Load
    entries = load_trace(trace_path)
    if not entries:
        print("Error: no valid entries in %s" % trace_path, file=sys.stderr)
        sys.exit(1)

    print("Loaded %d entries from %s" % (len(entries), trace_path))
    print()

    # Stats
    print_stats(entries)

    # Charts
    print()
    charts = generate_charts(entries, output_dir)
    if charts:
        print("Charts generated:")
        for c in charts:
            print("  %s" % c)
    elif HAS_MATPLOTLIB:
        print("No chart data available.")

    # Experiment recording
    if args["experiment"]:
        # Load custom thresholds
        thresholds = None
        if args["thresholds_file"]:
            with open(args["thresholds_file"], "r", encoding="utf-8") as f:
                thresholds = json.load(f)

        git_hash = _get_git_hash()
        experiment_id = _generate_experiment_id(git_hash)

        record = build_experiment_record(
            experiment_id=experiment_id,
            tag=args["tag"],
            trace_path=trace_path,
            entries=entries,
            device_model=args["device_model"],
            device_os=args["device_os"],
            thresholds=thresholds,
        )

        _print_verdicts(record["hypotheses"])

        print()
        append_to_experiments_json(record, db_path)
        append_to_experiments_md(record, md_path)


if __name__ == "__main__":
    main()
