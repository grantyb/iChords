import SwiftUI
import SwiftData
import UIKit

// MARK: - Editable line model

struct EditableLine: Identifiable {
    var id = UUID()
    var text: String
}

// MARK: - Bridge for inserting chord text at cursor

@MainActor
final class TextViewBridge: ObservableObject {
    weak var textView: UITextView?

    func insert(_ text: String) {
        textView?.insertText(text)
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

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }
    }
}

// MARK: - Main view

struct EditSongLinesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let song: Song
    let onSave: (String) -> Void

    @State private var lines: [EditableLine] = []
    @State private var editingLineId: UUID? = nil
    @State private var editingText: String = ""
    @State private var editMode: EditMode = .inactive
    @StateObject private var bridge = TextViewBridge()

    private var uniqueChords: [String] {
        let raw = lines.map(\.text).joined(separator: "\n")
        return ChordProParser.uniqueChords(in: ChordProParser.parse(raw))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(lines) { line in
                    if editingLineId == line.id {
                        inlineEditRow(lineId: line.id)
                            .listRowBackground(Theme.surface2.opacity(0.3))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    } else {
                        lineDisplayRow(line: line)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editMode == .inactive else { return }
                                startEditing(line)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteLine(id: line.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    duplicateLine(id: line.id)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .tint(.indigo)
                            }
                    }
                }
                .onMove { from, to in
                    lines.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.plain)
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .navigationTitle("Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textDim)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(editMode == .active ? "Done" : "Reorder") {
                        withAnimation {
                            if editMode == .active {
                                editMode = .inactive
                            } else {
                                editingLineId = nil
                                editMode = .active
                            }
                        }
                    }
                    .foregroundColor(Theme.accent)
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadLines() }
    }

    // MARK: - Row: display mode

    @ViewBuilder
    private func lineDisplayRow(line: EditableLine) -> some View {
        let trimmed = line.text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "return")
                    .font(.caption2)
                    .foregroundColor(Theme.surface2)
                Text("blank line")
                    .font(.caption2)
                    .foregroundColor(Theme.surface2)
            }
            .padding(.vertical, 4)
        } else if isSection(trimmed) {
            Text(sectionDisplayName(trimmed).uppercased())
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(Theme.sectionColor)
                .tracking(1)
                .padding(.vertical, 4)
        } else if isDirective(trimmed) {
            Text(trimmed)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.textDim)
                .italic()
                .padding(.vertical, 2)
        } else {
            Text(attributedLine(trimmed))
                .lineLimit(3)
                .padding(.vertical, 2)
        }
    }

    // MARK: - Row: edit mode

    @ViewBuilder
    private func inlineEditRow(lineId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Chord palette
            if !uniqueChords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(uniqueChords, id: \.self) { chord in
                            Button {
                                bridge.insert("[\(chord)]")
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
                    .padding(.vertical, 2)
                }
            }

            // Text editor
            InlineLineTextEditor(text: $editingText, bridge: bridge)
                .frame(height: 60)
                .padding(8)
                .background(Theme.surface)
                .cornerRadius(6)

            // Actions
            HStack {
                Button("Cancel") {
                    editingLineId = nil
                }
                .font(.subheadline)
                .foregroundColor(Theme.textDim)

                Spacer()

                Button("Save Line") {
                    commitEdit(lineId: lineId)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.accent)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func loadLines() {
        lines = song.chords
            .components(separatedBy: "\n")
            .map { EditableLine(text: $0) }
    }

    private func startEditing(_ line: EditableLine) {
        editingText = line.text
        editingLineId = line.id
    }

    private func commitEdit(lineId: UUID) {
        guard let idx = lines.firstIndex(where: { $0.id == lineId }) else { return }
        lines[idx].text = editingText
        editingLineId = nil
    }

    private func deleteLine(id: UUID) {
        if editingLineId == id { editingLineId = nil }
        lines.removeAll { $0.id == id }
    }

    private func duplicateLine(id: UUID) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        lines.insert(EditableLine(text: lines[idx].text), at: idx + 1)
    }

    private func save() {
        if let id = editingLineId, let idx = lines.firstIndex(where: { $0.id == id }) {
            lines[idx].text = editingText
        }
        let text = lines.map(\.text).joined(separator: "\n")
        ChordVersion.saveNewVersion(for: song, text: text, context: modelContext)
        onSave(text)
        dismiss()
    }

    // MARK: - Line classification

    private static let sectionPattern = try! NSRegularExpression(
        pattern: #"^(Chorus|Verse|Bridge|Intro|Outro|Pre-Chorus|Interlude|Solo|Tag)(\s*\d*)\s*:?\s*$"#,
        options: .caseInsensitive
    )

    private func isSection(_ text: String) -> Bool {
        if text.hasPrefix("{start_of_") || text == "{soc}" || text == "{sov}" || text == "{sob}" { return true }
        let r = NSRange(text.startIndex..., in: text)
        return Self.sectionPattern.firstMatch(in: text, range: r) != nil
    }

    private func isDirective(_ text: String) -> Bool {
        return text.hasPrefix("{") && text.hasSuffix("}")
    }

    private func sectionDisplayName(_ text: String) -> String {
        // {start_of_chorus: Chorus} → "Chorus"
        if let r = text.range(of: #"(?<=:\s)[\w ]+(?=\})"#, options: .regularExpression) {
            return String(text[r])
        }
        // "Chorus:" → "Chorus"
        return text.hasSuffix(":") ? String(text.dropLast()).trimmingCharacters(in: .whitespaces) : text
    }

    // MARK: - Attributed string (chord highlighting)

    private static let chordPattern = try! NSRegularExpression(pattern: #"\[([^\]]*)\]"#)

    private func attributedLine(_ raw: String) -> AttributedString {
        var result = AttributedString()
        let ns = raw as NSString
        let matches = Self.chordPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        var lastEnd = 0

        for match in matches {
            let beforeLen = match.range.location - lastEnd
            if beforeLen > 0 {
                var part = AttributedString(ns.substring(with: NSRange(location: lastEnd, length: beforeLen)))
                part.foregroundColor = Theme.textDim
                part.font = Font.system(.body, design: .monospaced)
                result += part
            }
            var chord = AttributedString(ns.substring(with: match.range))
            chord.foregroundColor = Theme.accent
            chord.font = Font.system(.body, design: .monospaced).bold()
            result += chord
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < ns.length {
            var part = AttributedString(ns.substring(from: lastEnd))
            part.foregroundColor = Theme.text
            part.font = Font.system(.body, design: .monospaced)
            result += part
        }

        return result
    }
}
