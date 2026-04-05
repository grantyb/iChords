import SwiftUI
import UIKit

// MARK: - Editable line model

struct EditableLine: Identifiable {
    var id = UUID()
    var text: String
}

// MARK: - Tab line detection (mirrors ChordProParser.isTabLine for raw strings)

private let _tabLinePattern = try! NSRegularExpression(pattern: #"^[A-Ga-g]#?\|"#)

func isTabRawLine(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return false }
    return _tabLinePattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
}

func isTabGroup(_ text: String) -> Bool {
    isTabRawLine(text.components(separatedBy: "\n").first ?? text)
}

// MARK: - UITextView bridge for chord insertion

@MainActor
final class TextViewBridge: ObservableObject {
    weak var textView: UITextView?

    /// Inserts `[chord]` at the cursor, or replaces an existing `[…]` if the cursor is inside one.
    func insert(_ chord: String) {
        guard let tv = textView,
              let selectedRange = tv.selectedTextRange else { return }

        let text = tv.text ?? ""
        let nsText = text as NSString
        let cursor = tv.offset(from: tv.beginningOfDocument, to: selectedRange.start)

        // Scan left for '[', stopping early if ']' is found first.
        var openPos: Int? = nil
        for i in stride(from: cursor - 1, through: 0, by: -1) {
            let c = nsText.character(at: i)
            if c == 93 { break }          // ']' — not inside a chord
            if c == 91 { openPos = i; break }  // '['
        }

        // Scan right for ']', stopping early if '[' is found first.
        var closePos: Int? = nil
        if openPos != nil {
            for i in cursor..<nsText.length {
                let c = nsText.character(at: i)
                if c == 91 { break }          // '[' — malformed / adjacent chord
                if c == 93 { closePos = i; break }  // ']'
            }
        }

        if let open = openPos, let close = closePos,
           let start = tv.position(from: tv.beginningOfDocument, offset: open),
           let end   = tv.position(from: tv.beginningOfDocument, offset: close + 1),
           let range = tv.textRange(from: start, to: end) {
            tv.replace(range, withText: "[\(chord)]")
        } else {
            tv.insertText("[\(chord)]")
        }
    }
}

// MARK: - UITextView wrapper for a single ChordPro line

struct InlineLineTextEditor: UIViewRepresentable {
    @Binding var text: String
    let bridge: TextViewBridge

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textColor = UIColor(Theme.text)
        tv.backgroundColor = .clear
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.isScrollEnabled = true
        tv.text = text
        bridge.textView = tv
        DispatchQueue.main.async { tv.becomeFirstResponder() }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        bridge.textView = tv
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: InlineLineTextEditor
        init(_ parent: InlineLineTextEditor) { self.parent = parent }
        func textViewDidChange(_ tv: UITextView) { parent.text = tv.text }
    }
}

// MARK: - Line editor modal (chord palette + text editor)

struct LineEditorModal: View {
    @Environment(\.dismiss) private var dismiss

    let line: EditableLine
    let uniqueChords: [String]
    let onSave: (String) -> Void

    @State private var editText: String
    @StateObject private var bridge = TextViewBridge()

    init(line: EditableLine, uniqueChords: [String], onSave: @escaping (String) -> Void) {
        self.line = line
        self.uniqueChords = uniqueChords
        self.onSave = onSave
        _editText = State(initialValue: line.text)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !uniqueChords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(uniqueChords, id: \.self) { chord in
                                Button {
                                    bridge.insert(chord)
                                } label: {
                                    Text(chord)
                                        .font(.system(.caption2, design: .monospaced).bold())
                                        .foregroundColor(Theme.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Theme.accent.opacity(0.15))
                                        .cornerRadius(5)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(Theme.surface)
                    Rectangle().fill(Theme.surface2).frame(height: 1)
                }
                InlineLineTextEditor(text: $editText, bridge: bridge)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Theme.bg)
            .navigationTitle("Edit Line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textDim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
