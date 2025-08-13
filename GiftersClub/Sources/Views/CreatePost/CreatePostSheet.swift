import SwiftUI
import PhotosUI

enum CreatePostStep { case pick, textEditor, details }

struct CreatePostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: CreatePostViewModel
    @State private var step: CreatePostStep
    @StateObject private var banners = BannerQueue()

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
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .pick: MediaPickStep()
        case .textEditor: TextPostEditor(onDone: { image in
            vm.addRenderedTextImage(image)
            step = .details
        })
        case .details: DetailsStep()
        }
    }

    private var title: String {
        switch step {
        case .pick: return "Create Post"
        case .textEditor: return "Text Post"
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(vm.media.enumerated()), id: \.1.id) { idx, item in
                            ZStack(alignment: .topTrailing) {
                                if item.mime.hasPrefix("image/"), let ui = UIImage(data: item.data) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06))
                                        Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundStyle(.white)
                                    }
                                }
                                Button {
                                    vm.media.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                                }
                                .padding(6)
                            }
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    step = .details
                }
            }
        }
        .padding()
    }

    private func DetailsStep() -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                vm.publish { _ in
                    banners.show(Banner(title: "Your post has been created", style: .success))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
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
        [AppColors.primaryStart, AppColors.primaryEnd],
        [AppColors.successStart, AppColors.successEnd],
        [AppColors.warningStart, AppColors.warningEnd],
        [AppColors.dangerStart, AppColors.dangerEnd]
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
                GradientButton(title: "Post") { exportAndDone() }
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
        let renderer = ImageRenderer(content:
            ZStack {
                LinearGradient(colors: gradients[bgIndex], startPoint: .topLeading, endPoint: .bottomTrailing)
                ScrollView { Text(AttributedString(attributed)).padding() }
            }
            .frame(width: 640, height: 640)
            .clipped()
        )
        #if os(iOS)
        if let ui = renderer.uiImage { onDone(ui); dismiss() }
        #endif
    }
    private func applyBold() { withCurrentTextView { $0.toggleFontTrait(.traitBold) } }
    private func applyItalic() { withCurrentTextView { $0.toggleFontTrait(.traitItalic) } }
    private func applyUnderline() { withCurrentTextView { $0.applyAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue) } }
    private func setHeading(_ level: Int) { let size: CGFloat = level == 1 ? 28 : 24; withCurrentTextView { $0.setFontSize(size) } }
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
    private func applyColor(_ color: UIColor) { withCurrentTextView { $0.applyAttribute(.foregroundColor, value: color) } }
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
