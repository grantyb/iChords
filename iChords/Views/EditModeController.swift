import SwiftUI
import SwiftData

@MainActor
@Observable
final class EditModeController {
    var lines: [EditableLine] = []
    var editingLine: EditableLine? = nil

    private let sectionPattern = try! NSRegularExpression(
        pattern: #"^(Chorus|Verse|Bridge|Intro|Outro|Pre-Chorus|Interlude|Solo|Tag)(\s*\d*)\s*:?\s*$"#,
        options: .caseInsensitive
    )
    private let chordPattern = try! NSRegularExpression(pattern: #"\[([^\]]*)\]"#)

    func load(from song: Song) {
        let rawLines = song.chords.components(separatedBy: "\n")
        var result: [EditableLine] = []
        var i = 0
        while i < rawLines.count {
            if isTabRawLine(rawLines[i]) {
                var j = i + 1
                while j < rawLines.count && isTabRawLine(rawLines[j]) { j += 1 }
                result.append(EditableLine(text: rawLines[i..<j].joined(separator: "\n")))
                i = j
            } else {
                result.append(EditableLine(text: rawLines[i]))
                i += 1
            }
        }
        lines = result
    }

    func save(to song: Song, context: ModelContext) {
        let text = lines.map(\.text).joined(separator: "\n")
        song.chords = text
        // linesData is intentionally left as-is here; reloadParsedSong() will
        // capture any recorded beats from it before clearing and rebuilding.
        ChordVersion.saveNewVersion(for: song, text: text, context: context)
    }

    func update(id: UUID, text: String) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[idx].text = text
    }

    func delete(id: UUID) {
        lines.removeAll { $0.id == id }
    }

    func duplicate(id: UUID) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        lines.insert(EditableLine(text: lines[idx].text), at: idx + 1)
        ensureTabGroupSpacing()
    }

    func move(from: IndexSet, to: Int) {
        lines.move(fromOffsets: from, toOffset: to)
        ensureTabGroupSpacing()
    }

    // MARK: - Row rendering helpers

    func isSectionHeader(_ trimmed: String) -> Bool {
        sectionPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
            || trimmed.hasPrefix("{start_of_")
    }

    func sectionName(_ text: String) -> String {
        if let r = text.range(of: #"(?<=:\s)[\w ]+(?=\})"#, options: .regularExpression) {
            return String(text[r])
        }
        return text.hasSuffix(":") ? String(text.dropLast()).trimmingCharacters(in: .whitespaces) : text
    }

    func attributedLine(_ raw: String) -> AttributedString {
        var result = AttributedString()
        let ns = raw as NSString
        let matches = chordPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
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

    // MARK: - Private

    private func ensureTabGroupSpacing() {
        var i = lines.count - 1
        while i >= 0 {
            guard isTabGroup(lines[i].text) else { i -= 1; continue }
            if i < lines.count - 1,
               !lines[i + 1].text.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.insert(EditableLine(text: ""), at: i + 1)
            }
            if i > 0,
               !lines[i - 1].text.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.insert(EditableLine(text: ""), at: i)
            }
            i -= 1
        }
    }
}
