import SwiftUI
import EdgeVeda

/// Chat screen matching Flutter's ChatScreen exactly.
///
/// Features:
/// - ChatSession-based streaming with persona presets
/// - Metrics bar (TTFT, Speed, Memory)
/// - Persona picker chips (Assistant, Coder, Creative)
/// - Context indicator with turn count and usage bar
/// - Message bubbles with avatars (user right, assistant left)
/// - System/summary messages as centered chips
/// - Circular send/stop button
/// - Benchmark mode (10 consecutive generations)
@available(iOS 16.0, *)
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Download progress
                if viewModel.isDownloading {
                    ProgressView(value: viewModel.downloadProgress)
                        .tint(AppTheme.accent)
                        .background(AppTheme.surfaceVariant)
                }

                // Metrics bar
                if viewModel.isInitialized {
                    metricsBar
                }

                // Persona picker or context indicator
                if viewModel.isInitialized {
                    if viewModel.displayMessages.isEmpty && !viewModel.isStreaming {
                        personaPicker
                    } else if !viewModel.displayMessages.isEmpty || viewModel.isStreaming {
                        contextIndicator
                    }
                }

                // Messages list
                messagesArea

                // Input area
                inputBar
            }
            .background(AppTheme.background)
            .navigationTitle("Veda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.isInitialized {
                        Button(action: viewModel.resetChat) {
                            Image(systemName: "plus.bubble")
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .disabled(viewModel.isStreaming || viewModel.isLoading)
                    }

                    Button(action: { viewModel.showModelSheet = true }) {
                        Image(systemName: "square.3.layers.3d")
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    if viewModel.isInitialized && !viewModel.runningBenchmark {
                        Button(action: viewModel.runBenchmark) {
                            Image(systemName: "chart.bar")
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }

                    if viewModel.isInitialized {
                        Button(action: { viewModel.showInfoDialog = true }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $viewModel.showModelSheet) {
                ModelSelectionSheet()
            }
            .alert("Performance Info", isPresented: $viewModel.showInfoDialog) {
                Button("OK") {}
            } message: {
                Text(viewModel.infoText)
            }
            .alert("Benchmark Results", isPresented: $viewModel.showBenchmarkDialog) {
                Button("OK") {}
            } message: {
                Text(viewModel.benchmarkResultText)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isDownloading || viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppTheme.accent)
            }

            Text(viewModel.statusMessage)
                .font(.system(size: 12))
                .foregroundColor(viewModel.isInitialized ? AppTheme.success : AppTheme.warning)
                .lineLimit(1)

            Spacer()

            if !viewModel.isInitialized && !viewModel.isLoading && !viewModel.isDownloading && viewModel.modelPath != nil {
                Button("Initialize") {
                    Task { await viewModel.initializeEdgeVeda() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.accent)
                .cornerRadius(8)
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border),
            alignment: .bottom
        )
    }

    // MARK: - Metrics Bar

    private var metricsBar: some View {
        HStack {
            metricChip(icon: "timer", label: "TTFT", value: viewModel.ttftText)
            Spacer()
            metricChip(icon: "speedometer", label: "Speed", value: viewModel.speedText)
            Spacer()
            metricChip(icon: "memorychip", label: "Memory", value: viewModel.memoryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border),
            alignment: .bottom
        )
    }

    private func metricChip(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
        }
    }

    // MARK: - Persona Picker

    private var personaPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a persona")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)

            HStack(spacing: 8) {
                ForEach(SystemPromptPreset.allCases, id: \.self) { preset in
                    let isSelected = preset == viewModel.selectedPreset
                    Button(action: { viewModel.changePreset(preset) }) {
                        Text(preset.label)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppTheme.accent.opacity(0.2) : AppTheme.surfaceVariant)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? AppTheme.accent : AppTheme.border, lineWidth: 1)
                            )
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border),
            alignment: .bottom
        )
    }

    // MARK: - Context Indicator

    private var contextIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "memorychip")
                .font(.system(size: 12))
                .foregroundColor(viewModel.contextUsage > 0.8 ? AppTheme.warning : AppTheme.accent)

            Text("\(viewModel.turnCount) \(viewModel.turnCount == 1 ? "turn" : "turns")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)

            Spacer()

            Text("\(Int(viewModel.contextUsage * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(viewModel.contextUsage > 0.8 ? AppTheme.warning : AppTheme.textTertiary)

            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.surfaceVariant)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(viewModel.contextUsage > 0.8 ? AppTheme.warning : AppTheme.accent)
                        .frame(width: 60 * min(max(viewModel.contextUsage, 0), 1))
                }
            }
            .frame(width: 60, height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(AppTheme.border),
            alignment: .bottom
        )
    }

    // MARK: - Messages Area

    private var messagesArea: some View {
        Group {
            if viewModel.displayMessages.isEmpty && !viewModel.isStreaming {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 64))
                        .foregroundColor(AppTheme.border)
                    Text("Start a conversation")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textTertiary)
                    Text("Ask anything. It runs on your device.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textTertiary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(viewModel.displayMessages.enumerated()), id: \.offset) { index, message in
                                MessageBubbleView(message: message)
                                    .id(index)
                            }

                            // Streaming text
                            if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                                MessageBubbleView(message: ChatMessage(
                                    role: .assistant,
                                    content: viewModel.streamingText
                                ))
                                .id("streaming")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: viewModel.displayMessages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.displayMessages.count - 1, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.streamingText) { _ in
                        withAnimation {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $viewModel.promptText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AppTheme.surfaceVariant)
                .foregroundColor(AppTheme.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .disabled(!viewModel.isInitialized || viewModel.isLoading || viewModel.isStreaming)
                .onSubmit { Task { await viewModel.sendMessage() } }

            // Send/Stop button
            Button(action: {
                if viewModel.isStreaming {
                    viewModel.cancelGeneration()
                } else {
                    Task { await viewModel.sendMessage() }
                }
            }) {
                Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.isStreaming ? AppTheme.textPrimary : AppTheme.background)
                    .frame(width: 48, height: 48)
                    .background(viewModel.isStreaming ? AppTheme.danger : AppTheme.accent)
                    .clipShape(Circle())
            }
            .disabled(!viewModel.isStreaming && (!viewModel.isInitialized || viewModel.isLoading))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            AppTheme.background
                .shadow(color: .black.opacity(0.4), radius: 8, y: -4)
        )
    }
}

