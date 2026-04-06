import Foundation
import SwiftData

// MARK: - Schema V1

enum SchemaV1: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Song.self, RecentSearch.self]
    }

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
        var speed: Double
        var sessionCount: Int
        var isFavourite: Bool
        var createdAt: Date
        var favouritedAt: Date?
        var lastPlayedAt: Date?
        var lastSessionAt: Date?
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.title = ""
            self.artist = ""
            self.artistSlug = ""
            self.titleSlug = ""
            self.chords = ""
            self.speed = 1.0
            self.sessionCount = 0
            self.isFavourite = false
            self.createdAt = Date()
        }
    }

    @Model
    final class RecentSearch {
        var id: UUID
        var query: String
        var searchedAt: Date

        init() {
            self.id = UUID()
            self.query = ""
            self.searchedAt = Date()
        }
    }
}

// MARK: - Schema V2 (adds ChordVersion)

enum SchemaV2: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier: Schema.Version = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Song.self, RecentSearch.self, ChordVersion.self]
    }

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
        var speed: Double
        var sessionCount: Int
        var isFavourite: Bool
        var createdAt: Date
        var favouritedAt: Date?
        var lastPlayedAt: Date?
        var lastSessionAt: Date?
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.title = ""
            self.artist = ""
            self.artistSlug = ""
            self.titleSlug = ""
            self.chords = ""
            self.speed = 1.0
            self.sessionCount = 0
            self.isFavourite = false
            self.createdAt = Date()
        }
    }

    @Model
    final class RecentSearch {
        var id: UUID
        var query: String
        var searchedAt: Date

        init() {
            self.id = UUID()
            self.query = ""
            self.searchedAt = Date()
        }
    }

    @Model
    final class ChordVersion {
        var id: UUID
        var songId: UUID
        var text: String
        var createdAt: Date

        init() {
            self.id = UUID()
            self.songId = UUID()
            self.text = ""
            self.createdAt = Date()
        }
    }
}

// MARK: - Schema V3 (adds linesData to Song)

enum SchemaV3: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier: Schema.Version = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Song.self, RecentSearch.self, ChordVersion.self]
    }

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
        var speed: Double
        var sessionCount: Int
        var isFavourite: Bool
        var createdAt: Date
        var favouritedAt: Date?
        var lastPlayedAt: Date?
        var lastSessionAt: Date?
        var deletedAt: Date?
        var linesData: Data?

        init() {
            self.id = UUID()
            self.title = ""
            self.artist = ""
            self.artistSlug = ""
            self.titleSlug = ""
            self.chords = ""
            self.speed = 1.0
            self.sessionCount = 0
            self.isFavourite = false
            self.createdAt = Date()
        }
    }

    @Model
    final class RecentSearch {
        var id: UUID
        var query: String
        var searchedAt: Date

        init() {
            self.id = UUID()
            self.query = ""
            self.searchedAt = Date()
        }
    }

    @Model
    final class ChordVersion {
        var id: UUID
        var songId: UUID
        var text: String
        var createdAt: Date

        init() {
            self.id = UUID()
            self.songId = UUID()
            self.text = ""
            self.createdAt = Date()
        }
    }
}

// MARK: - Schema V4 (removes speed from Song)

enum SchemaV4: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier: Schema.Version = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Song.self, RecentSearch.self, ChordVersion.self]
    }

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

        init() {
            self.id = UUID()
            self.title = ""
            self.artist = ""
            self.artistSlug = ""
            self.titleSlug = ""
            self.chords = ""
            self.sessionCount = 0
            self.isFavourite = false
            self.createdAt = Date()
        }
    }

    @Model
    final class RecentSearch {
        var id: UUID
        var query: String
        var searchedAt: Date

        init() {
            self.id = UUID()
            self.query = ""
            self.searchedAt = Date()
        }
    }

    @Model
    final class ChordVersion {
        var id: UUID
        var songId: UUID
        var text: String
        var createdAt: Date

        init() {
            self.id = UUID()
            self.songId = UUID()
            self.text = ""
            self.createdAt = Date()
        }
    }
}

// MARK: - Schema V5 (SongBeat timing: durationMs → durationNs in linesData JSON)
// SwiftData models are unchanged; the migration rewrites the JSON blob.

enum SchemaV5: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier: Schema.Version = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Song.self, RecentSearch.self, ChordVersion.self]
    }

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

        init() {
            self.id = UUID()
            self.title = ""
            self.artist = ""
            self.artistSlug = ""
            self.titleSlug = ""
            self.chords = ""
            self.sessionCount = 0
            self.isFavourite = false
            self.createdAt = Date()
        }
    }

    @Model
    final class RecentSearch {
        var id: UUID
        var query: String
        var searchedAt: Date

        init() {
            self.id = UUID()
            self.query = ""
            self.searchedAt = Date()
        }
    }

    @Model
    final class ChordVersion {
        var id: UUID
        var songId: UUID
        var text: String
        var createdAt: Date

        init() {
            self.id = UUID()
            self.songId = UUID()
            self.text = ""
            self.createdAt = Date()
        }
    }
}

// MARK: - Migration helpers (V4 linesData format)

private struct SongBeatV4: Codable {
    let index: Int
    let durationMs: Int?
}

private struct SongLineV4: Codable {
    enum Kind: String, Codable { case text, tab }
    let kind: Kind
    let parsedLineIndex: Int
    let parsedLineCount: Int
    let chordStartIndex: Int
    let beats: [SongBeatV4]
}

// MARK: - Migration Plan

enum iChordsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            .custom(
                fromVersion: SchemaV4.self,
                toVersion: SchemaV5.self,
                willMigrate: nil,
                didMigrate: { context in
                    let songs = try context.fetch(FetchDescriptor<SchemaV5.Song>())
                    let decoder = JSONDecoder()
                    let encoder = JSONEncoder()
                    for song in songs {
                        guard let data = song.linesData,
                              let oldLines = try? decoder.decode([SongLineV4].self, from: data)
                        else { continue }
                        let newLines = oldLines.map { line in
                            SongLine(
                                kind: line.kind == .tab ? .tab : .text,
                                parsedLineIndex: line.parsedLineIndex,
                                parsedLineCount: line.parsedLineCount,
                                chordStartIndex: line.chordStartIndex,
                                beats: line.beats.map { beat in
                                    SongBeat(
                                        index: beat.index,
                                        durationNs: beat.durationMs.map { $0 * 1_000_000 }
                                    )
                                }
                            )
                        }
                        song.linesData = try? encoder.encode(newLines)
                    }
                    try context.save()
                }
            )
        ]
    }
}
