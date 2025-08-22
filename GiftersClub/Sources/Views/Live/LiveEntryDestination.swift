import SwiftUI

struct LiveEntryDestination: View {
    let live: SupabaseManager.DBLiveStreamWithStats
    @ObservedObject private var supa = SupabaseManager.shared
    var body: some View {
        if supa.user?.id.uuidString == live.host_id {
            LiveHostEntryView(liveId: live.id)
        } else {
            LiveViewerView(live: live)
        }
    }
}

private struct LiveHostEntryView: View {
    let liveId: String
    @ObservedObject private var supa = SupabaseManager.shared
    @State private var stream: SupabaseManager.DBLiveStream? = nil
    @State private var error: String? = nil
    var body: some View {
        Group {
            if let s = stream {
                LiveBroadcastView(stream: s)
            } else if let e = error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(e).font(.subheadline).multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ProgressView("Preparing host view…")
                    .task { await load() }
            }
        }
    }
    private func load() async {
        do {
            let s = try await supa.fetchLiveSession(liveId)
            await MainActor.run { stream = s }
        } catch {
            await MainActor.run { self.error = (error as NSError).localizedDescription }
        }
    }
}

