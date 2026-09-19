import SwiftUI

/// System output volume for the A50 audio device (CoreAudio).
struct OutputVolumeView: View {
    @Bindable var monitor: A50Monitor

    var body: some View {
        if monitor.hasAudioDevice {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: speakerSymbol)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TrackSlider(
                        value: $monitor.systemVolume,
                        range: 0 ... 100,
                        step: 1,
                        label: "Output volume",
                        valueLabel: { "\(Int($0.rounded())) percent" },
                        onCommit: { _ in monitor.commitVolume() })
                    Text("\(Int(monitor.systemVolume))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var speakerSymbol: String {
        switch monitor.systemVolume {
        case 0: "speaker.slash.fill"
        case ..<34: "speaker.wave.1.fill"
        case ..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
