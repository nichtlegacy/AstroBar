import AstroBarCore
import SwiftUI

/// Microphone section: level, side tone, noise gate, mic EQ.
struct MicrophoneView: View {
    let monitor: A50Monitor

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Microphone", systemImage: "mic.fill")

                LabeledSlider(
                    title: "Mic level",
                    range: 0 ... 100,
                    step: 1,
                    value: sliderBinding(.mic),
                    valueLabel: { "\(Int($0.rounded()))%" },
                    onCommit: { _ in monitor.commitSlider(.mic) })

                LabeledSlider(
                    title: "Side tone",
                    range: 0 ... 100,
                    step: 1,
                    value: sliderBinding(.sideTone),
                    valueLabel: { "\(Int($0.rounded()))%" },
                    onCommit: { _ in monitor.commitSlider(.sideTone) })
                    .help("How much of your own voice you hear in the headset while talking.")

                Divider()

                HStack {
                    Text("Noise gate").font(.callout)
                    Spacer()
                    Picker("Noise gate", selection: Binding(get: { monitor.noiseGate }, set: { monitor.setNoiseGate($0) })) {
                        ForEach(NoiseGateMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                HStack {
                    Text("Mic EQ").font(.callout)
                    Spacer()
                    Picker("Mic EQ", selection: Binding(get: { monitor.micEQ }, set: { monitor.setMicEQ($0) })) {
                        Text("0").tag(0); Text("1").tag(1); Text("2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                    .help("Microphone EQ preset stored on the headset.")
                }
            }
        }
    }

    private func sliderBinding(_ slider: SliderType) -> Binding<Double> {
        Binding(
            get: { Double(monitor.sliders[slider] ?? 0) },
            set: { monitor.previewSlider(slider, percent: Int($0.rounded())) })
    }
}
