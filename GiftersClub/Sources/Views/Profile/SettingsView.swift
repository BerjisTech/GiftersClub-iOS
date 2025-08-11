import SwiftUI
import PhotosUI

private enum SettingsTab: String, CaseIterable { case profile = "Profile", security = "Security", moderation = "Moderation", interaction = "Interaction" }

struct SettingsView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @StateObject private var banners = BannerQueue()
    @State private var active: SettingsTab = .profile
    @State private var username: String = ""
    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var saving = false
    @State private var avatarURL: URL?
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedAvatarData: Data?
    @State private var blocked: [SupabaseManager.DBProfile] = []
    @State private var filtered: [String] = []
    @State private var reported: [SupabaseManager.DBReportedUserItem] = []
    @State private var newFilter: String = ""
    @State private var searchUsername: String = ""
    @State private var suggestions: [SupabaseManager.DBProfile] = []
    @State private var reportTarget: SupabaseManager.DBProfile?
    @State private var reportSheetVisible = false
    @State private var reportUsername: String = ""
    @State private var reportReason: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 16) {
                    // Tabs (minimal underline)
                    tabs
                    Divider()
                    tabContent
                }
                .padding()
            }
            BannerHost().environmentObject(banners)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
    }

    private var tabs: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let count = CGFloat(SettingsTab.allCases.count)
            let tabW = w / max(1, count)
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { active = tab } }) {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(active == tab ? .semibold : .regular))
                                .foregroundStyle(active == tab ? Color.primary : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                        }
                    }
                }
                Rectangle().fill(AppColors.primaryEnd)
                    .frame(width: 24, height: 2)
                    .offset(x: CGFloat(index(of: active)) * tabW + (tabW - 24)/2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: active)
            }
        }
        .frame(height: 30)
    }

    @ViewBuilder private var tabContent: some View {
        switch active {
        case .profile:
            VStack(alignment: .leading, spacing: 12) {
                Text("Profile").font(.headline)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.primary.opacity(0.06))
                        if let selectedImage {
                            selectedImage
                                .resizable().scaledToFill()
                        } else if let avatarURL {
                            AsyncImage(url: avatarURL) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { ProgressView() }
                        } else {
                            Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Text("Change Photo")
                    }
                    .onChange(of: selectedItem) { _, item in
                        guard let item else { return }
                        Task {
                            // Load and compress to JPEG to standardize mime type
                            if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.85) {
                                await MainActor.run {
                                    selectedImage = Image(uiImage: ui)
                                    selectedAvatarData = jpeg
                                }
                            }
                            await MainActor.run { selectedItem = nil }
                        }
                    }
                }
                TextField("Username", text: $username).textInputAutocapitalization(.never).disableAutocorrection(true)
                TextField("Name", text: $name)
                TextEditor(text: $bio).frame(minHeight: 100).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                GradientButton(title: saving ? "Saving…" : "Save", state: saving ? .loading : .normal) {
                    Task { await saveProfile() }
                }
            }
        case .security:
            VStack(alignment: .leading, spacing: 12) {
                Text("Security").font(.headline)
                // Unified search field with suggestions (block/report actions on right)
                TextField("Search @username", text: $searchUsername)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: searchUsername) { _, newVal in
                        Task { await loadSuggestions(prefix: newVal) }
                    }
                if !suggestions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(suggestions, id: \.user_id) { prof in
                            HStack(spacing: 10) {
                                Circle().fill(Color.primary.opacity(0.08)).frame(width: 28, height: 28)
                                Text("@\(prof.username)")
                                Spacer()
                                Button {
                                    Task { await blockUserId(prof.user_id) }
                                } label: {
                                    Image(systemName: "hand.raised.fill").foregroundStyle(.red)
                                }
                                Button {
                                    reportTarget = prof
                                    reportUsername = prof.username
                                    reportReason = ""
                                    reportSheetVisible = true
                                } label: {
                                    Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                }

                if blocked.isEmpty {
                    Text("You haven't blocked anyone.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Blocked").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(blocked, id: \.user_id) { prof in
                            HStack {
                                Text("@\(prof.username)")
                                Spacer()
                                Button("Unblock") { Task { await unblockUser(prof.user_id) } }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                // Reported users list (read-only)
                if reported.isEmpty {
                    Text("You haven't reported anyone.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reported").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(reported) { item in
                            HStack {
                                Text("@\(item.reported_user_id?.username ?? "user")")
                                Spacer()
                                Text((item.status ?? "").capitalized).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .sheet(isPresented: $reportSheetVisible) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Report @\(reportUsername)").font(.headline)
                    TextEditor(text: $reportReason)
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    HStack {
                        Button("Cancel") { reportSheetVisible = false }
                        Spacer()
                        Button("Submit") {
                            Task { await reportUserByUsername(); reportSheetVisible = false }
                        }
                    }
                }
                .padding()
                .presentationDetents([.medium])
                .presentationCornerRadius(20)
            }
        case .moderation:
            VStack(alignment: .leading, spacing: 12) {
                Text("Moderation").font(.headline)
                HStack {
                    TextField("Add filtered word", text: $newFilter)
                    GradientButton(title: "Add") { Task { await addFilterWord() } }
                }
                if filtered.isEmpty {
                    Text("No filtered words.").foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.self) { w in
                        HStack {
                            Text(w)
                            Spacer()
                            Button("Remove") { Task { await removeFilterWord(w) } }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        case .interaction:
            VStack(alignment: .leading, spacing: 12) {
                Text("Interaction").font(.headline)
                Text("Choose who can interact with you.")
                // TODO: save interaction setting (everyone / followers / friends)
                Picker("Interactions", selection: .constant(0)) {
                    Text("Everyone").tag(0)
                    Text("Followers only").tag(1)
                    Text("Friends only").tag(2)
                }.pickerStyle(.segmented)
            }
        }
    }

    private func index(of tab: SettingsTab) -> Int { SettingsTab.allCases.firstIndex(of: tab) ?? 0 }

    private func loadProfile() async {
        guard let me = supabase.user?.id.uuidString else { return }
        if let db = try? await supabase.fetchProfile(username: nil, userId: me) {
            username = db.username
            name = db.name ?? ""
            bio = db.bio ?? ""
            avatarURL = db.image.flatMap(URL.init(string:))
        }
        // Load security & moderation data
        blocked = (try? await supabase.fetchBlockedUsers()) ?? []
        reported = (try? await supabase.fetchReportedUsers(limit: 100, offset: 0)) ?? []
        filtered = (try? await supabase.fetchFilteredWords()) ?? []
    }

    private func saveProfile() async {
        guard let me = supabase.user?.id.uuidString else { return }
        saving = true
        defer { saving = false }
        do {
            var imageURL: String? = nil
            if let avatarBytes = selectedAvatarData {
                // Upload avatar then include URL in profile update
                if let url = try? await supabase.uploadAvatar(imageData: avatarBytes, mimeType: "image/jpeg") {
                    imageURL = url
                    avatarURL = URL(string: url)
                } else {
                    banners.show(Banner(title: "Could not upload avatar", style: .error))
                }
                selectedAvatarData = nil
            }
            _ = try await supabase.updateProfile(userId: me, updates: SupabaseManager.PartialProfile(username: username, name: name, bio: bio, image: imageURL))
            banners.show(Banner(title: "Profile saved", style: .success))
        } catch {
            print("Save profile error: \(error)")
            banners.show(Banner(title: "Failed to save profile", style: .error))
        }
    }

    private func loadSuggestions(prefix: String) async {
        if prefix.isEmpty { suggestions = []; return }
        suggestions = (try? await supabase.searchUsers(prefix: prefix, limit: 10)) ?? []
    }
    private func blockUserId(_ id: String) async {
        do {
            try await supabase.blockUser(targetUserId: id)
            blocked = (try? await supabase.fetchBlockedUsers()) ?? []
            banners.show(Banner(title: "User blocked", style: .success))
        } catch {
            print("Block user error: \(error)")
            banners.show(Banner(title: "Failed to block user", style: .error))
        }
    }
    private func unblockUser(_ id: String) async {
        do {
            try await supabase.unblockUser(targetUserId: id)
            blocked = (try? await supabase.fetchBlockedUsers()) ?? []
            banners.show(Banner(title: "User unblocked", style: .success))
        } catch {
            print("Unblock user error: \(error)")
            banners.show(Banner(title: "Failed to unblock user", style: .error))
        }
    }
    private func addFilterWord() async {
        let w = newFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        do {
            try await supabase.addFilteredWord(w)
            filtered = (try? await supabase.fetchFilteredWords()) ?? []
            newFilter = ""
            banners.show(Banner(title: "Filter added", style: .success))
        } catch {
            print("Add filter error: \(error)")
            banners.show(Banner(title: "Failed to add filter", style: .error))
        }
    }
    private func removeFilterWord(_ w: String) async {
        do {
            try await supabase.removeFilteredWord(w)
            filtered = (try? await supabase.fetchFilteredWords()) ?? []
            banners.show(Banner(title: "Filter removed", style: .success))
        } catch {
            print("Remove filter error: \(error)")
            banners.show(Banner(title: "Failed to remove filter", style: .error))
        }
    }

    private func reportUserByUsername() async {
        let handle = reportUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = reportReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty, !reason.isEmpty else { return }
        do {
            if let id = try await supabase.findUserId(byUsername: handle) {
                // Don't report self
                if id == supabase.user?.id.uuidString {
                    banners.show(Banner(title: "You cannot report yourself", style: .warning))
                    return
                }
                try await supabase.reportUser(reportedUserId: id, reason: reason)
                banners.show(Banner(title: "Report submitted", style: .success))
                reportUsername = ""
                reportReason = ""
            } else {
                banners.show(Banner(title: "User not found", style: .error))
            }
        } catch {
            print("Report user error: \(error)")
            banners.show(Banner(title: "Failed to submit report", style: .error))
        }
    }

    
}
