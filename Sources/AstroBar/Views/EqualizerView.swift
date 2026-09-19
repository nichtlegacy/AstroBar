import AstroBarCore
import SwiftUI

/// Collapsible list of the three EQ presets. The leading radio selects the
/// active preset; tapping the row body expands its editor inline (accordion,
/// one open at a time). Expansion is instant so the panel resize stays crisp.
struct EqualizerView: View {
    let monitor: A50Monitor
    @State private var expanded: Int?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "Equalizer", systemImage: "slider.horizontal.3")

                ForEach(A50Limits.eqPresets, id: \.self) { preset in
                    presetRow(preset)
                    if expanded == preset {
                        EQPresetEditor(monitor: monitor, preset: preset)
                    }
                    if preset != A50Limits.eqPresets.last {
                        Divider()
                    }
                }
            }
        }
    }

    private func presetRow(_ preset: Int) -> some View {
        let isActive = monitor.activePreset == preset
        let isOpen = expanded == preset
        return HStack(spacing: 10) {
            Button {
                monitor.setActivePreset(preset)
            } label: {
                RadioIndicator(isOn: isActive)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("Preset \(monitor.name(for: preset))")
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
            .help(isActive ? "Active preset" : "Make active")

            Button {
                expanded = isOpen ? nil : preset
            } label: {
                HStack(spacing: 10) {
                    Text(monitor.name(for: preset))
                        .font(.callout.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                    Spacer()
                    MiniEQBars(gains: monitor.gains(for: preset))
                    DisclosureChevron(isExpanded: isOpen)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .hoverHighlight()
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("Edit preset \(monitor.name(for: preset))")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isOpen ? "Collapses the editor" : "Expands the editor")
        }
        .padding(.vertical, 4)
    }
}
