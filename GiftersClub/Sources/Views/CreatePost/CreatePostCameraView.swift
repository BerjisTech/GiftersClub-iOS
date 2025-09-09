import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import UIKit

final class CameraController: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    enum Mode { case photo, video }
    enum CameraError: Error { case unavailable }

    @Published var isRunning = false
    @Published var isRecording = false
    @Published var mode: Mode = .photo
    @Published var zoomFactor: CGFloat = 1.0
    @Published var flashOn: Bool = false
    @Published var previewImage: UIImage? = nil
    @Published var isAvailable: Bool = false

    // Live filter support
    enum CameraFilter: String, CaseIterable { case none = "None", mono = "Mono", sepia = "Sepia", vivid = "Vivid" }
    @Published var currentFilter: CameraFilter = .none
    @Published var filterIntensity: Double = 1.0
    private let ciContext = CIContext()

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var captureCompletion: ((Result<Captured, Error>) -> Void)?

    struct Captured {
        let data: Data
        let mime: String
        let isVideo: Bool
    }

    override init() {
        super.init()
        configureSession()
    }

    func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        // input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { self.isAvailable = false; session.commitConfiguration(); return }
        session.addInput(input)
        self.videoDeviceInput = input
        self.isAvailable = true
        // outputs
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        // Video data output for live filter preview (photo pipeline)
        if session.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.queue"))
            session.addOutput(videoDataOutput)
        }
        session.commitConfiguration()
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        session.stopRunning()
        isRunning = false
    }

    func switchCamera() {
        currentPosition = currentPosition == .back ? .front : .back
        session.beginConfiguration()
        if let input = videoDeviceInput { session.removeInput(input) }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }
        session.commitConfiguration()
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let clamped = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.zoomFactor = clamped }
        } catch { }
    }

    func toggleTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on { device.torchMode = .off } else { try device.setTorchModeOn(level: 1.0) }
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.flashOn = device.torchMode == .on }
        } catch { }
    }

    func capturePhoto(delay: TimeInterval = 0, completion: @escaping (Result<Captured, Error>) -> Void) {
        // Ensure there is an active video connection
        guard session.isRunning, photoOutput.connection(with: .video)?.isEnabled == true else {
            completion(.failure(CameraError.unavailable)); return
        }
        self.captureCompletion = completion
        let work = { [weak self] in
            guard let self else { return }
            // Align orientation and mirroring for photo capture
            if let conn = self.photoOutput.connection(with: .video) {
                conn.videoOrientation = AVCaptureVideoOrientation.currentInterfaceOrientation
                conn.isVideoMirrored = (self.currentPosition == .front)
            }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = self.flashOn ? .on : .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) } else { work() }
    }

    func startRecording(maxDuration: TimeInterval?, completion: @escaping (Result<Captured, Error>) -> Void) {
        guard session.isRunning, !movieOutput.isRecording else { return }
        self.captureCompletion = completion
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mp4")
        if let conn = movieOutput.connection(with: .video) {
            conn.videoOrientation = AVCaptureVideoOrientation.currentInterfaceOrientation
            conn.isVideoMirrored = (currentPosition == .front)
        }
        if let max = maxDuration { movieOutput.maxRecordedDuration = CMTime(seconds: max, preferredTimescale: 1) }
        movieOutput.startRecording(to: tmp, recordingDelegate: self)
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording() { if movieOutput.isRecording { movieOutput.stopRecording() } }

    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.isRecording = false }
        if let error { captureCompletion?(.failure(error)); captureCompletion = nil; return }
        if let data = try? Data(contentsOf: outputFileURL) {
            captureCompletion?(.success(Captured(data: data, mime: "video/mp4", isVideo: true)))
            captureCompletion = nil
        }
        try? FileManager.default.removeItem(at: outputFileURL)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { captureCompletion?(.failure(error)); captureCompletion = nil; return }
        guard let data = photo.fileDataRepresentation() else { return }
        // Apply selected filter to captured photo if needed
        if currentFilter != .none, let ui = UIImage(data: data), let filtered = Self.applyFilter(currentFilter, intensity: filterIntensity, to: ui, context: ciContext), let outData = filtered.jpegData(compressionQuality: 0.9) {
            captureCompletion?(.success(Captured(data: outData, mime: "image/jpeg", isVideo: false)))
        } else {
            captureCompletion?(.success(Captured(data: data, mime: "image/jpeg", isVideo: false)))
        }
        captureCompletion = nil
    }
    private static func applyFilter(_ filter: CameraController.CameraFilter, intensity: Double, to image: UIImage, context: CIContext) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cg)
        let output: CIImage?
        switch filter {
        case .none:
            output = ciImage
        case .mono:
            output = CIFilter.photoEffectNoir().apply(to: ciImage)
        case .sepia:
            let f = CIFilter.sepiaTone()
            f.inputImage = ciImage
            f.intensity = Float(max(0.0, min(1.0, intensity)))
            output = f.outputImage
        case .vivid:
            output = CIFilter.photoEffectProcess().apply(to: ciImage)
        }
        guard let out = output, let cgimg = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cgimg, scale: image.scale, orientation: image.imageOrientation)
    }
}

