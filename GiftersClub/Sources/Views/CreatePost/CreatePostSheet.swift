import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit

// MARK: - UITextView helpers for formatting
private extension UITextView {
    func currentSelectedRange() -> NSRange {
        let beginning = beginningOfDocument
        let selectedStart = selectedTextRange?.start ?? endOfDocument
        let selectedEnd = selectedTextRange?.end ?? endOfDocument
        let loc = offset(from: beginning, to: selectedStart)
        let len = offset(from: selectedStart, to: selectedEnd)
        return NSRange(location: max(0, loc), length: max(0, len))
    }
    
    func gc_applyAttribute(_ key: NSAttributedString.Key, value: Any) {
        let range = currentSelectedRange()
        if range.length == 0 {
            // No selection: update typingAttributes so future text uses this style
            var attrs = typingAttributes
            attrs[key] = value
            typingAttributes = attrs
        } else {
            let mut = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
            mut.addAttribute(key, value: value, range: range)
            attributedText = mut
            selectedRange = range
        }
    }
    
    func gc_setFontSize(_ size: CGFloat) {
        let range = currentSelectedRange()
        if range.length == 0 {
            if let f = typingAttributes[.font] as? UIFont {
                typingAttributes[.font] = UIFont(descriptor: f.fontDescriptor, size: size)
            } else {
                typingAttributes[.font] = UIFont.systemFont(ofSize: size)
            }
        } else {
            let mut = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
            mut.enumerateAttribute(.font, in: range) { value, r, _ in
                let base = (value as? UIFont) ?? UIFont.systemFont(ofSize: size)
                let new = UIFont(descriptor: base.fontDescriptor, size: size)
                mut.addAttribute(.font, value: new, range: r)
            }
            attributedText = mut
            selectedRange = range
        }
    }
    
    func gc_toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        let range = currentSelectedRange()
        let toggle: (UIFont) -> UIFont = { font in
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: desc, size: font.pointSize)
            }
            return font
        }
        if range.length == 0 {
            if let f = typingAttributes[.font] as? UIFont {
                typingAttributes[.font] = toggle(f)
            } else {
                typingAttributes[.font] = toggle(UIFont.systemFont(ofSize: UIFont.systemFontSize))
            }
        } else {
            let mut = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
            mut.enumerateAttribute(.font, in: range) { value, r, _ in
                let base = (value as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
                mut.addAttribute(.font, value: toggle(base), range: r)
            }
            attributedText = mut
            selectedRange = range
        }
    }
}

enum CreatePostStep { case pick, textEditor, edit, details }

