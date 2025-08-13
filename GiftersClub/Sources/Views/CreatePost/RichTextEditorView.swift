import SwiftUI
import UIKit

struct RichTextEditorView: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var placeholder: String
    var onEditing: ((Bool) -> Void)? = nil
    var onResolve: ((UITextView) -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        tv.delegate = context.coordinator
        tv.keyboardDismissMode = .interactive
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.textAlignment = .center
        tv.attributedText = attributedText.length > 0 ? attributedText : NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor.secondaryLabel])
        onResolve?(tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Avoid resetting when user is typing
        if context.coordinator.shouldUpdateFromBinding {
            uiView.attributedText = attributedText.length > 0 ? attributedText : NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor.secondaryLabel])
            context.coordinator.shouldUpdateFromBinding = false
        }
        context.coordinator.centerContent(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditorView
        var isShowingPlaceholder = false
        var shouldUpdateFromBinding = false

        init(_ parent: RichTextEditorView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onEditing?(true)
            parent.onResolve?(textView)
            if textView.textColor == UIColor.secondaryLabel {
                textView.text = nil
                textView.textColor = UIColor.label
            }
            centerContent(textView)
        }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onEditing?(false) }
        func textViewDidChange(_ textView: UITextView) {
            parent.attributedText = textView.attributedText
            centerContent(textView)
        }

        func centerContent(_ tv: UITextView) {
            // Vertically center content if it is shorter than bounds
            DispatchQueue.main.async {
                let boundsHeight = tv.bounds.height
                guard boundsHeight > 0 else { return }
                let contentHeight = tv.contentSize.height
                let insetTop = max((boundsHeight - contentHeight) / 2 - tv.textContainerInset.top, 0)
                var inset = tv.contentInset
                inset.top = insetTop
                inset.bottom = 0
                tv.contentInset = inset
            }
        }
    }
}

// MARK: - Formatting helpers
extension UITextView {
    func applyAttribute(_ key: NSAttributedString.Key, value: Any) {
        let range = selectedRange
        guard range.length > 0 else { return }
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        mutable.addAttribute(key, value: value, range: range)
        attributedText = mutable
    }
    func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        let range = selectedRange
        guard range.length > 0 else { return }
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        mutable.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let base = (value as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
            let descriptor = base.fontDescriptor
            var traits = descriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let newDescriptor = descriptor.withSymbolicTraits(traits) {
                let newFont = UIFont(descriptor: newDescriptor, size: base.pointSize)
                mutable.addAttribute(.font, value: newFont, range: subRange)
            }
        }
        attributedText = mutable
    }
    func setFontSize(_ size: CGFloat) {
        let range = selectedRange
        guard range.length > 0 else { return }
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        mutable.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let base = (value as? UIFont) ?? UIFont.systemFont(ofSize: size)
            let newFont = UIFont(descriptor: base.fontDescriptor, size: size)
            mutable.addAttribute(.font, value: newFont, range: subRange)
        }
        attributedText = mutable
    }
}
