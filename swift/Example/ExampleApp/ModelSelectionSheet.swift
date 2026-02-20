import SwiftUI
import EdgeVeda

/// Model selection bottom sheet — read-only informational modal showing all available models
/// grouped by category, with live download status.
struct ModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ModelSheetViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Device status card
                        deviceStatusCard

                        // Model categories
                        modelCategory(
                            title: "Text",
                            icon: "text.alignleft",
                            models: ModelRegistry.getAllModels()
                        )

                        modelCategory(
                            title: "Vision",
                            icon: "eye",
                            models: ModelRegistry.getVisionModels() + [ModelRegistry.smolvlm2_500m_mmproj]
                        )

                        modelCategory(
                            title: "Speech",
                            icon: "waveform",
                            models: ModelRegistry.getWhisperModels()
                        )

                        modelCategory(
                            title: "Embedding",
                            icon: "chart.bar.xaxis",
                            models: ModelRegistry.getEmbeddingModels()
                        )
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .task { await vm.loadStatus() }
    }

    // MARK: - Device Status Card

    private var deviceStatusCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "iphone")
                .font(.system(size: 28))
                .foregroundColor(AppTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Device")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)

                Text(DeviceInfo.modelName)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Backend")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)

                Text(detectDeviceCapabilities().hasMetal ? "Metal GPU" : "CPU")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(AppTheme.surfaceVariant)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Category Section

    private func modelCategory(
        title: String,
        icon: String,
        models: [DownloadableModelInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(models, id: \.id) { model in
                    ModelSheetTile(
                        model: model,
                        isDownloaded: vm.downloadedIds.contains(model.id)
                    )
                }
            }
        }
    }
}

// MARK: - Model Tile

private struct ModelSheetTile: View {
    let model: DownloadableModelInfo
    let isDownloaded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tileIcon)
                .font(.system(size: 24))
                .foregroundColor(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textPrimary)

                Text(sizeLabel)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.success)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.accent)
            }
        }
        .padding(16)
        .background(AppTheme.surfaceVariant)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var sizeLabel: String {
        let mb = Double(model.sizeBytes) / (1024 * 1024)
        if mb >= 1024 { return String(format: "~%.1f GB", mb / 1024) }
        return "~\(Int(mb)) MB"
    }

    private var tileIcon: String {
        switch model.modelType {
        case .whisper:   return "waveform"
        case .vision:    return "eye"
        case .mmproj:    return "puzzlepiece.extension"
        case .embedding: return "chart.bar.xaxis"
        default:         return "brain"
        }
    }
}

// MARK: - View Model

@MainActor
private class ModelSheetViewModel: ObservableObject {
    @Published var downloadedIds: Set<String> = []

    private let modelManager = ModelManager()

    private var allModels: [DownloadableModelInfo] {
        ModelRegistry.getAllModels()
            + ModelRegistry.getVisionModels()
            + [ModelRegistry.smolvlm2_500m_mmproj]
            + ModelRegistry.getWhisperModels()
            + ModelRegistry.getEmbeddingModels()
    }

    func loadStatus() async {
        var ids = Set<String>()
        for model in allModels {
            if (try? await modelManager.isModelDownloaded(model.id)) == true {
                ids.insert(model.id)
            }
        }
        downloadedIds = ids
    }
}

#Preview {
    ModelSelectionSheet()
}
