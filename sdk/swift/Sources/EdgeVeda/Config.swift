import Foundation

/// Configuration for initializing Edge Veda.
public struct Config: Sendable {
    /// Path to the model file (GGUF format).
    public let modelPath: String

    /// Number of CPU threads (default: 4).
    public var numThreads: Int = 4

    /// Context size in tokens (default: 2048).
    public var contextSize: Int = 2048

    /// GPU layers to offload (-1 = all, 0 = none).
    public var gpuLayers: Int = -1

    /// Enable GPU acceleration (default: true, uses Metal).
    public var useGpu: Bool = true

    /// Maximum memory budget in MB (default: 1536).
    public var maxMemoryMB: Int = 1536

    /// Flash attention mode (-1 = auto, 0 = off, 1 = on).
    public var flashAttn: Int = -1

    /// KV cache type for keys (1 = F16, 8 = Q8_0).
    public var kvCacheTypeK: Int = 8

    /// KV cache type for values (1 = F16, 8 = Q8_0).
    public var kvCacheTypeV: Int = 8

    public init(modelPath: String) {
        self.modelPath = modelPath
    }
}
