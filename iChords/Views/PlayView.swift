import SwiftUI
import SwiftData
import OSLog


struct PlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Environment(AppState.self) private var appState

    @Bindable var song: Song
    @State private var parsedSong: ParsedSong?
    @State private var engine = PlaybackEngine()
    @State private var sessionRecorded = false
    @State private var autoplaySuspended = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var scrollEndTask: Task<Void, Never>? = nil
    @State private var linePositions: [Int: CGFloat] = [:]
    @State private var scrollViewCenter: CGFloat = UIScreen.main.bounds.height * 0.25
    @State private var heroHeight: CGFloat = 0

    @State private var isEditingBeatDuration = false
    @State private var beatDurationInput = ""
    @State private var beatEditCanceled = false
    @FocusState private var beatDurationFocused: Bool

    // Edit mode
    @State private var isEditing = false
    @State private var editMode = EditModeController()

    // Lookup tables built from SongLines during loadSong()
    @State private var parsedToSongLine: [Int: Int] = [:]   // parsedLineIndex → songLineIndex
    @State private var skippedParsedLines: Set<Int> = []    // secondary lines in tab groups

    var body: some View {
        VStack(spacing: 0) {
            if let parsed = parsedSong {
                if isEditing {
                    editModeContent(parsed)
                } else {
                    songContent(parsed)
                    controls
                }
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
                    toggleEditMode()
                } label: {
                    Image(systemName: isEditing ? "pencil.slash" : "pencil")
                        .foregroundColor(isEditing ? Theme.accent : Theme.textDim)
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
            if saved > 0 && saved < engine.songLines.count {
                engine.seek(toLine: saved, beatValue: 0)
            }
        }
        .onDisappear {
            engine.pause()
            appState.activeSongLineIndex = engine.activeSongLineIndex
            appState.save()
            isEditing = false
        }
        .onChange(of: engine.activeSongLineIndex) { _, newIdx in
            appState.activeSongLineIndex = newIdx
        }
        .onChange(of: engine.tickCount) { _, _ in
            scrollToLine(engine.activeSongLineIndex)
        }
        .sheet(item: Bindable(editMode).editingLine) { line in
            let chords = editMode.lines.map(\.text).joined(separator: "\n")
            LineEditorModal(
                line: line,
                uniqueChords: ChordProParser.uniqueChords(in: ChordProParser.parse(chords)),
                onSave: { newText in
                    editMode.update(id: line.id, text: newText)
                    editMode.save(to: song, context: modelContext)
                }
            )
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
            }
            .coordinateSpace(name: "scroll")
            .onAppear {
                scrollProxy = proxy
                if engine.activeSongLineIndex > 0 {
                    scrollToLine(engine.activeSongLineIndex)
                }
            }
            .onPreferenceChange(ContentOriginKey.self) { originY in
                guard originY > 1 else { return }
                scrollViewCenter = UIScreen.main.bounds.height / 2 - originY
            }
            .onPreferenceChange(LinePositionKey.self) { positions in
                linePositions = positions
            }
            .onPreferenceChange(HeroHeightKey.self) { h in
                heroHeight = h
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, _ in
                if !autoplaySuspended { updateLiveCursor() }
                scheduleScrollEnd()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        autoplaySuspended = engine.isPlaying
                    }
                    .onEnded { _ in
                        scheduleScrollEnd()
                    }
            )
        }
    }

    private func scheduleScrollEnd() {
        scrollEndTask?.cancel()
        scrollEndTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            autoplaySuspended = false
        }
    }

    private func scrollToLine(_ slIdx: Int) {
        guard let proxy = scrollProxy else { return }
        autoplaySuspended = true
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("songline-\(slIdx)", anchor: .center)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            autoplaySuspended = false
        }
    }

    // Finds the uppermost SongLine at or below the playback anchor and updates the engine cursor live.
    // Falls back to the last chord line above the anchor when scrolled past all content.
    private func updateLiveCursor() {
        guard !linePositions.isEmpty else { return }
        let anchor = scrollViewCenter
        let candidateIndices = Set(
            engine.songLines.indices.filter {
                engine.songLines[$0].kind == .tab ||
                engine.songLines[$0].beats.contains { $0.index > 0 }
            }
        )
        let chordPositions = linePositions.filter { candidateIndices.contains($0.key) }
        guard !chordPositions.isEmpty else { return }

        let slIdx: Int
        let atOrBelow = chordPositions.filter { $0.value >= anchor }
        if let (idx, _) = atOrBelow.min(by: { $0.value < $1.value }) {
            slIdx = idx
        } else if let (idx, _) = chordPositions.max(by: { $0.value < $1.value }) {
            slIdx = idx
        } else {
            return
        }

        guard slIdx != engine.activeSongLineIndex else { return }
        engine.seek(toLine: slIdx, beatValue: 0)
    }

    private func heroSection(_ parsed: ParsedSong) -> some View {
        ZStack(alignment: .bottomLeading) {
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
        .background {
            if let url = song.artworkUrl, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
                    .blur(radius: 30)
                    .brightness(-0.4)
                    .scaleEffect(1.2)
                    .clipped()
            }
        }
        .clipped()
        .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
        .padding(.bottom, 12)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: HeroHeightKey.self, value: geo.size.height)
                    .preference(key: ContentOriginKey.self, value: geo.frame(in: .global).minY)
            }
        )
    }

    @ViewBuilder
    private func songLines(_ parsed: ParsedSong) -> some View {
        // Ensure the first song line sits at the vertical centre when scrolled all the way to the top.
        let topPad = heroHeight // max(0, scrollViewCenter - heroHeight)
        if topPad > 0 {
            Color.clear.frame(height: topPad)
        }
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
        let wholeLineBeat = sl.beats.first { $0.index == 0 }
        let hasWholeLineBeat = wholeLineBeat != nil
        let wholeLineBeatColor: Color = wholeLineBeat?.durationMs == nil ? .red : .green
        let recordBeatDurations: [Int: Int?] = Dictionary(uniqueKeysWithValues: sl.beats.filter { $0.index > 0 }
                .map { (sl.chordStartIndex + $0.index - 1, $0.durationMs) })

        Group {
            if isTab {
                let tabHighlights: [TabBeatHighlight] = {
                    if engine.isRecording {
                        return sl.beats.enumerated().compactMap { (beatArrayIdx, beat) -> TabBeatHighlight? in
                            guard beat.index > 0 else { return nil }
                            guard let range = SongLineBuilder.beatColumnRange(for: beat.index, in: sl, parsed: parsed) else { return nil }
                            let color: Color = beat.durationMs != nil ? .green : .red
                            let beatIsActive = isActive && beatArrayIdx == engine.activeBeatIndex
                            return TabBeatHighlight(range: range, color: color, isActive: beatIsActive)
                        }
                    } else if isActive {
                        guard engine.activeBeatIndex < sl.beats.count else { return [] }
                        let beat = sl.beats[engine.activeBeatIndex]
                        guard beat.index > 0 else { return [] }
                        guard let range = SongLineBuilder.beatColumnRange(for: beat.index, in: sl, parsed: parsed) else { return [] }
                        return [TabBeatHighlight(range: range, color: Theme.accent, isActive: true)]
                    } else {
                        return []
                    }
                }()
                let pipeOffset: Int = {
                    let chars = Array(parsed.lines[sl.parsedLineIndex].chunks.first?.lyric ?? "")
                    return (chars.firstIndex(of: "|") ?? -1) + 1
                }()
                let onColumnTap: (Int) -> Void = { col in
                    let bodyCol = col - pipeOffset
                    if bodyCol >= 0,
                       let beatIdx = SongLineBuilder.beatIndex(atBodyColumn: bodyCol, in: sl, parsed: parsed) {
                        engine.seek(toLine: slIdx, beatValue: beatIdx)
                    } else {
                        engine.seek(toLine: slIdx, beatValue: sl.beats.first?.index ?? 1)
                    }
                    scrollToLine(slIdx)
                }
                VStack(spacing: 0) {
                    ForEach(sl.parsedLineIndex..<(sl.parsedLineIndex + sl.parsedLineCount), id: \.self) { tabIdx in
                        tabLine(parsed.lines[tabIdx], highlights: tabHighlights, onColumnTap: onColumnTap)
                    }
                }
            } else {
                chordLine(
                    chunks: line.chunks,
                    chordStartIndex: sl.chordStartIndex,
                    isActiveLine: isActive,
                    slIdx: slIdx,
                    recordBeatDurations: recordBeatDurations
                )
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
        .overlay {
            if engine.isRecording && hasWholeLineBeat { wholeLineBeatColor.opacity(0.12) }
        }
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
            engine.seek(toLine: slIdx, beatValue: sl.beats.first?.index ?? 0)
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

    private func tabLine(_ line: ChordProLine, highlights: [TabBeatHighlight] = [], onColumnTap: ((Int) -> Void)? = nil) -> some View {
        let text = line.chunks.first?.lyric ?? ""
        return TabLineView(text: text, highlights: highlights, onColumnTap: onColumnTap)
    }

    private struct WordItem: Identifiable {
        let id: Int
        let word: String
        let chord: String?
        let chordIdx: Int?
    }

    private func chordLine(chunks: [ChordChunk], chordStartIndex: Int, isActiveLine: Bool, slIdx: Int = 0, recordBeatDurations: [Int: Int?] = [:]) -> some View {
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
                let beatDuration = item.chordIdx.flatMap { recordBeatDurations[$0] }
                let isBeatTarget = beatDuration != nil
                let beatColor: Color = beatDuration == nil ? .red : .green
                VStack(alignment: .leading, spacing: 1) {
                    if let chord = item.chord, let ci = item.chordIdx {
                        let isActive = ci == engine.activeFlatChordIndex
                        Text(chord)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(isActive ? .black : (engine.isRecording && isBeatTarget ? beatColor : Theme.accent))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isActive ? Theme.accent : (engine.isRecording && isBeatTarget ? beatColor.opacity(0.15) : Theme.chordBg))
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
                        .foregroundColor(isBeatTarget ? beatColor : (isActiveLine ? Theme.text : Theme.textDim))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.trailing, item.word.trimmingCharacters(in: .whitespaces).isEmpty ? 8 : 0)
                .onTapGesture {
                    guard let ci = item.chordIdx else { return }
                    let beatValue = ci - chordStartIndex + 1
                    engine.seek(toLine: slIdx, beatValue: beatValue)
                    scrollToLine(slIdx)
                }
                .allowsHitTesting(item.chordIdx != nil)
            }
        }
    }

    private var controls: some View {
        HStack {
            HStack(spacing: 8) {
                Button {
                    engine.stepBack()
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
                    let isStalled = engine.isPlaying && (engine.isRecording || engine.currentBeatDurationMs == nil)
                    ZStack {
                        Circle()
                            .fill(engine.isPlaying ? Theme.surface2 : Theme.accent)
                        if isStalled {
                            StalledIndicator()
                        } else {
                            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundColor(engine.isPlaying ? Theme.accent : .black)
                        }
                    }
                    .frame(width: 56, height: 56)
                }

                Button {
                    if engine.isRecording {
                        engine.commitElapsedAndStepForward()
                        song.linesData = try? JSONEncoder().encode(engine.songLines)
                    } else {
                        engine.stepForward()
                    }
                    scrollToLine(engine.activeSongLineIndex)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                        .foregroundColor(Theme.text)
                        .frame(width: 44, height: 44)
                        .background(Circle().stroke(Theme.surface2, lineWidth: 1))
                }
            }

            Spacer()

            let durationMs = engine.currentBeatDurationMs
            Button {
                engine.deleteCurrentBeat()
                scrollToLine(engine.activeSongLineIndex)
                song.linesData = try? JSONEncoder().encode(engine.songLines)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
                    .frame(width: 28, height: 28)
            }
            if isEditingBeatDuration {
                TextField("ms", text: $beatDurationInput)
                    .keyboardType(.numberPad)
                    .focused($beatDurationFocused)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onSubmit { commitBeatDurationEdit() }
                    .onChange(of: beatDurationFocused) { _, focused in
                        guard !focused else { return }
                        if beatEditCanceled {
                            beatEditCanceled = false
                            isEditingBeatDuration = false
                        } else {
                            commitBeatDurationEdit()
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Button("Cancel") {
                                beatEditCanceled = true
                                beatDurationFocused = false
                            }
                            .foregroundColor(Theme.textDim)
                            Spacer()
                            Button("Done") {
                                commitBeatDurationEdit()
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.accent)
                        }
                    }
            } else {
                Text(durationMs.map { "\($0) ms" } ?? "-- ms")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textDim)
                    .onTapGesture {
                        beatDurationInput = durationMs.map { "\($0)" } ?? ""
                        isEditingBeatDuration = true
                        beatDurationFocused = true
                    }
            }

            Button {
                engine.isRecording.toggle()
            } label: {
                Image(systemName: engine.isRecording ? "record.circle.fill" : "record.circle")
                    .font(.title2)
                    .foregroundColor(engine.isRecording ? .red : Theme.textDim)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 0)
        .background {
            Theme.surface.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.surface2).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private func commitBeatDurationEdit() {
        isEditingBeatDuration = false
        if let ms = Int(beatDurationInput), ms >= 0 {
            engine.setCurrentBeatDuration(ms)
            song.linesData = try? JSONEncoder().encode(engine.songLines)
        }
    }


    private func loadSong() {
        let parsed = ChordProParser.parse(song.chords)
        var result = parsed
        if result.artist == nil { result.artist = song.artist }
        if result.title == nil { result.title = song.title }
        parsedSong = result

        var lines = song.ensureSongLines(for: result)

        // Ensure every line has at least one beat; for lines with chords, one beat per chord.
        var needsResave = false
        lines = lines.map { sl in
            guard sl.beats.isEmpty else { return sl }
            needsResave = true
            let beats: [SongBeat]
            if sl.kind == .tab {
                beats = SongLineBuilder.tabBeats(for: sl, in: result)
            } else {
                let chordCount = sl.parsedLineIndex < result.lines.count
                    ? result.lines[sl.parsedLineIndex].chunks.filter { $0.chord != nil }.count
                    : 0
                beats = chordCount > 0
                    ? (1...chordCount).map { SongBeat(index: $0, durationMs: 0) }
                    : [SongBeat(index: 0, durationMs: 0)]
            }
            return SongLine(
                kind: sl.kind,
                parsedLineIndex: sl.parsedLineIndex,
                parsedLineCount: sl.parsedLineCount,
                chordStartIndex: sl.chordStartIndex,
                beats: beats
            )
        }
        if needsResave {
            song.linesData = try? JSONEncoder().encode(lines)
        }

        engine.configure(lines: lines)

        // Debug: log beat count per song line
        for (i, sl) in lines.enumerated() {
            print("[iChords] songLine[\(i)] kind=\(sl.kind) parsedLineIndex=\(sl.parsedLineIndex) beats=\(sl.beats.count)")
        }

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

    // MARK: - Edit mode

    private func toggleEditMode() {
        if isEditing {
            isEditing = false
            reloadParsedSong()
        } else {
            engine.pause()
            editMode.load(from: song)
            isEditing = true
        }
    }

    // MARK: - Edit mode views

    private func editModeContent(_ parsed: ParsedSong) -> some View {
        List {
            heroSection(parsed)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(editMode.lines) { line in
                editModeRow(line)
            }
            .onMove { from, to in
                editMode.move(from: from, to: to)
                editMode.save(to: song, context: modelContext)
            }

            Color.clear.frame(height: 40)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    @ViewBuilder
    private func editModeRow(_ line: EditableLine) -> some View {
        HStack(spacing: 0) {
            editModeRowContent(line: line)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Button {
                editMode.delete(id: line.id)
                editMode.save(to: song, context: modelContext)
            } label: {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundColor(Theme.textDim.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            Button {
                editMode.duplicate(id: line.id)
                editMode.save(to: song, context: modelContext)
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.callout)
                    .foregroundColor(Theme.accent.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { editMode.editingLine = line }
    }

    @ViewBuilder
    private func editModeRowContent(line: EditableLine) -> some View {
        let trimmed = line.text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "return")
                    .font(.caption2)
                    .foregroundColor(Theme.surface2)
                Text("blank line")
                    .font(.caption2)
                    .foregroundColor(Theme.surface2)
            }
            .padding(.vertical, 4)
        } else if isTabGroup(line.text) {
            VStack(spacing: 0) {
                ForEach(Array(line.text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, tabLine in
                    TabLineView(text: tabLine)
                }
            }
            .padding(.vertical, 2)
        } else if editMode.isSectionHeader(trimmed) {
            Text(editMode.sectionName(trimmed).uppercased())
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(Theme.sectionColor)
                .tracking(1)
                .padding(.vertical, 4)
        } else if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            Text(trimmed)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.textDim)
                .italic()
                .padding(.vertical, 2)
        } else {
            Text(editMode.attributedLine(trimmed))
                .lineLimit(3)
                .padding(.vertical, 2)
        }
    }

}


