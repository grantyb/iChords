import Foundation

enum SongLineBuilder {

    /// Builds a flat array of `SongLine` values from a parsed ChordPro song.
    ///
    /// Rules:
    /// - Consecutive tab rows are grouped into a single SongLine (kind: .tab).
    /// - `.section`, `.comment`, and blank/whitespace-only `.line` rows are skipped.
    static func build(from parsed: ParsedSong) -> [SongLine] {
        var lines: [SongLine] = []
        var chordCount = 0
        var i = 0

        while i < parsed.lines.count {
            let pLine = parsed.lines[i]

            // Group consecutive tab lines
            if ChordProParser.isTabLine(pLine) {
                var j = i + 1
                while j < parsed.lines.count && ChordProParser.isTabLine(parsed.lines[j]) {
                    j += 1
                }
                lines.append(SongLine(
                    kind: .tab,
                    parsedLineIndex: i,
                    parsedLineCount: j - i,
                    chordStartIndex: chordCount,
                    beats: []
                ))
                i = j
                continue
            }

            // Skip section headers, comments, and blank lines — they have no timing
            if pLine.type == .section || pLine.type == .comment || pLine.chunks.isEmpty {
                i += 1
                continue
            }

            // .line type (prose / chord-bearing)
            let chordChunks = pLine.chunks.filter { $0.chord != nil }
            let n = chordChunks.count
            let lineChordStart = chordCount

            lines.append(SongLine(
                kind: .text,
                parsedLineIndex: i,
                parsedLineCount: 1,
                chordStartIndex: lineChordStart,
                beats: []
            ))
            chordCount += n
            i += 1
        }

        return lines
    }

    /// Returns one `SongBeat` per tab column that has at least one non-dash character
    /// across all rows in the tab group. Falls back to a single index-0 beat if none found.
    static func tabBeats(for sl: SongLine, in parsed: ParsedSong) -> [SongBeat] {
        guard sl.kind == .tab else { return [SongBeat(index: 0, durationMs: 0)] }

        // Collect the body of each tab row (content after the first `|`, trailing `|` stripped).
        var bodies: [[Character]] = []
        for i in sl.parsedLineIndex ..< sl.parsedLineIndex + sl.parsedLineCount {
            guard i < parsed.lines.count,
                  let lyric = parsed.lines[i].chunks.first?.lyric,
                  let pipeIdx = lyric.firstIndex(of: "|") else { continue }
            var body = String(lyric[lyric.index(after: pipeIdx)...])
            if body.hasSuffix("|") { body = String(body.dropLast()) }
            bodies.append(Array(body))
        }

        guard !bodies.isEmpty else { return [SongBeat(index: 0, durationMs: 0)] }

        let maxLen = bodies.map(\.count).max() ?? 0
        var beats: [SongBeat] = []
        var beatIndex = 0
        var prevWasDash = true

        for pos in 0 ..< maxLen {
            let hasFret = bodies.contains { $0.count > pos && $0[pos] != "-" }
            if hasFret && prevWasDash {
                beatIndex += 1
                beats.append(SongBeat(index: beatIndex, durationMs: 0))
            }
            prevWasDash = !hasFret
        }

        return beats.isEmpty ? [SongBeat(index: 0, durationMs: 0)] : beats
    }

    /// Returns the body-relative character-column range for the given 1-based beat index,
    /// or nil if not found. The range is relative to the content after the first `|`.
    static func beatColumnRange(for beatIndex: Int, in sl: SongLine, parsed: ParsedSong) -> Range<Int>? {
        guard sl.kind == .tab else { return nil }

        var bodies: [[Character]] = []
        for i in sl.parsedLineIndex ..< sl.parsedLineIndex + sl.parsedLineCount {
            guard i < parsed.lines.count,
                  let lyric = parsed.lines[i].chunks.first?.lyric,
                  let pipeIdx = lyric.firstIndex(of: "|") else { continue }
            var body = String(lyric[lyric.index(after: pipeIdx)...])
            if body.hasSuffix("|") { body = String(body.dropLast()) }
            bodies.append(Array(body))
        }

        guard !bodies.isEmpty else { return nil }

        let maxLen = bodies.map(\.count).max() ?? 0
        var currentBeat = 0
        var prevWasDash = true
        var startCol = 0

        for pos in 0 ..< maxLen {
            let hasFret = bodies.contains { $0.count > pos && $0[pos] != "-" }
            if hasFret && prevWasDash {
                currentBeat += 1
                if currentBeat == beatIndex { startCol = pos }
            } else if !hasFret && !prevWasDash && currentBeat == beatIndex {
                return startCol..<pos
            }
            prevWasDash = !hasFret
        }

        return currentBeat == beatIndex ? startCol..<maxLen : nil
    }

    /// Returns the 1-based beat index whose column start is nearest to the given body-relative column.
    static func beatIndex(atBodyColumn col: Int, in sl: SongLine, parsed: ParsedSong) -> Int? {
        guard sl.kind == .tab else { return nil }

        var bodies: [[Character]] = []
        for i in sl.parsedLineIndex ..< sl.parsedLineIndex + sl.parsedLineCount {
            guard i < parsed.lines.count,
                  let lyric = parsed.lines[i].chunks.first?.lyric,
                  let pipeIdx = lyric.firstIndex(of: "|") else { continue }
            var body = String(lyric[lyric.index(after: pipeIdx)...])
            if body.hasSuffix("|") { body = String(body.dropLast()) }
            bodies.append(Array(body))
        }

        guard !bodies.isEmpty else { return nil }

        let maxLen = bodies.map(\.count).max() ?? 0
        var beatStarts: [(index: Int, col: Int)] = []
        var current = 0
        var prevWasDash = true

        for pos in 0 ..< maxLen {
            let hasFret = bodies.contains { $0.count > pos && $0[pos] != "-" }
            if hasFret && prevWasDash {
                current += 1
                beatStarts.append((current, pos))
            }
            prevWasDash = !hasFret
        }

        return beatStarts.min(by: { abs($0.col - col) < abs($1.col - col) })?.index
    }
}
