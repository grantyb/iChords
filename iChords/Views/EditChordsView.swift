import SwiftUI
import SwiftData

struct EditChordsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var value: String
    @State private var versions: [ChordVersion] = []
    @State private var draftText: String?
    @State private var viewIndex: Int = 0
    @State private var suppressTextSync = false

    let song: Song
    let onSave: (String) -> Void

    init(song: Song, onSave: @escaping (String) -> Void) {
        self.song = song
        self.onSave = onSave
        _value = State(initialValue: song.chords)
    }

    private var hasDraft: Bool { draftText != nil }
    private var totalCount: Int { max(1, versions.count + (hasDraft ? 1 : 0)) }
    private var canGoBack: Bool { viewIndex > 0 }
    private var canGoForward: Bool { viewIndex < totalCount - 1 }
    private var isDraftSlot: Bool { hasDraft && viewIndex == versions.count }

    private var versionLabel: String {
        "\(viewIndex + 1) / \(totalCount)"
    }

    private var displayDate: Date? {
        if isDraftSlot {
            return versions.last?.createdAt
        }
        guard viewIndex >= 0, viewIndex < versions.count else { return nil }
        return versions[viewIndex].createdAt
    }

    var body: some View {
        @Bindable var state = appState
        NavigationStack {
            VStack(spacing: 0) {
                versionBar
                ChordsTextEditor(text: $value, cursorPosition: $state.editCursorPosition)
                    .padding(8)
            }
            .background(Theme.bg)
            .navigationTitle("Edit Chords")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ChordVersion.saveNewVersion(for: song, text: value, context: modelContext)
                        onSave(value)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ChordVersion.ensureInitialVersion(for: song, context: modelContext)
            versions = ChordVersion.versions(for: song.id, context: modelContext)
            viewIndex = versions.count - 1
        }
        .onDisappear {
            appState.save()
        }
        .onChange(of: value) {
            guard !suppressTextSync else { return }

            // Only track draft changes when at the latest saved version or the draft slot
            let atLatest = viewIndex == versions.count - 1
            let atDraft = isDraftSlot

            guard atLatest || atDraft else { return }

            let latestText = versions.last?.text ?? ""
            if value == latestText {
                draftText = nil
                viewIndex = versions.count - 1
            } else {
                draftText = value
                viewIndex = versions.count
            }
        }
    }

    private var versionBar: some View {
        HStack(spacing: 16) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(canGoBack ? Theme.accent : Theme.surface2)
            }
            .disabled(!canGoBack)

            VStack(spacing: 1) {
                Text(versionLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Theme.text)
                if let date = displayDate {
                    HStack(spacing: 4) {
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundColor(Theme.textDim)
                        if isDraftSlot {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }

            Button {
                goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(canGoForward ? Theme.accent : Theme.surface2)
            }
            .disabled(!canGoForward)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private func goBack() {
        guard canGoBack else { return }
        viewIndex -= 1
        loadVersionText()
    }

    private func goForward() {
        guard canGoForward else { return }
        viewIndex += 1
        loadVersionText()
    }

    private func loadVersionText() {
        suppressTextSync = true
        if isDraftSlot, let draft = draftText {
            value = draft
        } else if viewIndex < versions.count {
            value = versions[viewIndex].text
        }
        // Defer reset so onChange sees the flag
        DispatchQueue.main.async {
            suppressTextSync = false
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}
