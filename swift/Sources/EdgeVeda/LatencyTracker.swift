import Foundation

/// Tracks inference latency and calculates percentiles.
///
/// Maintains a sliding window of latency samples for calculating
/// p50, p95, and p99 metrics used in budget enforcement.
@available(iOS 15.0, macOS 12.0, *)
actor LatencyTracker {
    private var samples: [Double] = []
    private let maxSamples = 100
    
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
    private func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0.0 }
        
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count) * p).rounded(.down))
        let safeIndex = Swift.min(index, sorted.count - 1)
        
        return sorted[safeIndex]
    }
    
    /// Reset all samples.
    func reset() {
        samples.removeAll()
    }
}