import SwiftUI

private struct PlaylistIdea: Identifiable {
    let title: String
    let subtitle: String
    let symbol: String
    let prompt: String

    var id: String { title }
}

struct SmartPlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prompt = ""
    @State private var result: SmartPlaylistResult?
    @State private var errorMessage: String?
    @State private var phase: Phase = .compose
    @State private var generationTask: Task<Void, Never>?
    @State private var didSave = false
    @FocusState private var isPromptFocused: Bool

    private enum Phase: Equatable {
        case compose
        case generating
        case result
    }

    private let statusMessages = [
        "Reading your library…",
        "Finding the right songs…",
        "Shaping the order…",
        "Naming the mix…",
    ]

    private let ideas = [
        PlaylistIdea(
            title: "Late-night drive",
            subtitle: "Slow, after-hours songs",
            symbol: "moon.stars",
            prompt: "A late-night drive, slow and moody"
        ),
        PlaylistIdea(
            title: "Sunny Sunday",
            subtitle: "Warm and easy",
            symbol: "sun.max",
            prompt: "A sunny Sunday morning, warm and easy"
        ),
        PlaylistIdea(
            title: "Deep focus",
            subtitle: "Steady, low distraction",
            symbol: "circle.hexagongrid",
            prompt: "Songs for deep focus and flow"
        ),
        PlaylistIdea(
            title: "Workout",
            subtitle: "Fast and loud",
            symbol: "figure.run",
            prompt: "A high-energy workout mix"
        ),
        PlaylistIdea(
            title: "Morning coffee",
            subtitle: "Light and gentle",
            symbol: "cup.and.saucer",
            prompt: "Gentle songs for a slow morning coffee"
        ),
        PlaylistIdea(
            title: "Rainy day",
            subtitle: "Soft and close",
            symbol: "cloud.rain",
            prompt: "Soft songs for a rainy afternoon"
        ),
    ]

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedPrompt.isEmpty && !library.tracks.isEmpty && phase != .generating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch phase {
                    case .compose:
                        composeContent
                    case .generating:
                        generatingContent
                    case .result:
                        if let result {
                            resultContent(result)
                        } else {
                            composeContent
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background {
                backdrop
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .nativeScrollHeader()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .tint(.primary)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .animation(reduceMotion ? nil : MotifMotion.settle, value: phase)
        .onDisappear {
            generationTask?.cancel()
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            AppBackground()

            if phase == .result,
               let artworkURL = result?.tracks.compactMap(\.artworkURL).first {
                DetailBackdrop(artworkURL: artworkURL)
                    .transition(.opacity)
            }
        }
        .animation(MotifMotion.settle, value: phase)
    }

    // MARK: - Compose

    private var composeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("SMART PLAYLIST")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                }
                .foregroundStyle(.secondary)

                Text("What do you\nwant to hear?")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.9)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Describe a mood, a moment, or a kind of song. Lilt chooses the tracks and names it for you.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            promptComposer
            ideaShelf

            if let errorMessage {
                errorCard(errorMessage)
            }

            LiltPrimaryButton(
                title: "Create playlist",
                systemImage: "sparkles",
                height: 52,
                isEnabled: canGenerate
            ) {
                generate()
            }

            footerNote
        }
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "A late-night drive, warm and unhurried…",
                text: $prompt,
                axis: .vertical
            )
            .font(.system(size: 17))
            .foregroundStyle(.primary)
            .lineLimit(3...6)
            .focused($isPromptFocused)
            .textInputAutocapitalization(.sentences)
            .accessibilityLabel("Playlist description")

            HStack(spacing: 8) {
                Text("\(library.tracks.count) songs in your library")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                if !trimmedPrompt.isEmpty {
                    Button {
                        prompt = ""
                        isPromptFocused = true
                        MotifHaptics.play(.selection)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .rowControl(Circle())
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.9))
                    .accessibilityLabel("Clear description")
                }
            }
        }
        .padding(16)
        .nativeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
        }
    }

    private var ideaShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ideas")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ideas) { idea in
                        Button {
                            prompt = idea.prompt
                            isPromptFocused = true
                            MotifHaptics.play(.selection)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: idea.symbol)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .frame(width: 30, height: 30)
                                    .rowControl(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(idea.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(idea.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(width: 126, alignment: .leading)
                            .padding(12)
                            .nativeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(MotifPressStyle(scale: 0.96))
                        .accessibilityLabel("\(idea.title). \(idea.subtitle)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, -20)
        }
    }

    @ViewBuilder
    private var footerNote: some View {
        if library.tracks.isEmpty {
            Label(
                "Add songs to your library before making a smart playlist.",
                systemImage: "music.note"
            )
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        } else {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lock")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.top, 1)

                Text("Only song titles, artists, albums, and play counts are sent. Audio never leaves your iPhone.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't create that playlist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .nativeGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Generating

    private var generatingContent: some View {
        VStack(spacing: 24) {
            GeneratingCover()
                .frame(width: 172, height: 172)
                .padding(.top, 30)

            VStack(spacing: 8) {
                Text("“\(trimmedPrompt)”")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 18)

                statusLabel
                    .padding(.top, 10)

                Text("Usually a few seconds. Free models can take a little longer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                cancelGeneration()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .nativeGlass(Capsule(), interactive: true)
            }
            .buttonStyle(MotifPressStyle(scale: 0.95))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if reduceMotion {
            Text("Choosing your songs…")
                .font(.system(size: 19, weight: .semibold))
                .multilineTextAlignment(.center)
        } else {
            TimelineView(.periodic(from: Date(), by: 1.9)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / 1.9) % statusMessages.count
                Text(statusMessages[index])
                    .font(.system(size: 19, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Result

    private func resultContent(_ result: SmartPlaylistResult) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                PlaylistMosaic(tracks: result.tracks)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 9)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .bold))
                        Text("MADE FOR YOU")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.secondary)

                    Text(result.name)
                        .font(.system(size: 23, weight: .bold))
                        .tracking(-0.5)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !result.description.isEmpty {
                        Text(result.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(summary(for: result.tracks))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(.top, 2)
            }

            LiltPrimaryButton(
                title: didSave ? "Saved" : "Save playlist",
                systemImage: "plus",
                height: 50,
                isEnabled: !didSave
            ) {
                save(result)
            }

            HStack(spacing: 9) {
                secondaryButton("Try again", systemImage: "arrow.clockwise") {
                    generate()
                }

                secondaryButton("Edit prompt", systemImage: "pencil") {
                    resetToCompose()
                }

                Spacer(minLength: 0)
            }

            if let errorMessage {
                errorCard(errorMessage)
            }

            trackPreview(result.tracks)
        }
        .transition(.opacity)
    }

    private func secondaryButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .nativeGlass(Capsule(), interactive: true)
        }
        .buttonStyle(MotifPressStyle(scale: 0.95))
    }

    private func trackPreview(_ tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TRACKS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(tracks.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 6)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: 9) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)

                    ArtworkView(
                        url: track.artworkURL,
                        seed: track.title + track.artist,
                        thumbnail: true
                    )
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(track.durationText)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)

                if index < tracks.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.055))
                        .frame(height: 0.5)
                        .padding(.leading, 63)
                }
            }
        }
    }

    private func summary(for tracks: [Track]) -> String {
        let count = tracks.count
        let songs = count == 1 ? "1 song" : "\(count) songs"
        let total = Int(tracks.reduce(0) { $0 + $1.duration }.rounded())
        guard total > 0 else { return songs }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(songs) · \(hours) hr \(minutes) min"
        }
        return "\(songs) · \(minutes) min"
    }

    // MARK: - Actions

    @MainActor
    private func generate() {
        guard canGenerate else { return }

        generationTask?.cancel()
        isPromptFocused = false
        result = nil
        errorMessage = nil
        MotifHaptics.play(.light)

        withAnimation(reduceMotion ? nil : MotifMotion.settle) {
            phase = .generating
        }

        let prompt = trimmedPrompt
        let tracks = library.tracks
        let playCounts = library.playCounts
        let favoriteIDs = library.favoriteIDs
        let recentIDs = library.recentTrackIDs

        generationTask = Task {
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
                didSave = false
                withAnimation(reduceMotion ? nil : MotifMotion.settle) {
                    phase = .result
                }
                MotifHaptics.play(.success)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                withAnimation(reduceMotion ? nil : MotifMotion.settle) {
                    phase = .compose
                }
                MotifHaptics.play(.warning)
            }
        }
    }

    @MainActor
    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        MotifHaptics.play(.light)
        withAnimation(reduceMotion ? nil : MotifMotion.settle) {
            phase = .compose
        }
    }

    @MainActor
    private func resetToCompose() {
        result = nil
        errorMessage = nil
        didSave = false
        withAnimation(reduceMotion ? nil : MotifMotion.settle) {
            phase = .compose
        }
        isPromptFocused = true
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

private struct GeneratingCover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sweep: CGFloat = -1.2
    @State private var breathe = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.26), Color(white: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RadialGradient(
                colors: [Color.white.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 190
            )

            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .scaleEffect(breathe ? 1.08 : 0.92)
                .opacity(breathe ? 1 : 0.58)

            if !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.20), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 1.3)
                    .rotationEffect(.degrees(18))
                    .offset(x: proxy.size.width * sweep)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.24), radius: 20, y: 12)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                sweep = 1.2
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}
