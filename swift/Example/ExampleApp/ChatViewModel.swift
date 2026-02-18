//
//  ChatViewModel.swift
//  ExampleApp
//
//  ViewModel for chat interface with EdgeVeda integration
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
    private var modelManager = ModelManager()
    private let defaultModelId = "llama-3.2-1b"
    
    private var generationTask: Task<Void, Never>?
    private var generationStartTime: Date?
    private var firstTokenTime: Date?
    private var tokenCount: Int = 0
    
    func initializeIfNeeded() {
        guard edgeVeda == nil else { return }
        
        Task {
            await loadModel()
        }
    }
    
    private func loadModel() async {
        do {
            // Check if model is downloaded
            if !modelManager.isModelDownloaded(defaultModelId) {
                isDownloadingModel = true
                
                // Download model
                try await modelManager.downloadModel(defaultModelId)
                
                // Observe download progress
                for await progress in modelManager.$downloadProgress.values {
                    if let modelProgress = progress[defaultModelId] {
                        downloadProgress = modelProgress
                    }
                }
                
                isDownloadingModel = false
            }
            
            // Load model
            isLoadingModel = true
            
            let modelPath = modelManager.getModelPath(for: defaultModelId).path
            edgeVeda = try await EdgeVeda(
                modelPath: modelPath,
                config: .default
            )
            
            // Update initial memory usage
            if let edgeVeda = edgeVeda {
                let memory = await edgeVeda.memoryUsage
                memoryUsageMB = Int(memory / 1_024_000)
            }
            
            isLoadingModel = false
            
        } catch {
            isDownloadingModel = false
            isLoadingModel = false
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }
    }
    
    func sendMessage(_ text: String) {
        guard let edgeVeda = edgeVeda else {
            errorMessage = "Model not loaded"
            return
        }
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        
        // Reset metrics
        ttftMs = 0
        tokensPerSecond = 0
        tokenCount = 0
        currentStreamingText = ""
        generationStartTime = Date()
        firstTokenTime = nil
        
        // Start generation
        isGenerating = true
        
        generationTask = Task {
            do {
                // Build prompt with persona
                let systemMessage = selectedPersona.systemPrompt
                let prompt = "\(systemMessage)\n\nUser: \(text)\nAssistant:"
                
                // Stream generation
                for try await token in edgeVeda.generateStream(
                    prompt,
                    options: GenerateOptions(
                        maxTokens: 512,
                        temperature: 0.7,
                        topP: 0.9
                    )
                ) {
                    // Track first token time
                    if firstTokenTime == nil {
                        firstTokenTime = Date()
                        if let startTime = generationStartTime {
                            ttftMs = Int(firstTokenTime!.timeIntervalSince(startTime) * 1000)
                        }
                    }
                    
                    currentStreamingText += token
                    tokenCount += 1
                    
                    // Update tokens per second
                    if let firstToken = firstTokenTime {
                        let elapsed = Date().timeIntervalSince(firstToken)
                        if elapsed > 0 {
                            tokensPerSecond = Double(tokenCount) / elapsed
                        }
                    }
                    
                    // Update memory usage periodically
                    if tokenCount % 10 == 0 {
                        let memory = await edgeVeda.memoryUsage
                        memoryUsageMB = Int(memory / 1_024_000)
                    }
                }
                
                // Add assistant message
                if !currentStreamingText.isEmpty {
                    let assistantMessage = ChatMessage(role: .assistant, content: currentStreamingText)
                    messages.append(assistantMessage)
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
        
        // Add partial response if any
        if !currentStreamingText.isEmpty {
            let assistantMessage = ChatMessage(role: .assistant, content: currentStreamingText + " [cancelled]")
            messages.append(assistantMessage)
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
    }
}