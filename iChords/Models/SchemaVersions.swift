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

// MARK: - Migration Plan

enum iChordsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        ]
    }
}
