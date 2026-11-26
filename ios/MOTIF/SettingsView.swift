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
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("motif.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @ObservedObject private var equalizer = Equalizer.shared

    @State private var showEqualizer = false
    @State private var storageUsage: (library: Int64, downloads: Int64)?
    @State private var confirmRemoveDownloads = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var automix: Binding<Bool> {
        Binding(
            get: { player.automixEnabled },
            set: { player.setAutomix($0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Follow the system, or keep Lilt light or dark.")
                }

                Section {
                    Toggle(isOn: automix) {
                        Label("Automix", systemImage: "waveform.path.ecg")
                    }
                    .tint(.primary)

                    sleepTimerRow

                    crossfadeRow

                    qualityRow

                    Button {
                        showEqualizer = true
                    } label: {
                        SettingsValueRow(
                            title: "Equalizer",
                            systemImage: "slider.vertical.3",
                            value: equalizer.isEnabled ? "On" : "Off",
                            indicator: "chevron.right"
                        )
                    }
                    .accessibilityLabel("Equalizer")
                    .accessibilityValue(equalizer.isEnabled ? "On" : "Off")
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Automix blends tracks that flow together. Crossfade overlaps the end of one song with the next. Streaming quality caps network bandwidth and sets how far ahead audio buffers; downloaded songs always play at their original quality.")
                }

                Section {
                    LabeledContent("Imported Music") {
                        Text(bytesText(storageUsage?.library))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Downloads") {
                        Text(bytesText(storageUsage?.downloads))
                            .foregroundStyle(.secondary)
                    }
                    Button("Remove All Downloads", role: .destructive) {
                        confirmRemoveDownloads = true
                    }
                    .disabled((storageUsage?.downloads ?? 0) == 0)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Downloads are offline copies of cloud songs. Removing them frees space; the songs stay in your library and stream again when played.")
                }

                Section {
                    LabeledContent("Version") {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Lilt is a quiet player for your own library. Artwork is the only colour.")
                }
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .nativeScrollHeader()
            .task {
                storageUsage = await library.storageUsage()
            }
            .confirmationDialog(
                "Remove all downloads?",
                isPresented: $confirmRemoveDownloads,
                titleVisibility: .visible
            ) {
                Button("Remove Downloads", role: .destructive) {
                    library.removeAllDownloads()
                    Task { storageUsage = await library.storageUsage() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The songs stay in your library and will stream from the cloud.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView()
            }
        }
        .tint(.primary)
        .preferredColorScheme(AppAppearance.resolved(appearanceRaw))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var sleepTimerRow: some View {
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
            SettingsValueRow(
                title: "Sleep Timer",
                systemImage: "moon.zzz",
                value: player.sleepTimerRemainingText ?? "Off"
            )
        }
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(player.sleepTimerRemainingText ?? "Off")
    }

    private func bytesText(_ bytes: Int64?) -> String {
        guard let bytes else { return "Calculating…" }
        guard bytes > 0 else { return "None" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var qualityRow: some View {
        Menu {
            ForEach(PlaybackQuality.allCases) { option in
                Button {
                    player.setPlaybackQuality(option)
                } label: {
                    if option == player.playbackQuality {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            SettingsValueRow(
                title: "Streaming Quality",
                systemImage: "dot.radiowaves.left.and.right",
                value: player.playbackQuality.title
            )
        }
        .accessibilityLabel("Streaming Quality")
        .accessibilityValue(player.playbackQuality.title)
    }

    private var crossfadeRow: some View {
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
            SettingsValueRow(
                title: "Crossfade",
                systemImage: "arrow.left.arrow.right",
                value: player.crossfadeDuration > 0
                    ? "\(Int(player.crossfadeDuration))s"
                    : "Off"
            )
        }
        .accessibilityLabel("Crossfade")
        .accessibilityValue(
            player.crossfadeDuration > 0
                ? "\(Int(player.crossfadeDuration)) seconds"
                : "Off"
        )
    }
}

private struct SettingsValueRow: View {
    let title: String
    let systemImage: String
    let value: String
    var indicator: String? = "chevron.up.chevron.down"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(.primary)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let indicator {
                Image(systemName: indicator)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
