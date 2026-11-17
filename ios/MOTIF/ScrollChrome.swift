import SwiftUI
import UIKit

/// A small, scroll-visible page header used on pages that hide the native
/// navigation bar. It mirrors the compact state of Library's large title.
struct CompactPageHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            LiltWordmark(height: 14)

            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 1, height: 14)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lilt, \(title)")
        .allowsHitTesting(false)
    }
}

/// A section title that remains visible while its section is on screen.
struct PinnedSectionHeader<Trailing: View>: View {
    let title: String
    let count: Int?
    let horizontalPadding: CGFloat
    let trailing: Trailing

    init(
        title: String,
        count: Int? = nil,
        horizontalPadding: CGFloat = 20,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.count = count
        self.horizontalPadding = horizontalPadding
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(.primary)

            if let count {
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}

struct HeaderBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

extension View {
    func trackHeaderBottom(in coordinateSpace: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HeaderBottomPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpace)).maxY
                )
            }
        }
    }

    /// A restrained card reveal while scrolling. It is intentionally
    /// transform-only so pinned headers and large playlists stay smooth.
    @ViewBuilder
    func liltCardScrollTransition() -> some View {
        if #available(iOS 17.0, *) {
            scrollTransition(.interactive, axis: .vertical) { effect, phase in
                effect
                    .scaleEffect(phase.isIdentity ? 1 : 0.965)
                    .opacity(phase.isIdentity ? 1 : 0.78)
            }
        } else {
            self
        }
    }

    func liltEntrance(index: Int) -> some View {
        modifier(StaggeredAppearance(index: index))
    }
}

private struct StaggeredAppearance: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 9)
            .onAppear {
                guard !appeared else { return }

                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(
                        .spring(response: 0.48, dampingFraction: 0.86)
                            .delay(Double(index) * 0.035)
                    ) {
                        appeared = true
                    }
                }
            }
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
