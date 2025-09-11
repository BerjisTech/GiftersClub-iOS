import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

final class BeautyFilterPipeline: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private let context = CIContext()
    private let queue = DispatchQueue(label: "beauty.filter.pipeline")
    private let videoOutput = AVCaptureVideoDataOutput()
    @Published var latestImage: CGImage?

    func start() {
        guard session.inputs.isEmpty else { session.startRunning(); return }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if let conn = videoOutput.connection(with: .video), conn.isVideoMirroringSupported { conn.isVideoMirrored = true }
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() { session.stopRunning() }

    private func process(pixelBuffer pb: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        // Simple chain: slight smoothing + color tweak
        let noise = CIFilter.noiseReduction()
        noise.inputImage = ci
        noise.noiseLevel = 0.02
        noise.sharpness = 0.4
        let color = CIFilter.colorControls()
        color.inputImage = noise.outputImage
        color.saturation = 1.05
        color.brightness = 0.02
        color.contrast = 1.03
        guard let out = color.outputImage,
              let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return cg
    }
}

extension BeautyFilterPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let cg = process(pixelBuffer: pb) {
            DispatchQueue.main.async { self.latestImage = cg }
        }
    }
}

struct BeautyPreviewView: View {
    @ObservedObject var pipeline: BeautyFilterPipeline
    var body: some View {
        Group {
            if let img = pipeline.latestImage { Image(decorative: img, scale: 1.0, orientation: .upMirrored).resizable().scaledToFill() }
            else { Color.black }
        }
        .clipped()
    }
}

