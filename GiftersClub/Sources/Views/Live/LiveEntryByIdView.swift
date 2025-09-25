import SwiftUI

struct LiveEntryByIdView: View {
    let liveId: String
    var startManagePanel: Bool = false
    var setupMatch: Bool = false
    @ObservedObject private var supa = SupabaseManager.shared
    @State private var stream: SupabaseManager.DBLiveStream? = nil
    @State private var error: String? = nil

    var body: some View {
        Group {
            if let s = stream {
                if supa.user?.id.uuidString == s.host_id {
                    LiveBroadcastView(stream: s, startManagePanel: startManagePanel)
                        .onAppear {
                            if startManagePanel {
                                NotificationCenter.default.post(name: .hideBottomBar, object: nil)
                            }
                        }
                } else {
                    LiveViewerRouteWrapper(liveId: s.id)
                }
            } else if let e = error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(e).font(.subheadline).multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ProgressView("Loading live…")
                    .task { await load() }
            }
        }
    }

    private func load() async {
        do {
            // Edge function returns stream + token for current user role
            let s = try await supa.fetchLiveSession(liveId)
            await MainActor.run { stream = s }
        } catch {
            await MainActor.run { self.error = (error as NSError).localizedDescription }
        }
    }
}

/// Wraps viewer by fetching minimal stats row
private struct LiveViewerRouteWrapper: View {
    let liveId: String
    @ObservedObject private var supa = SupabaseManager.shared
    @State private var row: SupabaseManager.DBLiveStreamWithStats? = nil
    @State private var error: String? = nil
    var body: some View {
        Group {
            if let r = row { LiveViewerView(live: r) }
            else if let e = error { Text(e).padding() }
            else { ProgressView("Loading…").task { await load() } }
        }
    }
    private func load() async {
        do {
            // Build minimal WithStats from base row
            if let s = try await supa.fetchLiveStreamById(liveId) {
                let v = SupabaseManager.DBLiveStreamWithStats(
                    id: s.id, host_id: s.host_id, title: s.title, description: s.description,
                    status: s.status, started_at: s.started_at, ended_at: s.ended_at,
                    viewer_count: s.viewer_count, comment_count: nil, gift_count: nil,
                    tokens_received: nil, thumbnail_url: nil, stream_score: nil,
                    access_type: s.access_type, price: s.price, required_plan_id: s.required_plan_id
                )
                await MainActor.run { row = v }
            } else {
                await MainActor.run { error = "Live not found" }
            }
        } catch let err {
            await MainActor.run { self.error = (err as NSError).localizedDescription }
        }
    }
}
