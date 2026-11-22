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

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
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
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(
                    title: "Settings",
                    subtitle: "Make Lilt yours"
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
                footer
            }
            .screenEntrance()
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .tint(.primary)
        .sheet(isPresented: $showEqualizer) {
            EqualizerView()
        }
        // Apply the choice inside the sheet too, so the change is visible
        // before the sheet is dismissed.
        .preferredColorScheme(AppAppearance.resolved(appearanceRaw))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Appearance")

            HStack(spacing: 4) {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            appearanceRaw = option.rawValue
                        }
                    } label: {
                        appearanceOption(option)
                    }
                    .buttonStyle(MotifPressStyle(scale: 0.98))
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(
                        appearanceRaw == option.rawValue ? .isSelected : []
                    )
                }
            }
            .padding(4)
            .nativeGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("Follow the system, or keep Lilt light or dark.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func appearanceOption(_ option: AppAppearance) -> some View {
        let isSelected = appearanceRaw == option.rawValue

        VStack(spacing: 5) {
            Image(systemName: option.icon)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)

            Text(option.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(
            isSelected ? Color(uiColor: .systemBackground) : Color.primary
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Playback")

            SettingsGroup {
                automixRow

                SettingsDivider()

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
                    SettingsRow(
                        title: "Sleep Timer",
                        systemImage: "moon.zzz",
                        detail: "Stop playback after a while",
                        value: player.sleepTimerRemainingText ?? "Off",
                        trailingSymbol: "chevron.up.chevron.down"
                    )
                }
                .buttonStyle(SettingsRowButtonStyle())

                SettingsDivider()

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
                    SettingsRow(
                        title: "Crossfade",
                        systemImage: "arrow.left.arrow.right",
                        detail: "Blend one track into the next",
                        value: player.crossfadeDuration > 0
                            ? "\(Int(player.crossfadeDuration))s"
                            : "Off",
                        trailingSymbol: "chevron.up.chevron.down"
                    )
                }
                .buttonStyle(SettingsRowButtonStyle())

                SettingsDivider()

                Button {
                    showEqualizer = true
                } label: {
                    SettingsRow(
                        title: "Equalizer",
                        systemImage: "slider.vertical.3",
                        detail: "Shape bass, mids and treble",
                        value: equalizer.isEnabled ? "On" : "Off"
                    )
                }
                .buttonStyle(SettingsRowButtonStyle())
            }
        }
    }

    private var automixRow: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: "waveform.path.ecg")

            VStack(alignment: .leading, spacing: 2) {
                Text("Automix")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text("Blend tracks that flow together")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle(
                "Automix",
                isOn: Binding(
                    get: { player.automixEnabled },
                    set: { player.setAutomix($0) }
                )
            )
            .labelsHidden()
            .tint(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "About")

            SettingsGroup {
                SettingsRow(
                    title: "Version",
                    systemImage: "info.circle",
                    value: appVersion,
                    trailingSymbol: nil
                )
            }

            Text("Lilt plays your library and Apple Music previews. Artwork is the only colour.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            LiltWordmark(height: 13)
                .opacity(0.40)

            Text("BETA")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

private struct SettingsGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .nativeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SettingsRow: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var value: String? = nil
    var trailingSymbol: String? = "chevron.right"

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .accessibilityHidden(true)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.primary.opacity(0.06)
                    : Color.clear
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
