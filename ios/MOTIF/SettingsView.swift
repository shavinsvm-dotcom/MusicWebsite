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
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("motif.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @ObservedObject private var equalizer = Equalizer.shared

    @State private var showEqualizer = false
    @State private var showDownloads = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var downloadedCount: Int {
        library.tracks.filter { library.isDownloaded($0) }.count
    }

    private var cloudCount: Int {
        library.tracks.filter(\.isCloud).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Follow the system, or keep Lilt light or dark.")
                }

                Section("Playback") {
                    Toggle(
                        isOn: Binding(
                            get: { player.automixEnabled },
                            set: { player.setAutomix($0) }
                        )
                    ) {
                        Label("Automix", systemImage: "waveform.path.ecg")
                    }

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
                        LabeledContent {
                            Text(player.sleepTimerRemainingText ?? "Off")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Sleep Timer", systemImage: "moon.zzz")
                        }
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
                        LabeledContent {
                            Text(player.crossfadeDuration > 0
                                ? "\(Int(player.crossfadeDuration))s"
                                : "Off")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Crossfade", systemImage: "arrow.left.arrow.right")
                        }
                    }

                    Button {
                        showEqualizer = true
                    } label: {
                        LabeledContent {
                            Text(equalizer.isEnabled ? "On" : "Off")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Equalizer", systemImage: "slider.vertical.3")
                        }
                    }
                }

                Section("Library") {
                    Button {
                        Task { await library.refreshCloud() }
                    } label: {
                        LabeledContent {
                            Text("\(cloudCount)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Sync cloud library", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(library.isRefreshingCloud)

                    Button {
                        showDownloads = true
                    } label: {
                        LabeledContent {
                            Text("\(downloadedCount)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Downloads", systemImage: "arrow.down.circle")
                        }
                    }

                    Button {
                        Task { await library.uploadAllLocal() }
                    } label: {
                        Label("Upload local songs", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(!library.uploadingIDs.isEmpty)

                    Button {
                        Task { await library.repairMissingCovers() }
                    } label: {
                        Label("Find missing covers", systemImage: "photo.badge.magnifyingglass")
                    }
                    .disabled(!library.enrichingIDs.isEmpty)
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("Lilt plays your library and Apple Music previews. Artwork is the only colour.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView()
            }
            .sheet(isPresented: $showDownloads) {
                DownloadManagerView()
                    .environmentObject(library)
            }
        }
    }
}
