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
    // Access & scheduling
    enum AccessType: String, CaseIterable { case free, subscription, paid }
    @State private var accessType: AccessType = .free
    @State private var priceText: String = ""
    @State private var availablePlans: [SupabaseManager.DBSubscriptionPlan] = []
    @State private var selectedPlanId: String? = nil
    enum Timing: String, CaseIterable { case now, schedule }
    @State private var timing: Timing = .now
    @State private var scheduledAt: Date = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
    // Match
    @State private var startAsMatch: Bool = false

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
                        } }.frame(maxHeight: 260)
                        if let sc = selectedCategory { Text("Selected: \(sc.name)").font(.caption).foregroundStyle(.secondary) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags (optional)").font(.subheadline.bold())
                        TextField("Comma separated, e.g. gaming, music", text: $tagsText)
                            .textFieldStyle(.roundedBorder)
                    }
                    // Access configuration
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Access").font(.subheadline.bold())
                        Picker("Access", selection: $accessType) {
                            Text("Free").tag(AccessType.free)
                            Text("Subscription").tag(AccessType.subscription)
                            Text("One-time").tag(AccessType.paid)
                        }
                        .pickerStyle(.segmented)
                        if accessType == .paid {
                            TextField("Price (tokens)", text: $priceText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        } else if accessType == .subscription {
                            Picker("Plan (optional)", selection: Binding(get: { selectedPlanId ?? availablePlans.first?.id }, set: { selectedPlanId = $0 })) {
                                Text("Any Plan").tag(nil as String?)
                                ForEach(availablePlans, id: \.id) { p in
                                    Text("\(p.name) — \(p.tokens)").tag(p.id as String?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    // Timing
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When").font(.subheadline.bold())
                        Picker("When", selection: $timing) {
                            Text("Go Live Now").tag(Timing.now)
                            Text("Schedule").tag(Timing.schedule)
                        }
                        .pickerStyle(.segmented)
                        if timing == .schedule {
                            DatePicker("Start time", selection: $scheduledAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.graphical)
                        }
                    }
                    // Match toggle
                    Toggle("This is a Match (battle)", isOn: $startAsMatch)
                }
                .padding(.top, 8)

                Spacer()

                GradientButton(title: timing == .now ? "Start Live" : "Schedule", state: btnState) { Task { await startLive() } }
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
            if accessType == .subscription, let me = supa.user?.id.uuidString, let plans = try? await supa.fetchSubscriptionPlans(creatorId: me) {
                availablePlans = plans.sorted { $0.tokens < $1.tokens }
                selectedPlanId = availablePlans.first?.id
            }
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
            if timing == .now {
                let created = try await supa.createLiveSession(title: title, description: description.isEmpty ? nil : description, categoryId: selectedCategory?.id, tags: tags)
                // Apply access settings if needed
                switch accessType {
                case .free:
                    break
                case .paid:
                    if let price = Int(priceText), price > 0 {
                        _ = try? await supa.updateLiveSession(id: created.id, updates: ["access_type": "paid", "price": price])
                    }
                case .subscription:
                    var updates: [String: Any] = ["access_type": "subscription"]
                    if let pid = selectedPlanId { updates["required_plan_id"] = pid }
                    _ = try? await supa.updateLiveSession(id: created.id, updates: updates)
                }
                // Optionally start a battle immediately
                if startAsMatch { _ = try? await supa.createBattle(streamId: created.id) }
                await MainActor.run {
                    self.stream = created
                    self.btnState = .success
                    self.showBroadcast = true
                }
            } else {
                // Schedule live
                let iso = ISO8601DateFormatter().string(from: scheduledAt)
                let _ = try await supa.createScheduledLiveStream(
                    title: title,
                    description: description.isEmpty ? nil : description,
                    categoryId: selectedCategory?.id,
                    tags: tags,
                    scheduledAtISO: iso,
                    accessType: accessType.rawValue,
                    price: accessType == .paid ? (Int(priceText) ?? nil) : nil,
                    requiredPlanId: accessType == .subscription ? selectedPlanId : nil
                )
                await MainActor.run {
                    self.btnState = .success
                    self.errorText = "Scheduled successfully for \(scheduledAt.formatted(date: .abbreviated, time: .shortened))"
                }
                // Auto close after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
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