struct CreatePostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: CreatePostViewModel
    @State private var step: CreatePostStep
    @StateObject private var banners = BannerQueue()
    @State private var firstAppearHandled = false
    @State private var showSettings = false
    @State private var showPreview = false
    @State private var previewModel: PostViewerModel? = nil
    @State private var showFileImporter = false
    
    init(vm: CreatePostViewModel? = nil, initial: CreatePostStep = .pick) {
        _vm = StateObject(wrappedValue: vm ?? CreatePostViewModel())
        _step = State(initialValue: initial)
}

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                content
                BannerHost().environmentObject(banners)
            }
            .navigationTitle(step == .edit ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(step == .edit)
            .toolbar {
                if step != .edit {
                    ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showPreview) {
            if let model = previewModel {
                NavigationStack { PostViewer(model: model) }
            }
        }
        // If user picked media from the library, auto-advance to Edit step when media becomes available
        .onChange(of: vm.media) { newVal in
            // Move into editor whenever media becomes available
            if !newVal.isEmpty && step != .edit { step = .edit }
        }
        .onAppear {
            // If invoked directly with .details from camera/library, insert the edit step first
            if !firstAppearHandled {
                firstAppearHandled = true
                if step == .details && (vm.isLoadingMedia || !vm.media.isEmpty) { step = .edit }
            }
        }
        .onChange(of: vm.isLoadingMedia) { loading in
            // If we were launched in .details but media is loading, show the editor with loader immediately
            if loading && step == .details { step = .edit }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch step {
        case .pick: MediaPickStep()
        case .textEditor: TextPostEditor(onDone: { image in
            vm.addRenderedTextImage(image)
            step = .details
        })
        case .edit: EditStep()
        case .details: DetailsStep()
        }
    }
    
    private var title: String {
        switch step {
        case .pick: return "Create Post"
        case .textEditor: return "Text Post"
        case .edit: return "Edit"
        case .details: return "Details"
        }
    }
    
    // MARK: - Steps
    private func MediaPickStep() -> some View {
        VStack(spacing: 16) {
            // Primary actions row
            HStack(spacing: 12) {
                Button {
                    // Camera path: stub for now
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Camera")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                }
                .disabled(true) // TODO: Implement full camera per UI.md
                Button {
                    step = .textEditor
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "textformat")
                        Text("Text Post")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                }
                PhotosPicker(selection: $vm.selectedPickerItems, maxSelectionCount: 6, matching: .any(of: [.images, .videos])) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                        Text("Library")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                }
                .onChange(of: vm.selectedPickerItems, perform: { _ in
                    // Jump to edit immediately and load in the background for better responsiveness
                    if !vm.selectedPickerItems.isEmpty {
                        if step == .pick { step = .edit }
                        vm.loadPickerItems()
                    }
                })

                // Files (macOS / iOS) – allows importing from device storage
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text("Files")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                }
            }
            .frame(maxWidth: .infinity)
            
            if vm.media.isEmpty {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        Text("Select photos/videos or create a text post.")
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 200)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                let maxThumbs = 5
                let total = vm.media.count
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(vm.media.prefix(maxThumbs).enumerated()), id: \.1.id) { idx, item in
                            ZStack(alignment: .topTrailing) {
                                ZStack {
                                    MediaThumbView(item: item)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    if idx == maxThumbs - 1 && total > maxThumbs {
                                        Rectangle().fill(Color.black.opacity(0.35))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        Text("+\(total - maxThumbs)")
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                Button { vm.media.remove(at: idx) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                                }
                                .padding(6)
                            }
                            .frame(width: 120, height: 180)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
                
                Spacer()
                GradientButton(title: "Next") {
                    if vm.media.isEmpty {
                        banners.show(Banner(title: "Please add media or choose Text Post", style: .warning))
                    } else {
                        step = .edit
                    }
                }
            }
                .padding()
                .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.image, UTType.movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    var items: [CreatePostViewModel.MediaItem] = []
                    for url in urls {
                        #if targetEnvironment(macCatalyst)
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        #endif
                        if let data0 = try? Data(contentsOf: url) {
                            let mime0 = inferredMime(for: url) ?? "application/octet-stream"
                            if mime0 == "image/heic" || mime0 == "image/heif" || mime0 == "image/heif-sequence" {
                                if let img = UIImage(data: data0), let jpeg = img.jpegData(compressionQuality: 0.9) {
                                    items.append(.init(data: jpeg, mime: "image/jpeg", kind: .photo))
                                } else {
                                    items.append(.init(data: data0, mime: mime0, kind: .photo))
                                }
                            } else if mime0.hasPrefix("video/") && mime0 != "video/mp4" {
                                // For safety, try to transcode non-MP4 videos to MP4 using AVAssetExportSession
                                if let mp4 = await transcodeFileURLToMP4(inputURL: url) {
                                    items.append(.init(data: mp4, mime: "video/mp4", kind: .video))
                                } else {
                                    items.append(.init(data: data0, mime: mime0, kind: .video))
                                }
                            } else {
                                let kind: CreatePostViewModel.MediaItem.Kind = (mime0.hasPrefix("video/")) ? .video : .photo
                                items.append(.init(data: data0, mime: mime0, kind: kind))
                            }
                        }
                    }
                    await MainActor.run {
                        vm.media.append(contentsOf: items)
                        if !items.isEmpty { step = .edit }
                    }
                }
            case .failure:
                break
            }
        }
        }
        // Transcode a file URL video to MP4 Data (best-effort)
        private func transcodeFileURLToMP4(inputURL: URL) async -> Data? {
            let asset = AVAsset(url: inputURL)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
            let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("imp_\(UUID().uuidString).mp4")
            session.outputURL = outURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            return await withUnsafeContinuation { cont in
                session.exportAsynchronously {
                    defer { try? FileManager.default.removeItem(at: outURL) }
                    let data = try? Data(contentsOf: outURL)
                    cont.resume(returning: data)
                }
            }
        }
        private func presentPreview() {
            guard !vm.media.isEmpty else { return }
            // Write temporary URLs for current media
            let urls: [URL] = vm.media.compactMap { m in
                let isImage = m.mime.hasPrefix("image/")
                let ext = isImage ? "jpg" : "mp4"
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pv_\(UUID().uuidString).\(ext)")
                try? m.data.write(to: url, options: .atomic)
                return url
            }
            let media: PostViewerModel.Media = {
                if urls.count == 1 {
                    return vm.media.first!.mime.hasPrefix("video/") ? .video(urls[0]) : .image(urls[0])
                } else {
                    return .images(urls)
                }
            }()
            Task {
                let supa = SupabaseManager.shared
                var username: String = supa.user?.email ?? "you"
                var name: String? = nil
                var avatarURL: URL? = nil
                if let me = supa.user?.id.uuidString {
                    let profOpt: SupabaseManager.DBProfile? = try? await supa.fetchProfile(username: nil, userId: me)
                    if let prof = profOpt {
                        let u = prof.username.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !u.isEmpty { username = u }
                        name = prof.name
                        if let img = prof.image, let url = URL(string: img) { avatarURL = url }
                    }
                }
                await MainActor.run {
                    previewModel = PostViewerModel(
                        id: UUID().uuidString,
                        authorUsername: username,
                        authorName: name,
                        authorAvatar: avatarURL,
                        caption: vm.caption,
                        media: media
                    )
                    showPreview = true
                }
            }
        }
        private func EditStep() -> some View {
            Group {
                if vm.media.isEmpty {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text(vm.isLoadingMedia ? "Loading media…" : "No media selected")
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                } else {
                    FullscreenMediaEditor(vm: vm, onBack: { step = .pick }, onDone: { step = .details })
                }
            }
        }
        
        private func DetailsStep() -> some View {
            VStack(alignment: .leading, spacing: 12) {
                // Small media preview (like TikTok) so user can confirm selection
                if !vm.media.isEmpty {
                    let maxThumbs = 4
                    let total = vm.media.count
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(vm.media.prefix(maxThumbs).enumerated()), id: \.1.id) { idx, item in
                                ZStack(alignment: .center) {
                                    MediaThumbView(item: item)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    if idx == maxThumbs - 1 && total > maxThumbs {
                                        Rectangle().fill(Color.black.opacity(0.35))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        Text("+\(total - maxThumbs)")
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 80, height: 110)
                                .onTapGesture { presentPreview() }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                HashtagCaptionField(text: $vm.caption)
                
                Picker("Access", selection: $vm.accessType) {
                    ForEach(PostAccessType.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.accessType, perform: { t in
                    if t == .subscription { Task { await loadMyPlans() } }
                })
                
                if vm.accessType == .subscription {
                    if vm.availablePlans.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You have no subscription plans.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Create a subscription plan") { showSettings = true }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Who can view this post?")
                                .font(.subheadline.weight(.semibold))
                            Picker("Audience", selection: Binding(get: { vm.selectedPlanId ?? "__all__" }, set: { vm.selectedPlanId = ($0 == "__all__" ? nil : $0) })) {
                                Text("All subscribers").tag("__all__")
                                ForEach(vm.availablePlans, id: \.id) { p in
                                    Text("\(p.name) — \(p.tokens)").tag(p.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                
                if vm.accessType == .paid {
                    TextField("Price (tokens)", text: $vm.priceText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                
                Spacer()
                GradientButton(title: vm.isPosting ? "Posting..." : "Post") {
                    guard !vm.isPosting else { return }
                    if vm.accessType == .paid {
                        guard let price = Int(vm.priceText), price > 0 else {
                            banners.show(Banner(title: "Enter a valid price in tokens", style: .warning))
                            return
                        }
                    } else if vm.accessType == .subscription {
                        // Require at least one subscription plan before allowing a subscription post
                        Task {
                            let plans = vm.availablePlans
                            if plans.isEmpty {
                                await MainActor.run {
                                    banners.show(Banner(title: "Create a subscription plan first (Profile → Settings → Subscriptions)", style: .warning))
                                }
                                return
                            } else {
                                await MainActor.run { vm.publish { _ in
                                    banners.show(Banner(title: "Your post has been created", style: .success))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        // Close composer full-screen, then route to Profile
                                        NotificationCenter.default.post(name: .goHome, object: nil)
                                        NotificationCenter.default.post(name: .gotoProfile, object: nil)
                                        dismiss()
                                    }
                                } }
                            }
                        }
                        return
                    }
                    vm.publish { _ in
                        banners.show(Banner(title: "Post uploading in the background", style: .info))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            // Close composer full-screen, then route to Profile
                            NotificationCenter.default.post(name: .goHome, object: nil)
                            NotificationCenter.default.post(name: .gotoProfile, object: nil)
                            dismiss()
                        }
                    }
                }
                .disabled(vm.isPosting)
            }
            .padding()
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { _ in vm.errorMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        // MARK: - Hashtag-aware caption input
        private struct HashtagCaptionField: View {
            @Binding var text: String
            @State private var query: String = ""
            @State private var suggestions: [(name: String, count: Int)] = []
            @State private var isLoading = false
            var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Say something about your post...", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3, reservesSpace: true)
                        .onChange(of: text) { _ in refreshQuery() }
                    if !query.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if isLoading { ProgressView().scaleEffect(0.8) }
                                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, item in
                                    Button(action: { insertHashtag(item.name) }) {
                                        HStack(spacing: 8) {
                                            Text("#\(item.name)")
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                                .frame(maxWidth: 140, alignment: .leading)
                                            Text("\(item.count)")
                                                .font(.system(.caption2, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                                .frame(minWidth: 28, alignment: .trailing)
                                        }
                                        .frame(minWidth: 160)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            private func refreshQuery() {
                guard let token = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).last, token.first == "#" else {
                    query = ""; suggestions = []; return
                }
                let raw = String(token.dropFirst()).lowercased()
                query = raw
                guard !raw.isEmpty else { suggestions = []; return }
                isLoading = true
                Task {
                    let rows = await SupabaseManager.shared.suggestTags(prefix: raw, limit: 8)
                    await MainActor.run { self.suggestions = rows; self.isLoading = false }
                }
            }
            private func insertHashtag(_ name: String) {
                // Replace the trailing #token with the chosen one
                var parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
                guard let last = parts.last, last.hasPrefix("#") else { return }
                parts.removeLast()
                parts.append("#\(name)")
                // Rebuild preserving whitespace at end if any
                let suffixWhitespace: String = {
                    guard text.last?.isWhitespace == true else { return "" }
                    var rev: [Character] = []
                    for ch in text.reversed() {
                        if ch.isWhitespace { rev.append(ch) } else { break }
                    }
                    return String(rev.reversed())
                }()
                text = parts.joined(separator: " ") + suffixWhitespace
                query = ""; suggestions = []
            }
        }
        private func loadMyPlans() async {
            guard let me = SupabaseManager.shared.user?.id.uuidString else { return }
            if let plans = try? await SupabaseManager.shared.fetchSubscriptionPlans(creatorId: me) {
                let sorted = plans.sorted { $0.tokens < $1.tokens }
                await MainActor.run { vm.availablePlans = sorted; vm.selectedPlanId = nil }
            }
        }
    }

    // Infer MIME from URL using UTType or extension
    private func inferredMime(for url: URL) -> String? {
        if #available(iOS 14.0, *) {
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                return type.preferredMIMEType
            }
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return nil
        }
    }
    
    // MARK: - Text Post Editor (lightweight)
    private struct TextPostEditor: View {
        @Environment(\.dismiss) private var dismiss
        @State private var attributed = NSAttributedString(string: "", attributes: [.font: UIFont.systemFont(ofSize: 20, weight: .regular)])
        @State private var textColor: Color = .white
        @State private var bgIndex: Int = 0
        @State private var isPreview = false
        @State private var showColor = false
        @State private var textView: UITextView? = nil
        let onDone: (UIImage) -> Void
        
        private let gradients: [[Color]] = [
            // Existing
            [AppColors.primaryStart, AppColors.primaryEnd],
            [AppColors.successStart, AppColors.successEnd],
            [AppColors.warningStart, AppColors.warningEnd],
            [AppColors.dangerStart, AppColors.dangerEnd],
            // Additional vibrant presets (mirroring Android drawables vibe)
            [Color(hex: 0x8E2DE2), Color(hex: 0x4A00E0)], // purple → deep purple
            [Color(hex: 0xFF512F), Color(hex: 0xDD2476)], // orange → pink
            [Color(hex: 0x00F260), Color(hex: 0x0575E6)], // green → blue
            [Color(hex: 0x36D1DC), Color(hex: 0x5B86E5)], // teal → indigo
            [Color(hex: 0xF7971E), Color(hex: 0xFFD200)], // amber → yellow
            [Color(hex: 0xFD3A69), Color(hex: 0xFEC163)], // rose → peach
            [Color(hex: 0x00B4DB), Color(hex: 0x0083B0)], // cyan → teal
            [Color(hex: 0x11998E), Color(hex: 0x38EF7D)], // emerald
            [Color(hex: 0xEE0979), Color(hex: 0xFF6A00)]  // magenta → orange
        ]
        
        var body: some View {
            VStack(spacing: 12) {
                // Top nav mimic
                HStack {
                    Button("Cancel") { confirmCancel() }
                    Spacer()
                    Text("New Text Post").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Preview") { isPreview.toggle() }
                }
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: gradients[bgIndex], startPoint: .topLeading, endPoint: .bottomTrailing))
                    if isPreview {
                        ScrollView { Text(AttributedString(attributed)).padding() }
                    } else {
                        RichTextEditorView(attributedText: $attributed, placeholder: "Your text here…", onEditing: nil, onResolve: { tv in
                            // Avoid mutating @State during view update; defer to next runloop
                            DispatchQueue.main.async { self.textView = tv }
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 360)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1)))
                
                // Gradients row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(gradients.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: gradients[i], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 60, height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(i == bgIndex ? Color.white : Color.clear, lineWidth: 2))
                                .onTapGesture { bgIndex = i }
                        }
                    }
                }
                
                // Formatting (grouped)
                DisclosureGroup("Formatting") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Button { applyUndo() } label: { Image(systemName: "arrow.uturn.backward") }
                            Button { applyRedo() } label: { Image(systemName: "arrow.uturn.forward") }
                            Divider().frame(height: 16)
                            Button { applyBold() } label: { Text("B").fontWeight(.bold) }
                            Button { applyItalic() } label: { Text("I").italic() }
                            Button { applyUnderline() } label: { Text("U").underline() }
                            Divider().frame(height: 16)
                            Button { setHeading(1) } label: { Text("H1") }
                            Button { setHeading(2) } label: { Text("H2") }
                        }
                        HStack(spacing: 12) {
                            Button { insertBullet() } label: { Image(systemName: "list.bullet") }
                            Button { insertNumbered() } label: { Image(systemName: "list.number") }
                            Button { insertQuote() } label: { Image(systemName: "text.quote") }
                            Button { insertText("@") } label: { Text("@") }
                            Button { insertText("#") } label: { Text("#") }
                            Button { insertLink() } label: { Image(systemName: "link") }
                            Button { insertCode() } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                            Button { toggleAlign() } label: { Image(systemName: "text.aligncenter") }
                            Button { showColor.toggle() } label: { Label("A", systemImage: "square.fill").labelStyle(.iconOnly) }.tint(textColor)
                        }
                    }
                    .font(.caption)
                }
                
                // Primary CTA Row
                HStack {
                    GradientButton(title: "Next") { exportAndDone() }
                    Spacer()
                    Button { saveDraft() } label: { Label("Draft", systemImage: "tray.and.arrow.down.fill") }
                }
            }
            .padding()
            .sheet(isPresented: $showColor) {
                VStack {
                    ColorPicker("Text Color", selection: Binding(get: { textColor }, set: { newValue in
                        textColor = newValue
                        applyColor(UIColor(newValue))
                    }))
                    .padding()
                    Button("Close") { showColor = false }
                }
                .presentationDetents([.height(200)])
            }
        }
        
        private func exportAndDone() {
            let content = ZStack {
                // Opaque background to avoid alpha/NaN issues in CoreGraphics
                LinearGradient(colors: gradients[bgIndex], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack {
                    Text(AttributedString(attributed))
            .padding()
        }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
                .frame(width: 640, height: 640)
                .clipped()
            let renderer = ImageRenderer(content: content)
#if os(iOS)
            renderer.scale = UIScreen.main.scale
            renderer.isOpaque = true
#endif
#if os(iOS)
            if let ui = renderer.uiImage {
                // Pass the rendered image back to parent to proceed to Details step (price/access)
                onDone(ui)
            }
#endif
        }
        private func applyBold() { withCurrentTextView { $0.gc_toggleFontTrait(.traitBold) } }
        private func applyItalic() { withCurrentTextView { $0.gc_toggleFontTrait(.traitItalic) } }
        private func applyUnderline() { withCurrentTextView { $0.gc_applyAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue) } }
        private func applyUndo() { withCurrentTextView { $0.undoManager?.undo() } }
        private func applyRedo() { withCurrentTextView { $0.undoManager?.redo() } }
        private func setHeading(_ level: Int) { let size: CGFloat = level == 1 ? 28 : 24; withCurrentTextView { $0.gc_setFontSize(size) } }
        private func insertBullet() { insertText("\n• ") }
        private func insertNumbered() { insertText("\n1. ") }
        private func insertQuote() { insertText("\n\"\"") }
        private func insertLink() { insertText(" https://") }
        private func insertCode() { insertText(" `code` ") }
        private func toggleAlign() { /* could toggle center/left; for now do nothing visually */ }
        private func insertText(_ s: String) {
            withCurrentTextView { tv in
                if let sel = tv.selectedTextRange {
                    tv.replace(sel, withText: s)
                } else {
                    let end = tv.endOfDocument
                    if let range = tv.textRange(from: end, to: end) { tv.replace(range, withText: s) }
                }
            }
        }
        private func applyColor(_ color: UIColor) { withCurrentTextView { $0.gc_applyAttribute(.foregroundColor, value: color) } }
        private func saveDraft() { UserDefaults.standard.set(attributed.string, forKey: "draft_text_post") }
        private func shareDraft() { /* present share sheet in future */ }
        private func confirmCancel() { dismiss() }
        
        private func withCurrentTextView(_ block: @escaping (UITextView) -> Void) {
            if let tv = textView { block(tv) }
        }
    }
    
    // Removed extension; applyUndo/applyRedo are declared inside TextPostEditor
    
    // MARK: - Media thumbnail view (image or video)
    private struct MediaThumbView: View {
        let item: CreatePostViewModel.MediaItem
        @State private var thumbnail: UIImage? = nil
        
        var body: some View {
            Group {
                if let img = resolvedImage() {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(.white))
                }
            }
            .onAppear { generateIfNeeded() }
        }
        
        private func resolvedImage() -> UIImage? {
            if let thumb = thumbnail { return thumb }
            if item.mime.hasPrefix("image/"), let ui = UIImage(data: item.data) { return ui }
            return nil
        }
        
        private func generateIfNeeded() {
            guard item.mime.hasPrefix("video/"), thumbnail == nil else { return }
            // Write to a temporary file and generate a frame
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("thumb_\(item.id).mp4")
            do {
                try item.data.write(to: tmpURL, options: .atomic)
                let asset: AVAsset = AVURLAsset(url: tmpURL)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                if #available(iOS 18.0, *) {
                    gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                        if let cg { DispatchQueue.main.async { self.thumbnail = UIImage(cgImage: cg) } }
                    }
                } else {
                    if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                        thumbnail = UIImage(cgImage: cg)
                    }
                }
            } catch {
                // Ignore; placeholder will be shown
            }
        }
    }
    
    // MARK: - Fullscreen media editor with adjustable filters
    private struct FullscreenMediaEditor: View {
        @ObservedObject var vm: CreatePostViewModel
        var onBack: () -> Void
        var onDone: () -> Void
        @State private var current: Int = 0
        @State private var preview: UIImage? = nil
        @State private var params: [UUID: FilterParams] = [:]
        @State private var activeControl: Control = .brightness
        @State private var cropMode: Bool = false
        @State private var cropScale: CGFloat = 1.0
        @State private var cropOffset: CGSize = .zero
        @State private var cropAspect: CropAspect = .square
        @State private var controlsExpanded: Bool = false
        // Active tool indicator for side rail highlight
        enum Tool { case crop, caption, stickers, effects, meme, autocaptions }
        @State private var activeTool: Tool? = nil
        // For videos, keep track of duration to support timed overlays
        @State private var videoDuration: [UUID: Double] = [:]
        // Captions per media id
        struct Caption: Identifiable, Equatable {
            let id: UUID
            var text: String
            var center: CGPoint
            var scale: CGFloat
            var rotation: Angle
            var color: Color
            var fontName: String
            var fontSize: CGFloat // in image points
            var outline: Bool
            var alignment: NSTextAlignment
            // Optional timing for video overlays (seconds from start)
            var start: Double? = nil
            var end: Double? = nil
        }
        @State private var captions: [UUID: [Caption]] = [:]
        @State private var selectedCaptionId: UUID? = nil
        @State private var showingCaptionEditor: Bool = false
        // Stickers overlay
        struct Sticker: Identifiable, Equatable {
            let id: UUID
            var imageName: String
            var imageData: Data? = nil
            var center: CGPoint
            var scale: CGFloat
            var rotation: Angle
            // Optional timing for video overlays (seconds from start)
            var start: Double? = nil
            var end: Double? = nil
        }
        @State private var stickers: [UUID: [Sticker]] = [:]
        @State private var selectedStickerId: UUID? = nil
        @State private var showStickerPicker: Bool = false
        @State private var showMemeDialog: Bool = false
        @State private var isAIMemeWorking: Bool = false
        // For videos: remember the preview (thumbnail) size used as coordinate basis
        @State private var overlayBasisSize: [UUID: CGSize] = [:]
        
        private let ctx = CIContext()
        enum Control: String, CaseIterable { case brightness = "Brightness", contrast = "Contrast", saturation = "Saturation", sepia = "Sepia", vignette = "Vignette", temperature = "Temperature" }
        enum CropAspect: String, CaseIterable { case free = "Free", square = "1:1", fourFive = "4:5", sixteenNine = "16:9" }
        struct FilterParams { var brightness: Double = 0, contrast: Double = 1, saturation: Double = 1, sepia: Double = 0, vignette: Double = 0, temperature: Double = 6500 }
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                // Center content fills the screen; chrome is inset to edges
                mediaPagerView
                // Busy overlay for AI meme
                if isAIMemeWorking {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        VStack(spacing: 8) { ProgressView(); Text("AI meme generating…").foregroundStyle(.white) }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                    }
                }
                // Caption editor now appears in the bottomBar safe area inset (not floating)
                // Sticker timing editor when a sticker is selected on a video
                if let selS = selectedStickerId, let mid = currentMediaId(), let dur = videoDuration[mid], let st = (stickers[mid] ?? []).first(where: { $0.id == selS }) {
                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sticker Timing").font(.headline).foregroundStyle(.white)
                            TimingControls(start: st.start, end: st.end, duration: dur) { newStart, newEnd in
                                var arr = stickers[mid] ?? []
                                if let idx = arr.firstIndex(where: { $0.id == st.id }) { arr[idx].start = newStart; arr[idx].end = newEnd }
                                stickers[mid] = arr
                            }
                            HStack { Spacer(); Button("Done") { selectedStickerId = nil }.buttonStyle(.borderedProminent) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.65)))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            // Pin header to the top safe area
            .safeAreaInset(edge: .top) {
                headerBar
                    .background(.ultraThinMaterial)
            }
            // Bottom chrome: caption editor panel OR controls (mutually exclusive)
            .safeAreaInset(edge: .bottom) { bottomBar }
            // Sheet presenters owned by the editor, not the controls subview
            .sheet(isPresented: $showStickerPicker) { StickerPickerView(onPick: { name, data in addSticker(named: name, data: data); showStickerPicker = false }) }
            .sheet(isPresented: $showMemeDialog) { MemePromptSheet(onAdd: { top, bottom in addMeme(top: top, bottom: bottom); showMemeDialog = false }) }
        }

        // MARK: - Subviews (split to speed up type checking)
        @ViewBuilder private var headerBar: some View {
            HStack {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.title2.weight(.semibold)) }
                Spacer()
                Text("Edit").font(.headline)
                Spacer()
                // Actions: Clear overlays, Next
                HStack(spacing: 16) {
                    Button(role: .destructive) {
                        clearOverlaysForCurrent()
                    } label: {
                        Image(systemName: "trash").font(.headline)
                    }
                    Button(action: { Task { await bakeAllEdits(); applyAndNext() } }) { Text("Next").font(.headline) }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }

        private var currentToolLabel: String? {
            switch activeTool {
            case .none: return nil
            case .some(.crop): return "Crop"
            case .some(.caption): return "Caption"
            case .some(.stickers): return "Stickers"
            case .some(.effects): return "Effects"
            case .some(.meme): return "AI Meme"
            case .some(.autocaptions): return "Auto CC"
            }
        }

        @ViewBuilder private var mediaPagerView: some View {
            TabView(selection: $current) {
                ForEach(Array(vm.media.enumerated()), id: \.1.id) { idx, item in
                    ZStack {
                        editorCanvas(for: item)
                    }
                    .tag(idx)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onChange(of: current, perform: { _ in updatePreview() })
            .onAppear { updatePreview() }
            .overlay(alignment: .trailing) {
                SideRail(
                    active: activeTool,
                    onCrop: { selectTool(.crop) },
                    onCaption: { selectCaptionTool() },
                    onStickers: { selectTool(.stickers) },
                    onEffects: { selectTool(.effects) },
                    onMeme: { selectTool(.meme); generateAIMeme() },
                    onCaptions: { selectTool(.autocaptions); autoGenerateCaptions() }
                )
                .padding(.trailing, 8)
                .padding(.top, 40)
            }
            .overlay(alignment: .top) {
                // Context title: "Edit — <Tool>" for extra clarity
                if let label = currentToolLabel {
                    Text("Edit — \(label)")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                }
            }
        }

        @ViewBuilder private var controlsView: some View {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if cropMode {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(CropAspect.allCases, id: \.self) { a in
                                    Text(a.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(cropAspect == a ? Color.white.opacity(0.35) : Color.white.opacity(0.15))
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(Color.white.opacity(cropAspect == a ? 0.9 : 0), lineWidth: 1)
                                        )
                                        .onTapGesture { cropAspect = a }
                                }
                            }
                            .padding(.horizontal)
                        }
                        HStack {
                            Button("Reset") { cropScale = 1.0; cropOffset = .zero }
                            Spacer()
                            Button("Apply Crop") { applyCrop() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Control.allCases, id: \.self) { c in
                                    Text(c.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(activeControl == c ? Color.white.opacity(0.35) : Color.white.opacity(0.15))
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(Color.white.opacity(activeControl == c ? 0.9 : 0), lineWidth: 1)
                                        )
                                        .onTapGesture { activeControl = c }
                                }
                            }
                            .padding(.horizontal)
                        }
                        HStack {
                            Text("Min").foregroundStyle(.white.opacity(0.7)).font(.caption)
                            Slider(value: bindingForActive(), in: rangeForActive())
                            Text("Max").foregroundStyle(.white.opacity(0.7)).font(.caption)
                        }
                        .padding(.horizontal)
                        HStack {
                            Button("Reset Filters") { resetCurrent() }
                            Spacer()
                            Button("Apply to Image") { bakeCurrent() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
            }
        }

        // Bottom bar switches between caption editor and controls
        @ViewBuilder private var bottomBar: some View {
            if let mid = currentMediaId(), let sel = selectedCaptionId, let cap = (captions[mid] ?? []).first(where: { $0.id == sel }) {
                // Caption editor anchored at bottom
                VStack(alignment: .leading, spacing: 10) {
                    CaptionEditorInline(caption: cap, videoLength: (videoDuration[mid]), onChange: { updated in updateCaption(updated) }, onDelete: { deleteCaption(sel) })
                        .padding(.horizontal)
                    HStack {
                        Spacer()
                        Button("Done") { selectedCaptionId = nil }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: 6) {
                    Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5)
                        .padding(.top, 4)
                        .onTapGesture { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { controlsExpanded.toggle() } }
                    if controlsExpanded {
                        controlsView
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .frame(maxHeight: idealExpandedHeight)
                        HStack { Spacer(); Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { controlsExpanded = false } } label: { Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)) } .tint(.white.opacity(0.9)) .padding(.trailing) }
                    } else {
                        collapsedControlsView
                            .transition(.opacity)
                        HStack { Spacer(); Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { controlsExpanded = true } } label: { Image(systemName: "chevron.up").font(.subheadline.weight(.semibold)) } .tint(.white.opacity(0.9)) .padding(.trailing) }
                    }
                }
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }

        // Collapsed, compact version of controls: only the chips and a quick action
        @ViewBuilder private var collapsedControlsView: some View {
            VStack(spacing: 8) {
                if cropMode {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(CropAspect.allCases, id: \.self) { a in
                                Text(a.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(cropAspect == a ? Color.white.opacity(0.35) : Color.white.opacity(0.15))
                                    .clipShape(Capsule())
                                    .onTapGesture { cropAspect = a }
                            }
                        }
                        .padding(.horizontal)
                    }
                    HStack {
                        Button("Reset") { cropScale = 1.0; cropOffset = .zero }
                        Spacer()
                        Button("Apply") { applyCrop() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Control.allCases, id: \.self) { c in
                                Text(c.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(activeControl == c ? Color.white.opacity(0.35) : Color.white.opacity(0.15))
                                    .clipShape(Capsule())
                                    .onTapGesture { activeControl = c }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { controlsExpanded = true } }) {
                    Text("Expand").font(.caption.weight(.semibold))
                }
            }
        }

        // Heuristic height for expanded panel; shorter on compact devices
        private var idealExpandedHeight: CGFloat {
            #if os(iOS)
            let h = UIScreen.main.bounds.height
            if h < 700 { return 220 }
            if h < 820 { return 260 }
            return 300
            #else
            return 260
            #endif
        }
            
            func currentMediaId() -> UUID? { vm.media.indices.contains(current) ? vm.media[current].id : nil }
            func addCaption() {
                guard let mid = currentMediaId(), let ui = preview else { return }
                let center = CGPoint(x: ui.size.width/2, y: ui.size.height/2)
                let cap = Caption(
                    id: UUID(),
                    text: "Caption",
                    center: center,
                    scale: 1.0,
                    rotation: .degrees(0),
                    color: .white,
                    fontName: "HelveticaNeue",
                    fontSize: max(24, min(48, min(ui.size.width, ui.size.height) * 0.05)),
                    outline: false,
                    alignment: .center
                )
                var arr = captions[mid] ?? []
                arr.append(cap)
                captions[mid] = arr
                selectedCaptionId = cap.id
            }
            func addSticker(named: String, data: Data? = nil) {
                guard let mid = currentMediaId(), let ui = preview else { return }
                let center = CGPoint(x: ui.size.width/2, y: ui.size.height/2)
                let st = Sticker(id: UUID(), imageName: named, imageData: data, center: center, scale: 1.0, rotation: .degrees(0))
                var arr = stickers[mid] ?? []
                arr.append(st)
                stickers[mid] = arr
                selectedStickerId = st.id
            }
            func generateAIMeme() {
                guard let ui = preview else { showMemeDialog = true; return }
                isAIMemeWorking = true
                Task {
                    let resOpt = try? await SupabaseManager.shared.generateMeme(image: ui)
                    if let res = resOpt {
                        let top = res.top_text?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let bottom = res.bottom_text?.trimmingCharacters(in: .whitespacesAndNewlines)
                        addMeme(top: top, bottom: bottom)
                        if let sts = res.stickers {
                            let known = ["unicorn","rose","trophy","diamond","gift","friends","google","logo","bell","nebula"]
                            for s in sts {
                                let key = s.lowercased()
                                if let match = known.first(where: { key.contains($0) }) { addSticker(named: match) }
                            }
                        }
                // hint banner could be shown here if desired
                    } else {
                        showMemeDialog = true
                    }
                    isAIMemeWorking = false
                }
            }
            func autoGenerateCaptions() {
                guard vm.media.indices.contains(current) else { return }
                let item = vm.media[current]
                guard item.mime.hasPrefix("video/") else { return }
                isAIMemeWorking = true
                Task {
                    defer { isAIMemeWorking = false }
                    if let segments = try? await SupabaseManager.shared.generateAutoCaptions(videoData: item.data) {
                        let mid = item.id
                        let base = overlayBasisSize[mid] ?? CGSize(width: 1080, height: 1920)
                        var arr = captions[mid] ?? []
                        for seg in segments {
                            let y = base.height - max(28, base.height * 0.08)
                            let cap = Caption(
                                id: UUID(),
                                text: seg.text,
                                center: CGPoint(x: base.width/2, y: y),
                                scale: 1.0,
                                rotation: .degrees(0),
                                color: .white,
                                fontName: "HelveticaNeue-CondensedBlack",
                                fontSize: max(22, min(40, min(base.width, base.height) * 0.045)),
                                outline: true,
                                alignment: .center,
                                start: seg.start,
                                end: seg.end
                            )
                            arr.append(cap)
                        }
                        captions[mid] = arr
                    }
                }
            }
            func addMeme(top: String?, bottom: String?) {
                guard let _ = currentMediaId(), let ui = preview else { return }
                if let t = top, !t.trimmingCharacters(in: .whitespaces).isEmpty {
                    let cap = Caption(
                        id: UUID(),
                        text: t.uppercased(),
                        center: CGPoint(x: ui.size.width/2, y: max(24, ui.size.height * 0.08)),
                        scale: 1.0,
                        rotation: .degrees(0),
                        color: .white,
                        fontName: "HelveticaNeue-CondensedBlack",
                        fontSize: max(28, min(56, min(ui.size.width, ui.size.height) * 0.06)),
                        outline: true,
                        alignment: .center
                    )
                    var arr = captions[currentMediaId()!] ?? []
                    arr.append(cap)
                    captions[currentMediaId()!] = arr
                    selectedCaptionId = cap.id
                }
                if let b = bottom, !b.trimmingCharacters(in: .whitespaces).isEmpty {
                    let cap = Caption(
                        id: UUID(),
                        text: b.uppercased(),
                        center: CGPoint(x: ui.size.width/2, y: ui.size.height - max(28, ui.size.height * 0.08)),
                        scale: 1.0,
                        rotation: .degrees(0),
                        color: .white,
                        fontName: "HelveticaNeue-CondensedBlack",
                        fontSize: max(28, min(56, min(ui.size.width, ui.size.height) * 0.06)),
                        outline: true,
                        alignment: .center
                    )
                    var arr = captions[currentMediaId()!] ?? []
                    arr.append(cap)
                    captions[currentMediaId()!] = arr
                    selectedCaptionId = cap.id
                }
            }
             func updateCaption(_ updated: Caption) {
                guard let mid = currentMediaId() else { return }
                var arr = captions[mid] ?? []
                if let idx = arr.firstIndex(where: { $0.id == updated.id }) { arr[idx] = updated }
                captions[mid] = arr
            }
             func deleteCaption(_ id: UUID) {
                guard let mid = currentMediaId() else { return }
                var arr = captions[mid] ?? []
                arr.removeAll { $0.id == id }
                captions[mid] = arr
                if selectedCaptionId == id { selectedCaptionId = nil }
            }
             func bakeAllEdits() async {
                for i in vm.media.indices {
                    let item = vm.media[i]
                    if item.mime.hasPrefix("image/"), let base = UIImage(data: item.data) {
                        let filtered = filteredImage(for: base, params: params[item.id] ?? FilterParams()) ?? base
                        let baked = drawOverlays(on: filtered, mediaId: item.id)
                        if let out = baked.jpegData(compressionQuality: 0.9) {
                            await MainActor.run { vm.media[i] = .init(data: out, mime: "image/jpeg", kind: .photo) }
                        }
                    } else if item.mime.hasPrefix("video/") {
                        let basis = overlayBasisSize[item.id] ?? CGSize(width: 1080, height: 1920)
                        let caps = captions[item.id] ?? []
                        let sts = stickers[item.id] ?? []
                        let url = tempURL(for: item)
                        do { try item.data.write(to: url, options: .atomic) } catch { continue }
                        if let outURL = await exportVideoWithOverlays(input: url, basisSize: basis, captions: caps, stickers: sts),
                           let data = try? Data(contentsOf: outURL) {
                            await MainActor.run { vm.media[i] = .init(data: data, mime: "video/mp4", kind: .video) }
                            try? FileManager.default.removeItem(at: outURL)
                        }
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                await MainActor.run { updatePreview() }
            }
             func drawOverlays(on image: UIImage, mediaId: UUID) -> UIImage {
                let scale = image.scale
                // Use opaque=true to avoid introducing an alpha channel for opaque bases (saves memory, removes console warnings)
                UIGraphicsBeginImageContextWithOptions(image.size, true, scale)
                image.draw(in: CGRect(origin: .zero, size: image.size))
                if let arr = captions[mediaId] {
                    for cap in arr {
                        // Use base font size and scale via context to avoid double-scaling issues
                        let font = UIFont(name: cap.fontName, size: max(8, cap.fontSize)) ?? UIFont.systemFont(ofSize: max(8, cap.fontSize), weight: .semibold)
                        let para = NSMutableParagraphStyle(); para.alignment = cap.alignment
                        var attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: UIColor(cap.color),
                            .paragraphStyle: para
                        ]
                        if cap.outline {
                            attrs[.strokeColor] = UIColor.black
                            attrs[.strokeWidth] = -3.0
                        }
                        let text = NSString(string: cap.text)
                        let maxW: CGFloat = image.size.width * 0.9
                        let bounding = text.boundingRect(with: CGSize(width: maxW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil).integral
                        let size = bounding.size
                        let center = cap.center
                        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
                        if let ctx = UIGraphicsGetCurrentContext() {
                            ctx.saveGState()
                            ctx.translateBy(x: center.x, y: center.y)
                            ctx.rotate(by: CGFloat(cap.rotation.radians))
                            ctx.scaleBy(x: cap.scale, y: cap.scale)
                            ctx.translateBy(x: -center.x, y: -center.y)
                            text.draw(in: rect, withAttributes: attrs)
                            ctx.restoreGState()
                        }
                    }
                }
                if let sts = stickers[mediaId] {
                    for s in sts {
                        let ui: UIImage? = {
                            if let d = s.imageData, let img = UIImage(data: d) { return img }
                            return UIImage(named: s.imageName)
                        }()
                        if let ui = ui {
                            let size = CGSize(width: ui.size.width, height: ui.size.height)
                            let center = s.center
                            let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
                            let ctx = UIGraphicsGetCurrentContext()
                            ctx?.saveGState()
                            ctx?.translateBy(x: center.x, y: center.y)
                            ctx?.rotate(by: CGFloat(s.rotation.radians))
                            ctx?.scaleBy(x: s.scale, y: s.scale)
                            ctx?.translateBy(x: -center.x, y: -center.y)
                            ui.draw(in: rect)
                            ctx?.restoreGState()
                        }
                    }
                }
                let out = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
                return out
            }
            
            func tempURL(for item: CreatePostViewModel.MediaItem) -> URL {
                let ext = item.kind == .video ? "mp4" : "jpg"
                return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gc_\(item.id).\(ext)")
            }
            
            @MainActor
            func exportVideoWithOverlays(input: URL, basisSize: CGSize, captions: [Caption], stickers: [Sticker]) async -> URL? {
                let asset = AVAsset(url: input)
                let vTrackOpt: AVAssetTrack?
                let aTrackOpt: AVAssetTrack?
                let duration: CMTime
                let natural: CGSize
                let preferredTransform: CGAffineTransform
                if #available(iOS 16.0, *) {
                    let vTracks = try? await asset.loadTracks(withMediaType: .video)
                    vTrackOpt = vTracks?.first
                    let aTracks = try? await asset.loadTracks(withMediaType: .audio)
                    aTrackOpt = aTracks?.first
                    duration = (try? await asset.load(.duration)) ?? .zero
                    natural = (try? await vTrackOpt?.load(.naturalSize)) ?? .zero
                    preferredTransform = (try? await vTrackOpt?.load(.preferredTransform)) ?? .identity
                } else {
                    vTrackOpt = asset.tracks(withMediaType: .video).first
                    aTrackOpt = asset.tracks(withMediaType: .audio).first
                    duration = asset.duration
                    natural = vTrackOpt?.naturalSize ?? .zero
                    preferredTransform = vTrackOpt?.preferredTransform ?? .identity
                }
                guard let vTrack = vTrackOpt else { return nil }
                let comp = AVMutableComposition()
                guard let vComp = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
                let timeRange = CMTimeRange(start: .zero, duration: duration)
                try? vComp.insertTimeRange(timeRange, of: vTrack, at: .zero)
                if let aTrack = aTrackOpt, let aComp = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? aComp.insertTimeRange(timeRange, of: aTrack, at: .zero)
                }
                let naturalApplied = natural.applying(preferredTransform)
                let renderSize = CGSize(width: abs(naturalApplied.width), height: abs(naturalApplied.height))
                
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = timeRange
                let layerInst = AVMutableVideoCompositionLayerInstruction(assetTrack: vComp)
                layerInst.setTransform(preferredTransform, at: .zero)
                inst.layerInstructions = [layerInst]
                let videoComp = AVMutableVideoComposition()
                videoComp.instructions = [inst]
                videoComp.renderSize = renderSize
                videoComp.frameDuration = CMTime(value: 1, timescale: 30)
                
                let parent = CALayer()
                parent.frame = CGRect(origin: .zero, size: renderSize)
                let videoLayer = CALayer()
                videoLayer.frame = parent.frame
                parent.addSublayer(videoLayer)
                
                func mapPoint(_ p: CGPoint, from: CGSize, to: CGSize) -> CGPoint {
                    let imageAspect = from.width / from.height
                    let viewAspect = to.width / to.height
                    var drawSize: CGSize
                    if imageAspect > viewAspect { drawSize = CGSize(width: to.width, height: to.width / imageAspect) } else { drawSize = CGSize(width: to.height * imageAspect, height: to.height) }
                    let origin = CGPoint(x: (to.width - drawSize.width)/2, y: (to.height - drawSize.height)/2)
                    return CGPoint(x: origin.x + (p.x / from.width) * drawSize.width, y: origin.y + (p.y / from.height) * drawSize.height)
                }
                
                let totalSeconds = max(0.01, CMTimeGetSeconds(duration))
                for cap in captions {
                    let font = UIFont(name: cap.fontName, size: max(8, cap.fontSize)) ?? UIFont.systemFont(ofSize: max(8, cap.fontSize), weight: .bold)
                    let para = NSMutableParagraphStyle(); para.alignment = cap.alignment
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: UIColor(cap.color),
                        .paragraphStyle: para
                    ]
                    if cap.outline { attrs[.strokeColor] = UIColor.black; attrs[.strokeWidth] = -3.0 }
                    let text = NSAttributedString(string: cap.text, attributes: attrs)
                    let maxW: CGFloat = renderSize.width * 0.9
                    let bounding = text.boundingRect(with: CGSize(width: maxW, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral
                    let size = CGSize(width: bounding.width * cap.scale, height: bounding.height * cap.scale)
                    let center = mapPoint(cap.center, from: basisSize, to: renderSize)
                    let layer = CATextLayer()
                    layer.string = text
                    layer.alignmentMode = para.alignment == .center ? .center : (para.alignment == .right ? .right : .left)
                    layer.contentsScale = UIScreen.main.scale
                    layer.frame = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
                    layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(cap.rotation.radians)))
                    // Treat missing start/end as 0/duration so one-sided timing works
                    let s = cap.start ?? 0
                    let e = cap.end ?? totalSeconds
                    if e > s {
                        layer.opacity = 0
                        let anim = CAKeyframeAnimation(keyPath: "opacity")
                        anim.values = [0, 1, 1, 0]
                        anim.keyTimes = [NSNumber(value: 0.0), NSNumber(value: max(0.0, s/totalSeconds)), NSNumber(value: min(1.0, e/totalSeconds)), NSNumber(value: 1.0)]
                        anim.duration = totalSeconds
                        anim.isRemovedOnCompletion = false
                        anim.fillMode = .forwards
                        layer.add(anim, forKey: "opacity")
                    }
                    parent.addSublayer(layer)
                }
                for s in stickers {
                    let cg: CGImage? = {
                        if let d = s.imageData, let img = UIImage(data: d)?.cgImage { return img }
                        return UIImage(named: s.imageName)?.cgImage
                    }()
                    if let ui = cg {
                        let baseW = min(renderSize.width, renderSize.height) * 0.25
                        let w = baseW * s.scale
                        let h = w * CGFloat(ui.height) / CGFloat(ui.width)
                        let center = mapPoint(s.center, from: basisSize, to: renderSize)
                        let layer = CALayer()
                        layer.contents = ui
                        layer.frame = CGRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)
                        layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(s.rotation.radians)))
                        // Treat missing start/end as 0/duration so one-sided timing works
                        let st = s.start ?? 0
                        let en = s.end ?? totalSeconds
                        if en > st {
                            layer.opacity = 0
                            let anim = CAKeyframeAnimation(keyPath: "opacity")
                            anim.values = [0, 1, 1, 0]
                            anim.keyTimes = [NSNumber(value: 0.0), NSNumber(value: max(0.0, st/totalSeconds)), NSNumber(value: min(1.0, en/totalSeconds)), NSNumber(value: 1.0)]
                            anim.duration = totalSeconds
                            anim.isRemovedOnCompletion = false
                            anim.fillMode = .forwards
                            layer.add(anim, forKey: "opacity")
                        }
                        parent.addSublayer(layer)
                    }
                }
                videoComp.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
                let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gc_out_\(UUID().uuidString).mp4")
                return await withUnsafeContinuation { cont in
                    guard let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else { cont.resume(returning: nil); return }
                    exporter.outputURL = outURL
                    exporter.outputFileType = .mp4
                    exporter.videoComposition = videoComp
                    exporter.exportAsynchronously {
                        let exists = FileManager.default.fileExists(atPath: outURL.path)
                        cont.resume(returning: exists ? outURL : nil)
                    }
                }
            }
            
            func bindingForActive() -> Binding<Double> {
                guard vm.media.indices.contains(current) else { return .constant(0) }
                let id = vm.media[current].id
                let existing = params[id] ?? FilterParams()
                return Binding<Double>(
                    get: {
                        switch activeControl {
                        case .brightness: return (existing.brightness + 0.5) * 100
                        case .contrast: return (existing.contrast / 2) * 100
                        case .saturation: return (existing.saturation / 2) * 100
                        case .sepia: return existing.sepia * 100
                        case .vignette: return existing.vignette * 100
                        case .temperature: return (existing.temperature - 3000) / 7000 * 100
                        }
                    },
                    set: { newVal in
                        var p = existing
                        switch activeControl {
                        case .brightness: p.brightness = (newVal/100) - 0.5
                        case .contrast: p.contrast = max(0.0, (newVal/100) * 2)
                        case .saturation: p.saturation = max(0.0, (newVal/100) * 2)
                        case .sepia: p.sepia = newVal/100
                        case .vignette: p.vignette = newVal/100
                        case .temperature: p.temperature = 3000 + (newVal/100)*7000
                        }
                        params[id] = p
                        updatePreview()
                    }
                )
            }
            func rangeForActive() -> ClosedRange<Double> { 0...100 }
            
            func resetCurrent() {
                guard vm.media.indices.contains(current) else { return }
                params[vm.media[current].id] = FilterParams()
                cropScale = 1.0; cropOffset = .zero
                updatePreview()
            }
            func bakeCurrent() {
                guard vm.media.indices.contains(current) else { return }
                let item = vm.media[current]
                guard item.mime.hasPrefix("image/"), let original = UIImage(data: item.data), let ui = filteredImage(for: original, params: params[item.id] ?? FilterParams()) else { return }
                if let data = ui.jpegData(compressionQuality: 0.9) {
                    vm.media[current] = .init(data: data, mime: "image/jpeg", kind: .photo)
                }
                updatePreview()
            }
            func applyAndNext() { onDone() }

            func clearOverlaysForCurrent() {
                guard let mid = currentMediaId() else { return }
                captions[mid] = []
                stickers[mid] = []
                selectedCaptionId = nil
                selectedStickerId = nil
            }
            
            func applyCrop() {
                guard vm.media.indices.contains(current) else { return }
                let item = vm.media[current]
                guard item.mime.hasPrefix("image/"), let original = UIImage(data: item.data) else { return }
                // Compute crop rect in image coordinates based on cropScale and cropOffset within a unit viewport
                // Assume base uses aspect fill to cropAspect target; compute rect proportionally.
                let targetAspect: CGFloat = {
                    switch cropAspect { case .free: return original.size.width / original.size.height
                    case .square: return 1.0
                    case .fourFive: return 4.0/5.0
                        case .sixteenNine: return 16.0/9.0 }
                }()
                let iw = original.size.width, ih = original.size.height
                let cropH = (iw / targetAspect) <= ih ? (iw / targetAspect) : ih
                let cropW = min(iw, cropH * targetAspect)
                let x = (iw - cropW)/2 - cropOffset.width * (iw/cropW) / cropScale
                let y = (ih - cropH)/2 - cropOffset.height * (ih/cropH) / cropScale
                let w = cropW / cropScale
                let h = cropH / cropScale
                let rect = CGRect(x: max(0, min(iw - w, x)), y: max(0, min(ih - h, y)), width: min(iw, w), height: min(ih, h))
                if let cg = original.cgImage?.cropping(to: rect) {
                    let ui = UIImage(cgImage: cg, scale: original.scale, orientation: original.imageOrientation)
                    if let data = ui.jpegData(compressionQuality: 0.95) {
                        vm.media[current] = .init(data: data, mime: "image/jpeg", kind: .photo)
                    }
                    updatePreview()
                }
            }

            // Ensure only one pane is visible; close others and set state for selected tool.
            func selectTool(_ t: Tool) {
                activeTool = t
                // Close other panes
                selectedCaptionId = nil
                selectedStickerId = nil
                switch t {
                case .crop:
                    cropMode = true
                    controlsExpanded = true
                case .effects:
                    cropMode = false
                    controlsExpanded = true
                case .stickers:
                    cropMode = false
                    controlsExpanded = false
                    showStickerPicker = true
                case .meme, .autocaptions:
                    cropMode = false
                    controlsExpanded = false
                case .caption:
                    // handled by selectCaptionTool()
                    break
                }
            }
            func selectCaptionTool() {
                activeTool = .caption
                cropMode = false
                controlsExpanded = false
                selectedStickerId = nil
                if selectedCaptionId == nil {
                    if let mid = currentMediaId(), let existing = captions[mid], !existing.isEmpty {
                        selectedCaptionId = existing.last?.id
                    } else {
                        addCaption()
                    }
                }
            }
            
            func updatePreview() {
                guard vm.media.indices.contains(current) else { preview = nil; return }
                let item = vm.media[current]
                preview = renderPreview(for: item)
            }
            func renderPreview(for item: CreatePostViewModel.MediaItem) -> UIImage? {
                if item.mime.hasPrefix("image/"), let ui = UIImage(data: item.data) {
                    return filteredImage(for: ui, params: params[item.id] ?? FilterParams())
                }
                if item.mime.hasPrefix("video/") {
                    let url = tempURL(for: item)
                    do { try item.data.write(to: url, options: .atomic) } catch { return nil }
                    let asset = AVAsset(url: url)
                    if #available(iOS 16.0, *) {
                        Task {
                            let d = try? await asset.load(.duration)
                            let secs = CMTimeGetSeconds(d ?? .zero)
                            if secs.isFinite {
                                await MainActor.run { videoDuration[item.id] = secs }
                            }
                        }
                    } else {
                        let secs = CMTimeGetSeconds(asset.duration)
                        if secs.isFinite { videoDuration[item.id] = secs }
                    }
                    let gen = AVAssetImageGenerator(asset: asset)
                    gen.appliesPreferredTrackTransform = true
                    if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                        let ui = UIImage(cgImage: cg)
                        overlayBasisSize[item.id] = ui.size
                        return ui
                    }
                }
                return nil
            }
            
            func filteredImage(for ui: UIImage, params: FilterParams) -> UIImage? {
                guard let cg = ui.cgImage else { return ui }
                var img = CIImage(cgImage: cg)
                // Temperature/tint
                if let temp = CIFilter(name: "CITemperatureAndTint") {
                    temp.setValue(img, forKey: kCIInputImageKey)
                    temp.setValue(CIVector(x: CGFloat(params.temperature), y: 0), forKey: "inputNeutral")
                    img = temp.outputImage ?? img
                }
                // Color controls
                let color = CIFilter.colorControls()
                color.inputImage = img
                color.brightness = Float(params.brightness)
                color.contrast = Float(params.contrast)
                color.saturation = Float(params.saturation)
                img = color.outputImage ?? img
                // Sepia
                if params.sepia > 0 {
                    let f = CIFilter.sepiaTone(); f.inputImage = img; f.intensity = Float(params.sepia)
                    img = f.outputImage ?? img
                }
                // Vignette
                if params.vignette > 0, let f = CIFilter(name: "CIVignette") {
                    f.setValue(img, forKey: kCIInputImageKey)
                    f.setValue(params.vignette * 2.5, forKey: kCIInputIntensityKey)
                    f.setValue(2.0, forKey: kCIInputRadiusKey)
                    img = f.outputImage ?? img
                }
                if let out = ctx.createCGImage(img, from: img.extent) {
                    return UIImage(cgImage: out, scale: ui.scale, orientation: ui.imageOrientation)
                }
                return ui
            }
        }

        // MARK: - Android-style side rail
        private struct SideRail: View {
            var active: FullscreenMediaEditor.Tool?
            var onCrop: () -> Void
            var onCaption: () -> Void
            var onStickers: () -> Void
            var onEffects: () -> Void
            var onMeme: () -> Void
            var onCaptions: () -> Void
            @State private var expanded = false
            var body: some View {
                VStack(spacing: 12) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                        Image(systemName: expanded ? "chevron.right" : "chevron.left")
                            .rotationEffect(.degrees(90))
                            .padding(8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.15))
                    .foregroundStyle(.white)
                    railButton(icon: "crop", label: "Crop", isActive: active == .crop, action: onCrop, expanded: expanded)
                    railButton(icon: "textformat", label: "Caption", isActive: active == .caption, action: onCaption, expanded: expanded)
                    railButton(icon: "face.smiling", label: "Stickers", isActive: active == .stickers, action: onStickers, expanded: expanded)
                    railButton(icon: "wand.and.stars", label: "Effects", isActive: active == .effects, action: onEffects, expanded: expanded)
                    railButton(icon: "text.bubble", label: "AI Meme", isActive: active == .meme, action: onMeme, expanded: expanded)
                    railButton(icon: "captions.bubble.fill", label: "Auto CC", isActive: active == .autocaptions, action: onCaptions, expanded: expanded)
                }
            }
            @ViewBuilder
            private func railButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void, expanded: Bool) -> some View {
                HStack(spacing: 8) {
                    Button(action: action) {
                        Image(systemName: icon)
                            .padding(8)
                    }
                    .buttonStyle(.bordered)
                    .tint(isActive ? .white.opacity(0.35) : .white.opacity(0.15))
                    .foregroundStyle(.white)
                    if expanded {
                        Text(label)
                            .font(.caption.weight(isActive ? .bold : .regular))
                            .foregroundStyle(isActive ? .white : .white.opacity(0.85))
                            .transition(.opacity)
                    }
                }
                .padding(.leading, 4)
                .overlay(alignment: .leading) {
                    if isActive {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2)
                    }
                }
            }
        }
        
        // MARK: - Captions overlay view
        private struct CaptionsOverlay: View {
            let baseImage: UIImage
            var items: [FullscreenMediaEditor.Caption]
            var onChange: ([FullscreenMediaEditor.Caption]) -> Void
            @Binding var selectedId: UUID?
            var body: some View {
                GeometryReader { geo in
                    let imgSize = baseImage.size
                    ZStack {
                        ForEach(items) { c in
                            DraggableCaption(
                                caption: c,
                                imageSize: imgSize,
                                viewSize: geo.size,
                                isSelected: c.id == selectedId
                            ) { updated in
                                var arr = items
                                if let idx = arr.firstIndex(where: { $0.id == c.id }) {
                                    arr[idx] = updated
                                    onChange(arr)
                                }
                                selectedId = c.id
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedId = c.id }
                        }
                    }
                }
                .allowsHitTesting(true)
            }
        }
        
        // MARK: - Stickers overlay
        private struct StickersOverlay: View {
            let baseImage: UIImage
            var items: [FullscreenMediaEditor.Sticker]
            var onChange: ([FullscreenMediaEditor.Sticker]) -> Void
            @Binding var selectedId: UUID?
            var body: some View {
                GeometryReader { geo in
                    let imgSize = baseImage.size
                    ZStack {
                        ForEach(items) { s in
                            DraggableSticker(
                                sticker: s,
                                imageSize: imgSize,
                                viewSize: geo.size,
                                isSelected: s.id == selectedId,
                                onSelect: { selectedId = s.id },
                                onDelete: { id in
                                    var arr = items
                                    arr.removeAll { $0.id == id }
                                    onChange(arr)
                                    if selectedId == id { selectedId = nil }
                                },
                                onUpdate: { updated in
                                    var arr = items
                                    if let idx = arr.firstIndex(where: { $0.id == updated.id }) { arr[idx] = updated }
                                    onChange(arr)
                                }
                            )
                        }
                    }
                }
            }
        }
        
        private struct DraggableSticker: View {
            var sticker: FullscreenMediaEditor.Sticker
            var imageSize: CGSize
            var viewSize: CGSize
            var isSelected: Bool
            var onSelect: () -> Void
            var onDelete: (UUID) -> Void
            var onUpdate: (FullscreenMediaEditor.Sticker) -> Void
            @State private var localScale: CGFloat = 1.0
            @State private var localRotation: Angle = .degrees(0)
            @State private var localOffset: CGSize = .zero
            var body: some View {
                let mapped = mapImageToView(sticker.center, image: imageSize, in: viewSize)
                let ui: UIImage? = {
                    if let d = sticker.imageData { return UIImage(data: d) }
                    return nil
                }()
                let imageView: Image = {
                    if let img = ui { return Image(uiImage: img) }
                    return Image(sticker.imageName)
                }()
                imageView
                    .resizable()
                    .scaledToFit()
                    .frame(width: max(40, viewSize.width * 0.25) * (localScale == 1.0 ? sticker.scale : localScale))
                    .rotationEffect(localRotation == .degrees(0) ? sticker.rotation : localRotation)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
                    )
                    .shadow(color: Color.white.opacity(isSelected ? 0.25 : 0), radius: 6)
                    .position(x: mapped.x + localOffset.width, y: mapped.y + localOffset.height)
                    .onTapGesture { onSelect() }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDelete(sticker.id)
                        } label: {
                            Label("Delete Sticker", systemImage: "trash")
                        }
                    }
                    .gesture(
                        SimultaneousGesture(
                            DragGesture().onChanged { v in localOffset = v.translation }.onEnded { _ in
                                var updated = sticker
                                updated.center = mapViewToImage(CGPoint(x: mapped.x + localOffset.width, y: mapped.y + localOffset.height), image: imageSize, in: viewSize)
                                localOffset = .zero
                                onUpdate(updated)
                            },
                            SimultaneousGesture(
                                MagnificationGesture().onChanged { s in localScale = max(0.3, s) }.onEnded { _ in var u = sticker; u.scale = localScale; localScale = 1.0; onUpdate(u) },
                                RotationGesture().onChanged { r in localRotation = r }.onEnded { _ in var u = sticker; u.rotation = localRotation; localRotation = .degrees(0); onUpdate(u) }
                            )
                        )
                    )
            }
            private func contentRect(image: CGSize, in view: CGSize) -> CGRect {
                let imageAspect = image.width / image.height
                let viewAspect = view.width / view.height
                var drawSize: CGSize
                if imageAspect > viewAspect { drawSize = CGSize(width: view.width, height: view.width / imageAspect) }
                else { drawSize = CGSize(width: view.height * imageAspect, height: view.height) }
                let origin = CGPoint(x: (view.width - drawSize.width)/2, y: (view.height - drawSize.height)/2)
                return CGRect(origin: origin, size: drawSize)
            }
            private func mapImageToView(_ p: CGPoint, image: CGSize, in view: CGSize) -> CGPoint {
                let rect = contentRect(image: image, in: view)
                return CGPoint(x: rect.origin.x + (p.x / image.width) * rect.size.width,
                               y: rect.origin.y + (p.y / image.height) * rect.size.height)
            }
            private func mapViewToImage(_ q: CGPoint, image: CGSize, in view: CGSize) -> CGPoint {
                let rect = contentRect(image: image, in: view)
                let dx = q.x - rect.origin.x
                let dy = q.y - rect.origin.y
                let nx = max(0, min(rect.size.width, dx)) / rect.size.width
                let ny = max(0, min(rect.size.height, dy)) / rect.size.height
                return CGPoint(x: nx * image.width, y: ny * image.height)
            }
        }
        
        // MARK: - Simple sticker picker
        private struct StickerPickerView: View {
            var onPick: (String, Data?) -> Void
            @State private var remote: [SupabaseManager.DBSticker] = []
            private let supa = SupabaseManager.shared
            private let localCandidates = ["unicorn", "rose", "trophy", "diamond", "gift", "friends", "google", "logo", "bell", "nebula"]
            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !remote.isEmpty {
                                Text("Featured").font(.subheadline.weight(.semibold)).padding(.horizontal)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                                    ForEach(remote) { s in
                                        if let url = URL(string: s.image_url) {
                                            AsyncImage(url: url) { img in
                                                img.resizable().scaledToFit()
                                            } placeholder: { Color(.secondarySystemBackground) }
                                            .frame(height: 64)
                                            .onTapGesture {
                                                Task {
                                                    if let (data, _) = try? await URLSession.shared.data(from: url) {
                                                        onPick(s.name, data)
                                                    } else { onPick(s.name, nil) }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            Text("Library").font(.subheadline.weight(.semibold)).padding(.horizontal)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                                ForEach(localCandidates, id: \.self) { name in
                                    Image(name).resizable().scaledToFit().frame(height: 64).onTapGesture { onPick(name, nil) }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }
                    .navigationTitle("Stickers")
                }
                .task { if remote.isEmpty { if let rows = try? await supa.fetchStickers() { remote = rows } } }
            }
        }
        
        // MARK: - Meme prompt alert
        private struct MemePromptSheet: View {
            var onAdd: (String?, String?) -> Void
            @State private var top: String = ""
            @State private var bottom: String = ""
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Top text", text: $top)
                    TextField("Bottom text", text: $bottom)
                    HStack { Spacer(); Button("Add") { onAdd(top, bottom) } }
                }
                .padding(.vertical, 4)
            }
        }
        
        // MARK: - Utility modifiers
        private struct OutlineModifier: ViewModifier {
            let on: Bool
            func body(content: Content) -> some View {
                if on {
                    content
                        .shadow(color: .black.opacity(0.9), radius: 0, x: 1, y: 1)
                        .shadow(color: .black.opacity(0.9), radius: 0, x: -1, y: -1)
                } else {
                    content
                }
            }
        }
        
        private struct DraggableCaption: View {
            var caption: FullscreenMediaEditor.Caption
            var imageSize: CGSize
            var viewSize: CGSize
            var isSelected: Bool
            var onUpdate: (FullscreenMediaEditor.Caption) -> Void
            @State private var localCenter: CGPoint = .zero
            @State private var localScale: CGFloat = 1.0
            @State private var localRotation: Angle = .degrees(0)
            @State private var lastCenter: CGPoint = .zero
            @State private var lastScale: CGFloat = 1.0
            @State private var lastRotation: Angle = .degrees(0)
            var body: some View {
                let mapped = mapPoint(caption.center, from: imageSize, to: viewSize)
                let baseSize = caption.fontSize * (viewSize.width / imageSize.width)
                let displaySize = max(10, baseSize) * (localScale == 1.0 ? caption.scale : localScale)
                let textView = Text(caption.text)
                    .font(.custom(caption.fontName, size: displaySize))
                    .foregroundStyle(caption.color)
                    .modifier(OutlineModifier(on: caption.outline))
                textView
                    .position(localCenter == .zero ? mapped : localCenter)
                    .rotationEffect(localRotation == .degrees(0) ? caption.rotation : localRotation)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Circle().stroke(Color.white, lineWidth: 1).frame(width: 8, height: 8)
                                .offset(x: 12, y: -12)
                        }
                    }
                    .shadow(color: Color.white.opacity(isSelected ? 0.25 : 0), radius: 6)
                    .gesture(DragGesture().onChanged { v in
                        localCenter = v.location
                    }.onEnded { _ in
                        let imgPoint = mapPoint(localCenter == .zero ? mapped : localCenter, from: viewSize, to: imageSize)
                        var updated = caption
                        updated.center = imgPoint
                        updated.scale = (localScale == 1.0 ? caption.scale : localScale)
                        updated.rotation = (localRotation == .degrees(0) ? caption.rotation : localRotation)
                        onUpdate(updated)
                    })
                    .simultaneousGesture(MagnificationGesture().onChanged { s in
                        localScale = s
                    }.onEnded { _ in
                        let imgPoint = mapPoint(localCenter == .zero ? mapped : localCenter, from: viewSize, to: imageSize)
                        var updated = caption
                        updated.center = imgPoint
                        updated.scale = localScale
                        onUpdate(updated)
                    })
                    .simultaneousGesture(RotationGesture().onChanged { r in
                        localRotation = r
                    }.onEnded { _ in
                        let imgPoint = mapPoint(localCenter == .zero ? mapped : localCenter, from: viewSize, to: imageSize)
                        var updated = caption
                        updated.center = imgPoint
                        updated.rotation = localRotation
                        onUpdate(updated)
                    })
            }
            private func mapPoint(_ p: CGPoint, from src: CGSize, to dst: CGSize) -> CGPoint {
                CGPoint(x: p.x * dst.width / src.width, y: p.y * dst.height / src.height)
            }
        }
        
        private struct CaptionEditorInline: View {
            @State var caption: FullscreenMediaEditor.Caption
            var videoLength: Double? = nil
            var onChange: (FullscreenMediaEditor.Caption) -> Void
            var onDelete: () -> Void
            private let colors: [Color] = [.white, .black, .yellow, .red, .blue, .green, .orange, .purple, .pink]
            private let fonts: [String] = ["HelveticaNeue", "Arial", "Avenir-Heavy", "Courier", "Georgia", "TimesNewRomanPSMT"]
            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Caption", text: Binding(get: { caption.text }, set: { caption.text = $0; onChange(caption) }))
                            .foregroundStyle(caption.color)
                            .tint(caption.color)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash").foregroundStyle(.red) }
                    }
                    if let dur = videoLength {
                        TimingControls(start: caption.start, end: caption.end, duration: dur) { s, e in
                            caption.start = s; caption.end = e; onChange(caption)
                        }
                    }
                    // Colors
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(colors, id: \.self) { c in
                                Circle().fill(c).frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: caption.color == c ? 2 : 0))
                                    .onTapGesture { caption.color = c; onChange(caption) }
                            }
                        }
                    }
                    // Fonts
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(fonts, id: \.self) { name in
                                Text(name.replacingOccurrences(of: "-", with: " "))
                                    .font(.custom(name, size: 16))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(caption.fontName == name ? Color.white.opacity(0.25) : Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                                    .onTapGesture { caption.fontName = name; onChange(caption) }
                            }
                        }
                    }
                    // Size + outline + alignment
                    HStack(spacing: 12) {
                        Text("Size")
                        Slider(value: Binding(get: { Double(caption.fontSize) }, set: { caption.fontSize = CGFloat($0); onChange(caption) }), in: 12...96)
                            .frame(maxWidth: 220)
                        Toggle("Outline", isOn: Binding(get: { caption.outline }, set: { caption.outline = $0; onChange(caption) }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Picker("Align", selection: Binding(get: { caption.alignment }, set: { caption.alignment = $0; onChange(caption) })) {
                            Text("L").tag(NSTextAlignment.left)
                            Text("C").tag(NSTextAlignment.center)
                            Text("R").tag(NSTextAlignment.right)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                }
                .foregroundStyle(.white)
            }
        }

        // Reusable timing controls for video overlays
        private struct TimingControls: View {
            @State var start: Double?
            @State var end: Double?
            let duration: Double
            var onUpdate: (Double?, Double?) -> Void
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timing").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    HStack {
                        Text("Start")
                        Slider(value: Binding(get: { start ?? 0 }, set: { newVal in start = min(newVal, (end ?? duration)); onUpdate(start, end) }), in: 0...duration)
                        Text("\(Int(start ?? 0))s").frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("End  ")
                        Slider(value: Binding(get: { end ?? duration }, set: { newVal in end = max(newVal, (start ?? 0)); onUpdate(start, end) }), in: 0...duration)
                        Text("\(Int(end ?? duration))s").frame(width: 40, alignment: .trailing)
                    }
                    Text("Leave blank for full clip").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        
        // MARK: - Crop canvas view
        private struct CropCanvas: View {
            let image: UIImage
            let aspect: FullscreenMediaEditor.CropAspect
            @Binding var scale: CGFloat
            @Binding var offset: CGSize
            @State private var lastScale: CGFloat = 1.0
            @State private var lastOffset: CGSize = .zero
            var body: some View {
                GeometryReader { geo in
                    let container = geo.size
                    let cropSize = cropFrame(in: container)
                    let top = max(0, (container.height - cropSize.height) / 2)
                    let bottom = top
                    let left = max(0, (container.width - cropSize.width) / 2)
                    let right = left
                    
                    ZStack {
                        // Image content centered, clipped to crop rect
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cropSize.width * scale, height: cropSize.height * scale)
                            .offset(offset)
                            .gesture(dragGesture().simultaneously(with: magnificationGesture()))
                            .clipped()
                            .frame(width: cropSize.width, height: cropSize.height)
                            .position(x: container.width/2, y: container.height/2)
                        
                        // Dimmed overlays around crop rect
                        VStack(spacing: 0) {
                            Color.black.opacity(0.6).frame(height: top)
                            HStack(spacing: 0) {
                                Color.black.opacity(0.6).frame(width: left)
                                Rectangle().fill(Color.clear).frame(width: cropSize.width, height: cropSize.height)
                                Color.black.opacity(0.6).frame(width: right)
                            }
                            Color.black.opacity(0.6).frame(height: bottom)
                        }
                        // Border
                        Rectangle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            .frame(width: cropSize.width, height: cropSize.height)
                            .position(x: container.width/2, y: container.height/2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
            private func cropFrame(in size: CGSize) -> CGSize {
                switch aspect {
                case .free:
                    return CGSize(width: size.width * 0.9, height: size.height * 0.9)
                case .square:
                    let w = min(size.width, size.height) * 0.9
                    return CGSize(width: w, height: w)
                case .fourFive:
                    let w = min(size.width, size.height) * 0.95
                    return CGSize(width: w, height: w * 5/4)
                case .sixteenNine:
                    let w = min(size.width, size.height) * 0.95
                    return CGSize(width: w, height: w * 9/16)
                }
            }
            // Removed mask approach to avoid visibility issues; using four-rect overlay instead.
            private func dragGesture() -> some Gesture {
                DragGesture()
                    .onChanged { value in offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height) }
                    .onEnded { _ in lastOffset = offset }
            }
            private func magnificationGesture() -> some Gesture {
                MagnificationGesture()
                    .onChanged { v in scale = max(1.0, lastScale * v) }
                    .onEnded { _ in lastScale = scale }
            }
        }
        
    
extension FullscreenMediaEditor {
    @ViewBuilder private func editorCanvas(for item: CreatePostViewModel.MediaItem) -> some View {
            if item.mime.hasPrefix("video/") {
                ZStack {
                    LocalVideoPlayer(data: item.data, autoPlay: true)
                    if let basis = overlayBasisSize[item.id] {
                        // Use the basis size from generated thumbnail to map overlays
                        let dummy = UIImage(color: .black, size: basis) ?? UIImage()
                        CaptionsOverlay(baseImage: dummy, items: captions[item.id] ?? [], onChange: { updated in captions[item.id] = updated }, selectedId: $selectedCaptionId)
                        StickersOverlay(baseImage: dummy, items: stickers[item.id] ?? [], onChange: { updated in stickers[item.id] = updated }, selectedId: $selectedStickerId)
                    }
                }
            } else if let ui = renderPreview(for: item) {
                if cropMode {
                    CropCanvas(image: ui, aspect: cropAspect, scale: $cropScale, offset: $cropOffset)
                } else {
                    ZStack {
                        Image(uiImage: ui).resizable().scaledToFit()
                        if vm.media.indices.contains(current), vm.media[current].id == item.id {
                            CaptionsOverlay(
                                baseImage: ui,
                                items: captions[item.id] ?? [],
                                onChange: { updated in captions[item.id] = updated },
                                selectedId: $selectedCaptionId
                            )
                            StickersOverlay(
                                baseImage: ui,
                                items: stickers[item.id] ?? [],
                                onChange: { updated in stickers[item.id] = updated },
                                selectedId: $selectedStickerId
                            )
                        }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 0).fill(Color.white.opacity(0.08))
                    .overlay(Image(systemName: "play.circle.fill").font(.system(size: 60)).foregroundStyle(.white))
            }
        }

        private struct LocalVideoPlayer: View {
            let data: Data
            var autoPlay: Bool = true
            @State private var url: URL? = nil
            @State private var player: AVPlayer? = nil
            var body: some View {
                ZStack {
                    if let p = player {
                        VideoPlayer(player: p).onAppear { if autoPlay { p.play() } }
                    } else {
                        Color.black.opacity(0.2)
                    }
                }
                .onAppear {
                    if url == nil {
                        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lp_\(UUID().uuidString).mp4")
                        try? data.write(to: tmp, options: .atomic)
                        url = tmp
                        player = AVPlayer(url: tmp)
                        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { _ in
                            player?.seek(to: .zero)
                            if autoPlay { player?.play() }
                        }
                    }
                }
                .onDisappear { player?.pause() }
            }
        }
}

private extension UIImage {
            convenience init?(color: UIColor, size: CGSize) {
                UIGraphicsBeginImageContextWithOptions(size, true, 1)
                guard let ctx = UIGraphicsGetCurrentContext() else { UIGraphicsEndImageContext(); return nil }
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                let img = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                if let cg = img?.cgImage { self.init(cgImage: cg) } else { return nil }
            }
        }
