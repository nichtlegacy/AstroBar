import AstroBarCore
import SwiftUI

/// Controls for the A50 X / A50 Gen 5: the headset's own master volume, the
/// game/voice mix it reports, and whether the Mac's volume keys are routed to it.
struct LogitechVolumeView: View {
    let monitor: A50Monitor
    let session: LogitechSession

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(title: "Headset", systemImage: "headphones")

                LabeledSlider(
                    title: "Volume",
                    range: Double(A50X.volumeRange.lowerBound) ... Double(A50X.volumeRange.upperBound),
                    step: 1,
                    value: Binding(
                        get: { session.headsetVolume },
                        set: { session.headsetVolume = $0 }),
                    valueLabel: { Self.percentLabel(Int($0.rounded())) },
                    onCommit: { _ in session.commitHeadsetVolume() },
                    onEditingChanged: { session.setVolumeDragging($0) })
                    .help("The headset's own volume, the same level its wheel changes.")

                if let mix = session.chatMix {
                    HStack {
                        Text("Game / Voice").font(.callout)
                        Spacer()
                        Text(Self.mixLabel(mix))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .help("Set with the Game and Voice buttons on the headset.")
                }

                Divider()

                volumeKeys
            }
        }
        // A panel that closes mid-drag never reports the drag as ended.
        .onDisappear { session.setVolumeDragging(false) }
    }

    private var volumeKeys: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Volume keys control the headset", isOn: Binding(
                get: { monitor.settings?.routeVolumeKeys ?? false },
                set: { enabled in
                    monitor.settings?.routeVolumeKeys = enabled
                    monitor.updateVolumeKeys()
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.callout)
                .help("Applies while the headset is the Mac's sound output. Needs Accessibility access.")

            if monitor.volumeKeys.state == .needsPermission {
                HStack {
                    Label("Volume keys need Accessibility access", systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow…") { monitor.volumeKeys.requestPermission() }
                        .controlSize(.small)
                }
            }
        }
    }

    /// The wheel has 22 positions; shown as a percentage like the macOS slider.
    static func percentLabel(_ level: Int) -> String {
        let percent = Double(level) / Double(A50X.volumeRange.upperBound) * 100
        return "\(Int(percent.rounded()))%"
    }

    /// `"50/50"`, game share first.
    static func mixLabel(_ raw: Int) -> String {
        let game = Int((Double(raw) / Double(A50X.chatMixRange.upperBound) * 100).rounded())
        return "\(game)/\(100 - game)"
    }
}
