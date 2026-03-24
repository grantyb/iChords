import Foundation

struct SongsterrResult: Codable, Identifiable {
    let songId: Int
    let title: String
    let artist: String
    let hasChords: Bool?

    var id: Int { songId }
}

struct SongsterrChordsResponse: Codable {
    let chordpro: String?
    let chordsRevisionId: Int?
}

struct ITunesSearchResponse: Codable {
    let results: [ITunesResult]
}

struct ITunesResult: Codable {
    let artworkUrl100: String?
}
