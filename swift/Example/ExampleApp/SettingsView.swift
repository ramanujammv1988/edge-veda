import SwiftUI
import EdgeVeda

/// Settings tab — device info, capability tier, generation controls, model management, and developer tools.
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showPhoneDetective = false
    @State private var showSoakTest = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    deviceStatusSection
                    capabilityTierSection
                    generationSettingsSection
                    recommendedModelsSection
                    storageSection
                    modelsSection
                    developerToolsSection
                    aboutSection
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $showPhoneDetective) {
            PhoneDetectiveSheet(profile: viewModel.deviceProfile)
        }
        .sheet(isPresented: $showSoakTest) {
            SoakTestSheet()
        }
    }

    // MARK: - Device Status

    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DEVICE STATUS")

            VStack(spacing: 0) {
                settingRow(icon: "iphone", title: "Model", value: DeviceInfo.modelName)
                Divider().background(AppTheme.border)
                settingRow(icon: "cpu", title: "Chip", value: DeviceInfo.chipName)
                Divider().background(AppTheme.border)
                settingRow(icon: "memorychip", title: "Memory", value: DeviceInfo.memoryString)
                Divider().background(AppTheme.border)

                HStack {
                    Image(systemName: "brain")
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 22)
                    Text("Neural Engine")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: DeviceInfo.hasNeuralEngine ? "checkmark.circle" : "xmark.circle")
                        .foregroundColor(DeviceInfo.hasNeuralEngine ? AppTheme.success : AppTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Capability Tier

    private var capabilityTierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CAPABILITY")

            HStack(spacing: 12) {
                // Tier badge
                Text(viewModel.capabilityTier)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(viewModel.capabilityTierColor)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.deviceProfile.totalMemoryMb / 1024) GB RAM")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textPrimary)

                    HStack(spacing: 8) {
                        Text(viewModel.deviceProfile.hasMetal ? "Metal GPU" : "CPU only")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                        Text("·")
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(viewModel.deviceProfile.processorCount) cores")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(16)
            .appCard()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Generation Settings

    private var generationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("GENERATION")

            VStack(spacing: 0) {
                // Temperature
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "thermometer")
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 22)
                        Text("Temperature")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.1f", viewModel.temperature))
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Slider(value: $viewModel.temperature, in: 0.0...2.0, step: 0.1)
                        .accentColor(AppTheme.accent)
                        .padding(.horizontal, 16)

                    HStack {
                        Text("Precise")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                        Spacer()
                        Text("Creative")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                Divider().background(AppTheme.border)

                // Max Tokens
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 22)
                        Text("Max Tokens")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(viewModel.maxTokens))")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Slider(value: $viewModel.maxTokens, in: 32...1024, step: 32)
                        .accentColor(AppTheme.accent)
                        .padding(.horizontal, 16)

                    HStack {
                        Text("Short")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                        Spacer()
                        Text("Long")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Recommended Models

    private var recommendedModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("RECOMMENDED FOR THIS DEVICE")

            if viewModel.recommendedModels.isEmpty {
                Text("No models fit within available memory.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.recommendedModels.prefix(3).enumerated()), id: \.offset) { index, model in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 6, height: 6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                Text(model.description)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(modelSizeString(model.sizeBytes))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if index < min(viewModel.recommendedModels.count, 3) - 1 {
                            Divider().background(AppTheme.border)
                        }
                    }
                }
                .appCard()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("STORAGE")

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "externaldrive")
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 22)
                    Text("Models")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Spacer()
                    Text(viewModel.totalStorageString)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppTheme.surfaceVariant)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppTheme.accent)
                            .frame(width: geometry.size.width * min(viewModel.storageProgress, 1.0), height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(viewModel.totalStorageString) used of ~4 GB")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(16)
            .appCard()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - All Models

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MODELS")

            VStack(spacing: 0) {
                ForEach(Array(viewModel.allModels.enumerated()), id: \.offset) { index, model in
                    ModelRow(
                        model: model,
                        isDownloaded: viewModel.isDownloaded(model),
                        onDelete: { viewModel.deleteModel(model) }
                    )

                    if index < viewModel.allModels.count - 1 {
                        Divider().background(AppTheme.border)
                    }
                }
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Developer Tools

    private var developerToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DEVELOPER TOOLS")

            VStack(spacing: 0) {
                Button(action: { showPhoneDetective = true }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 22)
                        Text("Phone Detective")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Divider().background(AppTheme.border)

                Button(action: { showSoakTest = true }) {
                    HStack {
                        Image(systemName: "flame")
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 22)
                        Text("Soak Test")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .appCard()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ABOUT")

            VStack(spacing: 0) {
                settingRow(
                    icon: "sparkles",
                    title: "Veda",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                )
                Divider().background(AppTheme.border)
                settingRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Veda SDK",
                    value: EdgeVeda.getVersion()
                )
                Divider().background(AppTheme.border)
                settingRow(
                    icon: "cpu",
                    title: "Backend",
                    value: viewModel.deviceProfile.hasMetal ? "Metal GPU" : "CPU"
                )
                Divider().background(AppTheme.border)

                HStack(alignment: .top) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Text("All inference runs locally on device")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
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

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.accent)
            .kerning(1.2)
            .padding(.leading, 4)
    }

    private func settingRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppTheme.accent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func modelSizeString(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return "\(Int(mb)) MB"
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: DownloadableModelInfo
    let isDownloaded: Bool
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        HStack {
            Image(systemName: modelIcon)
                .foregroundColor(AppTheme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text(sizeString)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            if isDownloaded {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(AppTheme.success)

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(AppTheme.textSecondary)
                }
            } else {
                Image(systemName: "cloud.fill")
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Delete Model", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Delete \"\(model.name)\" (\(sizeString))? It will need to be re-downloaded.")
        }
    }

    private var sizeString: String {
        let mb = Double(model.sizeBytes) / (1024 * 1024)
        if mb >= 1024 { return String(format: "~%.1f GB", mb / 1024) }
        return "~\(Int(mb)) MB"
    }

    private var modelIcon: String {
        switch model.modelType {
        case .whisper:    return "waveform"
        case .vision:     return "eye"
        case .mmproj:     return "puzzlepiece.extension"
        case .embedding:  return "chart.bar.xaxis"
        default:          return "brain"
        }
    }
}

// MARK: - Settings View Model

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var temperature: Double = 0.7
    @Published var maxTokens: Double = 256
    @Published var totalStorageBytes: Int64 = 0
    @Published var downloadedModelIds: Set<String> = []
    @Published var deviceProfile: DeviceProfile = detectDeviceCapabilities()

    private let modelManager = ModelManager()

    let allModels: [DownloadableModelInfo] = ModelRegistry.getAllModels()
        + ModelRegistry.getVisionModels()
        + [ModelRegistry.smolvlm2_500m_mmproj]
        + ModelRegistry.getWhisperModels()
        + ModelRegistry.getEmbeddingModels()

    var recommendedModels: [DownloadableModelInfo] {
        recommendModels(profile: deviceProfile, from: ModelRegistry.getAllModels())
    }

    var capabilityTier: String {
        let mb = deviceProfile.availableForModelMb
        switch mb {
        case ..<1024:     return "Low"
        case 1024..<3072: return "Medium"
        case 3072..<6144: return "High"
        default:          return "Ultra"
        }
    }

    var capabilityTierColor: Color {
        switch capabilityTier {
        case "Low":    return AppTheme.warning
        case "Medium": return AppTheme.accent
        case "High":   return AppTheme.accent
        default:       return AppTheme.success
        }
    }

    var totalStorageString: String {
        let mb = Double(totalStorageBytes) / (1024 * 1024)
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return "\(Int(mb)) MB"
    }

    var storageProgress: Double {
        Double(totalStorageBytes) / (4.0 * 1024 * 1024 * 1024)
    }

    func refresh() async {
        deviceProfile = detectDeviceCapabilities()
        totalStorageBytes = (try? await modelManager.getTotalModelsSize()) ?? 0

        var ids = Set<String>()
        for model in allModels {
            if (try? await modelManager.isModelDownloaded(model.id)) == true {
                ids.insert(model.id)
            }
        }
        downloadedModelIds = ids
    }

    func isDownloaded(_ model: DownloadableModelInfo) -> Bool {
        downloadedModelIds.contains(model.id)
    }

    func deleteModel(_ model: DownloadableModelInfo) {
        Task {
            try? await modelManager.deleteModel(model.id)
            downloadedModelIds.remove(model.id)
            totalStorageBytes = (try? await modelManager.getTotalModelsSize()) ?? 0
        }
    }
}

