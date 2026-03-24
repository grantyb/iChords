import Foundation
import SwiftData

@Model
final class ChordVersion {
    var id: UUID
    var songId: UUID
    var text: String
    var createdAt: Date

    init(songId: UUID, text: String) {
        self.id = UUID()
        self.songId = songId
        self.text = text
        self.createdAt = Date()
    }

    /// Fetch all versions for a song, oldest first
    static func versions(for songId: UUID, context: ModelContext) -> [ChordVersion] {
        let descriptor = FetchDescriptor<ChordVersion>(
            predicate: #Predicate<ChordVersion> { $0.songId == songId },
            sortBy: [SortDescriptor(\ChordVersion.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Ensure at least one version exists for a song, seeding from its current chords text
    static func ensureInitialVersion(for song: Song, context: ModelContext) {
        let sid = song.id
        let descriptor = FetchDescriptor<ChordVersion>(
            predicate: #Predicate<ChordVersion> { $0.songId == sid }
        )
        let count = (try? context.fetchCount(descriptor)) ?? 0
        if count == 0 && !song.chords.isEmpty {
            let version = ChordVersion(songId: song.id, text: song.chords)
            version.createdAt = song.createdAt
            context.insert(version)
        }
    }

    /// Save a new version and update the song's chords field
    static func saveNewVersion(for song: Song, text: String, context: ModelContext) {
        let version = ChordVersion(songId: song.id, text: text)
        context.insert(version)
        song.chords = text
    }
}
