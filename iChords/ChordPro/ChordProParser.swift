import Foundation

struct ChordChunk: Identifiable {
    let id = UUID()
    var chord: String?
    var lyric: String
}

struct ChordProLine: Identifiable {
    let id = UUID()
    enum LineType { case line, section, comment }
    let type: LineType
    var section: String?
    var chunks: [ChordChunk]
    var text: String?
}

struct ParsedSong {
    var title: String?
    var artist: String?
    var lines: [ChordProLine]
}

enum ChordProParser {

    static func parse(_ raw: String) -> ParsedSong {
        let lines = raw.components(separatedBy: .newlines)
        var result = ParsedSong(lines: [])
        var inSection: String? = nil

        let directivePattern = try! NSRegularExpression(pattern: #"^\{(\w+)(?:[:\s]\s*(.+?))?\}$"#)
        let sectionPattern = try! NSRegularExpression(
            pattern: #"^(Chorus|Verse|Bridge|Intro|Outro|Pre-Chorus|Interlude|Solo|Tag)(\s*\d*)\s*:?\s*$"#,
            options: .caseInsensitive
        )

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                result.lines.append(ChordProLine(type: .line, chunks: []))
                continue
            }

            let range = NSRange(trimmed.startIndex..., in: trimmed)

            // Directive
            if let match = directivePattern.firstMatch(in: trimmed, range: range) {
                let key = String(trimmed[Range(match.range(at: 1), in: trimmed)!]).lowercased()
                let value = match.range(at: 2).location != NSNotFound
                    ? String(trimmed[Range(match.range(at: 2), in: trimmed)!])
                    : nil

                switch key {
                case "title", "t":
                    result.title = value
                case "artist":
                    result.artist = value
                case "comment", "c", "ci":
                    result.lines.append(ChordProLine(type: .comment, chunks: [], text: value ?? ""))
                case "start_of_chorus", "soc", "start_of_verse", "sov", "start_of_bridge", "sob":
                    let name = value ?? (key.contains("chorus") ? "Chorus" : key.contains("verse") ? "Verse" : "Bridge")
                    inSection = name
                    result.lines.append(ChordProLine(type: .section, section: name, chunks: []))
                case "end_of_chorus", "eoc", "end_of_verse", "eov", "end_of_bridge", "eob":
                    inSection = nil
                case "define", "key", "capo", "tempo", "time":
                    if let v = value {
                        result.lines.append(ChordProLine(type: .comment, chunks: [], text: "\(key): \(v)"))
                    }
                default:
                    break
                }
                continue
            }

            // Section header shorthand
            if let match = sectionPattern.firstMatch(in: trimmed, range: range) {
                let name1 = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
                let name2 = match.range(at: 2).location != NSNotFound
                    ? String(trimmed[Range(match.range(at: 2), in: trimmed)!])
                    : ""
                let name = name1 + name2
                inSection = name
                result.lines.append(ChordProLine(type: .section, section: name, chunks: []))
                continue
            }

            // Regular line
            let chunks = parseLineChords(trimmed)
            var parsed = ChordProLine(type: .line, chunks: chunks)
            if let s = inSection { parsed.section = s }
            result.lines.append(parsed)
        }

        return result
    }

    private static func parseLineChords(_ line: String) -> [ChordChunk] {
        var chunks: [ChordChunk] = []
        let pattern = try! NSRegularExpression(pattern: #"\[([^\]]*)\]"#)
        let range = NSRange(line.startIndex..., in: line)
        var lastIndex = line.startIndex

        pattern.enumerateMatches(in: line, range: range) { match, _, _ in
            guard let match = match else { return }
            let matchRange = Range(match.range, in: line)!
            let chordRange = Range(match.range(at: 1), in: line)!
            let chord = String(line[chordRange])

            if matchRange.lowerBound > lastIndex {
                let textBefore = String(line[lastIndex..<matchRange.lowerBound])
                if !chunks.isEmpty {
                    chunks[chunks.count - 1].lyric += textBefore
                } else {
                    chunks.append(ChordChunk(lyric: textBefore))
                }
            }

            chunks.append(ChordChunk(chord: chord, lyric: ""))
            lastIndex = matchRange.upperBound
        }

        if lastIndex < line.endIndex {
            let remaining = String(line[lastIndex...])
            if !chunks.isEmpty {
                chunks[chunks.count - 1].lyric += remaining
            } else {
                chunks.append(ChordChunk(lyric: remaining))
            }
        }

        if chunks.isEmpty {
            chunks.append(ChordChunk(lyric: line))
        }

        return chunks
    }

    // MARK: - Line classification

    private static let tabLinePattern = try! NSRegularExpression(pattern: #"^[A-Ga-g]#?\|"#)

    static func isTabLine(_ line: ChordProLine) -> Bool {
        guard line.type == .line,
              line.chunks.count == 1,
              line.chunks[0].chord == nil else { return false }
        let text = line.chunks[0].lyric
        return tabLinePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func isProseLine(_ line: ChordProLine) -> Bool {
        guard line.type == .line, !line.chunks.isEmpty else { return false }
        if line.chunks.contains(where: { $0.chord != nil }) { return false }
        let text = line.chunks.map(\.lyric).joined()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return !isTabLine(line)
    }

    static func uniqueChords(in song: ParsedSong) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in song.lines {
            for chunk in line.chunks {
                if let chord = chunk.chord, !seen.contains(chord) {
                    seen.insert(chord)
                    result.append(chord)
                }
            }
        }
        return result
    }
}
