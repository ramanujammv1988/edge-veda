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
"""

from __future__ import annotations

import json
import os
import sys
from collections import defaultdict
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


def main() -> None:
    """CLI entry point: parse args, load trace, print stats, generate charts."""
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: %s <trace.jsonl> [--output-dir <dir>]" % sys.argv[0])
        print()
        print("Analyze PerfTrace JSONL files from Edge Veda soak tests.")
        print()
        print("Arguments:")
        print("  trace.jsonl       Path to JSONL trace file")
        print("  --output-dir DIR  Directory for chart PNGs (default: same as JSONL)")
        sys.exit(0 if sys.argv[1] in ("-h", "--help") else 1)

    trace_path = sys.argv[1]

    # Parse --output-dir
    output_dir = None
    for i, arg in enumerate(sys.argv[2:], 2):
        if arg == "--output-dir" and i + 1 < len(sys.argv):
            output_dir = sys.argv[i + 1]
            break

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


if __name__ == "__main__":
    main()
