import SwiftUI
import AVFoundation

struct LiveBroadcastView: View {
    let stream: SupabaseManager.DBLiveStream
    @Environment(\.dismiss) private var dismiss
    @State private var isLive: Bool = false
    @State private var viewers: Int = 0
    @State private var ending: Bool = false
    @State private var errorText: String? = nil
    @StateObject private var supa = SupabaseManager.shared
    @StateObject private var publisher = LiveKitPublisher()

    var body: some View {
        ZStack {
            ZStack {
                // LiveKit local camera preview
                Color.black.ignoresSafeArea()
                if let track = publisher.localVideoTrack {
                    LKVideoView(track: track)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "video.fill").font(.system(size: 50)).foregroundStyle(.white.opacity(0.8))
                        Text("Initializing camera…").foregroundStyle(.white.opacity(0.9))
                    }
                }
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding()
        }
        .onAppear { Task { await goLiveIfNeeded() } }
        .alert("End Live Stream?", isPresented: $ending) {
            Button("End Live", role: .destructive) { Task { await endLive() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to end the live stream?") }
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(isLive ? .red : .gray).frame(width: 8, height: 8)
                Text(isLive ? "LIVE" : stream.status.uppercased())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(viewers) viewers")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())

            Spacer()

            Button { ending = true } label: {
                Text("End")
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
        HStack(spacing: 12) {
            Button { Task { await publisher.toggleMic() } } label: {
                Image(systemName: publisher.micOn ? "mic.fill" : "mic.slash.fill")
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button { Task { await publisher.toggleCamera() } } label: {
                Image(systemName: publisher.cameraOn ? "camera.fill" : "camera")
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer()

            Button { /* gifts sheet */ } label: {
                Image(systemName: "gift.fill").foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.bottom, 24)
    }

    private func goLiveIfNeeded() async {
        guard !isLive else { return }
        guard let token = stream.token else { await MainActor.run { errorText = "Missing LiveKit token" }; return }
        // Ensure LiveKit URL is configured
        if SupabaseConfig.livekitURL.host?.contains("your-livekit-host.example") == true {
            await MainActor.run { errorText = "Set SupabaseConfig.livekitURL to your LiveKit server (e.g., wss://yourdomain.livekit.cloud)" }
            return
        }
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            // Mark live in DB
            _ = try await supa.updateLiveSession(id: stream.id, updates: ["status": "live", "started_at": iso])
            // Connect to LiveKit and publish camera+mic
            try await publisher.connectAndPublish(url: SupabaseConfig.livekitURL, token: token)
            await MainActor.run { isLive = true }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }

    private func endLive() async {
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            // Disconnect from LiveKit and mark ended
            await publisher.disconnect()
            _ = try await supa.updateLiveSession(id: stream.id, updates: ["status": "ended", "ended_at": iso])
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }
}

#Preview {
    LiveBroadcastView(stream: .init(id: UUID().uuidString, host_id: UUID().uuidString, title: "My Stream", description: "", status: "scheduled", viewer_count: 0, started_at: nil, ended_at: nil, token: "tok"))
}