extension CIFilter {
    func apply(to input: CIImage) -> CIImage? {
        setValue(input, forKey: kCIInputImageKey)
        return outputImage
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvImageBuffer: buffer)
        // Mirror front camera for preview to feel natural
        if currentPosition == .front { image = image.oriented(.upMirrored) }
        if currentFilter != .none {
            switch currentFilter {
            case .none: break
            case .mono:
                image = CIFilter.photoEffectNoir().apply(to: image) ?? image
            case .sepia:
                let f = CIFilter.sepiaTone(); f.inputImage = image; f.intensity = Float(max(0, min(1, filterIntensity))); image = f.outputImage ?? image
            case .vivid:
                image = CIFilter.photoEffectProcess().apply(to: image) ?? image
            }
        }
        if let cg = ciContext.createCGImage(image, from: image.extent) {
            let ui = UIImage(cgImage: cg)
            DispatchQueue.main.async { self.previewImage = ui }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView { PreviewView(session: session) }
    func updateUIView(_ uiView: UIView, context: Context) {}

    final class PreviewView: UIView {
        private let layerView = AVCaptureVideoPreviewLayer()
        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            layerView.session = session
            layerView.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layerView)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            layerView.frame = bounds
            if let conn = layerView.connection, conn.isVideoOrientationSupported {
                conn.videoOrientation = AVCaptureVideoOrientation.currentInterfaceOrientation
            }
        }
    }
}

