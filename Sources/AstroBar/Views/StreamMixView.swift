import AstroBarCore
import SwiftUI

/// Levels mixed into the base station's stream port (what your audience
/// hears). Collapsed by default — most users never touch it.
struct StreamMixView: View {
    let monitor: A50Monitor
    @State private var expanded = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 10) {
                        SectionLabel(title: "Stream Output", systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        DisclosureChevron(isExpanded: expanded)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .hoverHighlight()
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("Stream output")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(expanded ? "Collapses the stream mix sliders" : "Expands the stream mix sliders")

                if expanded {
                    ForEach(streamSliders, id: \.rawValue) { slider in
                        LabeledSlider(
                            title: slider.shortName,
                            range: 0 ... 100,
                            step: 1,
                            value: Binding(
                                get: { Double(monitor.sliders[slider] ?? 0) },
                                set: { monitor.previewSlider(slider, percent: Int($0.rounded())) }),
                            valueLabel: { "\(Int($0.rounded()))%" },
                            onCommit: { _ in monitor.commitSlider(slider) })
                    }
                    Text("Levels sent to the base station's stream port — what your audience hears.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var streamSliders: [SliderType] {
        [.streamMixMic, .streamMixChat, .streamMixGame, .streamMixAux]
    }
}

extension SliderType {
    /// Short label inside the Stream Output card (the card names the context).
    var shortName: String {
        switch self {
        case .streamMixMic: "Mic"
        case .streamMixChat: "Chat"
        case .streamMixGame: "Game"
        case .streamMixAux: "Aux"
        case .mic, .sideTone: displayName
        }
    }
}
