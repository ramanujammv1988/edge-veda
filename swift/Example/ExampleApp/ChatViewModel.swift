//
//  ChatViewModel.swift
//  ExampleApp
//
//  ViewModel for chat interface with EdgeVeda SDK integration.
//  Uses SDK ModelManager (actor) for downloads and ChatSession for multi-turn context.
//

import Foundation
import EdgeVeda

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentStreamingText = ""
    @Published var isGenerating = false
    @Published var selectedPersona: ChatPersona = .assistant

    // Model loading state
    @Published var isDownloadingModel = false
    @Published var isLoadingModel = false
    @Published var downloadProgress: Double = 0

    // Metrics
    @Published var showMetrics = true
    @Published var ttftMs: Int = 0
    @Published var tokensPerSecond: Double = 0
    @Published var memoryUsageMB: Int = 0

    // Error state
    @Published var errorMessage: String?

    private var edgeVeda: EdgeVeda?
    private var chatSession: ChatSession?

    // SDK actor — injected so SettingsView can share the same instance if needed
    private let modelManager = ModelManager()
    private let defaultModel = ModelRegistry.llama32_1b

    private var generationTask: Task<Void, Never>?
    private var generationStartTime: Date?
    private var firstTokenTime: Date?
    private var tokenCount: Int = 0

    // MARK: - Initialisation

    func initializeIfNeeded() {
        guard edgeVeda == nil else { return }
        Task { await loadModel() }
    }

    // MARK: - Model Loading

    private func loadModel() async {
        do {
            // Check whether the model file is already present
            let isDownloaded = (try? await modelManager.isModelDownloaded(defaultModel.id)) ?? false

            if !isDownloaded {
                isDownloadingModel = true
                downloadProgress = 0

                _ = try await modelManager.downloadModel(
                    defaultModel,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.downloadProgress = progress.progress
                        }
                    }
                )

                isDownloadingModel = false
            }

            // Initialise the inference engine
            isLoadingModel = true
            let modelPath = try await modelManager.getModelPath(defaultModel.id)
            edgeVeda = try await EdgeVeda(modelPath: modelPath, config: .default)

            // Build the first chat session with the current persona
            if let ev = edgeVeda {
                chatSession = ChatSession(
                    edgeVeda: ev,
                    systemPrompt: systemPromptPreset,
                    maxContextLength: 2048,
                    template: .llama3
                )
            }

            // Snapshot initial memory usage
            if let ev = edgeVeda {
                let memory = await ev.memoryUsage
                memoryUsageMB = Int(memory / 1_048_576)
            }

            isLoadingModel = false

        } catch {
            isDownloadingModel = false
            isLoadingModel = false
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }
    }

    // MARK: - Messaging

    func sendMessage(_ text: String) {
        guard let session = chatSession else {
            errorMessage = "Model not loaded"
            return
        }

        // Add the user bubble to the UI
        messages.append(ChatMessage(role: .user, content: text))

        // Reset metrics for this turn
        ttftMs = 0
        tokensPerSecond = 0
        tokenCount = 0
        currentStreamingText = ""
        generationStartTime = Date()
        firstTokenTime = nil

        isGenerating = true

        generationTask = Task {
            do {
                let options = GenerateOptions(maxTokens: 512, temperature: 0.7, topP: 0.9)

                // ChatSession maintains conversation history internally
                for try await token in session.sendStream(text, options: options) {
                    // Record time-to-first-token
                    if firstTokenTime == nil {
                        firstTokenTime = Date()
                        if let start = generationStartTime {
                            ttftMs = Int(firstTokenTime!.timeIntervalSince(start) * 1_000)
                        }
                    }

                    currentStreamingText += token
                    tokenCount += 1

                    // Rolling tokens-per-second
                    if let ft = firstTokenTime {
                        let elapsed = Date().timeIntervalSince(ft)
                        if elapsed > 0 { tokensPerSecond = Double(tokenCount) / elapsed }
                    }

                    // Periodic memory snapshot
                    if tokenCount % 10 == 0, let ev = edgeVeda {
                        let mem = await ev.memoryUsage
                        memoryUsageMB = Int(mem / 1_048_576)
                    }
                }

                // Commit the completed response to the UI message list
                if !currentStreamingText.isEmpty {
                    messages.append(ChatMessage(role: .assistant, content: currentStreamingText))
                }
                currentStreamingText = ""
                isGenerating = false

            } catch {
                if !(error is CancellationError) {
                    errorMessage = "Generation failed: \(error.localizedDescription)"
                }
                currentStreamingText = ""
                isGenerating = false
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil

        if !currentStreamingText.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: currentStreamingText + " [cancelled]"))
        }
        currentStreamingText = ""
        isGenerating = false
    }

    func clearChat() {
        messages.removeAll()
        currentStreamingText = ""
        ttftMs = 0
        tokensPerSecond = 0
        tokenCount = 0
        // Reset ChatSession context so the model's KV-cache is cleared
        Task { try? await chatSession?.reset() }
    }

    // MARK: - Persona

    /// Switches persona and recreates the chat session with the new system prompt.
    func changePersona(_ persona: ChatPersona) {
        selectedPersona = persona
        guard let ev = edgeVeda else { return }
        chatSession = ChatSession(
            edgeVeda: ev,
            systemPrompt: systemPromptPreset,
            maxContextLength: 2048,
            template: .llama3
        )
        messages.removeAll()
    }

    private var systemPromptPreset: SystemPromptPreset {
        switch selectedPersona {
        case .assistant: return .assistant
        case .coder:     return .coder
        case .creative:  return .creative
        }
    }
}
