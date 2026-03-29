import Foundation

@MainActor
@Observable
final class PlaybackEngine {
    var isPlaying = false
    var activeSongLineIndex = 0
    var activeBeatIndex = 0   // index into the current SongLine's beats array

    private(set) var songLines: [SongLine] = []
    private(set) var paragraphStarts: [Int] = []  // SongLine indices that begin a paragraph

    private var elapsed: TimeInterval = 0
    private var playTask: Task<Void, Never>?

    var totalLines: Int { songLines.count }

    /// Flat chord index for the chord currently being highlighted, or -1 if none.
    var activeFlatChordIndex: Int {
        guard !songLines.isEmpty, activeSongLineIndex < songLines.count else { return -1 }
        let sl = songLines[activeSongLineIndex]
        guard activeBeatIndex < sl.beats.count else { return -1 }
        let beat = sl.beats[activeBeatIndex]
        guard beat.index > 0 else { return -1 }
        return sl.chordStartIndex + beat.index - 1
    }

    /// Index into `parsed.lines` of the active SongLine's first parsed row (for scrolling).
    var activeParsedLineIndex: Int {
        guard !songLines.isEmpty, activeSongLineIndex < songLines.count else { return -1 }
        return songLines[activeSongLineIndex].parsedLineIndex
    }

    func configure(lines: [SongLine]) {
        var paragraphs: [Int] = []
        var inParagraph = false

        for (idx, line) in lines.enumerated() {
            let hasChords = line.beats.contains { $0.index > 0 }
            if hasChords {
                if !inParagraph {
                    paragraphs.append(idx)
                    inParagraph = true
                }
            } else {
                inParagraph = false
            }
        }

        songLines = lines
        paragraphStarts = paragraphs.isEmpty ? (lines.isEmpty ? [] : [0]) : paragraphs
        activeSongLineIndex = 0
        activeBeatIndex = 0
        elapsed = 0
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !songLines.isEmpty else { return }
        isPlaying = true
        elapsed = 0
        playTask = Task {
            let interval: UInt64 = 1_000_000_000 / 30  // ~33 ms
            while !Task.isCancelled && isPlaying {
                try? await Task.sleep(nanoseconds: interval)
                tick()
            }
        }
    }

    func pause() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    func seek(toLine lineIndex: Int) {
        guard !songLines.isEmpty else { return }
        let clamped = max(0, min(lineIndex, totalLines - 1))
        activeSongLineIndex = clamped
        activeBeatIndex = 0
        elapsed = 0
    }

    func skipForward() {
        let current = activeSongLineIndex
        if let next = paragraphStarts.first(where: { $0 > current }) {
            seek(toLine: next)
        } else if totalLines > 0 {
            seek(toLine: totalLines - 1)
        }
    }

    func skipBack() {
        let current = activeSongLineIndex
        var prev = paragraphStarts.first ?? 0
        for s in paragraphStarts {
            if s >= current { break }
            prev = s
        }
        seek(toLine: prev)
    }

    func reset() {
        pause()
        activeSongLineIndex = 0
        activeBeatIndex = 0
        elapsed = 0
    }

