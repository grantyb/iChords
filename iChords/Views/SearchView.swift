import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecentSearch.searchedAt, order: .reverse)
    private var recentSearches: [RecentSearch]

    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var results: [SongsterrResult] = []
    @State private var loading = false
    @State private var searched = false
    @State private var loadingSongId: Int?
    @State private var navigateToSong: Song?

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            content
        }
        .background(Theme.bg)
        .navigationDestination(item: $navigateToSong) { song in
            PlayView(song: song)
        }
        .onAppear {
            query = appState.searchQuery
            if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                performSearch()
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private var header: some View {
        ZStack {
            VStack(spacing: 4) {
                Text("Chords")
                    .font(.largeTitle.bold())
                    .foregroundColor(Theme.text)
                Text("Find chords. Play along.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textDim)
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Theme.textDim)
                        .padding(8)
                        .background(Theme.surface)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Search songs, artists...", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .cornerRadius(10)
                .foregroundColor(Theme.text)
                .submitLabel(.search)
                .onSubmit { performSearch() }
                .autocorrectionDisabled()

            Button(action: performSearch) {
                ZStack {
                    Text("Search")
                        .fontWeight(.semibold)
                        .opacity(loading ? 0 : 1)
                    if loading {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.8)
                    }
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.accent)
                .cornerRadius(10)
            }
            .disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !searched && !recentSearches.isEmpty {
                    recentSearchesSection
                }

                if searched && !loading && results.isEmpty {
                    Text("No results found. Try a different search.")
                        .foregroundColor(Theme.textDim)
                        .padding(.top, 40)
                }

                ForEach(results) { result in
                    resultRow(result)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT SEARCHES")
                .font(.caption)
                .foregroundColor(Theme.textDim)
                .tracking(0.5)

            FlowLayout(spacing: 6) {
                ForEach(Array(recentSearches.prefix(10))) { search in
                    HStack(spacing: 0) {
                        Button {
                            query = search.query
                            performSearch()
                        } label: {
                            Text(search.query)
                                .font(.subheadline)
                                .foregroundColor(Theme.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        Button {
                            modelContext.delete(search)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(Theme.textDim)
                                .padding(.trailing, 8)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(Theme.surface)
                    .cornerRadius(20)
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func resultRow(_ result: SongsterrResult) -> some View {
        Button {
            selectSong(result)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(result.artist)
                        .font(.subheadline)
                        .foregroundColor(Theme.textDim)
                        .lineLimit(1)
                }

                Spacer()

                if loadingSongId == result.songId {
                    ProgressView()
                        .tint(Theme.accent)
                } else if result.hasChords == true {
                    Text("CHORDS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.chordBg)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .cornerRadius(10)
        }
        .disabled(loadingSongId != nil)
        .padding(.bottom, 6)
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        query = trimmed
        appState.searchQuery = trimmed
        appState.save()
        loading = true
        searched = true

        Task {
            do {
                let data = try await SongsterrService.search(query: trimmed)
                results = data
                saveRecentSearch(trimmed)
            } catch {
                results = []
            }
            loading = false
        }
    }

    private func saveRecentSearch(_ q: String) {
        // Remove existing entry with same query
        let existing = recentSearches.filter { $0.query.lowercased() == q.lowercased() }
        for e in existing { modelContext.delete(e) }

        let search = RecentSearch(query: q)
        modelContext.insert(search)

        // Trim to 10 most recent
        let overflow = recentSearches.dropFirst(10)
        for old in overflow { modelContext.delete(old) }
    }

    private func selectSong(_ result: SongsterrResult) {
        loadingSongId = result.songId

        Task {
            let sourceId = String(result.songId)

            // Check if song already exists
            if let existing = Song.findBySource("songsterr", sourceId: sourceId, context: modelContext) {
                existing.lastPlayedAt = Date()
                navigateToSong = existing
                loadingSongId = nil
                return
            }

            // Fetch chords and artwork in parallel
            async let chordsTask = SongsterrService.fetchChords(songId: result.songId)
            async let artworkTask = ITunesService.fetchArtworkUrl(artist: result.artist, title: result.title)

            let chords = await chordsTask
            let artworkUrl = await artworkTask

            let artistSlug = Song.slugify(result.artist)
            let baseTitleSlug = Song.slugify(result.title)
            let titleSlug = Song.uniqueTitleSlug(artistSlug: artistSlug, baseSlug: baseTitleSlug, context: modelContext)

            let song = Song(
                source: "songsterr",
                sourceId: sourceId,
                title: result.title,
                artist: result.artist,
                artistSlug: artistSlug,
                titleSlug: titleSlug,
                chords: chords,
                artworkUrl: artworkUrl
            )
            song.lastPlayedAt = Date()

            modelContext.insert(song)

            // Create initial chord version
            let version = ChordVersion(songId: song.id, text: chords)
            modelContext.insert(version)

            navigateToSong = song
            loadingSongId = nil
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
