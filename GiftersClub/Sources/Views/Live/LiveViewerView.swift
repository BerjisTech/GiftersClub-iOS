import SwiftUI

struct LiveViewerView: View {
    let live: SupabaseManager.DBLiveStreamWithStats
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewer = LiveKitViewer()
    @StateObject private var supa = SupabaseManager.shared
    @State private var errorText: String? = nil
    @State private var loading: Bool = true

    var body: some View {
        ZStack {
            if let track = viewer.remoteVideoTrack {
                LKVideoView(track: track)
                    .ignoresSafeArea()
            } else {
                // Fallback: thumbnail overlay until video subscribed
                ZStack {
                    if let t = live.thumbnail_url, let url = URL(string: t) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.black }
                    } else { Color.black }
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding()
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .task { await join() }
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("LIVE")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Label("\(live.viewer_count ?? 0)", systemImage: "eye.fill")
                    .foregroundStyle(.white.opacity(0.9))
                    .font(.footnote)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())

            Spacer()

            Button { Task { await viewer.disconnect(); dismiss() } } label: {
                Text("Close")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            // Placeholder for chat/gifts; future overlays here.
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func join() async {
        loading = true
        defer { Task { await MainActor.run { loading = false } } }
        do {
            let token = try await supa.fetchLiveViewerToken(streamId: live.id)
            try await viewer.connect(url: SupabaseConfig.livekitURL, token: token)
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }
}
