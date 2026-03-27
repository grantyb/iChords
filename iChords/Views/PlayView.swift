import SwiftUI
import SwiftData

struct PlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Environment(AppState.self) private var appState

    @Bindable var song: Song
    @State private var parsedSong: ParsedSong?
    @State private var engine = PlaybackEngine()
    @State private var sessionRecorded = false
    @State private var userScrolling = false
    @State private var wasPlayingBeforeScroll = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var linePositions: [Int: CGFloat] = [:]
    @State private var scrollViewCenter: CGFloat = 0

    // Fraction of scroll view height used as the playback anchor (0.5 = center of screen)
    private let playbackAnchorFraction: CGFloat = 0.5

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            if let parsed = parsedSong {
                songContent(parsed)
                controls
            } else {
                ProgressView("Loading...")
                    .foregroundColor(Theme.textDim)
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    appState.closeSong()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(Theme.accent)
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                        .lineLimit(1)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    appState.showEditSheet = true
                    appState.save()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(Theme.textDim)
                }
                Button { song.toggleFavourite() } label: {
                    Image(systemName: song.isFavourite ? "heart.fill" : "heart")
                        .foregroundColor(song.isFavourite ? Theme.heartRed : Theme.textDim)
                }
            }
        }
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            loadSong()
            appState.activeSongId = song.id.uuidString
            appState.save()
            if appState.activeChordIndex > 0 && appState.activeChordIndex < engine.totalChords {
                engine.seek(to: appState.activeChordIndex)
            }
        }
        .onDisappear {
            engine.pause()
            appState.activeChordIndex = engine.activeChordIndex
            appState.save()
        }
        .onChange(of: engine.activeChordIndex) { _, newIdx in
            appState.activeChordIndex = newIdx
        }
        .sheet(isPresented: $state.showEditSheet) {
            EditChordsView(song: song) { _ in
                reloadParsedSong()
            }
        }
        .onChange(of: engine.speed) { _, newSpeed in
            song.speed = newSpeed
        }
    }

    private func songContent(_ parsed: ParsedSong) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    heroSection(parsed)

                    songLines(parsed)

                    Spacer()
                        .frame(height: UIScreen.main.bounds.height * 0.7)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: geo.frame(in: .named("scroll")).midY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onAppear {
                scrollProxy = proxy
                if engine.activeLineIndex > 0 {
                    proxy.scrollTo("line-\(engine.activeLineIndex)", anchor: .center)
                }
            }
            .onChange(of: engine.activeLineIndex) { _, newLine in
                guard !userScrolling else { return }
                if engine.isPlaying {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("line-\(newLine)", anchor: .center)
                    }
                }
            }
            .onPreferenceChange(LinePositionKey.self) { positions in
                linePositions = positions
            }
            .overlay(
                GeometryReader { geo in
                    TouchInterceptView(
                        onTouchBegan: {
                            wasPlayingBeforeScroll = engine.isPlaying
                            engine.pause()
                            userScrolling = true
                        },
                        onTouchEnded: {},
                        onScrollEnd: {
                            userScrolling = false
                            if engine.activeLineIndex >= 0 {
                                scrollToLine(engine.activeLineIndex)
                            }
                            if wasPlayingBeforeScroll {
                                engine.play()
                            }
                        },
                        onScroll: {
                            if userScrolling {
                                updateLiveCursor()
                            }
                        }
                    )
                    .onAppear {
                        scrollViewCenter = geo.size.height * playbackAnchorFraction
                    }
                }
            )
        }
    }

    private func scrollToLine(_ lineIndex: Int) {
        guard let proxy = scrollProxy else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("line-\(lineIndex)", anchor: .center)
        }
    }

    // Called continuously while the user is dragging or the scroll is decelerating.
    // Finds the chord line closest to the playback anchor and updates the engine cursor live.
    private func updateLiveCursor() {
        guard !linePositions.isEmpty else { return }
        let anchor = scrollViewCenter
        let chordLineIndices = Set(engine.chordTimings.map(\.lineIndex))
        let chordPositions = linePositions.filter { chordLineIndices.contains($0.key) }
        guard !chordPositions.isEmpty else { return }
        guard let (lineIdx, _) = chordPositions.min(by: { abs($0.value - anchor) < abs($1.value - anchor) }),
              let chordIdx = engine.chordTimings.first(where: { $0.lineIndex == lineIdx })?.flatIndex,
              chordIdx != engine.activeChordIndex
        else { return }
        engine.seek(to: chordIdx)
    }

    private func heroSection(_ parsed: ParsedSong) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Blurred background
            if let url = song.artworkUrl, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
                    .frame(height: 180)
                    .clipped()
                    .blur(radius: 30)
                    .brightness(-0.4)
                    .scaleEffect(1.2)
            }

            // Gradient overlay
            LinearGradient(
                colors: [Theme.bg.opacity(0.3), Theme.bg.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if let url = song.artworkUrl, let imageUrl = URL(string: url) {
                        AsyncImage(url: imageUrl) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Theme.surface2
                        }
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                        .shadow(radius: 10)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(parsed.title ?? song.title)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text(parsed.artist ?? song.artist)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                let chords = ChordProParser.uniqueChords(in: parsed)
                if !chords.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(chords, id: \.self) { chord in
                            Text(chord)
                                .font(.system(.caption2, design: .monospaced).bold())
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func songLines(_ parsed: ParsedSong) -> some View {
        ForEach(Array(parsed.lines.enumerated()), id: \.offset) { lineIdx, line in
            switch line.type {
            case .section:
                sectionHeader(line.section ?? "")
                    .id("line-\(lineIdx)")

            case .comment:
                commentLine(line.text ?? "")
                    .id("line-\(lineIdx)")

            case .line:
                let isTab = ChordProParser.isTabLine(line)
                let isProse = !isTab && ChordProParser.isProseLine(line)
                let lineChordStart = countChordsBeforeLine(lineIdx, in: parsed)
                let isActiveLine = lineIdx == engine.activeLineIndex

                Group {
                    if isTab {
                        tabLine(line)
                    } else if isProse {
                        proseLine(line)
                    } else if line.chunks.isEmpty {
                        Spacer().frame(height: 16)
                    } else {
                        chordLine(
                            chunks: line.chunks,
                            chordStartIndex: lineChordStart,
                            isActiveLine: isActiveLine
                        )
                    }
                }
                .id("line-\(lineIdx)")
                .contentShape(Rectangle())
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: LinePositionKey.self,
                            value: [lineIdx: geo.frame(in: .named("scroll")).midY]
                        )
                    }
                )
                .onTapGesture {
                    let firstChord = lineChordStart
                    if firstChord < engine.totalChords {
                        engine.seek(to: firstChord)
                        scrollToLine(lineIdx)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .monospaced).bold())
            .foregroundColor(Theme.sectionColor)
            .tracking(1)
            .padding(.top, 20)
            .padding(.bottom, 4)
            .padding(.horizontal, 16)
    }

    private func commentLine(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .italic()
            .foregroundColor(Theme.textDim)
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
    }

    private func tabLine(_ line: ChordProLine) -> some View {
        let text = line.chunks.first?.lyric ?? ""
        return Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundColor(Theme.textDim)
            .padding(.horizontal, 12)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }

    private func proseLine(_ line: ChordProLine) -> some View {
        let text = line.chunks.map(\.lyric).joined()
        return Text(text)
            .font(.subheadline)
            .foregroundColor(Theme.textDim)
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
    }

    private struct WordItem: Identifiable {
        let id: Int
        let word: String
        let chord: String?
        let chordIdx: Int?
    }

    private func chordLine(chunks: [ChordChunk], chordStartIndex: Int, isActiveLine: Bool) -> some View {
        let words: [WordItem] = {
            var items: [WordItem] = []
            var ci = chordStartIndex
            var nextId = 0

            for chunk in chunks {
                let chordIdx: Int? = chunk.chord != nil ? { let c = ci; ci += 1; return c }() : nil

                // Split lyric into words, preserving trailing space on each word
                let lyric = chunk.lyric
                let parts = lyric.split(separator: " ", omittingEmptySubsequences: false)

                if parts.isEmpty || (parts.count == 1 && parts[0].isEmpty) {
                    // Chord with no lyric (e.g. trailing chord)
                    if chunk.chord != nil {
                        items.append(WordItem(id: nextId, word: "", chord: chunk.chord, chordIdx: chordIdx))
                        nextId += 1
                    }
                } else {
                    for (i, part) in parts.enumerated() {
                        let wordText = i < parts.count - 1 ? part + " " : String(part)
                        if wordText.isEmpty { continue }
                        let chord = i == 0 ? chunk.chord : nil
                        let idx = i == 0 ? chordIdx : nil
                        items.append(WordItem(id: nextId, word: wordText, chord: chord, chordIdx: idx))
                        nextId += 1
                    }
                }
            }
            return items
        }()

        return FlowLayout(spacing: 0) {
            ForEach(words) { item in
                VStack(alignment: .leading, spacing: 1) {
                    if let chord = item.chord, let ci = item.chordIdx {
                        let isActive = ci == engine.activeChordIndex
                        Text(chord)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(isActive ? .black : Theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isActive ? Theme.accent : Theme.chordBg)
                            )
                            .shadow(color: isActive ? Theme.accentGlow : .clear, radius: 5)
                    } else {
                        Text(" ")
                            .font(.system(.caption, design: .monospaced).bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .hidden()
                    }

                    Text(item.word.isEmpty ? " " : item.word)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(isActiveLine ? Theme.text : Theme.textDim)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.leading, 6)
        .padding(.horizontal, 10)
        .background(
            HStack(spacing: 0) {
                if isActiveLine {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 3)
                }
                Rectangle()
                    .fill(isActiveLine ? Theme.accent.opacity(0.06) : .clear)
            }
        )
        .cornerRadius(4)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                engine.skipBack()
                scrollToLine(engine.activeLineIndex)
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.body)
                    .foregroundColor(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().stroke(Theme.surface2, lineWidth: 1))
            }

            Button {
                engine.togglePlay()
                if engine.isPlaying && !sessionRecorded {
                    sessionRecorded = true
                    song.recordSession()
                }
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(engine.isPlaying ? Theme.accent : .black)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(engine.isPlaying ? Theme.surface2 : Theme.accent)
                    )
            }

            Button {
                engine.skipForward()
                scrollToLine(engine.activeLineIndex)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.body)
                    .foregroundColor(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().stroke(Theme.surface2, lineWidth: 1))
            }

            Spacer().frame(width: 4)

            HStack(spacing: 6) {
                Button {
                    engine.speed = max(0.05, (engine.speed * 100 - 5).rounded() / 100)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption)
                        .foregroundColor(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().stroke(Theme.surface2, lineWidth: 1))
                }

                Text(String(format: "%.2fx", engine.speed))
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
                    .monospacedDigit()
                    .frame(minWidth: 40)

                Button {
                    engine.speed = min(5.0, (engine.speed * 100 + 5).rounded() / 100)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().stroke(Theme.surface2, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.surface2).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private func loadSong() {
        let parsed = ChordProParser.parse(song.chords)
        var result = parsed
        if result.artist == nil { result.artist = song.artist }
        if result.title == nil { result.title = song.title }
        parsedSong = result
        engine.speed = song.speed
        engine.configure(song: result)
    }

    private func reloadParsedSong() {
        engine.reset()
        loadSong()
    }

    private func countChordsBeforeLine(_ lineIndex: Int, in parsed: ParsedSong) -> Int {
        var count = 0
        for i in 0..<lineIndex {
            let line = parsed.lines[i]
            if line.type == .line {
                for chunk in line.chunks where chunk.chord != nil {
                    count += 1
                }
            }
        }
        return count
    }
}

// MARK: - Scroll tracking

struct ScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LinePositionKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Corner radius helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
