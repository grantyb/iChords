# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Setup & Build

This project uses **XcodeGen** to generate the `.xcodeproj` from `project.yml`.

```bash
./setup.sh          # First-time setup: installs XcodeGen, generates project, opens Xcode
xcodegen generate   # Regenerate Xcode project after editing project.yml
```

Build and run via Xcode (iOS Simulator or device). The project targets **iOS 17.0+**, requires **Xcode 16+**, and uses **Swift 6.0** with strict concurrency enabled (`SWIFT_STRICT_CONCURRENCY: targeted`).

To run the project, use applescript to tell XCode to use the Run command from the Project menu

## Architecture Overview

**iChords** is a SwiftUI iPhone app for learning guitar chords. Users search Songsterr for songs, save them to a local library, and play along with synchronized chord display.

### Core Data Flow

1. **Search**: `SearchView` → `SongsterrService` → Songsterr API (two-step: metadata then ChordPro file) + iTunes API (artwork) → creates `Song` in SwiftData
2. **Library**: `LibraryView` queries SwiftData for all non-deleted `Song` records
3. **Playback**: `PlayView` loads a `Song`, instantiates `PlaybackEngine` which pre-computes chord timings, then drives auto-scroll and chord highlighting

### Key Layers

- **`AppState`** (`@Observable`, UserDefaults-backed) — singleton for cross-view state: active song, sort preference, scroll position
- **`PlaybackEngine`** — decoupled from UI; pre-computes timing for all chord events, supports speed adjustment and paragraph skipping
- **`ChordProParser`** — regex-based parser that classifies lines as lyrics, tabs, or prose and extracts chord positions
- **`SongsterrService`** — async API client; fetches song list then resolves ChordPro URL via revision ID
- **SwiftData models**: `Song` (core entity with soft-delete and play tracking), `ChordVersion` (edit history for rollback), `RecentSearch` (search cache)

### Data Persistence

- **SwiftData** for all models — schema versioning defined in `SchemaVersions.swift` (V1→V2 adds `ChordVersion`)
- Songs use **soft deletes** (`deletedAt` timestamp) rather than hard deletion
- `AppState` persists lightweight UI state to **UserDefaults**

### Networking

Songsterr endpoints:
- Search: `GET https://www.songsterr.com/api/songs?pattern={query}`
- Metadata: `GET https://www.songsterr.com/api/chords/{songId}`
- ChordPro file: `GET https://chordpro2.songsterr.com/{songId}/{revisionId}/{chordpro}.chordpro`

All requests use `User-Agent: iChords/1.0`.

## Project Configuration

Add new source files to `project.yml` under the `sources` key — the project will not compile them otherwise. After editing `project.yml`, run `xcodegen generate`.
