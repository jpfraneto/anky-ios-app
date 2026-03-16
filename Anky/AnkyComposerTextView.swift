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
    let onUserInput: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onUserInput: onUserInput)
    }

    func makeUIView(context: Context) -> LockedComposerTextView {
        let textView = LockedComposerTextView()
        textView.delegate = context.coordinator
        textView.pasteDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = isVisuallyHidden ? .clear : UIColor(Color.ankyInk)
        textView.tintColor = isVisuallyHidden ? .clear : UIColor(Color.ankyGold)
        textView.font = UIFont(name: "Palatino-Roman", size: 24) ?? .systemFont(ofSize: 24, weight: .regular)
        textView.textContainerInset = isVisuallyHidden ? .zero : UIEdgeInsets(top: 12, left: 0, bottom: 140, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = .dark
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocapitalizationType = .sentences
        textView.returnKeyType = .default
        textView.isScrollEnabled = !isVisuallyHidden
        textView.alwaysBounceVertical = !isVisuallyHidden
        textView.showsVerticalScrollIndicator = false
        textView.allowsEditingTextAttributes = false
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        textView.textDragInteraction?.isEnabled = false
        textView.isVisuallyHidden = isVisuallyHidden
        textView.text = text
        textView.moveCaretToEnd()
        return textView
    }

    func updateUIView(_ uiView: LockedComposerTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        uiView.isVisuallyHidden = isVisuallyHidden
        uiView.textColor = isVisuallyHidden ? .clear : UIColor(Color.ankyInk)
        uiView.tintColor = isVisuallyHidden ? .clear : UIColor(Color.ankyGold)

        if isFocused {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                    uiView.moveCaretToEnd()
                }
            } else {
                uiView.moveCaretToEnd()
            }
        } else if uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        private let onUserInput: (String) -> Void

        init(text: Binding<String>, isFocused: Binding<Bool>, onUserInput: @escaping (String) -> Void) {
            _text = text
            _isFocused = isFocused
            self.onUserInput = onUserInput
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused = true
            (textView as? LockedComposerTextView)?.moveCaretToEnd()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            let sanitized = textView.text.replacingOccurrences(of: "\n", with: " ")
            if sanitized != textView.text {
                textView.text = sanitized
            }

            text = textView.text
            onUserInput(textView.text)
            (textView as? LockedComposerTextView)?.moveCaretToEnd()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? LockedComposerTextView)?.moveCaretToEnd()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
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
            item.setNoResult()
        }
    }
}

final class LockedComposerTextView: UITextView {
    var isVisuallyHidden = false

    override var canBecomeFirstResponder: Bool { true }

    override func deleteBackward() {
        // Forward-only writing: never allow destructive edits.
    }

    override func paste(_ sender: Any?) {
        // Paste is intentionally blocked.
    }

    override func paste(itemProviders: [NSItemProvider]) {
        // Paste is intentionally blocked.
    }

    override func cut(_ sender: Any?) {
        // Cut is intentionally blocked.
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        isVisuallyHidden ? .zero : super.caretRect(for: position)
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        isVisuallyHidden ? [] : super.selectionRects(for: range)
    }

    func moveCaretToEnd() {
        let end = endOfDocument
        selectedTextRange = textRange(from: end, to: end)
        if !isVisuallyHidden {
            scrollRangeToVisible(NSRange(location: text.utf16.count, length: 0))
        }
    }
}
