import PhotosUI
import SwiftUI
import UIKit

private struct PlaylistRoute: Hashable {
    let id: UUID
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Binding var showNowPlaying: Bool

    @State private var showCreatePlaylist = false
    @State private var showSmartPlaylist = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    yourPlaylistsSection
                }
                .screenEntrance()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSmartPlaylist = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Smart playlist")

                    Button {
                        showCreatePlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New playlist")
                }
            }
            .navigationDestination(for: PlaylistRoute.self) { route in
                PlaylistDetailView(
                    playlistID: route.id,
                    showNowPlaying: $showNowPlaying
                )
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistEditorView()
            }
            .sheet(isPresented: $showSmartPlaylist) {
                SmartPlaylistView()
                    .environmentObject(library)
            }
        }
    }

    @ViewBuilder
    private var yourPlaylistsSection: some View {
        if library.playlists.isEmpty {
            emptyState
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .nativeGlass(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        } else {
            playlistGrid
        }
    }

    private var playlistGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ],
            alignment: .leading,
            spacing: 22
        ) {
            ForEach(library.playlists) { playlist in
                playlistTile(playlist)
            }

            newPlaylistTile
        }
        .padding(.horizontal, 2)
    }

    private func playlistTile(_ playlist: Playlist) -> some View {
        let tracks = library.tracks(in: playlist)

        return NavigationLink(value: PlaylistRoute(id: playlist.id)) {
            PlaylistTile(playlist: playlist, tracks: tracks)
        }
        .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.92))
        .contextMenu {
            Button {
                play(playlist)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            if tracks.contains(where: { $0.isCloud && !library.isDownloaded($0) }) {
                Button {
                    Task {
                        await library.downloadAll(
                            tracks.filter { $0.isCloud && !library.isDownloaded($0) }
                        )
                    }
                } label: {
                    Label("Download playlist", systemImage: "arrow.down.circle")
                }
            }

            Button(role: .destructive) {
                library.deletePlaylist(playlist)
            } label: {
                Label("Delete playlist", systemImage: "trash")
            }
        }
    }

    private var newPlaylistTile: some View {
        Button {
            showCreatePlaylist = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }

                Text("New playlist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Start a collection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MotifPressStyle(scale: 0.97, opacity: 0.92))
        .accessibilityLabel("New playlist")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No playlists yet")
                .font(.headline)

            Text("Create a playlist from your library and it will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GlassActionButton(
                title: "New Playlist",
                systemImage: "plus",
                prominent: true
            ) {
                showCreatePlaylist = true
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func play(_ playlist: Playlist) {
        let tracks = library.tracks(in: playlist)
        guard let first = tracks.first else { return }
        player.play(first, queue: tracks)
        showNowPlaying = true
    }
}

struct PlaylistArtwork: View {
    let playlist: Playlist
    let tracks: [Track]
    var card = true

    var body: some View {
        if let cover = playlist.customCoverURL {
            ArtworkView(url: cover, seed: playlist.name, card: card)
                .id(cover)
        } else {
            PlaylistMosaic(tracks: tracks, card: card)
        }
    }
}

struct PlaylistMosaic: View {
    let tracks: [Track]
    var card = true

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            if tracks.isEmpty {
                placeholder
            } else if tracks.count < 4 {
                // A two- or three-song playlist looks best as one strong cover.
                // Splitting a single square into thin strips crops artwork badly.
                let track = tracks.first(where: { $0.artworkURL != nil }) ?? tracks[0]
                ArtworkView(url: track.artworkURL, seed: track.title + track.artist, card: card)
                    .frame(width: width, height: height)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        cell(0, width: width / 2, height: height / 2)
                        cell(1, width: width / 2, height: height / 2)
                    }
                    HStack(spacing: 0) {
                        cell(2, width: width / 2, height: height / 2)
                        cell(3, width: width / 2, height: height / 2)
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.10))
        .overlay {
            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .black.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.20), Color(white: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "music.note.list")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private func cell(_ index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < tracks.count {
            let track = tracks[index]
            if card {
                ArtworkView(
                    url: track.artworkURL,
                    seed: track.title + track.artist,
                    thumbnail: true
                )
                .frame(width: width, height: height)
                .clipped()
            } else {
                ArtworkView(
                    url: track.artworkURL,
                    seed: track.title + track.artist,
                    card: true
                )
                .frame(width: width, height: height)
                .clipped()
            }
        } else {
            Color(white: 0.12)
                .frame(width: width, height: height)
        }
    }
}

struct PlaylistTile: View {
    let playlist: Playlist
    let tracks: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistArtwork(playlist: playlist, tracks: tracks)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(playlist.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(tracks.count == 1 ? "1 song" : "\(tracks.count) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Add Songs sheet needs both the addable catalogue and the current
/// matches, so a body read must not filter or sort the library more than once.
private struct AddSongsResults {
    var available: [Track] = []
    var matches: [Track] = []
}

struct AddSongsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID

    @State private var query = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var results: AddSongsResults?
    @State private var searchTask: Task<Void, Never>?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var playlist: Playlist? {
        library.playlists.first(where: { $0.id == playlistID })
    }

    private var existingIDs: Set<UUID> {
        Set(playlist?.trackIDs ?? [])
    }

    private var visibleResults: AddSongsResults {
        results ?? buildResults(for: query)
    }

    /// One pass over the library per settled query: the available list is
    /// filtered once and the matching subset is ranked once before sorting.
    private func buildResults(for rawQuery: String) -> AddSongsResults {
        let existing = existingIDs
        let available = library.tracks.filter { !existing.contains($0.id) }
        let text = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return AddSongsResults(available: available, matches: available)
        }

        let tokens = LibrarySearch.tokens(in: text)
        let matches = available
            .compactMap { track -> (track: Track, rank: Int)? in
                guard LibrarySearch.matches(tokens, in: [track.title, track.artist, track.album]) else {
                    return nil
                }
                return (track, LibrarySearch.rank(title: track.title, query: text))
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.track.title.localizedCaseInsensitiveCompare(rhs.track.title) == .orderedAscending
            }
            .map { $0.track }

        return AddSongsResults(available: available, matches: matches)
    }

    /// Wait for a short pause in typing, then search once instead of on every
    /// key press.
    private func scheduleSearch(_ rawQuery: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            results = buildResults(for: rawQuery)
        }
    }

    private func refreshResultsNow() {
        searchTask?.cancel()
        results = buildResults(for: query)
    }

    var body: some View {
        let shown = visibleResults

        NavigationStack {
            List {
                if shown.matches.isEmpty {
                    emptyState
                } else {
                    Section {
                        ForEach(shown.matches) { track in
                            Button {
                                toggle(track)
                            } label: {
                                AddSongRow(
                                    track: track,
                                    isSelected: selectedIDs.contains(track.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .listRowBackground(
                                selectedIDs.contains(track.id)
                                    ? Color.primary.opacity(0.06)
                                    : Color.clear
                            )
                            .accessibilityLabel("\(track.title), \(track.artist)")
                            .accessibilityValue(
                                Text(selectedIDs.contains(track.id) ? "Selected" : "Not selected")
                            )
                            .accessibilityHint(
                                selectedIDs.contains(track.id)
                                    ? "Removes from selection"
                                    : "Adds to selection"
                            )
                        }
                    } header: {
                        Text(trimmedQuery.isEmpty ? "Songs" : "Results")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .padding(.leading, 4)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search songs, artists, albums"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addSelected()
                    } label: {
                        Text(addTitle)
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .onAppear {
                if results == nil {
                    results = buildResults(for: query)
                }
            }
            .onChange(of: query) { newValue in
                scheduleSearch(newValue)
            }
            .onChange(of: library.tracks.count) { _ in
                refreshResultsNow()
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private var addTitle: String {
        selectedIDs.isEmpty ? "Add" : "Add \(selectedIDs.count)"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptySymbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text(emptyTitle)
                .font(.headline)

            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptySymbol: String {
        if library.tracks.isEmpty { return "music.note" }
        if visibleResults.available.isEmpty { return "checkmark.circle" }
        return "magnifyingglass"
    }

    private var emptyTitle: String {
        if library.tracks.isEmpty { return "Your library is empty" }
        if visibleResults.available.isEmpty { return "Everything is already here" }
        return "No songs match"
    }

    private var emptyMessage: String {
        if library.tracks.isEmpty {
            return "Import songs first, then come back to build this playlist."
        }
        if visibleResults.available.isEmpty {
            return "Every song in your library is already in this playlist."
        }
        return "Try a shorter title, artist, or album name."
    }

    private func toggle(_ track: Track) {
        if selectedIDs.contains(track.id) {
            selectedIDs.remove(track.id)
        } else {
            selectedIDs.insert(track.id)
        }
        MotifHaptics.play(.selection)
    }

    private func addSelected() {
        let chosen = library.tracks.filter { selectedIDs.contains($0.id) }
        guard !chosen.isEmpty else { return }
        library.add(chosen, to: playlistID)
        MotifHaptics.play(.success)
        dismiss()
    }
}

private struct AddSongRow: View {
    let track: Track
    let isSelected: Bool

    private var subtitle: String {
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if artist.isEmpty { return album.isEmpty ? "Unknown artist" : album }
        if album.isEmpty { return artist }
        return "\(artist) · \(album)"
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                url: track.artworkURL,
                seed: track.title + track.artist,
                thumbnail: true
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.55))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct PlaylistTracksEditor: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let playlistID: UUID

    private var playlist: Playlist? {
        library.playlists.first(where: { $0.id == playlistID })
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return library.tracks(in: playlist)
    }

    var body: some View {
        NavigationStack {
            List {
                if tracks.isEmpty {
                    Text("This playlist is empty.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tracks) { track in
                        HStack(spacing: 12) {
                            ArtworkView(
                                url: track.artworkURL,
                                seed: track.title + track.artist,
                                thumbnail: true
                            )
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onMove { source, destination in
                        library.moveTracks(in: playlistID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets where tracks.indices.contains(index) {
                            library.remove(tracks[index], from: playlistID)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Tracks")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PlaylistEditorView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist?

    @State private var name: String
    @State private var descriptionText: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var removeCover = false
    @State private var coverVariant = 0

    init(playlist: Playlist? = nil) {
        self.playlist = playlist
        _name = State(initialValue: playlist?.name ?? "")
        _descriptionText = State(initialValue: playlist?.description ?? "")
    }

    private var tracks: [Track] {
        guard let playlist else { return [] }
        return library.tracks(in: playlist)
    }

    private var previewPlaylist: Playlist {
        playlist ?? Playlist(name: name.isEmpty ? "Playlist" : name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        coverPreview
                            .frame(width: 156, height: 156)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                Button {
                                    generateCover()
                                } label: {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 36, height: 36)
                                        .nativeGlass(Circle(), interactive: true)
                                }
                                .buttonStyle(MotifPressStyle(scale: 0.9))
                                .offset(x: 8, y: 8)
                                .accessibilityLabel("Generate cover")
                            }
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 10)
                }

                Section("Cover") {
                    Button {
                        generateCover()
                    } label: {
                        Label("Generate artwork", systemImage: "wand.and.stars")
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                    }

                    if hasCover {
                        Button("Remove cover", role: .destructive) {
                            coverData = nil
                            selectedPhoto = nil
                            removeCover = true
                        }
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(playlist == nil ? "New Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto,
                      let data = try? await selectedPhoto.loadTransferable(type: Data.self)
                else { return }
                coverData = data
                removeCover = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var hasCover: Bool {
        coverData != nil || (!removeCover && playlist?.customCoverURL != nil)
    }

    /// Renders the same on-device artwork used by the detail menu, but keeps
    /// it as pending data until the playlist is saved.
    @MainActor
    private func generateCover() {
        let variant = coverVariant
        coverVariant += 1
        let coverName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Playlist"
            : name

        Task {
            let data = await Task.detached(priority: .userInitiated) {
                PlaylistCoverGenerator.jpegData(name: coverName, variant: variant)
            }.value

            guard let data else { return }
            coverData = data
            selectedPhoto = nil
            removeCover = false
            MotifHaptics.play(.light)
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let coverData, let image = UIImage(data: coverData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if !removeCover, let cover = playlist?.customCoverURL {
            ArtworkView(url: cover, seed: previewPlaylist.name, card: true)
        } else {
            PlaylistMosaic(tracks: tracks)
        }
    }

    private func save() {
        if let playlist {
            library.updatePlaylistDetails(
                playlist.id,
                name: name,
                description: descriptionText,
                coverData: coverData,
                removeCover: removeCover
            )
        } else {
            _ = library.createPlaylist(
                named: name,
                description: descriptionText,
                coverData: coverData
            )
        }
        dismiss()
    }
}
