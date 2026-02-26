import SwiftUI
import AVFoundation
import EdgeVeda

/// STT (Speech-to-Text) tab with live microphone transcription
///
/// Uses WhisperWorker for on-device speech recognition
/// Audio is captured from microphone, processed in chunks, and transcription appears in real-time
struct STTView: View {
    @StateObject private var viewModel = STTViewModel()
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if viewModel.isModelDownloaded {
                recordingStateView
            } else {
                downloadStateView
            }
        }
    }
    
    private var downloadStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "mic.fill")
                .font(.system(size: 72))
                .foregroundColor(AppTheme.accent)
            
            Text("Speech-to-Text")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Text("Download whisper-tiny.en (77 MB) to enable\non-device transcription")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if viewModel.isDownloading {
                VStack(spacing: 12) {
                    ProgressView(value: viewModel.downloadProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.accent))
                        .frame(width: 240)
                    
                    Text("\(Int(viewModel.downloadProgress * 100))%")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
            } else {
                Button(action: {
                    Task {
                        await viewModel.downloadModel()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                        Text("Download Model")
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                }
                .appButton()
            }
            
            Spacer()
        }
    }
    
    private var recordingStateView: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                Text("Speech-to-Text")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Copy button
                if !viewModel.transcript.isEmpty {
                    Button(action: viewModel.copyTranscript) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                
                // Clear button
                if !viewModel.segments.isEmpty && !viewModel.isRecording {
                    Button(action: viewModel.clearTranscript) {
                        Image(systemName: "trash")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .background(AppTheme.border)
            
            // Transcript area
            if viewModel.segments.isEmpty && !viewModel.isRecording {
                emptyTranscriptView
            } else if viewModel.segments.isEmpty && viewModel.isRecording {
                listeningIndicatorView
            } else {
                segmentListView
            }
            
            // Controls
            controlsView
        }
    }
    
    private var emptyTranscriptView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "mic")
                .font(.system(size: 64))
                .foregroundColor(AppTheme.border)
            
            Text("Tap to start recording")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textTertiary)
            
            Text("Audio is processed entirely on your device")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
            
            Spacer()
        }
    }
    
    private var listeningIndicatorView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            PulsingMicIcon()
            
            Text("Listening...")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textSecondary)
            
            Text("Transcription will appear shortly")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
            
            Spacer()
        }
    }
    
    private var segmentListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.segments) { segment in
                    SegmentRow(segment: segment)
                }
            }
            .padding(16)
        }
    }
    
    private var controlsView: some View {
        VStack(spacing: 12) {
            Divider()
                .background(AppTheme.border)
            
            // Recording status
            if viewModel.isRecording {
                HStack(spacing: 8) {
                    PulsingDot()
                    Text("Recording  \(viewModel.formattedDuration)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.brandRed)
                }
                .padding(.top, 8)
            }
            
            if viewModel.isInitializing {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                        .scaleEffect(0.8)
                    Text("Loading whisper model...")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.top, 8)
            }
            
            // Mic button
            Button(action: {
                Task {
                    if viewModel.isRecording {
                        await viewModel.stopRecording()
                    } else {
                        await viewModel.startRecording()
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? AppTheme.brandRed : AppTheme.accent)
                        .frame(width: 72, height: 72)
                        .shadow(
                            color: (viewModel.isRecording ? AppTheme.brandRed : AppTheme.accent).opacity(0.4),
                            radius: viewModel.isRecording ? 20 : 12,
                            x: 0,
                            y: 0
                        )
                    
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(viewModel.isRecording ? .white : Color.black)
                }
            }
            .disabled(viewModel.isInitializing)
            
            Text(viewModel.isRecording ? "Tap to stop" : (viewModel.isInitializing ? "" : "Tap to start recording"))
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
            
            Spacer()
                .frame(height: 20)
        }
        .background(Color.black)
    }
}

// MARK: - Segment Row

struct SegmentRow: View {
    let segment: TranscriptSegment
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timestamp
            Text(segment.formattedTimeRange)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.accent.opacity(0.12))
                )
            
            // Text
            Text(segment.text.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 14))
                .foregroundColor(.white)
                .lineLimit(nil)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Pulsing Mic Icon

struct PulsingMicIcon: View {
    @State private var isPulsing = false
    
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 48))
            .foregroundColor(AppTheme.accent)
            .opacity(isPulsing ? 0.3 : 0.7)
            .animation(
                Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Transcript Segment Model

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let startMs: Int64
    let endMs: Int64
    
    var formattedTimeRange: String {
        "\(formatTimestamp(startMs)) - \(formatTimestamp(endMs))"
    }
    
    private func formatTimestamp(_ ms: Int64) -> String {
        let seconds = Double(ms) / 1000.0
        return String(format: "%.1fs", seconds)
    }
}

