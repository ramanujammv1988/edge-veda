//
//  ChatView.swift
//  ExampleApp
//
//  Main chat interface with streaming and metrics
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @State private var showPersonaSheet = false
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with persona selector
                headerView
                
                // Metrics bar
                if viewModel.showMetrics {
                    metricsBar
                }
                
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            // Streaming indicator
                            if viewModel.isGenerating && !viewModel.currentStreamingText.isEmpty {
                                MessageBubble(message: ChatMessage(
                                    role: .assistant,
                                    content: viewModel.currentStreamingText
                                ))
                                .id("streaming")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.currentStreamingText) { _ in
                        withAnimation {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }
                
                // Input area
                inputBar
            }
            
            // Model download/loading overlay
            if viewModel.isDownloadingModel || viewModel.isLoadingModel {
                loadingOverlay
            }
            
            // Error alert
            if let error = viewModel.errorMessage {
                errorOverlay(error)
            }
        }
        .sheet(isPresented: $showPersonaSheet) {
            PersonaSelectionSheet(
                selectedPersona: $viewModel.selectedPersona
            )
        }
        .onAppear {
            viewModel.initializeIfNeeded()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("Chat")
                .font(AppTheme.Typography.titleLarge)
                .foregroundColor(AppTheme.textPrimary)
            
            Spacer()
            
            // Persona selector
            Button(action: { showPersonaSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.selectedPersona.icon)
                    Text(viewModel.selectedPersona.rawValue)
                }
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.surface)
                .cornerRadius(16)
            }
            
            // Clear button
            Button(action: { viewModel.clearChat() }) {
                Image(systemName: "trash")
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding()
        .background(AppTheme.surface)
    }
    
    // MARK: - Metrics Bar
    private var metricsBar: some View {
        HStack(spacing: 16) {
            MetricItem(
                label: "TTFT",
                value: viewModel.ttftMs > 0 ? "\(viewModel.ttftMs)ms" : "--"
            )
            
            MetricItem(
                label: "Speed",
                value: viewModel.tokensPerSecond > 0 ?
                    String(format: "%.1f tok/s", viewModel.tokensPerSecond) : "--"
            )
            
            MetricItem(
                label: "Memory",
                value: viewModel.memoryUsageMB > 0 ? "\(viewModel.memoryUsageMB)MB" : "--"
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceVariant)
    }
    
    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.bodyLarge)
                .foregroundColor(AppTheme.textPrimary)
                .padding(12)
                .background(AppTheme.surface)
                .cornerRadius(20)
                .lineLimit(1...5)
            
            Button(action: sendMessage) {
                if viewModel.isGenerating {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.danger)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(inputText.isEmpty ? AppTheme.textTertiary : AppTheme.accent)
                }
            }
            .disabled(inputText.isEmpty && !viewModel.isGenerating)
        }
        .padding()
        .background(AppTheme.surface)
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppTheme.accent)
                
                if viewModel.isDownloadingModel {
                    Text("Downloading model...")
                        .font(AppTheme.Typography.bodyLarge)
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if viewModel.downloadProgress > 0 {
                        ProgressView(value: viewModel.downloadProgress)
                            .tint(AppTheme.accent)
                            .frame(width: 200)
                        
                        Text("\(Int(viewModel.downloadProgress * 100))%")
                            .font(AppTheme.Typography.bodyMedium)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                } else {
                    Text("Loading model...")
                        .font(AppTheme.Typography.bodyLarge)
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            .padding(32)
            .background(AppTheme.surface)
            .cornerRadius(AppTheme.Layout.cornerRadius)
        }
    }
    
    // MARK: - Error Overlay
    private func errorOverlay(_ error: String) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.danger)
                
                Text(error)
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.textPrimary)
                
                Spacer()
                
                Button(action: { viewModel.errorMessage = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .padding()
            .background(AppTheme.surface)
            .cornerRadius(AppTheme.Layout.cornerRadius)
            .padding()
        }
    }
    
    // MARK: - Actions
    private func sendMessage() {
        if viewModel.isGenerating {
            viewModel.cancelGeneration()
        } else {
            let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            
            inputText = ""
            viewModel.sendMessage(message)
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(AppTheme.Typography.bodyLarge)
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(12)
                    .background(message.role == .user ? AppTheme.userBubble : AppTheme.assistantBubble)
                    .cornerRadius(16)
                
                Text(formatTime(message.timestamp))
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Metric Item
struct MetricItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.textTertiary)
            
            Text(value)
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.accent)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Persona Selection Sheet
struct PersonaSelectionSheet: View {
    @Binding var selectedPersona: ChatPersona
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                List {
                    ForEach(ChatPersona.allCases, id: \.self) { persona in
                        Button(action: {
                            selectedPersona = persona
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: persona.icon)
                                    .foregroundColor(AppTheme.accent)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(persona.rawValue)
                                        .font(AppTheme.Typography.bodyLarge)
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    Text(persona.systemPrompt)
                                        .font(AppTheme.Typography.bodyMedium)
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                if persona == selectedPersona {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.accent)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.accent)
                }
            }
        }
    }
}

#Preview {
    ChatView()
}