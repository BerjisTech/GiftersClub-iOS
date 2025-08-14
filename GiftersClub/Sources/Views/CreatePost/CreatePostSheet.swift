import SwiftUI
import PhotosUI
import AVFoundation

enum CreatePostStep { case pick, textEditor, edit, details }

struct CreatePostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: CreatePostViewModel
    @State private var step: CreatePostStep
    @StateObject private var banners = BannerQueue()
    @State private var firstAppearHandled = false

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
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.large])
        .onAppear {
            // If invoked directly with .details from camera/library, insert the edit step first
            if !firstAppearHandled {
                firstAppearHandled = true
                if step == .details && !vm.media.isEmpty { step = .edit }
            }
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
                .onChange(of: vm.selectedPickerItems) { _, _ in vm.loadPickerItems() }
            }
            .frame(maxWidth: .infinity)

            if vm.media.isEmpty {
                VStack(spacing: 8) {
                    Text("Select photos/videos or create a text post.")
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 200)
                }
                .frame(maxWidth: .infinity)
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
    }

    private func EditStep() -> some View {
        FullscreenMediaEditor(vm: vm, onBack: { step = .pick }, onDone: { step = .details })
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
                        }
                    }
                }
            }

            TextField("Say something about your post...", text: $vm.caption, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            Picker("Access", selection: $vm.accessType) {
                ForEach(PostAccessType.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)

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
                }
                vm.publish { _ in
                    banners.show(Banner(title: "Your post has been created", style: .success))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NotificationCenter.default.post(name: .goHome, object: nil)
                        dismiss()
                    }
                }
            }
            .disabled(vm.isPosting)
        }
        .padding()
        .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { _ in vm.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
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

// Undo/Redo helpers
extension TextPostEditor {
    private func applyUndo() { withCurrentTextView { $0.undoManager?.undo() } }
    private func applyRedo() { withCurrentTextView { $0.undoManager?.redo() } }
}

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

    private let ctx = CIContext()
    enum Control: String, CaseIterable { case brightness = "Brightness", contrast = "Contrast", saturation = "Saturation", sepia = "Sepia", vignette = "Vignette", temperature = "Temperature" }
    struct FilterParams { var brightness: Double = 0, contrast: Double = 1, saturation: Double = 1, sepia: Double = 0, vignette: Double = 0, temperature: Double = 6500 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) { Image(systemName: "chevron.left").font(.title2.weight(.semibold)) }
                    Spacer()
                    Text("Edit").font(.headline)
                    Spacer()
                    Button(action: applyAndNext) { Text("Next").font(.headline) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.3))

                TabView(selection: $current) {
                    ForEach(Array(vm.media.enumerated()), id: \.1.id) { idx, item in
                        ZStack {
                            if let ui = renderPreview(for: item) {
                                Image(uiImage: ui).resizable().scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 0).fill(Color.white.opacity(0.08))
                                    .overlay(Image(systemName: "play.circle.fill").font(.system(size: 60)).foregroundStyle(.white))
                            }
                        }
                        .tag(idx)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))

                VStack(spacing: 8) {
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
                    HStack {
                        Text("0%").foregroundStyle(.white.opacity(0.7)).font(.caption)
                        Slider(value: bindingForActive(), in: rangeForActive())
                        Text("100%").foregroundStyle(.white.opacity(0.7)).font(.caption)
                    }
                    .padding(.horizontal)
                    HStack {
                        Button("Reset") { resetCurrent() }
                        Spacer()
                        Button("Apply to Image") { bakeCurrent() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .background(Color.black.opacity(0.3))
            }
        }
        .onChange(of: current) { _, _ in updatePreview() }
        .onAppear { updatePreview() }
    }

    private func bindingForActive() -> Binding<Double> {
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
    private func rangeForActive() -> ClosedRange<Double> { 0...100 }

    private func resetCurrent() {
        guard vm.media.indices.contains(current) else { return }
        params[vm.media[current].id] = FilterParams()
        updatePreview()
    }
    private func bakeCurrent() {
        guard vm.media.indices.contains(current) else { return }
        let item = vm.media[current]
        guard item.mime.hasPrefix("image/"), let original = UIImage(data: item.data), let ui = filteredImage(for: original, params: params[item.id] ?? FilterParams()) else { return }
        if let data = ui.jpegData(compressionQuality: 0.9) {
            vm.media[current] = .init(data: data, mime: "image/jpeg", kind: .photo)
        }
        updatePreview()
    }
    private func applyAndNext() { onDone() }

    private func updatePreview() {
        guard vm.media.indices.contains(current) else { preview = nil; return }
        let item = vm.media[current]
        if item.mime.hasPrefix("image/"), let ui = UIImage(data: item.data) {
            preview = filteredImage(for: ui, params: params[item.id] ?? FilterParams())
        } else {
            preview = nil
        }
    }
    private func renderPreview(for item: CreatePostViewModel.MediaItem) -> UIImage? {
        if item.mime.hasPrefix("image/"), let ui = UIImage(data: item.data) {
            return filteredImage(for: ui, params: params[item.id] ?? FilterParams())
        }
        return nil
    }

    private func filteredImage(for ui: UIImage, params: FilterParams) -> UIImage? {
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
