import Foundation
import CryptoKit

// MARK: - CancelToken

/// Token for cancelling ongoing operations (downloads, streaming generation)
///
/// Thread-safe cancellation token that notifies listeners when cancel() is called.
@available(iOS 15.0, macOS 12.0, *)
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false
    private var _listeners: [() -> Void] = []

    /// Whether cancellation has been requested
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    /// Request cancellation of the operation
    ///
    /// Notifies all registered listeners synchronously.
    public func cancel() {
        lock.lock()
        guard !_isCancelled else {
            lock.unlock()
            return
        }
        _isCancelled = true
        let listeners = _listeners
        lock.unlock()

        for listener in listeners {
            listener()
        }
    }

    /// Add a listener to be notified when cancel() is called
    ///
    /// If the token is already cancelled, the listener is called immediately.
    public func addListener(_ listener: @escaping () -> Void) {
        lock.lock()
        if _isCancelled {
            lock.unlock()
            listener()
        } else {
            _listeners.append(listener)
            lock.unlock()
        }
    }

    /// Reset the token for reuse
    ///
    /// Clears the cancelled state and removes all listeners.
    public func reset() {
        lock.lock()
        _isCancelled = false
        _listeners.removeAll()
        lock.unlock()
    }
}

// MARK: - DownloadProgress

/// Model download progress information
@available(iOS 15.0, macOS 12.0, *)
public struct DownloadProgress: Sendable {
    /// Total bytes to download
    public let totalBytes: Int64

    /// Bytes downloaded so far
    public let downloadedBytes: Int64

    /// Download progress as fraction (0.0 - 1.0)
    public var progress: Double {
        totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0.0
    }

    /// Download progress as percentage (0 - 100)
    public var progressPercent: Int {
        Int((progress * 100).rounded())
    }

    /// Download speed in bytes per second
    public let speedBytesPerSecond: Double?

    /// Estimated time remaining in seconds
    public let estimatedSecondsRemaining: Int?

    public init(
        totalBytes: Int64,
        downloadedBytes: Int64,
        speedBytesPerSecond: Double? = nil,
        estimatedSecondsRemaining: Int? = nil
    ) {
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.estimatedSecondsRemaining = estimatedSecondsRemaining
    }
}

// MARK: - DownloadableModelInfo

/// Downloadable model information descriptor
///
/// Represents a model that can be downloaded from a remote URL.
/// Distinct from `ModelInfo` (in Types.swift) which represents a loaded model's metadata.
@available(iOS 15.0, macOS 12.0, *)
public struct DownloadableModelInfo: Codable, Sendable {
    /// Model identifier (e.g., "llama-3.2-1b-instruct-q4")
    public let id: String

    /// Human-readable model name
    public let name: String

    /// Model size in bytes
    public let sizeBytes: Int64

    /// Model description
    public let description: String?

    /// Download URL
    public let downloadUrl: String

    /// SHA256 checksum for verification
    public let checksum: String?

    /// Model format (e.g., "GGUF")
    public let format: String

    /// Quantization level (e.g., "Q4_K_M")
    public let quantization: String?

    public init(
        id: String,
        name: String,
        sizeBytes: Int64,
        description: String? = nil,
        downloadUrl: String,
        checksum: String? = nil,
        format: String = "GGUF",
        quantization: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
        self.description = description
        self.downloadUrl = downloadUrl
        self.checksum = checksum
        self.format = format
        self.quantization = quantization
    }
}

// MARK: - ModelManager

