import SwiftUI
import UIKit

struct LyricsFinderView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let track: Track

    @State private var title: String
    @State private var artist: String
    @State private var results: [LyricsRecord] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    trackHeader
                    queryFields

                    if isSearching {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching LRCLIB…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else if let errorMessage {
                        message(
                            icon: "wifi.exclamationmark",
                            title: "Search unavailable",
                            detail: errorMessage
                        )
                    } else if hasSearched, results.isEmpty {
                        message(
                            icon: "quote.bubble",
                            title: "No lyrics found",
                            detail: "Try a shorter title or a different spelling for the artist."
                        )
                    } else if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(results.count) matches")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(results) { record in
                                NavigationLink {
                                    LyricsMatchView(track: track, record: record)
                                        .environmentObject(library)
                                } label: {
                                    LyricsResultRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        message(
                            icon: "magnifyingglass",
                            title: "Find lyrics online",
                            detail: "Search by song title and artist, then choose the version that matches your track."
                        )
                    }

                    Text("Lyrics search by LRCLIB")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle("Find Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard !hasSearched else { return }
                await search()
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private var trackHeader: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkURL, seed: track.title + track.artist)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var queryFields: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                TextField("Song title", text: $title)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 14)
                    .frame(height: 48)

                Divider().padding(.leading, 14)

                TextField("Artist", text: $artist)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
            }
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }

            Button {
                Task { await search() }
            } label: {
                HStack(spacing: 7) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(uiColor: .systemBackground))
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(isSearching ? "Searching" : "Search Lyrics")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.primary, in: Capsule())
                .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .buttonStyle(MotifPressStyle(scale: 0.97))
            .disabled(isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private func search() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await LyricsService.search(title: trimmedTitle, artist: artist)
            hasSearched = true
        } catch {
            results = []
            hasSearched = true
            errorMessage = error.localizedDescription
        }
    }
}

private struct LyricsResultRow: View {
    let record: LyricsRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.trackName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(record.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let album = record.albumName, !album.isEmpty {
                    Text(album)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(record.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(record.isWordSynced ? "WORD SYNC" : (record.isSynced ? "SYNCED" : "PLAIN"))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(record.isSynced ? Color.green : Color.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }
}

private struct LyricsMatchView: View {
    @EnvironmentObject private var library: LibraryStore

    let track: Track
    let record: LyricsRecord

    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.trackName)
                        .font(.title3.weight(.bold))
                    Text(record.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(record.durationText)
                        Text("·")
                        Text(record.isWordSynced ? "Word-synced lyrics" : (record.isSynced ? "Synced lyrics" : "Plain lyrics"))
                        if record.instrumental == true {
                            Text("·")
                            Text("Instrumental")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }

                if let lyrics = displayLyrics {
                    Text(lyrics)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("This record has no usable lyrics.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Lyrics from LRCLIB")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(22)
        }
        .background(AppBackground())
        .navigationTitle("Lyrics Match")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(saved ? "Saved" : "Use Lyrics") {
                    if record.hasUsableLyrics {
                        library.setLyrics(
                            record.lyricsText,
                            lyricsFile: record.lyricsfile,
                            for: track
                        )
                        saved = true
                    }
                }
                .fontWeight(.semibold)
                .disabled(saved || !record.hasUsableLyrics)
            }
        }
    }

    private var displayLyrics: String? {
        if let lyricsfile = record.lyricsfile,
           let plain = LyricsFileParser.plainText(from: lyricsfile) {
            return plain
        }

        guard let lyrics = record.lyricsText else { return nil }
        let stripped = lyrics.replacingOccurrences(
            of: "\\[\\d{1,3}:\\d{2}(?:\\.\\d{1,3})?\\]|<\\d{1,3}:\\d{2}(?:\\.\\d{1,3})?>",
            with: "",
            options: .regularExpression
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
