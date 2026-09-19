import AstroBarCore
import SwiftUI

/// Game/chat balance and alert volume.
struct MixView: View {
    let monitor: A50Monitor

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(title: "Mix", systemImage: "dial.medium")

                VStack(spacing: 3) {
                    LabeledSlider(
                        title: "Balance",
                        range: 0 ... 255,
                        step: 1,
                        value: Binding(get: { Double(monitor.balanceRaw) }, set: { monitor.balanceRaw = Int($0.rounded()) }),
                        valueLabel: { Self.balanceLabel(Int($0.rounded())) },
                        onCommit: { _ in monitor.commitBalance() })
                        .help("The balance the base station restores when the headset powers on.")
                    HStack {
                        Text("Game").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("Chat").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                LabeledSlider(
                    title: "Alert volume",
                    range: 0 ... 100,
                    step: 1,
                    value: Binding(get: { Double(monitor.alertVolume) }, set: { monitor.alertVolume = Int($0.rounded()) }),
                    valueLabel: { "\(Int($0.rounded()))%" },
                    onCommit: { _ in monitor.commitAlertVolume() })
                    .help("Volume of the base station's voice prompts and alerts.")
            }
        }
    }

    /// `"70/30"` — game share first, the way the headset labels the wheel.
    static func balanceLabel(_ raw: Int) -> String {
        let chat = Int((Double(raw) / 255.0 * 100).rounded())
        return "\(100 - chat)/\(chat)"
    }
}
