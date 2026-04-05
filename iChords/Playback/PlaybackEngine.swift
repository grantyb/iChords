import Foundation

@MainActor
@Observable
final class PlaybackEngine {
    var isPlaying = false
    var isRecording = false
    var tickCount = 0
    var activeSongLineIndex = 0
    var activeBeatIndex = 0   // index into the current SongLine's beats array

    private(set) var songLines: [SongLine] = []
    private(set) var paragraphStarts: [Int] = []  // SongLine indices that begin a paragraph

    private var elapsed: TimeInterval = 0
    private var playTask: Task<Void, Never>?

    var currentBeatDurationMs: Int? {
        guard activeSongLineIndex < songLines.count,
              activeBeatIndex < songLines[activeSongLineIndex].beats.count else { return nil }
        return songLines[activeSongLineIndex].beats[activeBeatIndex].durationMs
    }

    func setCurrentBeatDuration(_ ms: Int) {
        guard activeSongLineIndex < songLines.count,
              activeBeatIndex < songLines[activeSongLineIndex].beats.count else { return }
        let sl = songLines[activeSongLineIndex]
        var beats = sl.beats
        beats[activeBeatIndex] = SongBeat(index: beats[activeBeatIndex].index, durationMs: ms)
        songLines[activeSongLineIndex] = withBeats(beats, in: sl)
    }

    /// Flat chord index for the chord currently being highlighted, or -1 if none.
    var activeFlatChordIndex: Int {
        guard !songLines.isEmpty, activeSongLineIndex < songLines.count else { return -1 }
        let sl = songLines[activeSongLineIndex]
        guard sl.kind != .tab else { return -1 }
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

    func seek(toLine slIdx: Int, beatValue: Int) {
        guard slIdx < songLines.count else { return }
        let sl = songLines[slIdx]
        guard let beatArrayIdx = sl.beats.firstIndex(where: { $0.index == beatValue }) else { return }
        activeSongLineIndex = slIdx
        activeBeatIndex = beatArrayIdx
        elapsed = 0
    }

    /// In recording mode: stamps the current beat's duration with elapsed time, then advances by a song beat.
    func commitElapsedAndStepForward() {
        guard !songLines.isEmpty, activeSongLineIndex < songLines.count else { return }
        let sl = songLines[activeSongLineIndex]
        guard activeBeatIndex < sl.beats.count else { return }
        let ms = max(1, Int(elapsed * 1000))
        setCurrentBeatDuration(ms)
        if activeBeatIndex < sl.beats.count - 1 {
            activeBeatIndex += 1
        } else {
            stepForward()
        }
        elapsed = 0
    }

    func stepForward() {
        guard !songLines.isEmpty else { return }
        var next = activeSongLineIndex + 1
        while next < songLines.count && songLines[next].beats.isEmpty { next += 1 }
        guard next < songLines.count else { return }
        activeSongLineIndex = next
        activeBeatIndex = 0
        elapsed = 0
    }

    func stepBack() {
        guard !songLines.isEmpty else { return }
        var prev = activeSongLineIndex - 1
        while prev >= 0 && songLines[prev].beats.isEmpty { prev -= 1 }
        guard prev >= 0 else { return }
        activeSongLineIndex = prev
        activeBeatIndex = 0
        elapsed = 0
    }

    func reset() {
        pause()
        activeSongLineIndex = 0
        activeBeatIndex = 0
        elapsed = 0
    }

    private func withBeats(_ beats: [SongBeat], in sl: SongLine) -> SongLine {
        SongLine(kind: sl.kind, parsedLineIndex: sl.parsedLineIndex,
                 parsedLineCount: sl.parsedLineCount, chordStartIndex: sl.chordStartIndex,
                 beats: beats)
    }

    func deleteCurrentBeat() {
        guard activeSongLineIndex < songLines.count else { return }
        let sl = songLines[activeSongLineIndex]
        guard activeBeatIndex < sl.beats.count else { return }
        let beatIndexValue = sl.beats[activeBeatIndex].index
        removeBeat(fromLine: activeSongLineIndex, withBeatIndex: beatIndexValue)
        // activeBeatIndex now points to the next beat on the same line (if any), or is out of bounds
        if activeBeatIndex >= songLines[activeSongLineIndex].beats.count {
            var next = activeSongLineIndex + 1
            while next < songLines.count && songLines[next].beats.isEmpty { next += 1 }
            if next < songLines.count {
                activeSongLineIndex = next
                activeBeatIndex = 0
            } else {
                // No next beat; clamp within current line or leave at 0
                activeBeatIndex = max(0, songLines[activeSongLineIndex].beats.count - 1)
            }
        }
        elapsed = 0
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

        elapsed += 1.0 / 30.0

        guard !isRecording else { return }

        // Skip lines that have no beats at all.
        while activeSongLineIndex < songLines.count && songLines[activeSongLineIndex].beats.isEmpty {
            activeSongLineIndex += 1
            activeBeatIndex = 0
            elapsed = 0
        }

        guard activeSongLineIndex < songLines.count else { return }

        let sl = songLines[activeSongLineIndex]
        if activeBeatIndex >= sl.beats.count { activeBeatIndex = sl.beats.count - 1 }
        let beat = sl.beats[activeBeatIndex]
        let rawDur = beat.durationMs ?? 0
        let durMs = rawDur > 0 ? rawDur : 2000

        guard elapsed >= Double(durMs) / 1000.0 else { return }
        elapsed = 0
        tickCount += 1

        if activeBeatIndex < sl.beats.count - 1 {
            activeBeatIndex += 1
        } else if activeSongLineIndex < songLines.count - 1 {
            activeSongLineIndex += 1
            activeBeatIndex = 0
        } else {
            pause()
        }
    }
}