// MARK: - Message Bubble

@available(iOS 15.0, *)
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        // System and summary messages as centered chips
        if message.role == .system || message.role == .summary {
            HStack {
                Spacer()
                Text(message.role == .summary ? "[Context summary] \(message.content)" : message.content)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceVariant)
                    .cornerRadius(12)
                Spacer()
            }
            .padding(.vertical, 4)
        } else {
            let isUser = message.role == .user

            HStack(alignment: .bottom, spacing: 8) {
                if !isUser {
                    // Assistant avatar
                    Circle()
                        .fill(AppTheme.surfaceVariant)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.accent)
                        )
                }

                if isUser { Spacer(minLength: 48) }

                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(isUser ? AppTheme.userBubble : AppTheme.assistantBubble)
                    .cornerRadius(20)
                    .overlay(
                        !isUser
                            ? RoundedRectangle(cornerRadius: 20)
                                .stroke(AppTheme.border, lineWidth: 1)
                            : nil
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 2)

                if !isUser { Spacer(minLength: 48) }

                if isUser {
                    // User avatar
                    Circle()
                        .fill(AppTheme.surfaceVariant)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.accent)
                        )
                }
            }
        }
    }
}

// MARK: - Chat View Model

@available(iOS 16.0, *)
@MainActor
class ChatViewModel: ObservableObject {
    // SDK
    private var edgeVeda: EdgeVeda?
    private var session: ChatSession?
    private let modelManager = ModelManager()

    // State
    @Published var isInitialized = false
    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var isDownloading = false
    @Published var runningBenchmark = false
    @Published var downloadProgress: Double = 0
    @Published var modelPath: String?
    @Published var statusMessage = "Ready to initialize"
    @Published var promptText = ""
    @Published var streamingText = ""
    @Published var selectedPreset: SystemPromptPreset = .assistant
    @Published var showModelSheet = false
    @Published var showInfoDialog = false
    @Published var showBenchmarkDialog = false
    @Published var benchmarkResultText = ""
    @Published var infoText = ""

    // Metrics
    @Published var timeToFirstTokenMs: Int?
    @Published var tokensPerSecond: Double?
    @Published var memoryMb: Double?

    var ttftText: String { timeToFirstTokenMs.map { "\($0)ms" } ?? "-" }
    var speedText: String { tokensPerSecond.map { "\(String(format: "%.1f", $0)) tok/s" } ?? "-" }
    var memoryText: String { memoryMb.map { "\(String(format: "%.0f", $0)) MB" } ?? "-" }

    var displayMessages: [ChatMessage] { session?.messages ?? [] }
    var turnCount: Int { session?.turnCount ?? 0 }
    var contextUsage: Double { session?.contextUsage ?? 0 }

    init() {
        Task { await checkAndDownloadModel() }
    }

    // MARK: - Model Download

    func checkAndDownloadModel() async {
        isDownloading = true
        statusMessage = "Checking for model..."

        do {
            let model = ModelRegistry.llama32_1b
            let isDownloaded = try await modelManager.isModelDownloaded(model.id)

            if !isDownloaded {
                statusMessage = "Downloading model (\(model.name))..."
                modelPath = try await modelManager.downloadModel(model) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress.progress
                        self?.statusMessage = "Downloading: \(progress.progressPercent)%"
                    }
                }
            } else {
                modelPath = try await modelManager.getModelPath(model.id)
            }

