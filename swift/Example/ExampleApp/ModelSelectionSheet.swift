import SwiftUI

/// Model selection bottom sheet showing device info and available models.
///
/// This is a read-only/informational modal. Model downloads happen
/// automatically on the Chat and Vision screens.
struct ModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = ModelManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Device status card
                        deviceStatusCard
                        
                        // Available models section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Available Models")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 20)
                            
                            // Chat models
                            ModelTile(
                                model: ModelInfo(
                                    name: "Llama 3.2 1B",
                                    size: 700_000_000,
                                    filename: "llama-3.2-1b-gguf"
                                ),
                                icon: "text.alignleft",
                                sizeLabel: "~700 MB",
                                modelManager: modelManager
                            )
                            
                            ModelTile(
                                model: ModelInfo(
                                    name: "Qwen 3 0.6B",
                                    size: 600_000_000,
                                    filename: "qwen-3-0.6b-gguf"
                                ),
                                icon: "text.alignleft",
                                sizeLabel: "~600 MB",
                                modelManager: modelManager
                            )
                            
                            // Vision models
                            ModelTile(
                                model: ModelInfo(
                                    name: "SmolVLM2 500M",
                                    size: 417_000_000,
                                    filename: "smolvlm2-500m-gguf"
                                ),
                                icon: "eye",
                                sizeLabel: "~417 MB",
                                modelManager: modelManager
                            )
                            
                            ModelTile(
                                model: ModelInfo(
                                    name: "SmolVLM2 MMProj",
                                    size: 190_000_000,
                                    filename: "smolvlm2-500m-mmproj-gguf"
                                ),
                                icon: "eye",
                                sizeLabel: "~190 MB",
                                modelManager: modelManager
                            )
                            
                            // Speech model
                            ModelTile(
                                model: ModelInfo(
                                    name: "Whisper Tiny EN",
                                    size: 75_000_000,
                                    filename: "whisper-tiny-en-ggml"
                                ),
                                icon: "mic",
                                sizeLabel: "~75 MB",
                                modelManager: modelManager
                            )
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }
    
    private var deviceStatusCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "iphone")
                .font(.system(size: 28))
                .foregroundColor(Theme.accent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Device")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                
                Text(DeviceInfo.modelName)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Backend")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                
                Text("Metal GPU")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.surfaceVariant)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

struct ModelTile: View {
    let model: ModelInfo
    let icon: String
    let sizeLabel: String
    @ObservedObject var modelManager: ModelManager
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Theme.accent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textPrimary)
                
                Text(sizeLabel)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            
            Spacer()
            
            // Download status indicator
            Group {
                if modelManager.isModelDownloaded(model.filename) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.success)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(16)
        .background(Theme.surfaceVariant)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

#Preview {
    ModelSelectionSheet()
}