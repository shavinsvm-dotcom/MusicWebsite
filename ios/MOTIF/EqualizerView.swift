import SwiftUI

struct EqualizerView: View {
    @ObservedObject private var equalizer = Equalizer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Equalizer",
                        isOn: Binding(
                            get: { equalizer.isEnabled },
                            set: { equalizer.setEnabled($0) }
                        )
                    )

                    band(
                        "Bass",
                        value: equalizer.bass,
                        onChange: equalizer.setBass
                    )

                    band(
                        "Mids",
                        value: equalizer.mid,
                        onChange: equalizer.setMid
                    )

                    band(
                        "Treble",
                        value: equalizer.treble,
                        onChange: equalizer.setTreble
                    )
                } footer: {
                    Text("Adjust the low, middle, and high frequencies during playback.")
                }

                Section {
                    Button("Reset") {
                        equalizer.reset()
                    }
                    .disabled(!equalizer.isEnabled)
                }
            }
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func band(
        _ title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)

                Spacer()

                Text(value == 0 ? "0 dB" : String(format: "%+.1f dB", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: onChange
                ),
                in: -12...12,
                step: 0.5
            )
            .disabled(!equalizer.isEnabled)
        }
        .padding(.vertical, 2)
    }
}
