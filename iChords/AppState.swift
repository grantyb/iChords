import Foundation

@MainActor
@Observable
final class AppState {
    // MARK: - Persisted state

    /// Library
    var sortOption: SortOption = .lastPlayedDesc
    var favouritesOnly: Bool = false

    /// Search sheet
    var showSearch: Bool = false
    var searchQuery: String = ""

    /// Song view
    var activeSongId: String = ""
    var activeSongLineIndex: Int = 0

    /// Edit sheet
    var showEditSheet: Bool = false
    var editCursorPosition: Int = 0

    // MARK: - Persistence

    private static let key = "appState"

    init() {
        load()
    }

    /// Navigate to a song
    func openSong(id: UUID) {
        activeSongId = id.uuidString
        activeSongLineIndex = 0
        showEditSheet = false
        editCursorPosition = 0
        save()
    }

    /// Return to library
    func closeSong() {
        activeSongId = ""
        activeSongLineIndex = 0
        showEditSheet = false
        editCursorPosition = 0
        save()
    }

    func save() {
        let data: [String: Any] = [
            "sortOption": sortOption.rawValue,
            "favouritesOnly": favouritesOnly,
            "showSearch": showSearch,
            "searchQuery": searchQuery,
            "activeSongId": activeSongId,
            "activeSongLineIndex": activeSongLineIndex,
            "showEditSheet": showEditSheet,
            "editCursorPosition": editCursorPosition,
        ]
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private func load() {
        guard let data = UserDefaults.standard.dictionary(forKey: Self.key) else { return }
        if let raw = data["sortOption"] as? String, let opt = SortOption(rawValue: raw) {
            sortOption = opt
        }
        favouritesOnly = data["favouritesOnly"] as? Bool ?? false
        showSearch = data["showSearch"] as? Bool ?? false
        searchQuery = data["searchQuery"] as? String ?? ""
        activeSongId = data["activeSongId"] as? String ?? ""
        activeSongLineIndex = data["activeSongLineIndex"] as? Int ?? 0
        showEditSheet = data["showEditSheet"] as? Bool ?? false
        editCursorPosition = data["editCursorPosition"] as? Int ?? 0
    }
}
