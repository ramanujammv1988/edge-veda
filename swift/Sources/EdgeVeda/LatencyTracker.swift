import Foundation

/// Tracks inference latency and calculates percentiles.
///
/// Maintains a sliding window of latency samples for calculating
/// p50, p95, and p99 metrics used in budget enforcement.
@available(iOS 15.0, macOS 12.0, *)
actor LatencyTracker {
    private var samples: [Double] = []
    private let maxSamples = 100

    // Sorted cache with dirty flag — rebuilt lazily on the first percentile access
    // after new data arrives, instead of sorting on every p50/p95/p99 call.
    private var sortedCache: [Double] = []
    private var dirty = false
    
    /// Total number of samples recorded.
    var sampleCount: Int {
        return samples.count
    }
    
    /// Record a latency sample in milliseconds.
    func record(_ latencyMs: Double) {
        samples.append(latencyMs)

        // Keep only most recent samples
        if samples.count > maxSamples {
            samples.removeFirst()
        }

        dirty = true
    }
    
    /// Get the 50th percentile (median) latency.
    var p50: Double {
        return percentile(0.50)
    }
    
    /// Get the 95th percentile latency.
    var p95: Double {
        return percentile(0.95)
    }
    
    /// Get the 99th percentile latency.
    var p99: Double {
        return percentile(0.99)
    }
    
    /// Get the average latency.
    var average: Double {
        guard !samples.isEmpty else { return 0.0 }
        return samples.reduce(0.0, +) / Double(samples.count)
    }
    
    /// Get the minimum latency.
    var min: Double {
        return samples.min() ?? 0.0
    }
    
    /// Get the maximum latency.
    var max: Double {
        return samples.max() ?? 0.0
    }
    
    /// Calculate a specific percentile.
    ///
    /// The sorted list is rebuilt only when `dirty` is set (i.e. after a new `record()` call),
    /// avoiding an O(n log n) sort on every p50/p95/p99 access.
    private func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0.0 }

        if dirty {
            sortedCache = samples.sorted()
            dirty = false
        }

        let index = Int((Double(sortedCache.count) * p).rounded(.down))
        let safeIndex = Swift.min(index, sortedCache.count - 1)

        return sortedCache[safeIndex]
    }

    /// Reset all samples.
    func reset() {
        samples.removeAll()
        sortedCache = []
        dirty = false
    }
}