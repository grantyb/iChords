import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID
    var source: String?
    var sourceId: String?
    var title: String
    var artist: String
    var artistSlug: String
    var titleSlug: String
    var chords: String
    var artworkUrl: String?
    var sessionCount: Int
    var isFavourite: Bool
    var createdAt: Date
    var favouritedAt: Date?
    var lastPlayedAt: Date?
    var lastSessionAt: Date?
    var deletedAt: Date?
    var linesData: Data?

    init(
        source: String? = nil,
        sourceId: String? = nil,
        title: String,
        artist: String,
        artistSlug: String,
        titleSlug: String,
        chords: String,
        artworkUrl: String? = nil
    ) {
        self.id = UUID()
        self.source = source
        self.sourceId = sourceId
        self.title = title
        self.artist = artist
        self.artistSlug = artistSlug
        self.titleSlug = titleSlug
        self.chords = chords
        self.artworkUrl = artworkUrl
        self.sessionCount = 0
        self.isFavourite = false
        self.createdAt = Date()
    }

    static func slugify(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    static func findBySource(_ source: String, sourceId: String, context: ModelContext) -> Song? {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> {
                $0.source == source && $0.sourceId == sourceId && $0.deletedAt == nil
            }
        )
        return try? context.fetch(descriptor).first
    }

    static func uniqueTitleSlug(artistSlug: String, baseSlug: String, context: ModelContext) -> String {
        var candidate = baseSlug
        var counter = 0
        while true {
            let slug = candidate
            let aSlug = artistSlug
            let descriptor = FetchDescriptor<Song>(
                predicate: #Predicate<Song> {
                    $0.artistSlug == aSlug && $0.titleSlug == slug && $0.deletedAt == nil
                }
            )
            let count = (try? context.fetchCount(descriptor)) ?? 0
            if count == 0 { return candidate }
            counter += 1
            candidate = "\(baseSlug)-\(counter)"
        }
    }

    func recordSession() {
        lastPlayedAt = Date()
        let calendar = Calendar.current
        if let last = lastSessionAt, calendar.isDateInToday(last) {
            return
        }
        sessionCount += 1
        lastSessionAt = Date()
    }

    /// Returns the stored SongLines if available, otherwise builds them from `parsed`,
    /// encodes them, and caches the result in `linesData` for future launches.
    /// Any stored SongLines that map to a blank parsed line are stripped and re-saved.
    func ensureSongLines(for parsed: ParsedSong) -> [SongLine] {
        if let data = linesData,
           let stored = try? JSONDecoder().decode([SongLine].self, from: data) {
            let cleaned = stored.filter { sl in
                guard sl.parsedLineIndex < parsed.lines.count else { return false }
                return !parsed.lines[sl.parsedLineIndex].chunks.isEmpty
            }
            if cleaned.count != stored.count {
                linesData = try? JSONEncoder().encode(cleaned)
            }
            return cleaned
        }
        let lines = SongLineBuilder.build(from: parsed)
        linesData = try? JSONEncoder().encode(lines)
        return lines
    }

    func toggleFavourite() {
        isFavourite.toggle()
        favouritedAt = isFavourite ? Date() : nil
    }
}
