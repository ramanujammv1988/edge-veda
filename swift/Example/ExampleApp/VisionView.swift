import SwiftUI
import AVFoundation
import EdgeVeda

/// Vision tab with continuous camera scanning and description overlay
///
/// Uses VisionWorker for on-device image description with SmolVLM2
/// Implements a Google Lens-style continuous scanning UX
struct VisionView: View {
    @StateObject private var viewModel = VisionViewModel()
    
    var body: some View {
        ZStack {
            // Full-screen camera preview
            if viewModel.isVisionReady {
                CameraPreview(session: viewModel.captureSession)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }
            
            VStack {
                Spacer()
                
                // Description overlay at bottom (AR-style)
                if let description = viewModel.currentDescription, !description.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        // Pulsing indicator when processing
                        if viewModel.isProcessing {
                            PulsingDot()
                        }
                        
                        Text(description)
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            .lineLimit(nil)
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.surface.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.border.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            
            // Loading/download overlay
            if !viewModel.isVisionReady {
                LoadingOverlay(
                    message: viewModel.statusMessage,
                    progress: viewModel.downloadProgress,
                    isDownloading: viewModel.isDownloading
                )
            }
            
            // Error overlay
            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.brandRed)
                        Text(error)
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.surface)
                    )
                    .padding(16)
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.initialize()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(AppTheme.accent)
            .frame(width: 10, height: 10)
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String
    let progress: Double
    let isDownloading: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.87)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                if isDownloading {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 64))
                        .foregroundColor(.white.opacity(0.7))
                    
                    if progress > 0 {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.accent))
                            .frame(width: 240)
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Vision View Model

@MainActor
class VisionViewModel: NSObject, ObservableObject {
    // Vision state
    @Published var isVisionReady = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage = "Preparing vision..."
    @Published var currentDescription: String?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    
    // Camera
    let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    
    // Vision worker
    private var visionWorker: VisionWorker?
    private var modelManager = ModelManager()
    
    // Model paths
    private var modelPath: String?
    private var mmprojPath: String?
    
    // Frame throttling
    private var lastProcessTime: Date?
    private let minFrameInterval: TimeInterval = 2.0 // Process every 2 seconds
    
    override init() {
        super.init()
    }
    
    func initialize() async {
        do {
            // Step 1: Request camera permission
            let status = await requestCameraPermission()
            guard status == .authorized else {
                statusMessage = "Camera permission denied"
                errorMessage = "Please enable camera access in Settings"
                return
            }
            
            // Step 2: Download vision models if needed
            statusMessage = "Checking vision models..."
            try await ensureModelsDownloaded()
            
            // Step 3: Initialize camera
            statusMessage = "Initializing camera..."
            try await initializeCamera()
            
            // Step 4: Initialize vision worker
            statusMessage = "Loading vision model..."
            try await initializeVisionWorker()
            
            statusMessage = "Vision ready"
            isVisionReady = true
            
            // Step 5: Start capturing frames
            startCameraSession()
            
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            errorMessage = error.localizedDescription
        }
    }
    
    func cleanup() {
        stopCameraSession()
        
        Task {
            await visionWorker?.cleanup()
            visionWorker = nil
        }
    }
    
