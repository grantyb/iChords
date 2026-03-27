import Foundation

@MainActor
@Observable
final class PlaybackEngine {
    var isPlaying = false
    var activeSongLineIndex = 0
    var activeBeatIndex = 0   // index into the current SongLine's beats array
    var speed: Double = 1.0

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

    private func tick() {
        guard !songLines.isEmpty, activeSongLineIndex < songLines.count else { return }
        elapsed += 1.0 / 30.0

        let sl = songLines[activeSongLineIndex]
        let beat = sl.beats[activeBeatIndex]
        let durationSec = Double(beat.durationMs) / 1000.0 / speed

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
