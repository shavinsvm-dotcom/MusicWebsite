import SwiftUI

/// Adds a short, additive wash of the cover's sampled colours on each beat.
/// The pulse is scheduled from the existing beat grid instead of polling the
/// playhead at display rate, so it adds two tiny state changes per beat rather
/// than a second render loop.
struct BeatPulseOverlay: View {
    let grid: BeatGrid?
    let isPlaying: Bool
    let gradient: PlayerGradient

    @EnvironmentObject private var progress: PlaybackProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse: Double = 0

    private var colors: [Color] {
        let sampled = gradient.colors
        guard sampled.count >= 5 else {
            return [Color.white.opacity(0.62), Color.white.opacity(0.30)]
        }
        return [sampled[4], sampled[1]]
    }

    private var sessionID: String {
        "\(grid?.bpm ?? 0)-\(grid?.firstBeat ?? 0)-\(isPlaying)-\(reduceMotion)-\(scenePhase)"
    }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    colors[0].opacity(0.50),
                    Color.white.opacity(0.10),
                    colors[1].opacity(0.28),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 430
            )
            .blendMode(.plusLighter)
            .opacity(pulse)
            .scaleEffect(0.92 + pulse * 0.10)

            RadialGradient(
                colors: [
                    Color.white.opacity(0.16),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .blendMode(.softLight)
            .opacity(pulse * 0.72)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: sessionID) {
            await run()
        }
        .onDisappear {
            pulse = 0
        }
    }

    @MainActor
    private func run() async {
        guard let grid,
              isPlaying,
              scenePhase == .active,
              !reduceMotion,
              grid.confidence >= 0.15,
              grid.bpm.isFinite,
              grid.bpm > 0
        else {
            if pulse != 0 {
                withAnimation(.easeOut(duration: 0.18)) { pulse = 0 }
            }
            return
        }

        var nextBeat = grid.beat(after: progress.elapsed)

        while !Task.isCancelled {
            let delay = nextBeat - progress.elapsed
            if delay > 0 {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(delay * 1_000_000_000)
                    )
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }

            // A seek moves the playhead out from under the scheduled beat.
            // Resync instead of firing a burst of expired pulses.
            if progress.elapsed > nextBeat + max(0.55, grid.beatInterval * 1.5) {
                nextBeat = grid.beat(after: progress.elapsed)
                continue
            }

            withAnimation(.easeOut(duration: 0.07)) {
                pulse = 1
            }

            do {
                try await Task.sleep(nanoseconds: 70_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.30)) {
                pulse = 0
            }

            nextBeat += grid.beatInterval
            if nextBeat <= progress.elapsed {
                nextBeat = grid.beat(after: progress.elapsed)
            }
        }
    }
}