    private func requestCameraPermission() async -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted ? .authorized : .denied)
                }
            }
        }
        
        return status
    }
    
    private func ensureModelsDownloaded() async throws {
        // For SmolVLM2-500M model (vision)
        let modelName = "smolvlm2-500m-gguf"
        let mmprojName = "smolvlm2-500m-mmproj-gguf"
        
        let modelDownloaded = modelManager.isModelDownloaded(modelName)
        let mmprojDownloaded = modelManager.isModelDownloaded(mmprojName)
        
        if !modelDownloaded || !mmprojDownloaded {
            isDownloading = true
            
            if !modelDownloaded {
                statusMessage = "Downloading vision model (500MB)..."
                modelPath = try await withCheckedThrowingContinuation { continuation in
                    modelManager.downloadModel(modelName) { progress in
                        Task { @MainActor in
                            self.downloadProgress = progress
                            self.statusMessage = "Downloading: \(Int(progress * 100))%"
                        }
                    } completion: { result in
                        continuation.resume(with: result)
                    }
                }
            } else {
                modelPath = modelManager.getModelPath(modelName)
            }
            
            if !mmprojDownloaded {
                statusMessage = "Downloading mmproj..."
                mmprojPath = try await withCheckedThrowingContinuation { continuation in
                    modelManager.downloadModel(mmprojName) { progress in
                        Task { @MainActor in
                            self.downloadProgress = progress
                            self.statusMessage = "Downloading mmproj: \(Int(progress * 100))%"
                        }
                    } completion: { result in
                        continuation.resume(with: result)
                    }
                }
            } else {
                mmprojPath = modelManager.getModelPath(mmprojName)
            }
            
            isDownloading = false
        } else {
            modelPath = modelManager.getModelPath(modelName)
            mmprojPath = modelManager.getModelPath(mmprojName)
        }
    }
    
    private func initializeCamera() async throws {
        captureSession.beginConfiguration()
        
        // Set session preset
        if captureSession.canSetSessionPreset(.medium) {
            captureSession.sessionPreset = .medium
        }
        
        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "VisionView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera available"])
        }
        
        let input = try AVCaptureDeviceInput(device: camera)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        // Add video output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.processing"))
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoOutput = output
        }
        
        captureSession.commitConfiguration()
    }
    
    private func initializeVisionWorker() async throws {
        guard let modelPath = modelPath, let mmprojPath = mmprojPath else {
            throw NSError(domain: "VisionView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model paths not set"])
        }
        
        let worker = VisionWorker()
        
        let config = VisionConfig(
            modelPath: modelPath,
            mmprojPath: mmprojPath,
            numThreads: 4,
            contextSize: 4096,
            gpuLayers: 999, // Use GPU
            batchSize: 512,
            useMmap: true
        )
        
        try await worker.initialize(config: config)
        self.visionWorker = worker
    }
    
    private func startCameraSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    private func stopCameraSession() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VisionViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Throttle frame processing
        let now = Date()
        if let lastTime = lastProcessTime, now.timeIntervalSince(lastTime) < minFrameInterval {
            return
        }
        
        Task { @MainActor in
            self.lastProcessTime = now
            await processFrame(sampleBuffer)
        }
    }
    
    private func processFrame(_ sampleBuffer: CMSampleBuffer) async {
        guard let visionWorker = visionWorker else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        isProcessing = true
        
        do {
            // Convert pixel buffer to RGB data
            let (rgbData, width, height) = try convertToRGB(pixelBuffer: pixelBuffer)
            
            // Describe the frame
            let result = try await visionWorker.describeFrame(
                rgb: rgbData,
                width: width,
                height: height,
                prompt: "Describe what you see in this image in one sentence.",
                params: VisionGenerationParams(
                    maxTokens: 100,
                    temperature: 0.7,
                    topP: 0.9,
                    topK: 40,
                    repeatPenalty: 1.1
                )
            )
            
            currentDescription = result.description
            
        } catch {
            print("Vision processing error: \(error)")
            errorMessage = "Processing error: \(error.localizedDescription)"
            
            // Clear error after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                errorMessage = nil
            }
        }
        
        isProcessing = false
    }
    
    private func convertToRGB(pixelBuffer: CVPixelBuffer) throws -> (Data, Int, Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "VisionView", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel buffer base address"])
        }
        
        // Convert BGRA to RGB
        var rgbData = Data(count: width * height * 3)
        
        rgbData.withUnsafeMutableBytes { rgbPtr in
            let bgraPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
            var rgbIndex = 0
            
            for y in 0..<height {
                let rowStart = y * bytesPerRow
                for x in 0..<width {
                    let bgraIndex = rowStart + x * 4
                    let b = bgraPtr[bgraIndex]
                    let g = bgraPtr[bgraIndex + 1]
                    let r = bgraPtr[bgraIndex + 2]
                    // Skip alpha channel (index + 3)
                    
                    rgbPtr[rgbIndex] = r
                    rgbPtr[rgbIndex + 1] = g
                    rgbPtr[rgbIndex + 2] = b
                    rgbIndex += 3
                }
            }
        }
        
        return (rgbData, width, height)
    }
}