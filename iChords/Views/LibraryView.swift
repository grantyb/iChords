import SwiftUI
import SwiftData

enum SortOption: String, CaseIterable {
    case lastPlayedDesc = "Last played (newest)"
    case lastPlayedAsc = "Last played (oldest)"
    case artist = "Artist"
    case songName = "Song name"
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var songs: [Song] = []
    @State private var hasFavourites = false

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            header
            if !songs.isEmpty || appState.favouritesOnly {
                controls
            }
            songList
        }
        .background(Theme.bg)
        .onAppear { loadSongs() }
        .onChange(of: appState.sortOption) { loadSongs() }
        .onChange(of: appState.favouritesOnly) { loadSongs() }
        .onChange(of: appState.showSearch) {
            if !appState.showSearch { loadSongs() }
        }
        .sheet(isPresented: $state.showSearch) {
            NavigationStack {
                SearchView()
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "music.note.list")
                .font(.title.weight(.bold))
                .foregroundColor(Theme.accent)
            Text("Chords")
                .font(.largeTitle.bold())
                .foregroundColor(Theme.text)

            Spacer()

            Button {
                appState.showSearch = true
                appState.save()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accent)
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        appState.sortOption = option
                        appState.save()
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if appState.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(appState.sortOption.rawValue)
                        .font(.subheadline)
                        .foregroundColor(Theme.text)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surface)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.surface2, lineWidth: 1)
                )
            }

            Spacer()

            if hasFavourites {
                Button {
                    appState.favouritesOnly.toggle()
                    appState.save()
                } label: {
                    Image(systemName: appState.favouritesOnly ? "heart.fill" : "heart")
                        .foregroundColor(appState.favouritesOnly ? Theme.heartRed : Theme.textDim)
                        .font(.title3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var songList: some View {
        Group {
            if songs.isEmpty && !appState.favouritesOnly {
                VStack {
                    Spacer()
                    Text("No songs yet.\nTap Add to search and add chords.")
                        .foregroundColor(Theme.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if songs.isEmpty && appState.favouritesOnly {
                VStack {
                    Spacer()
                    Text("No favourites yet.")
                        .foregroundColor(Theme.textDim)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(songs) { song in
                        NavigationLink(value: song.id) {
                            songRow(song)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteSong(song)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func deleteSong(_ song: Song) {
        song.deletedAt = Date()
        loadSongs()
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 10) {
            if let url = song.artworkUrl, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.surface2
                }
                .frame(width: 40, height: 40)
                .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if let lastPlayed = song.lastPlayedAt {
                        Text(formatTimeAgo(lastPlayed))
                            .font(.caption2)
                            .foregroundColor(Theme.textDim)
                    }

                    Button {
                        song.toggleFavourite()
                    } label: {
                        Image(systemName: song.isFavourite ? "heart.fill" : "heart")
                            .font(.subheadline)
                            .foregroundColor(song.isFavourite ? Theme.heartRed : Theme.textDim)
                    }

                    Text("\(song.sessionCount)x")
                        .font(.caption2)
                        .foregroundColor(Theme.textDim)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .cornerRadius(10)
    }

    private func loadSongs() {
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.deletedAt == nil }
        )

        if appState.favouritesOnly {
            descriptor = FetchDescriptor<Song>(
                predicate: #Predicate<Song> { $0.deletedAt == nil && $0.isFavourite == true }
            )
        }

        switch appState.sortOption {
        case .lastPlayedDesc:
            descriptor.sortBy = [SortDescriptor(\Song.lastPlayedAt, order: .reverse)]
        case .lastPlayedAsc:
            descriptor.sortBy = [SortDescriptor(\Song.lastPlayedAt, order: .forward)]
        case .artist:
            descriptor.sortBy = [SortDescriptor(\Song.artist, order: .forward), SortDescriptor(\Song.title, order: .forward)]
        case .songName:
            descriptor.sortBy = [SortDescriptor(\Song.title, order: .forward)]
        }

        songs = (try? modelContext.fetch(descriptor)) ?? []

        let favDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.deletedAt == nil && $0.isFavourite == true }
        )
        hasFavourites = ((try? modelContext.fetchCount(favDescriptor)) ?? 0) > 0
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        let mins = Int(diff / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
