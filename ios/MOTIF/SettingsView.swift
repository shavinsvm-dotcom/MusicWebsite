import SwiftUI
import UIKit
import WidgetKit

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
    @AppStorage("motif.animatedCovers") private var animatedCovers = false
    @AppStorage("motif.offlineAnimatedCovers") private var offlineAnimatedCovers = true
    @ObservedObject private var equalizer = Equalizer.shared
    @ObservedObject private var motionArtwork = MotionArtworkStore.shared

    @State private var showEqualizer = false
    @State private var storageUsage: (library: Int64, downloads: Int64)?
    @State private var confirmRemoveDownloads = false
    @State private var confirmClearSavedCovers = false
    @State private var widgetRefreshNote: String?
    @State private var appGroupCopied = false

    private var widgetGroupReady: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedNowPlaying.appGroup
        ) != nil
    }

    private var appBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.example.motif"
    }

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

    private var animatedCoverScanLabel: String {
        if motionArtwork.isScanning {
            return "\(motionArtwork.scanDone)/\(motionArtwork.scanTotal)"
        }
        if let found = motionArtwork.lastScanFound {
            return found == 1 ? "1 cover" : "\(found) covers"
        }
        return "Scan"
    }

    private var savedCoversLabel: String {
        guard motionArtwork.savedCoverBytes > 0 else { return "None" }
        let count = motionArtwork.savedCoverCount == 1
            ? "1 cover"
            : "\(motionArtwork.savedCoverCount) covers"
        return "\(count) · \(bytesText(motionArtwork.savedCoverBytes))"
    }

    private func findAnimatedCovers() {
        Task {
            let found = await motionArtwork.scan(tracks: library.tracks)
            if found > 0 {
                animatedCovers = true
            }
        }
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
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.92),
                                            Color.black.opacity(0.70)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                                }

                            Image(systemName: "waveform")
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 54, height: 54)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Lilt")
                                .font(.system(size: 22, weight: .bold))
                                .tracking(-0.4)
                            Text("A quiet player for your library")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)

                Section {
                    Picker("Appearance", selection: appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                } footer: {
                    Text("Follow the system, or keep Lilt light or dark.")
                }

                Section {
                    Toggle(isOn: $animatedCovers) {
                        Label("Animated Covers", systemImage: "sparkles")
                    }
                    .tint(.primary)
                    .accessibilityHint("Plays official Apple Music motion artwork as the main cover")

                    Toggle(isOn: $offlineAnimatedCovers) {
                        Label("Download Covers on Wi-Fi", systemImage: "wifi")
                    }
                    .tint(.primary)
                    .accessibilityHint("Saves played motion artwork on Wi-Fi only for offline use")

                    Button(action: findAnimatedCovers) {
                        SettingsValueRow(
                            title: "Find Animated Covers",
                            systemImage: "wand.and.stars",
                            value: animatedCoverScanLabel,
                            indicator: "arrow.clockwise"
                        )
                    }
                    .disabled(motionArtwork.isScanning)
                    .accessibilityLabel("Find animated covers")
                    .accessibilityValue(animatedCoverScanLabel)

                    Button(role: .destructive) {
                        confirmClearSavedCovers = true
                    } label: {
                        SettingsValueRow(
                            title: "Saved Covers",
                            systemImage: "internaldrive",
                            value: savedCoversLabel,
                            indicator: motionArtwork.savedCoverBytes > 0 ? "trash" : nil
                        )
                    }
                    .disabled(motionArtwork.savedCoverBytes == 0)
                    .accessibilityLabel("Saved animated covers")
                    .accessibilityValue(savedCoversLabel)
                    .accessibilityHint("Clears the saved cover cache")
                    .confirmationDialog(
                        "Clear saved covers?",
                        isPresented: $confirmClearSavedCovers,
                        titleVisibility: .visible
                    ) {
                        Button("Clear Saved Covers", role: .destructive) {
                            motionArtwork.clearSavedCovers()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("They’ll download again over Wi-Fi when you play those albums.")
                    }
                } header: {
                    Label("Artwork", systemImage: "sparkles")
                } footer: {
                    Text("Official Apple Music motion artwork, played as the main cover and offered to the Lock Screen — tap the artwork there to expand it. Saved covers stay private, never appear in Files, and download only on Wi-Fi up to 300 MB. Availability varies by album; Lilt isn’t affiliated with Apple.")
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
                    Label("Playback", systemImage: "play.circle")
                } footer: {
                    Text("Automix blends tracks that flow together. Crossfade overlaps song endings. Streaming quality caps bandwidth and buffer depth; downloads always play at original quality.")
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
                    Label("Storage", systemImage: "internaldrive")
                } footer: {
                    Text("Downloads are offline copies of cloud songs. Removing them frees space; the songs stay in your library and stream again when played.")
                }

                Section {
                    LabeledContent("Status") {
                        Text(widgetGroupReady ? "Ready" : "No App Group")
                            .foregroundStyle(widgetGroupReady ? .secondary : .primary)
                    }

                    LabeledContent("App Group") {
                        Text(SharedNowPlaying.appGroup)
                            .font(.system(.footnote, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }

                    LabeledContent("App Identifier") {
                        Text(appBundleIdentifier)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }

                    Button {
                        UIPasteboard.general.string = SharedNowPlaying.appGroup
                        appGroupCopied = true
                    } label: {
                        Label(
                            appGroupCopied ? "App Group Copied" : "Copy App Group",
                            systemImage: appGroupCopied ? "checkmark" : "doc.on.doc"
                        )
                    }

                    Button {
                        WidgetCenter.shared.reloadAllTimelines()
                        widgetRefreshNote = "Requested"
                    } label: {
                        SettingsValueRow(
                            title: "Refresh Widgets",
                            systemImage: "rectangle.3.group",
                            value: widgetGroupReady
                                ? (widgetRefreshNote ?? "Ready")
                                : "No App Group",
                            indicator: "arrow.clockwise"
                        )
                    }
                    .disabled(!widgetGroupReady)
                    .accessibilityLabel("Refresh widgets")
                    .accessibilityValue(widgetGroupReady ? "Ready" : "App Group unavailable")
                } header: {
                    Label("Widgets", systemImage: "rectangle.3.group")
                } footer: {
                    if widgetGroupReady {
                        Text("Widgets read this private container. If a widget looks stale, play a song in Lilt and it refreshes with the current track.")
                    } else {
                        Text("Lilt is signed without this App Group, so the widgets have nothing to read. App Groups need a paid Apple Developer account: register \(SharedNowPlaying.appGroup) under Identifiers › App Groups, enable App Groups for both \(appBundleIdentifier) and \(appBundleIdentifier).widgets, then sign the app and the widget extension with that group in their entitlements.")
                    }
                }

                Section {
                    LabeledContent("Version") {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
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
                motionArtwork.refreshSavedCoverUsage()
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
