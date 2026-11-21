import SwiftUI

struct HeroScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A full-bleed artwork header for playlist and album pages. The cover fills
/// the top of the page, drifts slightly slower than the scroll, and dissolves
/// into the page's cover-derived backdrop instead of ending in a hard edge.
struct EditorialHeroHeader<Cover: View, Actions: View>: View {
    let title: String
    let eyebrow: String?
    let subtitle: String
    let description: String?
    let coordinateSpace: String
    let height: CGFloat

    private let cover: Cover
    private let actions: Actions

    init(
        title: String,
        eyebrow: String? = nil,
        subtitle: String,
        description: String? = nil,
        coordinateSpace: String,
        height: CGFloat,
        @ViewBuilder cover: () -> Cover,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.description = description
        self.coordinateSpace = coordinateSpace
        self.height = height
        self.cover = cover()
        self.actions = actions()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                let minY = proxy.frame(in: .named(coordinateSpace)).minY
                let pull = max(0, minY)
                let lift = min(0, minY)

                cover
                    .frame(width: proxy.size.width, height: height + 120)
                    .scaleEffect(1 + pull / max(1, height) * 0.30, anchor: .bottom)
                    .offset(y: lift * 0.30 - 60)
                    .clipped()
            }
            .frame(height: height)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.70),
                        .init(color: .black.opacity(0.66), location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // A light top scrim keeps the status bar and navigation chrome
            // readable over pale covers without touching the middle of the art.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.48), location: 0),
                    .init(color: .black.opacity(0.20), location: 0.10),
                    .init(color: .clear, location: 0.26)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Darkens only the lower half so white type and glass controls
            // stay readable over bright artwork, then fades away with the
            // cover so the playlist rows keep the clean backdrop.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.26),
                    .init(color: .black.opacity(0.12), location: 0.42),
                    .init(color: .black.opacity(0.44), location: 0.60),
                    .init(color: .black.opacity(0.68), location: 0.78),
                    .init(color: .black.opacity(0.72), location: 0.90),
                    .init(color: .black.opacity(0.42), location: 0.96),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 7) {
                if let eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.80))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                }

                Text(title)
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-1.0)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 2)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)

                if let description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.42), radius: 6, y: 1)
                }

                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.42), radius: 5, y: 1)

                actions
                    .padding(.top, 5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HeroScrollOffsetKey.self,
                    value: proxy.frame(in: .named(coordinateSpace)).minY
                )
            }
        }
    }
}

/// The small cover and title that take over once the hero scrolls away.
struct CompactHeroTitle<Thumbnail: View>: View {
    let title: String
    let visible: Bool

    private let thumbnail: Thumbnail

    init(
        title: String,
        visible: Bool,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) {
        self.title = title
        self.visible = visible
        self.thumbnail = thumbnail()
    }

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(title)
                .font(.headline)
                .lineLimit(1)
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(!visible)
        .animation(.easeOut(duration: 0.16), value: visible)
    }
}

/// A material fade that appears under the navigation bar only after the hero
/// has scrolled away, keeping the back button and compact title readable.
struct DetailNavScrim: View {
    let visible: Bool

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.92), location: 0.55),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 132)
            .ignoresSafeArea(edges: .top)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.20), value: visible)
            .allowsHitTesting(false)
    }
}
