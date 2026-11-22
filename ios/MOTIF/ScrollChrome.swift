import SwiftUI

/// A horizontal shelf with soft, blurred-looking edges. The mask is cheap and
/// keeps the first and last card from looking sliced off at the screen edge.
extension View {
    func carouselEdgeBlur(_ width: CGFloat = 18) -> some View {
        mask {
            GeometryReader { proxy in
                let fade = min(width, proxy.size.width / 2)

                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: fade)

                    Rectangle().fill(.black)

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: fade)
                }
            }
        }
    }
}

struct CarouselScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
        }
        .carouselEdgeBlur()
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
        .onAppear { active = true }
        .onDisappear { active = false }
        .onChange(of: isPlaying) { playing in
            active = playing
        }
        .accessibilityHidden(true)
    }
}
