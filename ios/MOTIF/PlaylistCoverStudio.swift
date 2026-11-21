import SwiftUI
import UIKit

/// A visual picker for generated playlist artwork. Six looks are rendered on
/// demand, each labelled with its pattern and palette, and a tap applies the
/// cover immediately without leaving the sheet.
struct PlaylistCoverStudio: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist

    @State private var shuffleSeed = Int.random(in: 0..<100_000)
    @State private var options: [StudioOption] = []
    @State private var isLoading = true
    @State private var selectedVariant: Int?
    @State private var applyingVariant: Int?

    private struct StudioOption: Identifiable {
        let id: Int
        let variant: Int
        let pattern: String
        let palette: String
        let image: UIImage
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
        count: 3
    )

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    HStack(alignment: .center, spacing: 12) {
                        shuffleButton

                        Spacer(minLength: 8)

                        Text("Tap a cover to apply")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    grid
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: shuffleSeed) {
            await loadOptions()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Cover Studio")
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.6)

                Text("Generated looks for \(playlist.name).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .nativeGlass(Circle(), interactive: true)
            }
            .buttonStyle(MotifPressStyle(scale: 0.9))
            .accessibilityLabel("Close cover studio")
        }
    }

    private var shuffleButton: some View {
        Button {
            shuffleAll()
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .semibold))
                }

                Text("Shuffle all")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .nativeGlass(Capsule(), interactive: true)
        }
        .buttonStyle(MotifPressStyle(scale: 0.96))
        .disabled(isLoading)
        .accessibilityHint("Generates six new covers")
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            if options.isEmpty && isLoading {
                ForEach(0..<6, id: \.self) { _ in
                    loadingTile
                }
            } else {
                ForEach(options) { option in
                    tile(option)
                }
            }
        }
        .opacity(isLoading && !options.isEmpty ? 0.55 : 1)
        .allowsHitTesting(!isLoading)
        .animation(.easeOut(duration: 0.18), value: isLoading)
    }

    private func tile(_ option: StudioOption) -> some View {
        let isSelected = selectedVariant == option.variant
        let isApplying = applyingVariant == option.variant

        return Button {
            apply(option)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(uiImage: option.image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.36), radius: 3, y: 1)
                                .padding(7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .overlay {
                        if isApplying {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.38))

                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isSelected)

                Text(option.pattern)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(option.palette)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MotifPressStyle(scale: 0.96, opacity: 0.96))
        .accessibilityLabel("\(option.pattern), \(option.palette) cover")
        .accessibilityHint("Applies this cover to the playlist")
    }

    private var loadingTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 52, height: 8)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .frame(width: 38, height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadOptions() async {
        isLoading = true
        let name = playlist.name
        let variants = (0..<6).map { shuffleSeed + $0 }

        let payloads = await Task.detached(priority: .userInitiated) {
            variants.compactMap {
                PlaylistCoverGenerator.preview(name: name, variant: $0, side: 420)
            }
        }.value

        guard !Task.isCancelled else { return }

        options = payloads.compactMap { payload in
            guard let image = UIImage(data: payload.data) else { return nil }
            return StudioOption(
                id: payload.variant,
                variant: payload.variant,
                pattern: payload.pattern,
                palette: payload.palette,
                image: image
            )
        }
        isLoading = false
    }

    @MainActor
    private func shuffleAll() {
        guard !isLoading else { return }
        shuffleSeed += 6
        selectedVariant = nil
        MotifHaptics.play(.light)
    }

    @MainActor
    private func apply(_ option: StudioOption) {
        guard applyingVariant == nil else { return }
        applyingVariant = option.variant
        let name = playlist.name
        let variant = option.variant

        Task {
            let data = await Task.detached(priority: .userInitiated) {
                PlaylistCoverGenerator.jpegData(name: name, variant: variant)
            }.value

            guard let data,
                  library.applyGeneratedPlaylistCover(playlist.id, data: data)
            else {
                applyingVariant = nil
                return
            }

            selectedVariant = variant
            applyingVariant = nil
            MotifHaptics.play(.success)
        }
    }
}
