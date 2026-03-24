import SwiftUI
import SwiftData

@main
struct iChordsApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Song.self, RecentSearch.self, ChordVersion.self,
                migrationPlan: iChordsMigrationPlan.self
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(appState)
        }
        .modelContainer(modelContainer)
    }
}