// MARK: - Phone Detective Sheet

private struct PhoneDetectiveSheet: View {
    let profile: DeviceProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        row(label: "Device Model", value: profile.deviceModel)
                        Divider().background(AppTheme.border)
                        row(label: "Total RAM", value: "\(profile.totalMemoryMb) MB")
                        Divider().background(AppTheme.border)
                        row(label: "Available for Model", value: "\(profile.availableForModelMb) MB")
                        Divider().background(AppTheme.border)
                        row(label: "Metal GPU", value: profile.hasMetal ? "Yes" : "No")
                        Divider().background(AppTheme.border)
                        row(label: "GPU Memory", value: "\(profile.estimatedGpuMemoryMb) MB")
                        Divider().background(AppTheme.border)
                        row(label: "CPU Cores", value: "\(profile.processorCount)")
                    }
                    .appCard()
                    .padding(16)
                }
            }
            .navigationTitle("Phone Detective")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Soak Test Sheet

private struct SoakTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRunning = false
    @State private var results: [String] = []
    @State private var avgToksPerSec: Double = 0

    private let prompts = [
        "What is 2 + 2?",
        "Name the capital of France.",
        "What colour is the sky?",
        "How many days in a week?",
        "What is the speed of light?"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    if isRunning {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(AppTheme.accent)
                            Text("Running \(prompts.count)-prompt soak test…")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !results.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Avg: \(String(format: "%.1f", avgToksPerSec)) tok/s")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.bottom, 4)

                                ForEach(results, id: \.self) { line in
                                    Text(line)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                            .padding(16)
                        }

                        Button("Run Again") { runTest() }
                            .appButton()
                            .padding(.bottom, 20)
                    } else {
                        VStack(spacing: 16) {
                            Text("Runs \(prompts.count) short prompts and measures average tokens per second.")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Text("Requires Llama 3.2 1B to be downloaded.")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)

                            Button("Start Soak Test") { runTest() }
                                .appButton()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Soak Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
    }

    private func runTest() {
        isRunning = true
        results = []
        avgToksPerSec = 0

        Task {
            let modelManager = ModelManager()
            guard let modelPath = try? await modelManager.getModelPath(ModelRegistry.llama32_1b.id),
                  let engine = try? await EdgeVeda(modelPath: modelPath, config: .default) else {
                results = ["Model not available. Download Llama 3.2 1B first."]
                isRunning = false
                return
            }

            var speeds: [Double] = []
            for (i, prompt) in prompts.enumerated() {
                let start = Date()
                var tokenCount = 0
                for try? await _ in engine.generateStream(prompt, options: GenerateOptions(maxTokens: 64)) {
                    tokenCount += 1
                }
                let elapsed = Date().timeIntervalSince(start)
                let tps = elapsed > 0 ? Double(tokenCount) / elapsed : 0
                speeds.append(tps)
                let line = "Run \(i + 1): \(String(format: "%.1f", tps)) tok/s — \"\(prompt)\""
                results.append(line)
            }

            avgToksPerSec = speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count)
            isRunning = false
        }
    }
}
