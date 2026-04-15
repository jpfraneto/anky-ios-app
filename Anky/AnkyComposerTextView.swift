//
//  AnkyComposerTextView.swift
//  Anky
//

import SwiftUI
import UIKit

struct AnkyComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var isVisuallyHidden = false
    var forwardOnly = true
    var placeholder: String? = nil
    var font: UIFont = UIFont(name: "Righteous-Regular", size: 24) ?? .systemFont(ofSize: 24, weight: .regular)
    var textInsets: UIEdgeInsets = UIEdgeInsets(top: 12, left: 0, bottom: 20, right: 0)
    var isScrollable = true
    var caretColor: UIColor? = nil
    var placeholderOpacity: CGFloat? = nil
    let onUserInput: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, forwardOnly: forwardOnly, onUserInput: onUserInput)
    }

    func makeUIView(context: Context) -> LockedComposerTextView {
        let textView = LockedComposerTextView()
        textView.forwardOnly = forwardOnly
        textView.delegate = context.coordinator
        textView.pasteDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = isVisuallyHidden ? .clear : UIColor(Color.ankyInk)
        textView.tintColor = isVisuallyHidden ? .clear : (caretColor ?? UIColor(Color.ankyGold))
        textView.font = font
        textView.textAlignment = .left
        textView.textContainerInset = isVisuallyHidden ? .zero : textInsets
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = .dark
        textView.keyboardType = forwardOnly ? .alphabet : .default
        textView.autocorrectionType = forwardOnly ? .no : .default
        textView.spellCheckingType = forwardOnly ? .no : .default
        textView.smartQuotesType = forwardOnly ? .no : .default
        textView.smartDashesType = forwardOnly ? .no : .default
        textView.smartInsertDeleteType = forwardOnly ? .no : .default
        textView.autocapitalizationType = forwardOnly ? .none : .sentences
        textView.returnKeyType = .default
        textView.textContentType = forwardOnly ? .none : nil
        textView.isScrollEnabled = isScrollable && !isVisuallyHidden
        textView.alwaysBounceVertical = isScrollable && !isVisuallyHidden
        textView.showsVerticalScrollIndicator = false
        textView.allowsEditingTextAttributes = false
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        textView.textDragInteraction?.isEnabled = false
        textView.isVisuallyHidden = isVisuallyHidden
        textView.text = text

        // Hide predictive text bar on iOS 17+
        if forwardOnly {
            if #available(iOS 17.0, *) {
                textView.inlinePredictionType = .no
            }
        }

        // Placeholder
        if let placeholder, !isVisuallyHidden {
            textView.placeholderText = placeholder
            textView.placeholderFont = font
            textView.placeholderColor = UIColor(Color.ankyInk).withAlphaComponent(placeholderOpacity ?? 0.34)
            textView.updatePlaceholder()
        }

        if forwardOnly { textView.moveCaretToEnd() }
        return textView
    }

    static func dismantleUIView(_ uiView: LockedComposerTextView, coordinator: Coordinator) {
        coordinator.cancelPendingFocusSync()
        uiView.delegate = nil
        uiView.pasteDelegate = nil
        if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func updateUIView(_ uiView: LockedComposerTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        uiView.forwardOnly = forwardOnly
        context.coordinator.forwardOnly = forwardOnly
        uiView.isVisuallyHidden = isVisuallyHidden
        uiView.textColor = isVisuallyHidden ? .clear : UIColor(Color.ankyInk)
        uiView.tintColor = isVisuallyHidden ? .clear : (caretColor ?? UIColor(Color.ankyGold))
        uiView.font = font
        uiView.textAlignment = .left
        uiView.textContainerInset = isVisuallyHidden ? .zero : textInsets
        uiView.isScrollEnabled = isScrollable && !isVisuallyHidden
        uiView.alwaysBounceVertical = isScrollable && !isVisuallyHidden
        uiView.placeholderText = placeholder
        uiView.placeholderColor = UIColor(Color.ankyInk).withAlphaComponent(placeholderOpacity ?? 0.34)
        if let placeholderOpacity {
            uiView.placeholderAlpha = placeholderOpacity
        }
        uiView.updatePlaceholder()

        context.coordinator.syncFocus(
            for: uiView,
            shouldFocus: isFocused,
            forwardOnly: forwardOnly
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        var forwardOnly: Bool
        private let onUserInput: (String) -> Void
        private var pendingFocusSyncID = 0

        init(text: Binding<String>, isFocused: Binding<Bool>, forwardOnly: Bool, onUserInput: @escaping (String) -> Void) {
            _text = text
            _isFocused = isFocused
            self.forwardOnly = forwardOnly
            self.onUserInput = onUserInput
        }

        func cancelPendingFocusSync() {
            pendingFocusSyncID += 1
        }

        func syncFocus(for textView: LockedComposerTextView, shouldFocus: Bool, forwardOnly: Bool) {
            pendingFocusSyncID += 1
            let syncID = pendingFocusSyncID

            if shouldFocus {
                guard !textView.isFirstResponder else {
                    if forwardOnly {
                        textView.moveCaretToEnd()
                    }
                    return
                }

                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    guard self.pendingFocusSyncID == syncID, self.isFocused else { return }
                    textView.becomeFirstResponder()
                    if forwardOnly {
                        textView.moveCaretToEnd()
                    }
                }
                return
            }

            guard textView.isFirstResponder else { return }
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                guard self.pendingFocusSyncID == syncID else { return }
                textView.resignFirstResponder()
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused = true
            if forwardOnly {
                (textView as? LockedComposerTextView)?.moveCaretToEnd()
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            // v2: newlines are banned, strip them (shouldn't arrive due to shouldChangeTextIn, but safety net)
            let sanitized = textView.text.filter { !$0.isNewline && $0 != "\t" }
            if sanitized != textView.text {
                textView.text = sanitized
            }

            text = textView.text
            onUserInput(textView.text)
            (textView as? LockedComposerTextView)?.updatePlaceholder()
            if forwardOnly {
                (textView as? LockedComposerTextView)?.moveCaretToEnd()
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if forwardOnly {
                (textView as? LockedComposerTextView)?.moveCaretToEnd()
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard forwardOnly else { return true }

            if text.isEmpty {
                return false
            }

            if text.contains(where: { $0.isNewline || $0 == "\t" }) {
                return false
            }

            let utf16Count = textView.text.utf16.count
            if range.location != utf16Count || range.length != 0 {
                return false
            }

            return true
        }

        func textPasteConfigurationSupporting(
            _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
            transform item: any UITextPasteItem
        ) {
            if forwardOnly {
                item.setNoResult()
            } else {
                item.setDefaultResult()
            }
        }
    }
}

final class LockedComposerTextView: UITextView {
    var isVisuallyHidden = false
    var forwardOnly = true
    var placeholderText: String?
    var placeholderFont: UIFont?
    var placeholderAlpha: CGFloat = 0.2
    var placeholderColor: UIColor?

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.white.withAlphaComponent(0.2)
        label.numberOfLines = 0
        label.isUserInteractionEnabled = false
        addSubview(label)
        return label
    }()

    func updatePlaceholder() {
        let availableWidth = max(
            bounds.width - textContainerInset.left - textContainerInset.right - 2 * textContainer.lineFragmentPadding,
            0
        )

        placeholderLabel.text = placeholderText
        placeholderLabel.font = UIFont(name: "Righteous-Regular", size: (placeholderFont?.pointSize ?? 18))
            ?? placeholderFont
        placeholderLabel.textColor = placeholderColor ?? UIColor.white.withAlphaComponent(placeholderAlpha)
        placeholderLabel.textAlignment = textAlignment
        placeholderLabel.isHidden = !(text ?? "").isEmpty || placeholderText == nil
        guard !placeholderLabel.isHidden else { return }

        placeholderLabel.preferredMaxLayoutWidth = availableWidth
        let measuredSize = placeholderLabel.sizeThatFits(
            CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        )
        placeholderLabel.frame = CGRect(
            x: textContainerInset.left + textContainer.lineFragmentPadding,
            y: textContainerInset.top,
            width: availableWidth,
            height: measuredSize.height
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePlaceholder()
    }

    override var canBecomeFirstResponder: Bool { true }

    override func deleteBackward() {
        guard !forwardOnly else { return }
        super.deleteBackward()
    }

    override func paste(_ sender: Any?) {
        guard !forwardOnly else { return }
        super.paste(sender)
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard !forwardOnly else { return }
        super.paste(itemProviders: itemProviders)
    }

    override func cut(_ sender: Any?) {
        guard !forwardOnly else { return }
        super.cut(sender)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard !forwardOnly else { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        isVisuallyHidden ? .zero : super.caretRect(for: position)
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        isVisuallyHidden ? [] : super.selectionRects(for: range)
    }

    func moveCaretToEnd() {
        guard window != nil else { return }
        let end = endOfDocument
        guard let endRange = textRange(from: end, to: end) else { return }
        selectedTextRange = endRange
        if !isVisuallyHidden {
            scrollRangeToVisible(NSRange(location: text.utf16.count, length: 0))
        }
    }
}