            isDownloading = false
            statusMessage = "Model ready. Tap \"Initialize\" to start."
        } catch {
            isDownloading = false
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Initialize

    func initializeEdgeVeda() async {
        guard let path = modelPath else { return }

        isLoading = true
        statusMessage = "Initializing Veda..."

        do {
            edgeVeda = try await EdgeVeda(
                modelPath: path,
                config: EdgeVedaConfig(
                    backend: .metal,
                    threads: 4,
                    contextSize: 2048,
                    gpuLayers: -1
                )
            )

            session = ChatSession(edgeVeda: edgeVeda!, preset: selectedPreset)

            isInitialized = true
            isLoading = false
            statusMessage = "Ready to chat!"
        } catch {
            isLoading = false
            statusMessage = "Initialization failed"
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        guard isInitialized, let session = session else { return }
        guard !isStreaming else { return }

        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        promptText = ""
        isStreaming = true
        isLoading = true
        streamingText = ""
        timeToFirstTokenMs = nil
        tokensPerSecond = nil

        let startTime = CFAbsoluteTimeGetCurrent()
        var receivedFirstToken = false
        var tokenCount = 0

        do {
            let stream = session.sendStream(
                prompt,
                options: GenerateOptions(maxTokens: 256, temperature: 0.7, topP: 0.9)
            )

            statusMessage = "Streaming..."

            for try await token in stream {
                if !receivedFirstToken {
                    let ttft = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                    timeToFirstTokenMs = ttft
                    receivedFirstToken = true
                }

                streamingText += token
                tokenCount += 1

                if tokenCount % 3 == 0 {
                    statusMessage = "Streaming... (\(tokenCount) tokens)"
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            tokensPerSecond = tokenCount > 0 ? Double(tokenCount) / elapsed : 0
            statusMessage = "Complete (\(tokenCount) tokens, \(String(format: "%.1f", tokensPerSecond ?? 0)) tok/s)"

            // Get memory stats
            if let ev = edgeVeda {
                let mem = await ev.memoryUsage
                memoryMb = Double(mem) / (1024 * 1024)
            }

            streamingText = ""
        } catch {
            statusMessage = "Stream error"
            streamingText = ""
        }

        isStreaming = false
        isLoading = false
    }

    // MARK: - Actions

    func cancelGeneration() {
        Task {
            try? await edgeVeda?.cancelGeneration()
            isStreaming = false
            isLoading = false
            statusMessage = "Cancelled"
        }
    }

    func resetChat() {
        session?.reset()
        streamingText = ""
        timeToFirstTokenMs = nil
        tokensPerSecond = nil
        memoryMb = nil
        statusMessage = "Ready to chat!"
    }

    func changePreset(_ preset: SystemPromptPreset) {
        guard preset != selectedPreset || session == nil else { return }
        selectedPreset = preset
        if isInitialized, let ev = edgeVeda {
            session = ChatSession(edgeVeda: ev, preset: preset)
            streamingText = ""
            statusMessage = "Ready to chat!"
        }
    }

    // MARK: - Benchmark

    func runBenchmark() {
        guard isInitialized, let ev = edgeVeda else { return }
        runningBenchmark = true
        statusMessage = "Running benchmark (10 tests)..."

        let prompts = [
            "What is the capital of France?",
            "Explain quantum computing in simple terms.",
            "Write a haiku about nature.",
            "What are the benefits of exercise?",
            "Describe the solar system.",
            "What is machine learning?",
            "Tell me about the ocean.",
            "Explain photosynthesis.",
            "What is artificial intelligence?",
            "Describe the water cycle.",
        ]

        Task {
            var tokenRates: [Double] = []
            var peakMemory: Double = 0

            for i in 0..<10 {
                statusMessage = "Benchmark \(i + 1)/10..."
                let start = CFAbsoluteTimeGetCurrent()

                do {
                    let response = try await ev.generate(prompts[i], options: GenerateOptions(maxTokens: 100, temperature: 0.7))
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    let tokens = Double(response.count) / 4.0
                    let rate = tokens / elapsed
                    tokenRates.append(rate)

                    let mem = await ev.memoryUsage
                    let memMb = Double(mem) / (1024 * 1024)
                    peakMemory = max(peakMemory, memMb)

                    try? await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    break
                }
            }

            let avg = tokenRates.reduce(0, +) / Double(tokenRates.count)
            let minR = tokenRates.min() ?? 0
            let maxR = tokenRates.max() ?? 0

            benchmarkResultText = """
            Avg Speed: \(String(format: "%.1f", avg)) tok/s
            Range: \(String(format: "%.1f", minR)) - \(String(format: "%.1f", maxR)) tok/s
            Peak Memory: \(String(format: "%.0f", peakMemory)) MB
            \(avg >= 15 ? "✅ Meets >15 tok/s target" : "⚠️ Below 15 tok/s target")
            """

            runningBenchmark = false
            statusMessage = "Benchmark complete"
            showBenchmarkDialog = true
        }
    }
}

// MARK: - SystemPromptPreset Extension

extension SystemPromptPreset: CaseIterable {
    public static var allCases: [SystemPromptPreset] { [.assistant, .coder, .creative] }

    var label: String {
        switch self {
        case .assistant: return "Assistant"
        case .coder: return "Coder"
        case .creative: return "Creative"
        }
    }
}