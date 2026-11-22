import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func resolved(_ rawValue: String) -> ColorScheme? {
        (AppAppearance(rawValue: rawValue) ?? .system).colorScheme
    }
}

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("motif.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @ObservedObject private var equalizer = Equalizer.shared

    @State private var showEqualizer = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader(
                    title: "Settings",
                    subtitle: "Appearance, playback and about"
                ) {
                    GlassIconButton(
                        systemImage: "xmark",
                        label: "Close settings",
                        size: 36
                    ) {
                        dismiss()
                    }
                }

                appearanceSection
                playbackSection
                aboutSection
            }
            .screenEntrance()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .sheet(isPresented: $showEqualizer) {
            EqualizerView()
        }
        // Apply the choice inside the sheet too, so the change is visible
        // before the sheet is dismissed.
        .preferredColorScheme(AppAppearance.resolved(appearanceRaw))
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Appearance")

            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            appearanceRaw = option.rawValue
                        }
                    } label: {
                        appearanceChip(option)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.95))
                    .accessibilityAddTraits(
                        appearanceRaw == option.rawValue ? .isSelected : []
                    )
                }
            }

            Text("Follow the system, or keep Lilt light or dark.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func appearanceChip(_ option: AppAppearance) -> some View {
        let isSelected = appearanceRaw == option.rawValue
        let label = Text(option.title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)

        if isSelected {
            label
                .foregroundStyle(Color(uiColor: .systemBackground))
                .background(Color.primary, in: Capsule())
        } else {
            label
                .foregroundStyle(.primary)
                .nativeGlass(Capsule(), interactive: true)
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Playback")

            HStack(spacing: 12) {
                Label("Automix", systemImage: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .regular))

                Spacer(minLength: 8)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { player.automixEnabled },
                        set: { player.setAutomix($0) }
                    )
                )
                .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .nativeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Menu {
                if player.isSleepTimerActive {
                    Button(role: .destructive) {
                        player.cancelSleepTimer()
                    } label: {
                        Label("Cancel Sleep Timer", systemImage: "xmark.circle")
                    }

                    Divider()
                }

                ForEach([5, 10, 15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        player.setSleepTimer(minutes: minutes)
                    }
                }
            } label: {
                playbackRow(
                    title: "Sleep Timer",
                    systemImage: "moon.zzz",
                    value: player.sleepTimerRemainingText ?? "Off"
                )
            }

            Menu {
                ForEach([0, 2, 4, 6, 8, 12], id: \.self) { seconds in
                    Button {
                        player.setCrossfade(Double(seconds))
                    } label: {
                        if abs(player.crossfadeDuration - Double(seconds)) < 0.01 {
                            Label(
                                seconds == 0 ? "Off" : "\(seconds) seconds",
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(seconds == 0 ? "Off" : "\(seconds) seconds")
                        }
                    }
                }
            } label: {
                playbackRow(
                    title: "Crossfade",
                    systemImage: "arrow.left.arrow.right",
                    value: player.crossfadeDuration > 0
                        ? "\(Int(player.crossfadeDuration))s"
                        : "Off"
                )
            }

            Button {
                showEqualizer = true
            } label: {
                playbackRow(
                    title: "Equalizer",
                    systemImage: "slider.vertical.3",
                    value: equalizer.isEnabled ? "On" : "Off"
                )
            }
        }
    }

    private func playbackRow(
        title: String,
        systemImage: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .regular))

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "About")

            HStack(spacing: 12) {
                Label("Version", systemImage: "info.circle")
                    .font(.system(size: 15, weight: .regular))

                Spacer(minLength: 8)

                Text(appVersion)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .nativeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Lilt plays your library and Apple Music previews. Artwork is the only colour.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
