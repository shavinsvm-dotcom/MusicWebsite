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
struct PlayingWaveform: View {
    var color: Color = .primary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    private let heights: [CGFloat] = [0.55, 1.0, 0.72, 0.9]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(color)
                    .frame(width: 2, height: 11 * height)
                    .scaleEffect(y: active ? 1 : 0.35, anchor: .bottom)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.46)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.07),
                        value: active
                    )
            }
        }
        .frame(width: 14, height: 12)
        .onAppear { active = true }
        .onDisappear { active = false }
        .accessibilityHidden(true)
    }
}
