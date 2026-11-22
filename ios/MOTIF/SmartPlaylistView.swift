import SwiftUI

struct SmartPlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var result: SmartPlaylistResult?
    @State private var errorMessage: String?
    @State private var isGenerating = false
    @State private var didSave = false
    @FocusState private var isPromptFocused: Bool

    private let examples = [
        "Late-night drive",
        "Sunny Sunday morning",
        "Songs for focus",
        "A 30-minute workout",
    ]

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedPrompt.isEmpty && !library.tracks.isEmpty && !isGenerating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("A mix from your own library", systemImage: "sparkles")
                            .font(.headline)

                        Text("Describe a mood, a moment, or a kind of song. Lilt will choose the tracks and name the playlist.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField(
                        "A late-night drive, warm and unhurried…",
                        text: $prompt,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .focused($isPromptFocused)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Playlist description")
                } header: {
                    Text("Describe it")
                } footer: {
                    if library.tracks.isEmpty {
                        Text("Add songs to your library before making a smart playlist.")
                    } else {
                        Text("Only song titles, artists, albums, and play counts are sent to OpenRouter. Audio never leaves your iPhone.")
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(examples, id: \.self) { example in
                                Button(example) {
                                    prompt = example
                                    isPromptFocused = true
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "Choosing songs…" : "Generate Playlist")
                            Spacer()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 3)
                    }
                    .disabled(!canGenerate)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let result {
                    preview(result)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Smart Playlist")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .tint(.primary)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func preview(_ result: SmartPlaylistResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(result.name)
                    .font(.headline)

                if !result.description.isEmpty {
                    Text(result.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(result.tracks.count == 1 ? "1 song" : "\(result.tracks.count) songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            ForEach(result.tracks.prefix(6)) { track in
                HStack(spacing: 10) {
                    ArtworkView(
                        url: track.artworkURL,
                        seed: track.title + track.artist,
                        thumbnail: true
                    )
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Text(track.durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if result.tracks.count > 6 {
                Text("+ \(result.tracks.count - 6) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Preview")
        }

        Section {
            Button {
                save(result)
            } label: {
                Label("Save Playlist", systemImage: "plus")
                    .fontWeight(.semibold)
            }

            Button("Try Again") {
                generate()
            }
            .disabled(isGenerating)
        }
    }

    @MainActor
    private func generate() {
        guard canGenerate else { return }

        isPromptFocused = false
        result = nil
        errorMessage = nil
        isGenerating = true

        let prompt = trimmedPrompt
        let tracks = library.tracks
        let playCounts = library.playCounts
        let favoriteIDs = library.favoriteIDs
        let recentIDs = library.recentTrackIDs

        Task {
            do {
                let generated = try await SmartPlaylistService.generate(
                    prompt: prompt,
                    library: tracks,
                    playCounts: playCounts,
                    favoriteIDs: favoriteIDs,
                    recentIDs: recentIDs
                )
                guard !Task.isCancelled else { return }
                result = generated
                isGenerating = false
                MotifHaptics.play(.success)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                isGenerating = false
            }
        }
    }

    @MainActor
    private func save(_ result: SmartPlaylistResult) {
        guard !didSave else { return }
        guard let playlist = library.createPlaylist(
            named: result.name,
            description: result.description
        ) else {
            errorMessage = "The playlist could not be saved."
            return
        }

        library.add(result.tracks, to: playlist.id)
        didSave = true
        MotifHaptics.play(.success)
        dismiss()
    }
}