struct CreatePostCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @StateObject private var vm = CreatePostViewModel()
    @State private var showDetails = false
    @State private var selectedTimer: TimeInterval? = nil // seconds or minutes
    @State private var isVideoMode = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var alertText: String? = nil
    enum ActiveSheet: Identifiable { case details, textEditor, timer; var id: Int { hashValue } }
    @State private var activeSheet: ActiveSheet? = nil

    var body: some View {
        ZStack {
            // Use filtered preview image when a filter is selected; otherwise use camera preview layer
            Group {
                if camera.currentFilter == .none, camera.previewImage == nil {
                    CameraPreview(session: cameraSession)
                } else if let img = camera.previewImage {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    CameraPreview(session: cameraSession)
                }
            }
            .ignoresSafeArea()
            .gesture(magnification)

            // Top gradient for legibility on real devices
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Unavailable camera (Simulator/permissions denied) helper overlay
            if !camera.isAvailable {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Camera not available")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Use Library or Text Post on Simulator.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Open Library") { DispatchQueue.main.async { activeSheet = .details } }
                            .buttonStyle(.borderedProminent)
                        Button("Text Post") { DispatchQueue.main.async { activeSheet = .textEditor } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            // Top overlay: left cancel + right controls
            VStack {
                HStack(alignment: .top) {
                    // Top-left cancel/back
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                            .accessibilityLabel("Close")
                    }
                    .padding(.leading, 12)
                    .padding(.top, 12)

                    Spacer()

                    // Top-right vertical controls
                    VStack(spacing: 14) {
                        iconButton(system: "arrow.triangle.2.circlepath.camera") { camera.switchCamera() }
                        iconButton(system: camera.flashOn ? "bolt.fill" : "bolt.slash.fill") { camera.toggleTorch() }
                        iconButton(system: "timer") { DispatchQueue.main.async { activeSheet = .timer } }
                        iconButton(system: "camera.filters") { /* Advanced filters panel could be implemented here */ }
                    }
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                }
                Spacer()
            }
            .zIndex(1)

            // Bottom overlay with two rows
            VStack(spacing: 10) {
                Spacer()
                VStack(spacing: 12) {
                    // Timer presets (centered)
                    HStack(spacing: 10) {
                        timerItem("5s", 5)
                        timerItem("15s", 15)
                        timerItem("60s", 60)
                        timerItem("10m", 600)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)

                    HStack(alignment: .center) {
                        // Filters scroller (left)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CameraController.CameraFilter.allCases, id: \.self) { f in
                                    Text(f.rawValue)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(camera.currentFilter == f ? Color.white.opacity(0.35) : Color.white.opacity(0.15))
                                        .clipShape(Capsule())
                                        .onTapGesture { camera.currentFilter = f }
                                }
                            }
                        }
                        .frame(width: 140)

                        Spacer(minLength: 0)

                        // Capture button (center)
                        ZStack {
                            Circle().fill(Color.white.opacity(0.18)).frame(width: 88, height: 88)
                            Circle().fill(Color.white).frame(width: 72, height: 72)
                            if camera.isRecording {
                                Circle().fill(Color.red).frame(width: 32, height: 32)
                            }
                        }
                        .contentShape(Circle())
                        .onTapGesture { handleTapCapture() }
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.3).onEnded { _ in handleLongPressCapture() })

                        Spacer(minLength: 0)

                        // Right icon row: toggle mode, text, library
                        HStack(spacing: 16) {
                            iconButton(system: isVideoMode ? "camera.fill" : "video.fill") {
                                isVideoMode.toggle(); camera.mode = isVideoMode ? .video : .photo
                            }
                            iconButton(system: "textformat") { DispatchQueue.main.async { activeSheet = .textEditor } }
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .any(of: [.images, .videos])) {
                                Image(systemName: "photo.on.rectangle").font(.title3).foregroundStyle(.white)
                            }
                            .onChange(of: pickerItems, perform: { newItems in
                                Task {
                                    var loaded: [CreatePostViewModel.MediaItem] = []
                                    for item in newItems {
                                        if let data = try? await item.loadTransferable(type: Data.self) {
                                            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream"
                                            let kind: CreatePostViewModel.MediaItem.Kind = mime.hasPrefix("video/") ? .video : .photo
                                            loaded.append(.init(data: data, mime: mime, kind: kind))
                                        }
                                    }
                                    await MainActor.run { vm.media = loaded; activeSheet = .details }
                                }
                            })
                        }
                        .frame(width: 140)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
                .zIndex(1)
            }
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { camera.start() }
            }
        }
        .onDisappear { camera.stop() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .details:
                CreatePostSheet(vm: vm, initial: .details)
            case .textEditor:
                CreatePostSheet(vm: vm, initial: .textEditor)
            case .timer:
                TimerPickerSheet(seconds: Int(selectedTimer ?? 0)) { value in selectedTimer = value == 0 ? nil : TimeInterval(value) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Camera", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertText ?? "") }
    }

    private var cameraSession: AVCaptureSession { camera.session }

    // MARK: - Gestures and actions
    private var magnification: some Gesture {
        MagnificationGesture().onChanged { value in
            let target = min(max(1.0, value), 8.0)
            camera.setZoom(target)
        }
    }

    private func handleTapCapture() {
        if isVideoMode {
            if camera.isRecording { camera.stopRecording() } else {
                camera.startRecording(maxDuration: selectedTimer) { result in
                    switch result {
                    case .success(let cap):
                        vm.media = [CreatePostViewModel.MediaItem(data: cap.data, mime: cap.mime, kind: .video)]
                        activeSheet = .details
                    case .failure:
                        alertText = "Camera unavailable. Try selecting from library."
                    }
                }
            }
        } else {
            let delay = selectedTimer ?? 0
            camera.capturePhoto(delay: delay) { result in
                switch result {
                case .success(let cap):
                    vm.media = [CreatePostViewModel.MediaItem(data: cap.data, mime: cap.mime, kind: .photo)]
                    activeSheet = .details
                case .failure:
                    alertText = "Camera unavailable. Try selecting from library."
                }
            }
        }
    }

    private func handleLongPressCapture() {
        if !isVideoMode {
            camera.startRecording(maxDuration: selectedTimer) { result in
                switch result {
                case .success(let cap):
                    vm.media = [CreatePostViewModel.MediaItem(data: cap.data, mime: cap.mime, kind: .video)]
                    activeSheet = .details
                case .failure:
                    alertText = "Camera unavailable. Try selecting from library."
                }
            }
        }
    }

    private func iconButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
    }

    private func timerItem(_ label: String, _ seconds: TimeInterval) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background((selectedTimer ?? 0) == seconds ? Color.white.opacity(0.25) : Color.white.opacity(0.12))
            .clipShape(Capsule())
            .onTapGesture { selectedTimer = seconds }
    }
}

// MARK: - Timer Picker Sheet
private struct TimerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value: Int
    let onDone: (Int) -> Void
    private let options: [Int] = [0, 5, 10, 15, 30, 60, 120, 300, 600]
    init(seconds: Int, onDone: @escaping (Int) -> Void) {
        self._value = State(initialValue: seconds)
        self.onDone = onDone
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Timer", selection: $value) {
                    ForEach(options, id: \.self) { s in
                        Text(label(for: s)).tag(s)
                    }
                }
            }
            .navigationTitle("Timer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone(value); dismiss() }
                }
            }
        }
        .presentationDetents([.height(240), .medium])
    }
    private func label(for s: Int) -> String {
        if s == 0 { return "Off" }
        if s < 60 { return "\(s)s" }
        let m = s/60
        return "\(m)m"
    }
}
// Helper to map device/interface orientation to AVCaptureVideoOrientation
extension AVCaptureVideoOrientation {
    static var currentInterfaceOrientation: AVCaptureVideoOrientation {
        let orientation: UIInterfaceOrientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first ?? .portrait
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }
}
