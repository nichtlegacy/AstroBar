import AstroBarCore
import SwiftUI

/// Inline editor for one EQ preset: rename, activate, per-band gain, and an
/// optional frequency/bandwidth section. Shown expanded inside EqualizerView.
struct EQPresetEditor: View {
    let monitor: A50Monitor
    let preset: Int

    @State private var name = ""
    @State private var showFrequencies = false
    @State private var importedPresets: [EQTemplate] = []
    @FocusState private var nameFocused: Bool

    @Environment(\.dismissMenuPanel) private var dismissMenuPanel

    private let bandLabels = ["80", "300", "1k", "4k", "12k"]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                TextField("Preset name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.callout.weight(.medium))
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .trailing) {
                presetLibrary
                    .padding(.trailing, 4)
            }

            ForEach(Array(monitor.gains(for: preset).enumerated()), id: \.offset) { index, db in
                LabeledSlider(
                    title: "\(bandLabels[safe: index] ?? "B\(index + 1)") Hz",
                    range: Double(A50Limits.minGain) ... Double(A50Limits.maxGain),
                    step: 1,
                    value: Binding(
                        get: { Double(db) },
                        set: { monitor.previewGain(preset: preset, band: index, db: Int($0.rounded())) }),
                    valueLabel: { let v = Int($0.rounded()); return v > 0 ? "+\(v) dB" : "\(v) dB" },
                    onCommit: { _ in monitor.commitGains(preset: preset) })
            }

            Button {
                showFrequencies.toggle()
            } label: {
                HStack {
                    Text("Frequencies")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    DisclosureChevron(isExpanded: showFrequencies)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            if showFrequencies {
                frequencies
            }
        }
        .padding(.bottom, 4)
        .task(id: preset) {
            name = monitor.name(for: preset)
            await monitor.loadBands(preset)
        }
    }

    /// Loads a whole preset into this slot. Sits at the trailing edge of the
    /// name field, where it reads as an action on this preset.
    private var presetLibrary: some View {
        Menu {
            Section("Astro Command Center") {
                ForEach(EQTemplate.stock, content: menuEntry)
            }
            Section("The ZEFERENCE by ZaliaS") {
                ForEach(EQTemplate.community, content: menuEntry)
            }
            if !importedPresets.isEmpty {
                Section("Imported") {
                    ForEach(importedPresets, content: menuEntry)
                }
            }
            Divider()
            Button("Import from File…") { runImport() }
        } label: {
            // Icon-only visually, but the text stays for VoiceOver — an
            // `Image` alone gets announced by its SF Symbol name.
            Label("Replace this preset", systemImage: "square.and.arrow.down")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Replace this preset's name, gains and bands. Only permanent once you press Save.")
    }

    /// One menu row. A second `Text` in a button's label becomes the item's
    /// subtitle on macOS, which is where the preset's purpose goes; `help`
    /// repeats it for anyone hovering.
    private func menuEntry(_ template: EQTemplate) -> some View {
        Button {
            monitor.apply(template, to: preset)
        } label: {
            Text(template.name)
            if let summary = template.summary {
                Text(summary)
            }
        }
        .help(template.summary ?? "")
    }

    /// The open panel is modal and the menu panel floats above it, so the menu
    /// panel has to go away first.
    private func runImport() {
        dismissMenuPanel()
        switch EQTemplateIO.importPresets() {
        case .cancelled:
            break
        case .presets(let presets):
            importedPresets = presets
        case .failure(let message):
            monitor.report(message)
        }
    }

    @ViewBuilder
    private var frequencies: some View {
        let bands = monitor.bands(for: preset)
        if bands.isEmpty {
            HStack { ProgressView().controlSize(.small); Text("Loading…").font(.caption).foregroundStyle(.secondary) }
        } else {
            VStack(spacing: 8) {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    let isShelf = index == 0 || index == 4
                    VStack(spacing: 4) {
                        HStack {
                            Text("Band \(index + 1)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text(freqLabel(band.centerFreq)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        CompactSlider(
                            title: "Freq", range: Double(A50Limits.minCenterFreq) ... Double(A50Limits.maxCenterFreq),
                            step: 10, labelWidth: 50,
                            value: Binding(
                                get: { Double(band.centerFreq) },
                                set: { monitor.previewBand(preset: preset, index: index, centerFreq: Int($0.rounded())) }),
                            valueLabel: { freqLabel(Int($0.rounded())) },
                            onCommit: { _ in monitor.commitBand(preset: preset, index: index) })
                        if !isShelf {
                            CompactSlider(
                                title: "Width",
                                range: Double(A50Limits.minBandwidth) ... Double(A50Limits.maxBandwidth),
                                step: 64, labelWidth: 50,
                                value: Binding(
                                    get: { Double(band.bandwidth) },
                                    set: { monitor.previewBand(preset: preset, index: index, bandwidth: Int($0.rounded())) }),
                                valueLabel: { String(format: "%.1f", $0 / Double(A50Limits.bandwidthScale)) },
                                onCommit: { _ in monitor.commitBand(preset: preset, index: index) })
                        }
                    }
                }
            }
        }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != monitor.name(for: preset) {
            monitor.renamePreset(preset, name: trimmed)
        }
    }

    private func freqLabel(_ hz: Int) -> String {
        hz >= 1000 ? String(format: "%.1fk Hz", Double(hz) / 1000) : "\(hz) Hz"
    }
}
