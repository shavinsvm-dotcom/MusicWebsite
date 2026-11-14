import SwiftUI
import UIKit

struct AirPodsConnectOverlay: View {
    @ObservedObject var monitor: AudioRouteMonitor
    var topPadding: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .top) {
            if let connection = monitor.connection {
                Button {
                    monitor.dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            if !reduceMotion {
                                Circle()
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1.5)
                                    .frame(width: 38, height: 38)
                                    .scaleEffect(pulse ? 1.55 : 0.88)
                                    .opacity(pulse ? 0 : 0.8)
                                    .animation(
                                        .easeOut(duration: 1.35)
                                            .repeatForever(autoreverses: false),
                                        value: pulse
                                    )
                            }

                            Image(systemName: connection.symbolName)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.12), in: Circle())
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(connection.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.vertical, 8)
                    .nativeGlass(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(connection.name) connected")
                .padding(.horizontal, 16)
                .padding(.top, topPadding)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    )
                )
                .onAppear {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    guard !reduceMotion else { return }
                    pulse = false
                    DispatchQueue.main.async {
                        pulse = true
                    }
                }
                .id(connection.id)
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.18)
                : .spring(response: 0.38, dampingFraction: 0.82),
            value: monitor.connection?.id
        )
    }
}
