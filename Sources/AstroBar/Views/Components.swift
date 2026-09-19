import AppKit
import AstroBarCore
import SwiftUI

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Shared visual language for the menu panel.
enum Theme {
    static let panelWidth: CGFloat = 340
    static let panelCornerRadius: CGFloat = 13
    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 12

    /// Battery tint using system colors so it adapts to appearance,
    /// accent changes, and increased-contrast settings.
    static func batteryColor(_ percent: Int, charging: Bool) -> Color {
        if charging { return .green }
        switch percent {
        case ..<15: return .red
        case ..<30: return .orange
        case ..<50: return .yellow
        default:    return .green
        }
    }
}

/// AppKit vibrancy material bridged into SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// AppKit's Liquid Glass surface, bridged into SwiftUI.
///
/// `NSVisualEffectView` still renders the pre-Tahoe vibrancy, so a floating
/// panel that wants the system's current look has to ask for glass explicitly.
@available(macOS 26.0, *)
struct GlassBackgroundView: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
    }
}

/// Backdrop for the floating menu panel: Liquid Glass on macOS 26 and later,
/// the menu material before that, and a solid fill when the user turns on
/// Reduce Transparency.
struct PanelBackground: View {
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(nsColor: .controlBackgroundColor)
        } else if #available(macOS 26.0, *) {
            GlassBackgroundView(cornerRadius: cornerRadius)
        } else {
            VisualEffectView(material: .menu)
        }
    }
}

/// Vibrant background that falls back to a solid fill when the user turns on
/// Reduce Transparency.
struct MaterialBackground: View {
    let material: NSVisualEffectView.Material
    var fallback: Color = Color(nsColor: .windowBackgroundColor)

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            fallback
        } else {
            VisualEffectView(material: material)
        }
    }
}

/// Pointer feedback for rows that act as buttons.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                isHovered ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

/// A grouped card with a subtle fill, used to separate panel sections.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// Small uppercase section label with an icon.
struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// Radio dot drawn by hand. The `largecircle.fill.circle` symbol inside a
/// button picks up the system focus highlight, which draws a filled rounded
/// square behind the glyph; shapes keep the indicator round in every state.
struct RadioIndicator: View {
    let isOn: Bool
    var size: CGFloat = 15

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)))
            Circle()
                .strokeBorder(isOn ? Color.clear : Color.primary.opacity(contrast == .increased ? 0.5 : 0.22), lineWidth: 1)
            if isOn {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.34, height: size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Chevron that points down when collapsed and up when expanded.
struct DisclosureChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .accessibilityHidden(true)
    }
}

/// The system slider, with the tick strip suppressed.
///
/// `Slider(value:in:step:)` draws a row of tick marks under the track on macOS,
/// which is what made the panel look wrong. Dropping `step` removes the ticks
/// and keeps the filled track and Liquid Glass knob the system slider has had
/// since macOS 26; the snapping the device needs happens in the binding.
///
/// Going through the real control also means role, label, value, arrow keys and
/// Tab focus come from AppKit instead of being rebuilt by hand.
struct TrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var tint: Color = .accentColor
    /// What VoiceOver announces for this control, and how it reads the value.
    var label: String
    var valueLabel: (Double) -> String
    var onCommit: (Double) -> Void

    /// True between the slider reporting the start and the end of a drag.
    @State private var isDragging = false

    var body: some View {
        Slider(value: snapped, in: range) { editing in
            isDragging = editing
            if !editing { onCommit(value) }
        }
        .controlSize(.small)
        .tint(tint)
        .accessibilityLabel(label)
        .accessibilityValue(valueLabel(value))
    }

    /// Rounds to the device's step. Keyboard and accessibility changes arrive
    /// without a drag to end on, so those commit as they happen.
    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { raw in
                let stepped = step > 0 ? (raw / step).rounded() * step : raw
                let clamped = min(max(stepped, range.lowerBound), range.upperBound)
                guard clamped != value else { return }
                value = clamped
                if !isDragging { onCommit(clamped) }
            })
    }
}

/// A horizontal slider with a leading label and trailing value, committing only
/// when the drag ends (so we don't flood the device with writes).
struct LabeledSlider: View {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double
    var valueLabel: (Double) -> String
    var onCommit: (Double) -> Void
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(valueLabel(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            TrackSlider(
                value: $value,
                range: range,
                step: step,
                tint: tint,
                label: title,
                valueLabel: valueLabel,
                onCommit: onCommit)
        }
    }
}

/// Dense single-line slider: label · slider · value, committing on release.
struct CompactSlider: View {
    let title: String
    let range: ClosedRange<Double>
    var step: Double = 1
    var labelWidth: CGFloat = 86
    @Binding var value: Double
    var valueLabel: (Double) -> String
    var onCommit: (Double) -> Void
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .frame(minWidth: labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            TrackSlider(
                value: $value,
                range: range,
                step: step,
                tint: tint,
                label: title,
                valueLabel: valueLabel,
                onCommit: onCommit)
            Text(valueLabel(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

/// Battery ring gauge with charge percent and a charging bolt.
struct BatteryRing: View {
    let percent: Int
    let charging: Bool
    var size: CGFloat = 60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { Double(max(0, min(100, percent))) / 100 }
    private var color: Color { Theme.batteryColor(percent, charging: charging) }
    private var lineWidth: CGFloat { size * 0.1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: fraction)
            VStack(spacing: -1) {
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.18))
                        .foregroundStyle(.green)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(percent)")
                        .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: size * 0.16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue("\(percent) percent\(charging ? ", charging" : "")")
    }
}

/// Tiny 5-bar preview of an EQ preset's gains, centered on 0 dB.
struct MiniEQBars: View {
    let gains: [Int]
    var tint: Color = .accentColor

    private let barHeight: CGFloat = 18

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(gains.enumerated()), id: \.offset) { _, db in
                    let frac = Double(db) / Double(A50Limits.maxGain)
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: 3, height: max(2, abs(frac) * (barHeight - 4)))
                        .offset(y: -frac * (barHeight - 4) / 2)
                }
            }
        }
        .frame(width: 27, height: barHeight)
        .accessibilityHidden(true)
    }
}

/// A small rounded status chip.
struct StatusChip: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .fixedSize(horizontal: true, vertical: false)
    }
}
