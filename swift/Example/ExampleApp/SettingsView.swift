import SwiftUI

/// Settings tab with device info, generation controls, and model management
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Device Status
                    deviceStatusSection
                    
                    // Generation Settings
                    generationSettingsSection
                    
                    // Storage
                    storageSection
                    
                    // Models
                    modelsSection
                    
                    // About
                    aboutSection
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }
    
    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DEVICE STATUS")
            
            VStack(spacing: 0) {
                settingRow(icon: "iphone", title: "Model", value: DeviceInfo.modelName)
                Divider().background(Theme.border)
                settingRow(icon: "cpu", title: "Chip", value: DeviceInfo.chipName)
                Divider().background(Theme.border)
                settingRow(icon: "memorychip", title: "Memory", value: DeviceInfo.memoryString)
                Divider().background(Theme.border)
                
                HStack {
                    Image(systemName: "brain")
                        .foregroundColor(Theme.accent)
                        .frame(width: 22)
                    Text("Neural Engine")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: DeviceInfo.hasNeuralEngine ? "checkmark.circle" : "xmark.circle")
                        .foregroundColor(DeviceInfo.hasNeuralEngine ? Theme.success : Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }
    
    private var generationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("GENERATION")
            
            VStack(spacing: 0) {
                // Temperature
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "thermometer")
                            .foregroundColor(Theme.accent)
                            .frame(width: 22)
                        Text("Temperature")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.1f", viewModel.temperature))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    Slider(value: $viewModel.temperature, in: 0.0...2.0, step: 0.1)
                        .accentColor(Theme.accent)
                        .padding(.horizontal, 16)
                    
                    HStack {
                        Text("Precise")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                        Text("Creative")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                
                Divider().background(Theme.border)
                
                // Max Tokens
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(Theme.accent)
                            .frame(width: 22)
                        Text("Max Tokens")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(viewModel.maxTokens))")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    Slider(value: $viewModel.maxTokens, in: 32...1024, step: 32)
                        .accentColor(Theme.accent)
                        .padding(.horizontal, 16)
                    
                    HStack {
                        Text("Short")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                        Text("Long")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }
    
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("STORAGE")
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "externaldrive")
                        .foregroundColor(Theme.accent)
                        .frame(width: 22)
                    Text("Models")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Spacer()
                    Text(viewModel.totalStorageString)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                }
                
                // Storage bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.surfaceVariant)
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.accent)
                            .frame(width: geometry.size.width * min(viewModel.storageProgress, 1.0), height: 6)
                    }
                }
                .frame(height: 6)
                
                Text("\(viewModel.totalStorageString) used")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(16)
            .appCard()
        }
        .padding(.horizontal, 16)
    }
    
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MODELS")
            
            VStack(spacing: 0) {
                ForEach(Array(viewModel.models.enumerated()), id: \.offset) { index, model in
                    ModelRow(
                        model: model,
                        isDownloaded: viewModel.isModelDownloaded(model),
                        onDelete: {
                            viewModel.deleteModel(model)
                        }
                    )
                    
                    if index < viewModel.models.count - 1 {
                        Divider().background(Theme.border)
                    }
                }
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ABOUT")
            
            VStack(spacing: 0) {
                settingRow(icon: "sparkles", title: "Veda", value: "1.0.0")
                Divider().background(Theme.border)
                settingRow(icon: "chevron.left.forwardslash.chevron.right", title: "Veda SDK", value: "1.0.0")
                Divider().background(Theme.border)
                settingRow(icon: "cpu", title: "Backend", value: "Metal GPU")
                Divider().background(Theme.border)
                
                HStack(alignment: .top) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(Theme.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Text("All inference runs locally on device")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.accent)
            .kerning(1.2)
            .padding(.leading, 4)
    }
    
    private func settingRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.accent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: ModelInfo
    let isDownloaded: Bool
    let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack {
            Image(systemName: modelIcon)
                .foregroundColor(Theme.accent)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text(model.sizeString)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            
            Spacer()
            
            if isDownloaded {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(Theme.success)
                
                Button(action: {
                    showDeleteConfirm = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                Image(systemName: "cloud.fill")
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Delete Model", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Delete \"\(model.name)\" (\(model.sizeString))? It will be re-downloaded when needed.")
        }
    }
    
    private var modelIcon: String {
        if model.name.contains("mmproj") {
            return "puzzlepiece.extension"
        } else if model.name.contains("vlm") || model.name.contains("smol") {
            return "eye"
        } else if model.name.contains("whisper") {
            return "waveform"
        }
        return "brain"
    }
}

// MARK: - Model Info

struct ModelInfo {
    let name: String
    let size: Int
    let filename: String
    
    var sizeString: String {
        let mb = Double(size) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "~%.1f GB", mb / 1024)
        }
        return "~\(Int(mb)) MB"
    }
}

// MARK: - Settings View Model

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var temperature: Double = 0.7
    @Published var maxTokens: Double = 256
    
    private var modelManager = ModelManager()
    
    let models: [ModelInfo] = [
        ModelInfo(name: "Llama 3.2 1B", size: 650 * 1024 * 1024, filename: "llama-3.2-1b-gguf"),
        ModelInfo(name: "Qwen 3 0.6B", size: 400 * 1024 * 1024, filename: "qwen-3-0.6b-gguf"),
        ModelInfo(name: "SmolVLM2 500M", size: 500 * 1024 * 1024, filename: "smolvlm2-500m-gguf"),
        ModelInfo(name: "SmolVLM2 MMProj", size: 25 * 1024 * 1024, filename: "smolvlm2-500m-mmproj-gguf"),
        ModelInfo(name: "Whisper Tiny EN", size: 77 * 1024 * 1024, filename: "whisper-tiny-en-ggml")
    ]
    
    var totalStorageString: String {
        let totalBytes = modelManager.getTotalStorageUsed()
        let mb = Double(totalBytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return "\(Int(mb)) MB"
    }
    
    var storageProgress: Double {
        let totalBytes = modelManager.getTotalStorageUsed()
        let gb = Double(totalBytes) / (1024 * 1024 * 1024)
        return gb / 4.0 // Estimate out of 4GB
    }
    
    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        return modelManager.isModelDownloaded(model.filename)
    }
    
    func deleteModel(_ model: ModelInfo) {
        modelManager.deleteModel(model.filename)
        objectWillChange.send()
    }
}