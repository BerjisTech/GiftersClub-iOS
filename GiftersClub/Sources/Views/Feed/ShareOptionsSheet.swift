import SwiftUI
import UIKit

struct ShareOptionsSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var presentSystemShare = false

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 36, height: 5).padding(.top, 8)
            Text("Share").font(.headline)
            VStack(spacing: 12) {
                Button(action: { presentSystemShare = true }) {
                    HStack { Image(systemName: "square.and.arrow.up"); Text("Share..."); Spacer() }
                }
                .buttonStyle(.bordered)
                Button(action: copy) {
                    HStack { Image(systemName: "link"); Text("Copy Link"); Spacer() }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $presentSystemShare) {
            ActivityView(activityItems: [url])
        }
        .presentationDetents([.height(180), .medium])
        .sheetStyleCompat()
    }

    private func copy() {
        UIPasteboard.general.url = url
        dismiss()
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
