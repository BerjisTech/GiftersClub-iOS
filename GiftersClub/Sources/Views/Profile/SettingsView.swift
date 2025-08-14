import SwiftUI
import PhotosUI

private enum SettingsTab: String, CaseIterable { case profile = "Profile", security = "Security", moderation = "Moderation", interaction = "Interaction", subscriptions = "Subscriptions" }

struct SettingsView: View {
    @StateObject private var banners = BannerQueue()

    var body: some View {
        ZStack(alignment: .top) {
            List {
                Section {
                    NavigationLink(destination: SettingsDetailView(tab: .profile)) { Label("Profile", systemImage: "person.circle") }
                    NavigationLink(destination: SettingsDetailView(tab: .security)) { Label("Security", systemImage: "lock.shield") }
                    NavigationLink(destination: SettingsDetailView(tab: .moderation)) { Label("Moderation", systemImage: "hand.raised") }
                    NavigationLink(destination: SettingsDetailView(tab: .interaction)) { Label("Interaction", systemImage: "bubble.left.and.bubble.right") }
                    NavigationLink(destination: SettingsDetailView(tab: .subscriptions)) { Label("Subscriptions", systemImage: "star.circle") }
                }
            }
            .listStyle(.insetGrouped)
            BannerHost().environmentObject(banners)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings Detail Screens (native navigation style)
private struct SettingsDetailView: View {
    let tab: SettingsTab
    @ObservedObject private var supabase = SupabaseManager.shared
    @StateObject private var banners = BannerQueue()

    // Profile state
    @State private var username: String = ""
    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var saving = false
    @State private var avatarURL: URL?
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedAvatarData: Data?
    // Security/Moderation state
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
    // Subscriptions state
    @State private var subPlans: [SupabaseManager.DBSubscriptionPlan] = []
    @State private var subName: String = ""
    @State private var subDescription: String = ""
    @State private var subTokens: String = ""
    @State private var subDuration: String = "one_time"
    @State private var subEditingPlanId: String? = nil
    @State private var subSaving: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch tab {
                case .profile: profileContent
                case .security: securityContent
                case .moderation: moderationContent
                case .interaction: interactionContent
                case .subscriptions: subscriptionsContent
                }
            }
            .padding()
        }
        .navigationTitle(tab.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .task { await onAppearLoad() }
        .sheet(isPresented: $reportSheetVisible) { reportSheet }
        .overlay(alignment: .top, content: { BannerHost().environmentObject(banners) })
    }

    // MARK: - Content Builders
    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile").font(.headline)
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.06))
                    if let selectedImage { selectedImage.resizable().scaledToFill() }
                    else if let avatarURL { AsyncImage(url: avatarURL) { img in img.resizable().scaledToFill() } placeholder: { ProgressView() } }
                    else { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(8) }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                PhotosPicker(selection: $selectedItem, matching: .images) { Text("Change Photo") }
                .onChange(of: selectedItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.85) {
                            await MainActor.run { selectedImage = Image(uiImage: ui); selectedAvatarData = jpeg }
                        }
                        await MainActor.run { selectedItem = nil }
                    }
                }
            }
            TextField("Username", text: $username).textInputAutocapitalization(.never).disableAutocorrection(true)
            TextField("Name", text: $name)
            TextEditor(text: $bio).frame(minHeight: 100).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            GradientButton(title: saving ? "Saving…" : "Save", state: saving ? .loading : .normal) { Task { await saveProfile() } }
        }
    }

    private var securityContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security").font(.headline)
            TextField("Search @username", text: $searchUsername)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onChange(of: searchUsername) { _, newVal in Task { await loadSuggestions(prefix: newVal) } }
            if !suggestions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(suggestions, id: \.user_id) { prof in
                        HStack(spacing: 10) {
                            Circle().fill(Color.primary.opacity(0.08)).frame(width: 28, height: 28)
                            Text("@\(prof.username)")
                            Spacer()
                            Button { Task { await blockUserId(prof.user_id) } } label: { Image(systemName: "hand.raised.fill").foregroundStyle(.red) }
                            Button { reportTarget = prof; reportUsername = prof.username; reportReason = ""; reportSheetVisible = true } label: { Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.orange) }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            }
            if blocked.isEmpty { Text("You haven't blocked anyone.").foregroundStyle(.secondary) } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blocked").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(blocked, id: \.user_id) { prof in
                        HStack { Text("@\(prof.username)"); Spacer(); Button("Unblock") { Task { await unblockUser(prof.user_id) } } }.padding(.vertical, 6)
                    }
                }
            }
            if reported.isEmpty { Text("You haven't reported anyone.").foregroundStyle(.secondary) } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reported").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(reported) { item in
                        HStack { Text("@\(item.reported_user_id?.username ?? "user")"); Spacer(); Text((item.status ?? "").capitalized).foregroundStyle(.secondary) }.padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var moderationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moderation").font(.headline)
            HStack { TextField("Add filtered word", text: $newFilter); GradientButton(title: "Add") { Task { await addFilterWord() } } }
            if filtered.isEmpty { Text("No filtered words.").foregroundStyle(.secondary) } else {
                ForEach(filtered, id: \.self) { w in HStack { Text(w); Spacer(); Button("Remove") { Task { await removeFilterWord(w) } } }.padding(.vertical, 6) }
            }
        }
    }

    private var interactionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interaction").font(.headline)
            Text("Choose who can interact with you.")
            Picker("Interactions", selection: .constant(0)) { Text("Everyone").tag(0); Text("Followers only").tag(1); Text("Friends only").tag(2) }.pickerStyle(.segmented)
        }
    }

    private var subscriptionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscriptions").font(.headline)
            if subPlans.isEmpty { Text("No plans yet.").foregroundStyle(.secondary) }
            ForEach(subPlans, id: \.id) { plan in
                HStack(alignment: .center) {
                    VStack(alignment: .leading) {
                        Text(plan.name).font(.subheadline.weight(.semibold))
                        Text("\(plan.tokens) tokens • \(plan.duration_type)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { subEditingPlanId = plan.id; subName = plan.name; subDescription = plan.description ?? ""; subTokens = String(plan.tokens); subDuration = plan.duration_type } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain).padding(.horizontal, 6)
                    Button(role: .destructive) { Task { await deletePlan(plan.id) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                Divider()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(subEditingPlanId == nil ? "Create plan" : "Edit plan").font(.subheadline)
                TextField("Plan name", text: $subName)
                TextField("Description (optional)", text: $subDescription)
                TextField("Tokens", text: $subTokens).keyboardType(.numberPad)
                Picker("Duration", selection: $subDuration) { Text("One-time").tag("one_time"); Text("Monthly").tag("monthly"); Text("Annual").tag("annual") }.pickerStyle(.segmented)
                HStack {
                    if subEditingPlanId != nil { Button("Cancel") { resetPlanForm() } }
                    Spacer()
                    GradientButton(title: subSaving ? "Saving…" : "Save plan", state: subSaving ? .loading : .normal) { Task { await savePlan() } }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
    }

    // MARK: - Report Sheet
    private var reportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report @\(reportUsername)").font(.headline)
            TextEditor(text: $reportReason).frame(minHeight: 120).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            HStack { Button("Cancel") { reportSheetVisible = false }; Spacer(); Button("Submit") { Task { await reportUserByUsername(); reportSheetVisible = false } } }
        }
        .padding()
        .presentationDetents([.medium])
        .presentationCornerRadius(20)
    }

    // MARK: - Loads & Actions
    private func onAppearLoad() async {
        switch tab {
        case .profile:
            guard let me = supabase.user?.id.uuidString else { return }
            if let db = try? await supabase.fetchProfile(username: nil, userId: me) { username = db.username; name = db.name ?? ""; bio = db.bio ?? ""; avatarURL = db.image.flatMap(URL.init(string:)) }
        case .security, .moderation:
            blocked = (try? await supabase.fetchBlockedUsers()) ?? []
            reported = (try? await supabase.fetchReportedUsers(limit: 100, offset: 0)) ?? []
            filtered = (try? await supabase.fetchFilteredWords()) ?? []
        case .interaction:
            break
        case .subscriptions:
            await loadPlans()
        }
    }

    private func saveProfile() async {
        guard let me = supabase.user?.id.uuidString else { return }
        saving = true; defer { saving = false }
        do {
            var imageURL: String? = nil
            if let avatarBytes = selectedAvatarData {
                if let url = try? await supabase.uploadAvatar(imageData: avatarBytes, mimeType: "image/jpeg") { imageURL = url; avatarURL = URL(string: url) } else { banners.show(Banner(title: "Could not upload avatar", style: .error)) }
                selectedAvatarData = nil
            }
            _ = try await supabase.updateProfile(userId: me, updates: SupabaseManager.PartialProfile(username: username, name: name, bio: bio, image: imageURL))
            banners.show(Banner(title: "Profile saved", style: .success))
        } catch { banners.show(Banner(title: "Failed to save profile", style: .error)) }
    }
    private func loadSuggestions(prefix: String) async { if prefix.isEmpty { suggestions = []; return }; suggestions = (try? await supabase.searchUsers(prefix: prefix, limit: 10)) ?? [] }
    private func blockUserId(_ id: String) async { do { try await supabase.blockUser(targetUserId: id); blocked = (try? await supabase.fetchBlockedUsers()) ?? []; banners.show(Banner(title: "User blocked", style: .success)) } catch { banners.show(Banner(title: "Failed to block user", style: .error)) } }
    private func unblockUser(_ id: String) async { do { try await supabase.unblockUser(targetUserId: id); blocked = (try? await supabase.fetchBlockedUsers()) ?? []; banners.show(Banner(title: "User unblocked", style: .success)) } catch { banners.show(Banner(title: "Failed to unblock user", style: .error)) } }
    private func addFilterWord() async { let w = newFilter.trimmingCharacters(in: .whitespacesAndNewlines); guard !w.isEmpty else { return }; do { try await supabase.addFilteredWord(w); filtered = (try? await supabase.fetchFilteredWords()) ?? []; newFilter = ""; banners.show(Banner(title: "Filter added", style: .success)) } catch { banners.show(Banner(title: "Failed to add filter", style: .error)) } }
    private func removeFilterWord(_ w: String) async { do { try await supabase.removeFilteredWord(w); filtered = (try? await supabase.fetchFilteredWords()) ?? []; banners.show(Banner(title: "Filter removed", style: .success)) } catch { banners.show(Banner(title: "Failed to remove filter", style: .error)) } }
    private func reportUserByUsername() async {
        let handle = reportUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = reportReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty, !reason.isEmpty else { return }
        do {
            if let id = try await supabase.findUserId(byUsername: handle) {
                if id == supabase.user?.id.uuidString { banners.show(Banner(title: "You cannot report yourself", style: .warning)); return }
                try await supabase.reportUser(reportedUserId: id, reason: reason)
                banners.show(Banner(title: "Report submitted", style: .success)); reportUsername = ""; reportReason = ""
            } else { banners.show(Banner(title: "User not found", style: .error)) }
        } catch { banners.show(Banner(title: "Failed to submit report", style: .error)) }
    }
    // Subscriptions helpers
    private func loadPlans() async { guard let me = supabase.user?.id.uuidString else { return }; subPlans = (try? await supabase.fetchSubscriptionPlans(creatorId: me)) ?? [] }
    private func resetPlanForm() { subEditingPlanId = nil; subName = ""; subDescription = ""; subTokens = ""; subDuration = "one_time" }
    private func savePlan() async {
        guard let tokens = Int(subTokens), tokens > 0, !subName.trimmingCharacters(in: .whitespaces).isEmpty else { banners.show(Banner(title: "Name and valid tokens required", style: .error)); return }
        if subEditingPlanId == nil && subPlans.count >= 5 { banners.show(Banner(title: "Maximum of 5 plans allowed", style: .warning)); return }
        subSaving = true; defer { subSaving = false }
        do {
            if let id = subEditingPlanId { let updates = SupabaseManager.UpdateSubscriptionPlanInput(name: subName, description: subDescription.isEmpty ? nil : subDescription, tokens: tokens, duration_type: subDuration); _ = try await supabase.updateSubscriptionPlan(id: id, updates: updates); banners.show(Banner(title: "Plan updated", style: .success)) }
            else { _ = try await supabase.createSubscriptionPlan(name: subName, description: subDescription.isEmpty ? nil : subDescription, tokens: tokens, durationType: subDuration); banners.show(Banner(title: "Plan created", style: .success)) }
            await loadPlans(); resetPlanForm()
        } catch { banners.show(Banner(title: "Failed to save plan", style: .error)) }
    }
    private func deletePlan(_ id: String) async { do { try await supabase.deleteSubscriptionPlan(id: id); await loadPlans(); banners.show(Banner(title: "Plan deleted", style: .success)) } catch { banners.show(Banner(title: "Failed to delete plan", style: .error)) } }
}

