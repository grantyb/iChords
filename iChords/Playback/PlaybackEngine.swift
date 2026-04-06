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

    private var beatStartDate: Date = Date()
    private var playTask: Task<Void, Never>?

    var currentBeatDurationNs: Int? {
        guard activeSongLineIndex < songLines.count,
              activeBeatIndex < songLines[activeSongLineIndex].beats.count else { return nil }
        return songLines[activeSongLineIndex].beats[activeBeatIndex].durationNs
    }

    func setCurrentBeatDurationNs(_ ns: Int) {
        guard activeSongLineIndex < songLines.count,
              activeBeatIndex < songLines[activeSongLineIndex].beats.count else { return }
        let sl = songLines[activeSongLineIndex]
        var beats = sl.beats
        beats[activeBeatIndex] = SongBeat(index: beats[activeBeatIndex].index, durationNs: ns)
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
        beatStartDate = Date()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !songLines.isEmpty else { return }
        isPlaying = true
        beatStartDate = Date()
        playTask = Task {
            // Absolute time the next beat-advance should fire.
            // Using this instead of relative sleeps prevents overshoot from accumulating.
            var nextFireDate = Date()

            while isPlaying && !isRecording && !Task.isCancelled {
                // Skip lines with no beats.
                while activeSongLineIndex < songLines.count && songLines[activeSongLineIndex].beats.isEmpty {
                    activeSongLineIndex += 1
                    activeBeatIndex = 0
                }
                guard activeSongLineIndex < songLines.count else { pause(); break }

                let sl = songLines[activeSongLineIndex]
                if activeBeatIndex >= sl.beats.count { activeBeatIndex = sl.beats.count - 1 }
                let rawDur = sl.beats[activeBeatIndex].durationNs ?? 0
                let durNs = rawDur > 0 ? rawDur : 2_000_000_000

                // Advance the absolute target by this beat's duration.
                nextFireDate = nextFireDate.addingTimeInterval(Double(durNs) / 1_000_000_000)
                beatStartDate = Date()

                // Sleep only for the remaining time to the target — any prior overshoot is
                // automatically absorbed here, preventing drift from accumulating.
                let remainingNs = nextFireDate.timeIntervalSinceNow * 1_000_000_000
                if remainingNs > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remainingNs))
                    } catch { break }
                }

                guard isPlaying && !isRecording else { continue }

                tickCount += 1
                if activeBeatIndex < sl.beats.count - 1 {
                    activeBeatIndex += 1
                } else if activeSongLineIndex < songLines.count - 1 {
                    activeSongLineIndex += 1
                    activeBeatIndex = 0
                } else {
                    pause()
                    break
                }
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
        restartPlayTask()
    }

    /// In recording mode: stamps the current beat with the actual elapsed wall-clock time, then advances.
    func commitElapsedAndStepForward() {
        guard !songLines.isEmpty, activeSongLineIndex < songLines.count else { return }
        let sl = songLines[activeSongLineIndex]
        guard activeBeatIndex < sl.beats.count else { return }
        let ns = max(1, Int(Date().timeIntervalSince(beatStartDate) * 1_000_000_000))
        setCurrentBeatDurationNs(ns)
        if activeBeatIndex < sl.beats.count - 1 {
            activeBeatIndex += 1
        } else {
            stepForward()
        }
        beatStartDate = Date()
    }

    func stepForward() {
        guard !songLines.isEmpty else { return }
        var next = activeSongLineIndex + 1
        while next < songLines.count && songLines[next].beats.isEmpty { next += 1 }
        guard next < songLines.count else { return }
        activeSongLineIndex = next
        activeBeatIndex = 0
        restartPlayTask()
    }

    func stepBack() {
        guard !songLines.isEmpty else { return }
        var prev = activeSongLineIndex - 1
        while prev >= 0 && songLines[prev].beats.isEmpty { prev -= 1 }
        if prev < 0 {
            prev = songLines.indices.first { !songLines[$0].beats.isEmpty } ?? 0
        }
        activeSongLineIndex = prev
        activeBeatIndex = 0
        restartPlayTask()
    }

    func reset() {
        pause()
        activeSongLineIndex = 0
        activeBeatIndex = 0
        beatStartDate = Date()
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
        if activeBeatIndex >= songLines[activeSongLineIndex].beats.count {
            var next = activeSongLineIndex + 1
            while next < songLines.count && songLines[next].beats.isEmpty { next += 1 }
            if next < songLines.count {
                activeSongLineIndex = next
                activeBeatIndex = 0
            } else {
                activeBeatIndex = max(0, songLines[activeSongLineIndex].beats.count - 1)
            }
        }
        beatStartDate = Date()
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

    private func restartPlayTask() {
        beatStartDate = Date()
        guard isPlaying else { return }
        playTask?.cancel()
        playTask = nil
        play()
    }

}
