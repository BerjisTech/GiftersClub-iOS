import SwiftUI
import AVFoundation
import AVFAudio

struct GoLiveSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var categories: [SupabaseManager.DBSystemCategory] = []
    @State private var categoryQuery: String = ""
    @State private var selectedCategory: SupabaseManager.DBSystemCategory? = nil
    @State private var tagsText: String = ""
    @State private var btnState: GradientButtonState = .normal
    @State private var stream: SupabaseManager.DBLiveStream? = nil
    @State private var showBroadcast: Bool = false
    @State private var errorText: String? = nil

    @StateObject private var supa = SupabaseManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Go Live")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Set a compelling title and optional description before you start streaming.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    TextField("Live stream title", text: $title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category (required)").font(.subheadline.bold())
                        TextField("Search categories…", text: $categoryQuery)
                            .textFieldStyle(.roundedBorder)
                        ScrollView { VStack(alignment: .leading) {
                            ForEach(filteredCategories, id: \.id) { c in
                                Button(action: { selectedCategory = c; categoryQuery = c.name }) {
                                    HStack { Text(c.name); Spacer(); if selectedCategory?.id == c.id { Image(systemName: "checkmark") } }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 6)
                            }
                        } }.frame(maxHeight: 120)
                        if let sc = selectedCategory { Text("Selected: \(sc.name)").font(.caption).foregroundStyle(.secondary) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags (optional)").font(.subheadline.bold())
                        TextField("Comma separated, e.g. gaming, music", text: $tagsText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 8)

                Spacer()

                GradientButton(title: "Start Live", state: btnState) {
                    Task { await startLive() }
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline) }
                }
            }
            .alert("Oops", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
            .navigationDestination(isPresented: $showBroadcast) {
                if let s = stream { LiveBroadcastView(stream: s) }
            }
        }
        .task {
            if categories.isEmpty { if let rows = try? await supa.fetchSystemCategories() { categories = rows } }
        }
    }

    private func startLive() async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorText = "Please enter a title"; return }
        guard selectedCategory != nil else { errorText = "Please select a category"; return }
        guard supa.user != nil else { errorText = "Please sign in to go live"; return }
        // Preflight permissions for mic & camera (avoids late failures)
        let ok = await ensurePermissions()
        guard ok else { await MainActor.run { errorText = "Camera and microphone access are required to go live." }; return }
        await MainActor.run { btnState = .loading }
        do {
            let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let created = try await supa.createLiveSession(title: title, description: description.isEmpty ? nil : description, categoryId: selectedCategory?.id, tags: tags)
            await MainActor.run {
                self.stream = created
                self.btnState = .success
                self.showBroadcast = true
            }
        } catch {
            await MainActor.run {
                self.btnState = .error
                self.errorText = (error as NSError).localizedDescription
            }
        }
    }

    private var filteredCategories: [SupabaseManager.DBSystemCategory] {
        let q = categoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return categories }
        return categories.filter { $0.name.lowercased().contains(q) }
    }

    private func ensurePermissions() async -> Bool {
        // Camera
        let camGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
        }
        // Microphone (use new API on iOS 17+)
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
            }
        } else {
            micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        return camGranted && micGranted
    }
}

#Preview {
    GoLiveSetupView()
}
