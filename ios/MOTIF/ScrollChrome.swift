import SwiftUI

/// A horizontal shelf that lets card shadows and glass edges breathe past the
/// scroll view. On iOS 17+ it also snaps to card boundaries, so a shelf never
/// comes to rest half-clipped at the screen edge.
struct CarouselScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                ScrollView(.horizontal, showsIndicators: false) {
                    content
                        .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    content
                }
            }
        }
        .padding(.vertical, 6)
    }
}

extension View {
    /// Cards ease in and out of the shelf instead of being cut off by the
    /// scroll view's edge. Motion is disabled when Reduce Motion is on.
    func carouselItemTransition() -> some View {
        modifier(CarouselItemTransition())
    }
}

private struct CarouselItemTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), !reduceMotion {
            content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
                view
                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
                    .opacity(phase.isIdentity ? 1 : 0.78)
            }
        } else {
            content
        }
    }
}

/// A compact four-bar indicator for the row that is currently playing.
/// Core Animation handles the motion, so a paused row is completely still
/// and the bars stay smooth without a timer or a timeline.
struct PlayingWaveform: View {
    var isPlaying: Bool = true
    var color: Color = .primary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    private let heights: [CGFloat] = [0.55, 1.0, 0.72, 0.9]

    private var animating: Bool { isPlaying && !reduceMotion }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(color)
                    .frame(width: 2, height: 11 * height)
                    .scaleEffect(
                        y: active && animating ? 1 : (isPlaying ? 0.72 : 0.45),
                        anchor: .bottom
                    )
                    .animation(
                        animating
                            ? .easeInOut(duration: 0.46)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.07)
                            : .easeOut(duration: 0.20),
                        value: active
                    )
            }
        }
        .frame(width: 14, height: 12)
        .onAppear { active = isPlaying }
        .onDisappear { active = false }
        .onChange(of: isPlaying) { playing in
            active = playing
        }
        .accessibilityHidden(true)
    }
}