/// Manages model downloads, caching, and verification.
///
/// Uses actor isolation for thread-safe state management.
/// Downloads use atomic temp-file + rename pattern to prevent corrupt files.
/// SHA-256 checksum verification via CryptoKit.
/// Retry with exponential backoff for transient network errors (up to 3 attempts).
///
/// Models are stored in Application Support/edge_veda_models/ which:
/// - iOS: ~/Library/Application Support/ (excluded from iCloud backup)
/// - macOS: ~/Library/Application Support/
/// - Persists across app launches; only removed on app uninstall
///
/// Example:
/// ```swift
/// let manager = ModelManager()
/// let path = try await manager.downloadModel(ModelRegistry.llama32_1b) { progress in
///     print("Download: \(progress.progressPercent)%")
/// }
/// let edgeVeda = try await EdgeVeda(modelPath: path)
/// ```
@available(iOS 15.0, macOS 12.0, *)
public actor ModelManager {
    private static let modelsCacheDir = "edge_veda_models"
    private static let metadataFileName = "metadata.json"
    private static let maxRetries = 3
    private static let initialRetryDelay: TimeInterval = 1.0

    /// Current active download cancel token
    private var currentDownloadToken: CancelToken?

    // MARK: - Directory Management

    /// Get the models directory path
    ///
    /// Uses Application Support directory which is NOT cleared when the user clears cache,
    /// ensuring models survive between app sessions.
    public func getModelsDirectory() throws -> URL {
        let appSupportDir: URL
        #if os(iOS)
        appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #else
        appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #endif

        let modelsDir = appSupportDir.appendingPathComponent(Self.modelsCacheDir)

        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        return modelsDir
    }

    /// Get path for a specific model file
    public func getModelPath(_ modelId: String) throws -> String {
        let modelsDir = try getModelsDirectory()
        return modelsDir.appendingPathComponent("\(modelId).gguf").path
    }

    /// Check if a model is already downloaded
    public func isModelDownloaded(_ modelId: String) throws -> Bool {
        let modelPath = try getModelPath(modelId)
        return FileManager.default.fileExists(atPath: modelPath)
    }

    /// Get downloaded model file size in bytes
    public func getModelSize(_ modelId: String) throws -> Int64? {
        let modelPath = try getModelPath(modelId)
        guard FileManager.default.fileExists(atPath: modelPath) else { return nil }
        let attrs = try FileManager.default.attributesOfItem(atPath: modelPath)
        return attrs[.size] as? Int64
    }

    // MARK: - Download

    /// Cancel the current download (if any)
    public func cancelDownload() {
        currentDownloadToken?.cancel()
    }

    /// Download a model with progress tracking
    ///
    /// Downloads to a temporary file first, verifies checksum, then atomically
    /// renames to final location. This ensures no corrupt files are left if
    /// download is interrupted.
    ///
    /// If a valid cached model exists, returns immediately without re-downloading (cache-first).
    ///
    /// - Parameters:
    ///   - model: Model information including download URL
    ///   - verifyChecksum: Whether to verify SHA-256 checksum (default: true)
    ///   - cancelToken: Optional token for cancelling the download
    ///   - onProgress: Optional progress callback
    /// - Returns: File path to the downloaded model
    /// - Throws: `EdgeVedaError` on failure
    public func downloadModel(
        _ model: DownloadableModelInfo,
        verifyChecksum: Bool = true,
        cancelToken: CancelToken? = nil,
        onProgress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws -> String {
        let modelPath = try getModelPath(model.id)

        // CACHE-FIRST: skip download if valid model exists
        if FileManager.default.fileExists(atPath: modelPath) {
            if verifyChecksum, let expectedChecksum = model.checksum {
                let isValid = try await self.verifyChecksum(filePath: modelPath, expected: expectedChecksum)
                if isValid {
                    return modelPath
                }
                // Invalid checksum — delete and re-download
                try FileManager.default.removeItem(atPath: modelPath)
            } else {
                // No checksum to verify — assume cached file is valid
                return modelPath
            }
        }

        currentDownloadToken = cancelToken

        defer { currentDownloadToken = nil }

        return try await downloadWithRetry(
            model: model,
            modelPath: modelPath,
            verifyChecksum: verifyChecksum,
            cancelToken: cancelToken,
            onProgress: onProgress
        )
    }

    /// Internal download implementation with retry logic
    private func downloadWithRetry(
        model: DownloadableModelInfo,
        modelPath: String,
        verifyChecksum: Bool,
        cancelToken: CancelToken?,
        onProgress: (@Sendable (DownloadProgress) -> Void)?
    ) async throws -> String {
        var attempt = 0
        var retryDelay = Self.initialRetryDelay

        while true {
            attempt += 1
            do {
                return try await performDownload(
                    model: model,
                    modelPath: modelPath,
                    verifyChecksum: verifyChecksum,
                    cancelToken: cancelToken,
                    onProgress: onProgress
                )
            } catch let error as URLError where error.code == .notConnectedToInternet
                || error.code == .timedOut
                || error.code == .networkConnectionLost
                || error.code == .cannotConnectToHost {
                // Transient network error — retry with exponential backoff
                if attempt >= Self.maxRetries {
                    throw EdgeVedaError.downloadFailed(
                        message: "Failed to download model after \(Self.maxRetries) attempts",
                        underlyingError: error
                    )
                }
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                retryDelay *= 2
            }
        }
    }

    /// Perform the actual download to temp file with atomic rename
    private func performDownload(
        model: DownloadableModelInfo,
        modelPath: String,
        verifyChecksum: Bool,
        cancelToken: CancelToken?,
        onProgress: (@Sendable (DownloadProgress) -> Void)?
    ) async throws -> String {
        // Create temporary file path (atomic pattern)
        let tempPath = modelPath + ".tmp"
        let tempURL = URL(fileURLWithPath: tempPath)

        // Clean up any stale temp file from previous interrupted download
        if FileManager.default.fileExists(atPath: tempPath) {
            try FileManager.default.removeItem(atPath: tempPath)
        }

        // Check for cancellation before starting
        if cancelToken?.isCancelled == true {
            throw EdgeVedaError.downloadFailed(message: "Download cancelled", underlyingError: nil)
        }

        guard let url = URL(string: model.downloadUrl) else {
            throw EdgeVedaError.downloadFailed(
                message: "Invalid download URL: \(model.downloadUrl)",
                underlyingError: nil
            )
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw EdgeVedaError.downloadFailed(
                message: "HTTP \(statusCode)",
                underlyingError: nil
            )
        }

        let totalBytes = Int64(httpResponse.expectedContentLength > 0
            ? httpResponse.expectedContentLength
            : model.sizeBytes)

        // Open temp file for writing
        FileManager.default.createFile(atPath: tempPath, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        var downloadedBytes: Int64 = 0
        var lastReportedBytes: Int64 = 0
        let startTime = Date()
        var buffer = Data()
        let flushThreshold = 256 * 1024 // 256KB flush chunks

        do {
            for try await byte in asyncBytes {
                // Check cancellation
                if cancelToken?.isCancelled == true {
                    try fileHandle.close()
                    try FileManager.default.removeItem(atPath: tempPath)
                    throw EdgeVedaError.downloadFailed(message: "Download cancelled", underlyingError: nil)
                }

                buffer.append(byte)
                downloadedBytes += 1

                // Flush buffer periodically
                if buffer.count >= flushThreshold {
                    fileHandle.write(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }

                // Report progress at reasonable intervals (~every 64KB)
                if downloadedBytes - lastReportedBytes >= 65536 {
                    lastReportedBytes = downloadedBytes

                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Double(downloadedBytes) / elapsed : 0
                    let remaining = speed > 0
                        ? Int(Double(totalBytes - downloadedBytes) / speed)
                        : nil

                    onProgress?(DownloadProgress(
                        totalBytes: totalBytes,
                        downloadedBytes: downloadedBytes,
                        speedBytesPerSecond: speed,
                        estimatedSecondsRemaining: remaining
                    ))
                }
            }

            // Flush remaining buffer
            if !buffer.isEmpty {
                fileHandle.write(buffer)
            }
            try fileHandle.close()
        } catch {
            // Clean up temp file on error
            try? fileHandle.close()
            try? FileManager.default.removeItem(atPath: tempPath)

            if let edgeError = error as? EdgeVedaError {
                throw edgeError
            }
            throw EdgeVedaError.downloadFailed(
                message: "Download failed: \(error.localizedDescription)",
                underlyingError: error
            )
        }

        // Verify checksum BEFORE atomic rename
        if verifyChecksum, let expectedChecksum = model.checksum {
            let isValid = try await self.verifyChecksum(filePath: tempPath, expected: expectedChecksum)
            if !isValid {
                try FileManager.default.removeItem(atPath: tempPath)
                throw EdgeVedaError.checksumMismatch(
                    expected: expectedChecksum,
                    actual: "computed hash did not match"
                )
            }
        }

        // Atomic rename — ensures no corrupt files if interrupted
        try FileManager.default.moveItem(atPath: tempPath, toPath: modelPath)

        // Emit final 100% progress
        onProgress?(DownloadProgress(
            totalBytes: totalBytes,
            downloadedBytes: totalBytes,
            speedBytesPerSecond: 0,
            estimatedSecondsRemaining: 0
        ))

        // Save metadata
        try saveModelMetadata(model)

        return modelPath
    }

    // MARK: - Checksum Verification

    /// Verify file SHA-256 checksum
    ///
    /// - Parameters:
    ///   - filePath: Path to the file to verify
    ///   - expected: Expected SHA-256 hex string
    /// - Returns: true if checksum matches
    public func verifyChecksum(filePath: String, expected: String) async throws -> Bool {
        let hash = try await computeSHA256(filePath: filePath)
        return hash.lowercased() == expected.lowercased()
    }

    /// Compute SHA-256 hash of a file using CryptoKit
    ///
    /// Reads file in chunks to support large model files without loading entirely into memory.
    private func computeSHA256(filePath: String) async throws -> String {
        let url = URL(fileURLWithPath: filePath)
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks

        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Model Deletion & Listing

    /// Delete a downloaded model
    public func deleteModel(_ modelId: String) throws {
        let modelPath = try getModelPath(modelId)
        if FileManager.default.fileExists(atPath: modelPath) {
            try FileManager.default.removeItem(atPath: modelPath)
        }
        try deleteModelMetadata(modelId)
    }

    /// Get list of all downloaded model IDs
    public func getDownloadedModels() throws -> [String] {
        let modelsDir = try getModelsDirectory()
        let contents = try FileManager.default.contentsOfDirectory(atPath: modelsDir.path)

        return contents
            .filter { $0.hasSuffix(".gguf") }
            .map { String($0.dropLast(5)) } // Remove .gguf extension
    }

    /// Get total size of all downloaded models in bytes
    public func getTotalModelsSize() throws -> Int64 {
        let modelsDir = try getModelsDirectory()
        let contents = try FileManager.default.contentsOfDirectory(atPath: modelsDir.path)
        var totalSize: Int64 = 0

        for filename in contents where filename.hasSuffix(".gguf") {
            let filePath = modelsDir.appendingPathComponent(filename).path
            let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
            totalSize += (attrs[.size] as? Int64) ?? 0
        }

        return totalSize
    }

    /// Clear all downloaded models
    public func clearAllModels() throws {
        let modelsDir = try getModelsDirectory()
        if FileManager.default.fileExists(atPath: modelsDir.path) {
            try FileManager.default.removeItem(at: modelsDir)
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Metadata

    /// Save model metadata to disk
    private func saveModelMetadata(_ model: DownloadableModelInfo) throws {
        let modelsDir = try getModelsDirectory()
        let metadataURL = modelsDir.appendingPathComponent("\(model.id)_\(Self.metadataFileName)")

        let wrapper = ModelMetadataWrapper(
            model: model,
            downloadedAt: ISO8601DateFormatter().string(from: Date())
        )

        let data = try JSONEncoder().encode(wrapper)
        try data.write(to: metadataURL)
    }

    /// Delete model metadata
    private func deleteModelMetadata(_ modelId: String) throws {
        let modelsDir = try getModelsDirectory()
        let metadataPath = modelsDir.appendingPathComponent("\(modelId)_\(Self.metadataFileName)").path

        if FileManager.default.fileExists(atPath: metadataPath) {
            try FileManager.default.removeItem(atPath: metadataPath)
        }
    }

    /// Get model metadata if available
    public func getModelMetadata(_ modelId: String) throws -> DownloadableModelInfo? {
        let modelsDir = try getModelsDirectory()
        let metadataURL = modelsDir.appendingPathComponent("\(modelId)_\(Self.metadataFileName)")

        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }

        let data = try Data(contentsOf: metadataURL)
        let wrapper = try JSONDecoder().decode(ModelMetadataWrapper.self, from: data)
        return wrapper.model
    }
}

// MARK: - Internal Metadata Wrapper

@available(iOS 15.0, macOS 12.0, *)
private struct ModelMetadataWrapper: Codable {
    let model: DownloadableModelInfo
    let downloadedAt: String
}

// MARK: - EdgeVedaError Extensions for ModelManager

@available(iOS 15.0, macOS 12.0, *)
extension EdgeVedaError {
    /// Download failed error
    static func downloadFailed(message: String, underlyingError: Error?) -> EdgeVedaError {
        return .unknown(message: "Download failed: \(message)")
    }

    /// Checksum mismatch error
    static func checksumMismatch(expected: String, actual: String) -> EdgeVedaError {
        return .unknown(message: "SHA256 checksum mismatch. Expected: \(expected), Got: \(actual)")
    }
}
