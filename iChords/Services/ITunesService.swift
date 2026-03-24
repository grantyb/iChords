import Foundation

enum ITunesService {

    static func fetchArtworkUrl(artist: String, title: String) async -> String? {
        do {
            let term = "\(artist) \(title)"
            guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1")
            else { return nil }

            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)

            guard let artworkUrl = response.results.first?.artworkUrl100 else { return nil }
            return artworkUrl.replacingOccurrences(of: "100x100", with: "600x600")
        } catch {
            return nil
        }
    }
}
