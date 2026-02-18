//
//  ModelManager.swift
//  ExampleApp
//
//  Model download and management
//

import Foundation

@MainActor
class ModelManager: ObservableObject {
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    
    // Available models
    static let availableModels: [ModelInfo] = [
        ModelInfo(
            id: "llama-3.2-1b",
            name: "Llama 3.2 1B",
            size: 650_000_000, // ~650 MB
            url: "https://huggingface.co/EdgeVeda/llama-3.2-1b-gguf/resolve/main/llama-3.2-1b-q4_k_m.gguf",
            description: "Fast chat model for general conversation"
        ),
        ModelInfo(
            id: "qwen-3-0.6b",
            name: "Qwen 3 0.6B",
            size: 400_000_000, // ~400 MB
            url: "https://huggingface.co/EdgeVeda/qwen-3-0.6b-gguf/resolve/main/qwen-3-0.6b-q4_k_m.gguf",
            description: "Compact model with tool calling support"
        )
    ]
    
    func isModelDownloaded(_ modelId: String) -> Bool {
        guard let model = Self.availableModels.first(where: { $0.id == modelId }) else {
            return false
        }
        let fileURL = getModelPath(for: modelId)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    func getModelPath(for modelId: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("models").appendingPathComponent("\(modelId).gguf")
    }
    
    func downloadModel(_ modelId: String) async throws {
        guard let model = Self.availableModels.first(where: { $0.id == modelId }) else {
            throw ModelError.modelNotFound
        }
        
        isDownloading[modelId] = true
        downloadProgress[modelId] = 0
        
        defer {
            isDownloading[modelId] = false
        }
        
        // Create models directory if needed
        let modelsDir = getModelPath(for: modelId).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        
        guard let url = URL(string: model.url) else {
            throw ModelError.invalidURL
        }
        
        // Download with progress tracking
        let (tempURL, response) = try await URLSession.shared.download(from: url) { progress in
            Task { @MainActor in
                self.downloadProgress[modelId] = progress
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }
        
        // Move to final location
        let finalURL = getModelPath(for: modelId)
        try? FileManager.default.removeItem(at: finalURL) // Remove if exists
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        
        downloadProgress[modelId] = 1.0
    }
    
    func deleteModel(_ modelId: String) throws {
        let fileURL = getModelPath(for: modelId)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    func getTotalStorageUsed() -> UInt64 {
        var total: UInt64 = 0
        for model in Self.availableModels {
            if isModelDownloaded(model.id) {
                let fileURL = getModelPath(for: model.id)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? UInt64 {
                    total += fileSize
                }
            }
        }
        return total
    }
}

// MARK: - Model Info
struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let size: UInt64
    let url: String
    let description: String
    
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - Model Error
enum ModelError: LocalizedError {
    case modelNotFound
    case invalidURL
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model not found"
        case .invalidURL:
            return "Invalid model URL"
        case .downloadFailed:
            return "Download failed"
        }
    }
}

// MARK: - URLSession Download with Progress
extension URLSession {
    func download(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        let (asyncBytes, response) = try await self.bytes(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
              let totalBytes = Int64(contentLength) else {
            throw ModelError.downloadFailed
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        
        defer {
            try? fileHandle.close()
        }
        
        var downloadedBytes: Int64 = 0
        
        for try await byte in asyncBytes {
            let data = Data([byte])
            try fileHandle.write(contentsOf: data)
            downloadedBytes += 1
            
            if downloadedBytes % 1_000_000 == 0 { // Update every MB
                let progress = Double(downloadedBytes) / Double(totalBytes)
                progressHandler(progress)
            }
        }
        
        progressHandler(1.0)
        
        return (tempURL, response)
    }
}