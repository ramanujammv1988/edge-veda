import SwiftUI
import EdgeVeda

/// Model selection sheet matching Flutter's ModelSelectionModal.
///
/// Shows device info and available models with download status.
@available(iOS 16.0, *)
struct ModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Models")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("On-device AI models")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)

                    // Device status card
                    deviceStatusCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Model list section
                    Text("Available Models")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    VStack(spacing: 8) {
                        modelTile(model: ModelRegistry.llama32_1b, icon: "text.justify.left", sizeLabel: "~700 MB")
                        modelTile(model: ModelRegistry.smolvlm2_500m, icon: "eye", sizeLabel: "~417 MB")
                        modelTile(model: ModelRegistry.smolvlm2_500m_mmproj, icon: "eye", sizeLabel: "~190 MB")
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .background(AppTheme.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var deviceStatusCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "iphone")
                .font(.system(size: 24))
                .foregroundColor(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Device")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                Text("iOS")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("Backend")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                Text("Metal GPU")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
            }
        }
        .padding(16)
        .background(AppTheme.surfaceVariant)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func modelTile(model: EdgeVeda.ModelInfo, icon: String, sizeLabel: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(AppTheme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textPrimary)
                Text(sizeLabel)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            ModelDownloadStatusView(modelId: model.id)
        }
        .padding(16)
        .background(AppTheme.surfaceVariant)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

/// Shows download status icon for a model
@available(iOS 15.0, *)
struct ModelDownloadStatusView: View {
    let modelId: String
    @State private var isDownloaded: Bool?

    var body: some View {
        Group {
            if let downloaded = isDownloaded {
                if downloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.success)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.accent)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppTheme.accent)
            }
        }
        .task {
            let mm = ModelManager()
            isDownloaded = try? await mm.isModelDownloaded(modelId)
        }
    }
}