import Foundation

struct SongBeat: Codable {
    let index: Int       // 0 = no chord highlighted; 1-based chord offset within this line
    let durationMs: Int?
}

struct SongLine: Codable {
    enum Kind: String, Codable { case text, tab }

    let kind: Kind
    let parsedLineIndex: Int   // index of the first parsed line this SongLine represents
    let parsedLineCount: Int   // number of consecutive parsed lines (> 1 for grouped tab rows)
    let chordStartIndex: Int   // flat chord index of the first chord on this line
    let beats: [SongBeat]
}