// MARK: - STT View Model

@MainActor
class STTViewModel: NSObject, ObservableObject {
    // Model state
    @Published var isModelDownloaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    
    // Recording state
    @Published var isRecording = false
    @Published var isInitializing = false
    @Published var transcript = ""
    @Published var segments: [TranscriptSegment] = []
    @Published var recordingDuration: TimeInterval = 0
    
    // Audio engine
    private var audioEngine: AVAudioEngine?
    private var whisperWorker: WhisperWorker?
    private var modelManager = ModelManager()
    
    // Recording tracking
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var audioBuffer: [Float] = []
    private let processingInterval: TimeInterval = 3.0 // Process every 3 seconds
    private var lastProcessTime: Date?
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    override init() {
        super.init()
        checkModel()
    }
    
    private func checkModel() {
        let modelName = "whisper-tiny-en-ggml"
        isModelDownloaded = modelManager.isModelDownloaded(modelName)
    }
    
    func downloadModel() async {
        isDownloading = true
        downloadProgress = 0.0
        
        let modelName = "whisper-tiny-en-ggml"
        
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                modelManager.downloadModel(modelName) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                } completion: { result in
                    continuation.resume(with: result)
                }
            }
            
            isDownloading = false
            isModelDownloaded = true
        } catch {
            isDownloading = false
            print("Download failed: \(error)")
        }
    }
    
    func startRecording() async {
        // Request microphone permission
        let status = await requestMicrophonePermission()
        guard status == .authorized else {
            print("Microphone permission denied")
            return
        }
        
        isInitializing = true
        
        do {
            // Get model path
            let modelName = "whisper-tiny-en-ggml"
            guard let modelPath = modelManager.getModelPath(modelName) else {
                throw NSError(domain: "STTView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model path not found"])
            }
            
            // Initialize whisper worker
            let worker = WhisperWorker()
            let config = WhisperConfig(
                modelPath: modelPath,
                threads: 4,
                contextSize: 448,
                gpuLayers: 0,
                useMemoryMapping: true
            )
            try await worker.initialize(config: config)
            self.whisperWorker = worker
            
            // Initialize audio engine
            try initializeAudioEngine()
            
            isInitializing = false
            isRecording = true
            recordingStartTime = Date()
            audioBuffer = []
            
            // Start duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                Task { @MainActor in
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                }
            }
            
            // Start audio engine
            try audioEngine?.start()
            
        } catch {
            isInitializing = false
            print("Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() async {
        durationTimer?.invalidate()
        durationTimer = nil
        
        audioEngine?.stop()
        audioEngine = nil
        
        // Process any remaining audio
        if !audioBuffer.isEmpty {
            await processAudioBuffer()
        }
        
        await whisperWorker?.cleanup()
        whisperWorker = nil
        
        isRecording = false
        recordingDuration = 0
    }
    
    func clearTranscript() {
        segments.removeAll()
        transcript = ""
    }
    
    func copyTranscript() {
        #if os(iOS)
        UIPasteboard.general.string = transcript
        #endif
    }
    
    private func requestMicrophonePermission() async -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted ? .authorized : .denied)
                }
            }
        }
        
        return status
    }
    
    private func initializeAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Convert to 16kHz mono for Whisper
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "STTView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "STTView", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Convert to target format
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate)
            ) else {
                return
            }
            
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if error != nil {
                return
            }
            
            // Extract float samples
            guard let channelData = convertedBuffer.floatChannelData?[0] else {
                return
            }
            
            let frameLength = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            
            Task { @MainActor in
                self.audioBuffer.append(contentsOf: samples)
                
                // Process buffer every 3 seconds
                let now = Date()
                if let lastTime = self.lastProcessTime {
                    if now.timeIntervalSince(lastTime) >= self.processingInterval {
                        await self.processAudioBuffer()
                        self.lastProcessTime = now
                    }
                } else {
                    self.lastProcessTime = now
                }
            }
        }
        
        self.audioEngine = engine
    }
    
    private func processAudioBuffer() async {
        guard !audioBuffer.isEmpty, let worker = whisperWorker else { return }
        
        let bufferCopy = audioBuffer
        audioBuffer.removeAll()
        
        do {
            let params = WhisperParams(language: "en", threads: 4)
            let result = try await worker.transcribe(audioData: bufferCopy, params: params)
            
            // Add new segments
            for segment in result.segments {
                let transcriptSegment = TranscriptSegment(
                    text: segment.text,
                    startMs: segment.startTime,
                    endMs: segment.endTime
                )
                segments.append(transcriptSegment)
            }
            
            // Update full transcript
            transcript = segments.map { $0.text }.joined(separator: " ")
            
        } catch {
            print("Transcription error: \(error)")
        }
    }
}