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

    // Lookup tables built from SongLines during loadSong()
    @State private var parsedToSongLine: [Int: Int] = [:]   // parsedLineIndex → songLineIndex
    @State private var skippedParsedLines: Set<Int> = []    // secondary lines in tab groups

    // Fraction of scroll view height used as the playback anchor (0.5 = centre)
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
            let saved = appState.activeSongLineIndex
            if saved > 0 && saved < engine.totalLines {
                engine.seek(toLine: saved)
            }
        }
        .onDisappear {
            engine.pause()
            appState.activeSongLineIndex = engine.activeSongLineIndex
            appState.save()
        }
        .onChange(of: engine.activeSongLineIndex) { _, newIdx in
            appState.activeSongLineIndex = newIdx
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
                if engine.activeSongLineIndex > 0 {
                    proxy.scrollTo("songline-\(engine.activeSongLineIndex)", anchor: .center)
                }
            }
            .onChange(of: engine.activeSongLineIndex) { _, newIdx in
                guard !userScrolling else { return }
                if engine.isPlaying {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("songline-\(newIdx)", anchor: .center)
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
                            scrollToLine(engine.activeSongLineIndex)
                            if wasPlayingBeforeScroll {
                                engine.play()
                            }
                        },
                        onScroll: {
                            if userScrolling { updateLiveCursor() }
                        }
                    )
                    .onAppear {
                        scrollViewCenter = geo.size.height * playbackAnchorFraction
                    }
                }
            )
        }
    }

    private func scrollToLine(_ slIdx: Int) {
        guard let proxy = scrollProxy else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("songline-\(slIdx)", anchor: .center)
        }
    }

    // Finds the SongLine closest to the playback anchor and updates the engine cursor live.
    private func updateLiveCursor() {
        guard !linePositions.isEmpty else { return }
        let anchor = scrollViewCenter
        let chordLineIndices = Set(
            engine.songLines.indices.filter { engine.songLines[$0].beats.contains { $0.index > 0 } }
        )
        let chordPositions = linePositions.filter { chordLineIndices.contains($0.key) }
        guard !chordPositions.isEmpty else { return }
        guard let (slIdx, _) = chordPositions.min(by: { abs($0.value - anchor) < abs($1.value - anchor) }),
              slIdx != engine.activeSongLineIndex
        else { return }
        engine.seek(toLine: slIdx)
    }

    private func heroSection(_ parsed: ParsedSong) -> some View {
        ZStack(alignment: .bottomLeading) {
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

            LinearGradient(
                colors: [Theme.bg.opacity(0.3), Theme.bg.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

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
            songLineView(lineIdx: lineIdx, line: line, parsed: parsed)
        }
    }

    @ViewBuilder
    private func songLineView(lineIdx: Int, line: ChordProLine, parsed: ParsedSong) -> some View {
        if skippedParsedLines.contains(lineIdx) {
            EmptyView()
        } else {
            switch line.type {
            case .section:
                sectionHeader(line.section ?? "")
                    .id("parsed-\(lineIdx)")

            case .comment:
                commentLine(line.text ?? "")
                    .id("parsed-\(lineIdx)")

            case .line:
                if let slIdx = parsedToSongLine[lineIdx] {
                    let sl = engine.songLines[slIdx]
                    let isActive = slIdx == engine.activeSongLineIndex
                    songLineContent(lineIdx: lineIdx, slIdx: slIdx, line: line, sl: sl, parsed: parsed, isActive: isActive)
                } else if line.chunks.isEmpty {
                    Spacer().frame(height: 16).id("parsed-\(lineIdx)")
                }
            }
        }
    }

    @ViewBuilder
    private func songLineContent(lineIdx: Int, slIdx: Int, line: ChordProLine, sl: SongLine, parsed: ParsedSong, isActive: Bool) -> some View {
        let isTab = sl.kind == .tab
        let isProse = !isTab && ChordProParser.isProseLine(line)

        Group {
            if isTab {
                VStack(spacing: 0) {
                    ForEach(sl.parsedLineIndex..<(sl.parsedLineIndex + sl.parsedLineCount), id: \.self) { tabIdx in
                        tabLine(parsed.lines[tabIdx])
                    }
                }
            } else if isProse {
                proseLine(line)
            } else {
                chordLine(chunks: line.chunks, chordStartIndex: sl.chordStartIndex, isActiveLine: isActive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.leading, 6)    // 3 pt bar area + 3 pt gap between bar and content
        .background(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? Theme.accent : .clear)
                    .frame(width: 3)
                Rectangle()
                    .fill(isActive ? Theme.accent.opacity(0.06) : .clear)
            }
        )
        .cornerRadius(4)
        .padding(.horizontal, 10) // outer screen margin — outside the background
        .id("songline-\(slIdx)")
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: LinePositionKey.self,
                    value: [slIdx: geo.frame(in: .named("scroll")).midY]
                )
            }
        )
        .onTapGesture {
            engine.seek(toLine: slIdx)
            scrollToLine(slIdx)
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
        return TabLineView(text: text, activeColumn: 0)
    }

    private func proseLine(_ line: ChordProLine) -> some View {
        let text = line.chunks.map(\.lyric).joined()
        return Text(text)
            .font(.subheadline)
            .foregroundColor(Theme.textDim)
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

                let lyric = chunk.lyric
                let parts = lyric.split(separator: " ", omittingEmptySubsequences: false)

                if parts.isEmpty || (parts.count == 1 && parts[0].isEmpty) {
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
                        let isActive = ci == engine.activeFlatChordIndex
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
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                engine.skipBack()
                scrollToLine(engine.activeSongLineIndex)
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
                scrollToLine(engine.activeSongLineIndex)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.body)
                    .foregroundColor(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().stroke(Theme.surface2, lineWidth: 1))
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    engine.speed = max(0.05, (engine.speed * 100 - 5).rounded() / 100)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption)
                        .foregroundColor(Theme.text)
                        .frame(width: 32, height: 32)
                        .background(Circle().stroke(Theme.surface2, lineWidth: 1))
                }

                Text(String(format: "%.2fx", engine.speed))
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
                    .monospacedDigit()
                    .frame(minWidth: 36)

                Button {
                    engine.speed = min(5.0, (engine.speed * 100 + 5).rounded() / 100)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(Theme.text)
                        .frame(width: 32, height: 32)
                        .background(Circle().stroke(Theme.surface2, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 10)
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

        let lines = song.ensureSongLines(for: result)
        engine.configure(lines: lines)

        // Build lookup tables for the view
        var map: [Int: Int] = [:]
        var skipped: Set<Int> = []
        for (slIdx, sl) in lines.enumerated() {
            map[sl.parsedLineIndex] = slIdx
            for i in (sl.parsedLineIndex + 1)..<(sl.parsedLineIndex + sl.parsedLineCount) {
                skipped.insert(i)
            }
        }
        parsedToSongLine = map
        skippedParsedLines = skipped
    }

    private func reloadParsedSong() {
        engine.reset()
        song.linesData = nil   // force rebuild of SongLines from updated chords
        loadSong()
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

// MARK: - Tab line renderer

private struct TabLineView: View {
    let text: String
    var activeColumn: Int = 0   // reserved for future column highlighting; 0 = none

    var body: some View {
        let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let cw = ("0" as NSString).size(withAttributes: [.font: font]).width
        let ch = font.lineHeight
        let chars = Array(text)

        Canvas { context, size in
            guard !chars.isEmpty, size.width > 0 else { return }

            let naturalWidth = CGFloat(chars.count) * cw
            if naturalWidth > size.width {
                context.concatenate(CGAffineTransform(scaleX: size.width / naturalWidth, y: 1))
            }

            let midY = size.height / 2
            var i = 0

            while i < chars.count {
                let x = CGFloat(i) * cw
                let c = chars[i]

                if c == "-" {
                    var j = i
                    while j < chars.count && chars[j] == "-" { j += 1 }
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: midY))
                    p.addLine(to: CGPoint(x: CGFloat(j) * cw, y: midY))
                    context.stroke(p, with: .color(Theme.textDim.opacity(0.5)), lineWidth: 0.75)
                    i = j

                } else if c == "|" {
                    var p = Path()
                    p.move(to: CGPoint(x: x + cw / 2, y: 0))
                    p.addLine(to: CGPoint(x: x + cw / 2, y: size.height))
                    context.stroke(p, with: .color(Theme.textDim.opacity(0.5)), lineWidth: 0.75)
                    i += 1

                } else if c.isNumber {
                    var j = i
                    while j < chars.count && chars[j].isNumber { j += 1 }
                    let numStr = String(chars[i..<j])
                    let numWidth = CGFloat(j - i) * cw

                    var p = Path()
                    p.move(to: CGPoint(x: x, y: midY))
                    p.addLine(to: CGPoint(x: x + numWidth, y: midY))
                    context.stroke(p, with: .color(Theme.textDim.opacity(0.2)), lineWidth: 0.75)

                    let label = context.resolve(
                        Text(numStr)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.text)
                    )
                    context.draw(label, at: CGPoint(x: x + numWidth / 2, y: midY), anchor: .center)
                    i = j

                } else {
                    let label = context.resolve(
                        Text(String(c))
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundColor(Theme.textDim)
                    )
                    context.draw(label, at: CGPoint(x: x + cw / 2, y: midY), anchor: .center)
                    i += 1
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: ch, maxHeight: ch)
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
