import SwiftUI
import EdgeVeda

/// Settings screen matching Flutter's SettingsScreen exactly.
///
/// Sections: Device Status, Generation (sliders), Storage, Models,
/// Developer (Soak Test link), About.
@available(iOS 16.0, *)
struct SettingsView: View {
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Double = 256

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    deviceStatusSection
                    generationSection
                    storageSection
                    modelsSection
                    aboutSection
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(AppTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.accent)
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.bottom, -8)
    }

    // MARK: - Card Container

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(AppTheme.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }

    // MARK: - Device Status Section

    private var deviceStatusSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Device Status")
            card {
                aboutRow(icon: "iphone", title: "Model", value: deviceModel)
                divider
                aboutRow(icon: "cpu", title: "Chip", value: "Apple Silicon")
                divider
                aboutRow(icon: "memorychip", title: "Memory", value: memoryString)
                divider
                HStack {
                    Image(systemName: "brain")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 22)
                    Text("Neural Engine")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.success)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Generation Section

    private var generationSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Generation")
            card {
                // Temperature
                settingRow(icon: "thermometer.medium", title: "Temperature", value: String(format: "%.1f", temperature))

                Slider(value: $temperature, in: 0...2, step: 0.1)
                    .tint(AppTheme.accent)
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

                divider

                // Max Tokens
                settingRow(icon: "doc.text", title: "Max Tokens", value: "\(Int(maxTokens))")

                Slider(value: $maxTokens, in: 32...1024, step: 32)
                    .tint(AppTheme.accent)
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
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        let models = [ModelRegistry.llama32_1b, ModelRegistry.smolvlm2_500m, ModelRegistry.smolvlm2_500m_mmproj]
        let totalBytes = models.reduce(0) { $0 + $1.sizeBytes }
        let totalGb = Double(totalBytes) / (1024 * 1024 * 1024)

        return VStack(spacing: 0) {
            sectionHeader("Storage")
            card {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.accent)
                        Text("Models")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text("~\(String(format: "%.1f", totalGb)) GB")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    // Storage bar
                    GeometryReader { _ in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.surfaceVariant)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.accent)
                                .frame(width: max(0, min(1, totalGb / 4.0)) * (UIScreen.main.bounds.width - 64))
                        }
                    }
                    .frame(height: 6)

                    Text("\(String(format: "%.1f", totalGb)) GB used")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        let models = [ModelRegistry.llama32_1b, ModelRegistry.smolvlm2_500m, ModelRegistry.smolvlm2_500m_mmproj]

        return VStack(spacing: 0) {
            sectionHeader("Models")
            card {
                ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                    ModelRow(model: model)
                    if index < models.count - 1 {
                        divider
                    }
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: 0) {
            sectionHeader("About")
            card {
                aboutRow(icon: "sparkles", title: "Veda", value: "1.1.0")
                divider
                aboutRow(icon: "chevron.left.forwardslash.chevron.right", title: "Veda SDK", value: "1.1.0")
                divider
                aboutRow(icon: "memorychip", title: "Backend", value: "Metal GPU")
                divider
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("All inference runs locally on device")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Helper Views

    private var divider: some View {
        Divider()
            .background(AppTheme.border)
            .padding(.horizontal, 16)
    }

    private func settingRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppTheme.accent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func aboutRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppTheme.accent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Device Info

    private var deviceModel: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    private var memoryString: String {
        let memSize = ProcessInfo.processInfo.physicalMemory
        let gb = Double(memSize) / (1024 * 1024 * 1024)
        return String(format: "%.2f GB", gb)
    }
}

// MARK: - Model Row

@available(iOS 15.0, *)
struct ModelRow: View {
    let model: EdgeVeda.ModelInfo
    @State private var isDownloaded: Bool?
    @State private var isDeleting = false

    private func modelIcon() -> String {
        if model.id.contains("mmproj") { return "puzzlepiece.extension" }
        if model.id.contains("vlm") || model.id.contains("smol") { return "eye" }
        return "cpu"
    }

    private func formatSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return "~\(String(format: "%.1f", mb / 1024)) GB"
        }
        return "~\(Int(mb)) MB"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: modelIcon())
                .font(.system(size: 18))
                .foregroundColor(AppTheme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
                Text(formatSize(model.sizeBytes))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()

            if isDeleting {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppTheme.accent)
            } else if let downloaded = isDownloaded {
                if downloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.success)

                    Button(action: deleteModel) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.textTertiary)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppTheme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .task {
            let mm = ModelManager()
            isDownloaded = try? await mm.isModelDownloaded(model.id)
        }
    }

    private func deleteModel() {
        isDeleting = true
        Task {
            let mm = ModelManager()
            try? await mm.deleteModel(model.id)
            isDownloaded = false
            isDeleting = false
        }
    }
}