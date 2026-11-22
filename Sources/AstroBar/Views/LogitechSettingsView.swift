import AstroBarCore
import SwiftUI

/// The A50 X / A50 Gen 5 settings beyond volume: sidetone, microphone noise
/// gate and the base station's light. Each row appears only once the device
/// has reported the current value, so a control never shows a guess.
struct LogitechSettingsView: View {
    let session: LogitechSession

    private var hasAnything: Bool {
        session.sidetone != nil || session.dockLight != nil || session.noiseGateRaw != nil
    }

    var body: some View {
        if hasAnything {
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel(title: "Settings", systemImage: "slider.horizontal.3")

                    if let sidetone = session.sidetone {
                        LabeledSlider(
                            title: "Sidetone",
                            range: Double(A50X.sidetoneRange.lowerBound) ... Double(A50X.sidetoneRange.upperBound),
                            step: 1,
                            value: Binding(get: { sidetone }, set: { session.sidetone = $0 }),
                            valueLabel: { Self.sidetoneLabel(Int($0.rounded())) },
                            onCommit: { _ in session.commitSidetone() })
                            .help("How much of your own voice you hear in the headset.")
                    }

                    if let raw = session.noiseGateRaw {
                        HStack {
                            Text("Noise gate").font(.callout)
                            Spacer()
                            Picker("Noise gate", selection: Binding(
                                get: { A50XNoiseGate(rawValue: raw) },
                                set: { mode in
                                    if let mode { session.setNoiseGate(mode) }
                                })) {
                                ForEach(A50XNoiseGate.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(Optional(mode))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .fixedSize()
                        }
                        .help("Cuts background noise from the microphone. A mode set elsewhere that has no name here shows as unselected.")
                    }

                    if let dockLight = session.dockLight {
                        LabeledSlider(
                            title: "Base station light",
                            range: Double(A50X.dockLightRange.lowerBound) ... Double(A50X.dockLightRange.upperBound),
                            step: 5,
                            value: Binding(get: { dockLight }, set: { session.dockLight = $0 }),
                            valueLabel: { "\(Int($0.rounded()))%" },
                            onCommit: { _ in session.commitDockLight() })
                    }
                }
            }
        }
    }

    static func sidetoneLabel(_ level: Int) -> String {
        level == 0 ? "Off" : "\(level) of \(A50X.sidetoneRange.upperBound)"
    }
}
