import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var navigationPath = NavigationPath()
    @State private var didRestore = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            LibraryView()
                .navigationDestination(for: UUID.self) { songId in
                    if let song = fetchSong(id: songId) {
                        PlayView(song: song)
                    }
                }
        }
        .tint(Theme.accent)
        .onAppear {
            guard !didRestore else { return }
            didRestore = true
            if let uuid = UUID(uuidString: appState.activeSongId),
               fetchSong(id: uuid) != nil {
                navigationPath.append(uuid)
            }
        }
    }

    private func fetchSong(id: UUID) -> Song? {
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.id == id && $0.deletedAt == nil }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
