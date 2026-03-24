import SwiftUI
import UIKit

struct ChordsTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = UIColor(Theme.text)
        tv.backgroundColor = UIColor(Theme.surface)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.text = text

        // Restore cursor position
        let safePos = min(cursorPosition, text.count)
        if let pos = tv.position(from: tv.beginningOfDocument, offset: safePos) {
            tv.selectedTextRange = tv.textRange(from: pos, to: pos)
        }

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChordsTextEditor

        init(_ parent: ChordsTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            saveCursor(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            saveCursor(textView)
        }

        private func saveCursor(_ textView: UITextView) {
            if let selected = textView.selectedTextRange {
                let offset = textView.offset(from: textView.beginningOfDocument, to: selected.start)
                parent.cursorPosition = offset
            }
        }
    }
}
