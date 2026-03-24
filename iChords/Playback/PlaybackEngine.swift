import Foundation
import Combine

struct ChordTiming {
    let flatIndex: Int
    let lineIndex: Int
    let wordCount: Int
}

@MainActor
@Observable
final class PlaybackEngine {
    var isPlaying = false
    var activeChordIndex = 0
    var activeLineIndex = -1
    var speed: Double = 1.0

    private(set) var chordTimings: [ChordTiming] = []
    private(set) var paragraphStarts: [Int] = []

    private var elapsed: TimeInterval = 0
    private var playTask: Task<Void, Never>?

    var totalChords: Int { chordTimings.count }

    func configure(song: ParsedSong) {
        var timings: [ChordTiming] = []
        var paragraphs: [Int] = [0]
        var flatIdx = 0
        var inParagraph = false

        for (lineIdx, line) in song.lines.enumerated() {
            let isLyricLine = line.type == .line && !line.chunks.isEmpty
            let hasChords = isLyricLine && line.chunks.contains { $0.chord != nil }

            if isLyricLine && hasChords {
                if !inParagraph {
                    paragraphs.append(flatIdx)
                    inParagraph = true
                }
                for chunk in line.chunks where chunk.chord != nil {
                    let words = chunk.lyric
                        .trimmingCharacters(in: .whitespaces)
                        .split(separator: " ")
                        .filter { !$0.isEmpty }
                    timings.append(ChordTiming(
                        flatIndex: flatIdx,
                        lineIndex: lineIdx,
                        wordCount: max(1, words.count)
                    ))
                    flatIdx += 1
                }
            } else {
                inParagraph = false
                if isLyricLine {
                    for chunk in line.chunks where chunk.chord != nil {
                        timings.append(ChordTiming(
                            flatIndex: flatIdx,
                            lineIndex: lineIdx,
                            wordCount: 1
                        ))
                        flatIdx += 1
                    }
                }
            }
        }

        chordTimings = timings
        paragraphStarts = Array(Set(paragraphs)).sorted()
        activeChordIndex = 0
        activeLineIndex = timings.first?.lineIndex ?? -1
        elapsed = 0
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !chordTimings.isEmpty else { return }
        isPlaying = true
        elapsed = 0
        playTask = Task {
            let interval: UInt64 = 1_000_000_000 / 30 // ~33ms
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

    func seek(to chordIndex: Int) {
        let clamped = max(0, min(chordIndex, totalChords - 1))
        activeChordIndex = clamped
        activeLineIndex = chordTimings.isEmpty ? -1 : chordTimings[clamped].lineIndex
        elapsed = 0
    }

    func skipForward() {
        let current = activeChordIndex
        if let next = paragraphStarts.first(where: { $0 > current }) {
            seek(to: next)
        } else if totalChords > 0 {
            seek(to: totalChords - 1)
        }
    }

    func skipBack() {
        let current = activeChordIndex
        var prev = 0
        for s in paragraphStarts {
            if s >= current { break }
            prev = s
        }
        seek(to: prev)
    }

    func reset() {
        pause()
        activeChordIndex = 0
        activeLineIndex = chordTimings.first?.lineIndex ?? -1
        elapsed = 0
    }

    private func tick() {
        guard !chordTimings.isEmpty else { return }
        elapsed += 1.0 / 30.0

        let timing = chordTimings[activeChordIndex]
        let baseDuration = max(0.5, Double(timing.wordCount) * 0.35)
        let duration = baseDuration / speed

        if elapsed >= duration {
            if activeChordIndex < totalChords - 1 {
                activeChordIndex += 1
                activeLineIndex = chordTimings[activeChordIndex].lineIndex
                elapsed = 0
            } else {
                pause()
            }
        }
    }
}
