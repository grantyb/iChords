import Foundation

enum SongsterrService {

    static func search(query: String) async throws -> [SongsterrResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.songsterr.com/api/songs?pattern=\(encoded)")
        else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("iChords/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([SongsterrResult].self, from: data)
    }

    static func fetchChords(songId: Int) async -> String {
        do {
            // Step 1: Get chord metadata
            guard let metaUrl = URL(string: "https://www.songsterr.com/api/chords/\(songId)") else { return "" }
            var metaReq = URLRequest(url: metaUrl)
            metaReq.setValue("iChords/1.0", forHTTPHeaderField: "User-Agent")

            let (metaData, _) = try await URLSession.shared.data(for: metaReq)
            let meta = try JSONDecoder().decode(SongsterrChordsResponse.self, from: metaData)

            guard let chordpro = meta.chordpro, let revisionId = meta.chordsRevisionId else { return "" }

            // Step 2: Fetch actual ChordPro data
            guard let cpUrl = URL(string: "https://chordpro2.songsterr.com/\(songId)/\(revisionId)/\(chordpro).chordpro") else { return "" }
            var cpReq = URLRequest(url: cpUrl)
            cpReq.setValue("iChords/1.0", forHTTPHeaderField: "User-Agent")

            let (cpData, _) = try await URLSession.shared.data(for: cpReq)
            return String(data: cpData, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
