import SwiftUI
import AVFoundation
import EdgeVeda

/// Vision screen with continuous camera scanning and description overlay.
///
/// Matches Flutter's VisionScreen: full-screen camera preview,
/// AR-style description overlay at bottom with pulsing dot during inference,
/// and model download overlay on first launch.
@available(iOS 16.0, *)
struct VisionView: View {
    @StateObject private var viewModel = VisionViewModel()

    var body: some View {
        ZStack {
            // Full-screen camera preview
            if viewModel.isCameraReady {
                CameraPreviewView(session: viewModel.captureSession)
                    .ignoresSafeArea()
            } else {
                AppTheme.background.ignoresSafeArea()
            }

            // Description overlay at bottom (AR-style)
            if let description = viewModel.description, !description.isEmpty {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        if viewModel.isProcessing {
                            PulsingDot()
                        }
                        Text(description)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.surface.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.border.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(16)
                }
            }

            // Download/loading overlay
            if viewModel.isDownloading || !viewModel.isVisionReady {
                loadingOverlay
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.87).ignoresSafeArea()

            VStack(spacing: 24) {
                if viewModel.isDownloading {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 64))
                        .foregroundColor(.white.opacity(0.7))

                    ProgressView(value: viewModel.downloadProgress > 0 ? viewModel.downloadProgress : nil)
                        .tint(AppTheme.accent)
                        .frame(width: 240)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white.opacity(0.7))
                }

                Text(viewModel.statusMessage)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        Circle()
            .fill(AppTheme.accent)
            .frame(width: 10, height: 10)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}

// MARK: - Vision View Model

@available(iOS 16.0, *)
@MainActor
class VisionViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let visionWorker = VisionWorker()
    private let frameQueue = FrameQueue()
    private let modelManager = ModelManager()

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.edgeveda.vision.processing")

    @Published var isVisionReady = false
    @Published var isCameraReady = false
    @Published var isDownloading = false
    @Published var isProcessing = false
    @Published var downloadProgress: Double = 0
    @Published var statusMessage = "Preparing vision..."
    @Published var description: String?

    private var modelPath: String?
    private var mmprojPath: String?

    func start() {
        Task { await initializeVision() }
    }

    func stop() {
        captureSession.stopRunning()
        Task { await visionWorker.cleanup() }
    }

    // MARK: - Initialization

    private func initializeVision() async {
        do {
            // Step 1: Download models
            await ensureModelsDownloaded()

            // Step 2: Initialize camera
            statusMessage = "Initializing camera..."
            setupCamera()

            // Step 3: Initialize vision worker
            statusMessage = "Loading vision model..."
            try await visionWorker.initialize(config: VisionConfig(
                modelPath: modelPath!,
                mmprojPath: mmprojPath!,
                threads: 4,
                contextSize: 4096,
                gpuLayers: -1
            ))

            isVisionReady = true
            statusMessage = "Vision ready"

            // Step 4: Start camera
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isDownloading = false
        }
    }

    private func ensureModelsDownloaded() async {
        let model = ModelRegistry.smolvlm2_500m
        let mmproj = ModelRegistry.smolvlm2_500m_mmproj

        do {
            let modelDownloaded = try await modelManager.isModelDownloaded(model.id)
            let mmprojDownloaded = try await modelManager.isModelDownloaded(mmproj.id)

            if !modelDownloaded || !mmprojDownloaded {
                isDownloading = true
                statusMessage = "Downloading vision model..."

                if !modelDownloaded {
                    modelPath = try await modelManager.downloadModel(model) { [weak self] progress in
                        Task { @MainActor in
                            self?.downloadProgress = progress.progress
                            self?.statusMessage = "Downloading: \(progress.progressPercent)%"
                        }
                    }
                } else {
                    modelPath = try await modelManager.getModelPath(model.id)
                }

                if !mmprojDownloaded {
                    mmprojPath = try await modelManager.downloadModel(mmproj) { [weak self] progress in
                        Task { @MainActor in
                            self?.downloadProgress = progress.progress
                        }
                    }
                } else {
                    mmprojPath = try await modelManager.getModelPath(mmproj.id)
                }

                isDownloading = false
            } else {
                modelPath = try await modelManager.getModelPath(model.id)
                mmprojPath = try await modelManager.getModelPath(mmproj.id)
            }
        } catch {
            statusMessage = "Download error: \(error.localizedDescription)"
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            statusMessage = "No camera available"
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        isCameraReady = true
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Convert BGRA to RGB
        let rgb = CameraUtils.convertBgraToRgb(
            Data(bytes: baseAddress, count: bytesPerRow * height),
            width: width,
            height: height
        )

        Task { @MainActor in
            self.frameQueue.enqueue(rgb, width: width, height: height)
            await self.processNextFrame()
        }
    }

    // MARK: - Frame Processing

    private func processNextFrame() async {
        guard let frame = frameQueue.dequeue() else { return }

        isProcessing = true

        do {
            let result = try await visionWorker.describeFrame(
                rgb: frame.rgb,
                width: frame.width,
                height: frame.height,
                prompt: "Describe what you see in this image in one sentence.",
                params: VisionGenerationParams(maxTokens: 100)
            )
            description = result.description
        } catch {
            print("Vision inference error: \(error)")
        }

        frameQueue.markDone()
        isProcessing = false

        // Process next pending frame
        if frameQueue.hasPending {
            await processNextFrame()
        }
    }
}