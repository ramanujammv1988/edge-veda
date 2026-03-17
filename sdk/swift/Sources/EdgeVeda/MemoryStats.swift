import Foundation

/// Memory usage statistics.
public struct MemoryStats: Sendable {
    public let currentBytes: Int
    public let peakBytes: Int
    public let limitBytes: Int
    public let modelBytes: Int
    public let contextBytes: Int

    public var usagePercent: Double {
        guard limitBytes > 0 else { return 0 }
        return Double(currentBytes) / Double(limitBytes)
    }

    public var isHighPressure: Bool { usagePercent > 0.8 }
}