    /// In record mode during playback: records the elapsed duration for the current beat,
    /// deletes all beats between the current one (exclusive) and the tapped position (inclusive),
    /// and inserts a new 0-duration beat at the tapped position, then seeks there.
    /// Returns true if the tap was handled (i.e. the position is forward of the current beat).
    @discardableResult
    func recordTap(atLine tappedSlIdx: Int, beatValue tappedBeatValue: Int) -> Bool {
        guard isPlaying, activeSongLineIndex < songLines.count else { return false }
        let currentSLIdx = activeSongLineIndex
        let currentBeatArrayIdx = activeBeatIndex
        let currentSL = songLines[currentSLIdx]
        guard currentBeatArrayIdx < currentSL.beats.count else { return false }
        let currentBeatValue = currentSL.beats[currentBeatArrayIdx].index

        // Verify tapped position is forward of current beat
        if tappedSlIdx < currentSLIdx { return false }
        if tappedSlIdx == currentSLIdx, tappedBeatValue <= currentBeatValue { return false }

        // 1. Stamp current beat's duration with elapsed time
        let elapsedMs = max(1, Int(elapsed * 1000))
        var currentBeats = currentSL.beats
        currentBeats[currentBeatArrayIdx] = SongBeat(index: currentBeatValue, durationMs: elapsedMs)

        if tappedSlIdx == currentSLIdx {
            // Same line: drop beats between current (exclusive) and tapped (inclusive)
            let kept = currentBeats.enumerated().compactMap { idx, beat -> SongBeat? in
                (idx <= currentBeatArrayIdx || beat.index > tappedBeatValue) ? beat : nil
            }
            songLines[currentSLIdx] = withBeats(kept, in: songLines[currentSLIdx])
        } else {
            // Trim current line to just up through the current beat
            songLines[currentSLIdx] = withBeats(Array(currentBeats.prefix(currentBeatArrayIdx + 1)),
                                                 in: songLines[currentSLIdx])
            // Clear all intermediate lines
            for idx in (currentSLIdx + 1)..<tappedSlIdx {
                songLines[idx] = withBeats([], in: songLines[idx])
            }
            // Drop beats up to and including tappedBeatValue from the tapped line
            let kept = songLines[tappedSlIdx].beats.filter { $0.index > tappedBeatValue }
            songLines[tappedSlIdx] = withBeats(kept, in: songLines[tappedSlIdx])
        }

        // 2. Insert new 0-duration beat at tapped position
        var tslBeats = songLines[tappedSlIdx].beats
        let insertIdx = tslBeats.firstIndex(where: { $0.index > tappedBeatValue }) ?? tslBeats.count
        tslBeats.insert(SongBeat(index: tappedBeatValue, durationMs: 0), at: insertIdx)
        songLines[tappedSlIdx] = withBeats(tslBeats, in: songLines[tappedSlIdx])

        // 3. Seek to the new beat
        activeSongLineIndex = tappedSlIdx
        activeBeatIndex = insertIdx
        elapsed = 0
        return true
    }

    private func withBeats(_ beats: [SongBeat], in sl: SongLine) -> SongLine {
        SongLine(kind: sl.kind, parsedLineIndex: sl.parsedLineIndex,
                 parsedLineCount: sl.parsedLineCount, chordStartIndex: sl.chordStartIndex,
                 beats: beats)
    }

    func removeBeat(fromLine slIdx: Int, withBeatIndex beatIndex: Int) {
        guard slIdx < songLines.count else { return }
        let sl = songLines[slIdx]
        let newBeats = sl.beats.filter { $0.index != beatIndex }
        songLines[slIdx] = SongLine(
            kind: sl.kind,
            parsedLineIndex: sl.parsedLineIndex,
            parsedLineCount: sl.parsedLineCount,
            chordStartIndex: sl.chordStartIndex,
            beats: newBeats
        )
    }

    private func tick() {
        guard !songLines.isEmpty else { return }

        // Advance past any lines that have no beats.
        while activeSongLineIndex < songLines.count && songLines[activeSongLineIndex].beats.isEmpty {
            activeSongLineIndex += 1
            activeBeatIndex = 0
            elapsed = 0
        }
        guard activeSongLineIndex < songLines.count else { pause(); return }

        elapsed += 1.0 / 30.0

        let sl = songLines[activeSongLineIndex]
        // Clamp beat index in case beats were deleted mid-line.
        if activeBeatIndex >= sl.beats.count { activeBeatIndex = sl.beats.count - 1 }
        let beat = sl.beats[activeBeatIndex]
        let durationSec = Double(beat.durationMs) / 1000.0
        guard beat.durationMs > 0 else { return }  // stall; elapsed keeps accumulating for record mode

        guard elapsed >= durationSec else { return }
        elapsed = 0

        if activeBeatIndex < sl.beats.count - 1 {
            activeBeatIndex += 1
        } else if activeSongLineIndex < totalLines - 1 {
            activeSongLineIndex += 1
            activeBeatIndex = 0
        } else {
            pause()
        }
    }
}
