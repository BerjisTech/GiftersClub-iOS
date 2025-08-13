import SwiftUI
import AVFoundation

public struct VideoThumbnail: View {
    let url: URL
    @State private var image: UIImage? = nil
    public init(url: URL) { self.url = url }
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black.opacity(0.8)
                }
            }
        }
        .task { await generate() }
    }
    private func generate() async {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                if let cg { Task { await MainActor.run { image = UIImage(cgImage: cg) } } }
                continuation.resume()
            }
        }
    }
}

