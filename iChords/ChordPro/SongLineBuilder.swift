import Foundation

enum SongLineBuilder {

    /// Builds a flat array of `SongLine` values from a parsed ChordPro song.
    ///
    /// Rules:
    /// - Consecutive tab rows are grouped into a single SongLine (kind: .tab) with one
    ///   beat at 4 000 ms (index 0, no chord highlight).
    /// - `.section`, `.comment`, and blank/whitespace-only `.line` rows are skipped.
    /// - A text row with N chords produces N beats, each at ⌊4 000 / N⌋ ms (minimum 500 ms),
    ///   with beat indices 1…N.
    /// - A text row with 0 chords (prose) produces one beat at 4 000 ms (index 0).
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
                    beats: [SongBeat(index: 0, durationMs: 4000)]
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

            let beats: [SongBeat]
            if n == 0 {
                beats = [SongBeat(index: 0, durationMs: 4000)]
            } else {
                let dur = max(500, 4000 / n)
                beats = (1...n).map { SongBeat(index: $0, durationMs: dur) }
            }

            lines.append(SongLine(
                kind: .text,
                parsedLineIndex: i,
                parsedLineCount: 1,
                chordStartIndex: lineChordStart,
                beats: beats
            ))
            chordCount += n
            i += 1
        }

        return lines
    }
}
