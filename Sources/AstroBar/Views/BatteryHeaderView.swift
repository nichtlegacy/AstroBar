import AstroBarCore
import SwiftUI

/// Top banner: battery ring, model name, where the headset is, and what it is
/// doing — plus the estimated runtime while it runs on battery.
struct BatteryHeaderView: View {
    let monitor: A50Monitor

    @Environment(\.legibilityWeight) private var legibilityWeight

    private var state: HeadsetPowerState { monitor.powerState }

    private var accent: Color {
        if monitor.batteryIsStale { return .secondary }
        if let b = monitor.battery {
            return Theme.batteryColor(b.chargePercent, charging: b.isCharging)
        }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 16) {
            ring

            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    titleRowHorizontal
                    titleRowStacked
                }

                Text(placement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let projection = projectionText {
                    Label(projection.text, systemImage: projection.symbol)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help("Estimated from how fast the charge has been moving.")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The panel window already provides the vibrant backdrop; only the
            // battery tint is layered on top of it here.
            LinearGradient(
                colors: [accent.opacity(0.26), accent.opacity(0.03), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var ring: some View {
        if let battery = monitor.battery {
            BatteryRing(percent: battery.chargePercent, charging: battery.isCharging, size: 66)
                .opacity(monitor.batteryIsStale ? 0.45 : 1)
        } else {
            Circle()
                .fill(.quaternary)
                .overlay(
                    Image(systemName: monitor.status == .cableMode ? "cable.connector" : "headphones")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary))
                .frame(width: 66, height: 66)
                .accessibilityHidden(true)
        }
    }

    /// The base keeps serving the last level it saw, so a reading taken while
    /// the headset is off has to be labelled as remembered.
    private var placement: String {
        let base = state.placement(status: monitor.status)
        return monitor.batteryIsStale ? "\(base) · last known charge" : base
    }

    private var modelName: some View {
        Text("ASTRO A50")
            // Hand-set weight, so it has to answer to the Bold Text setting.
            .font(.system(
                size: 18,
                weight: legibilityWeight == .bold ? .heavy : .semibold,
                design: .rounded))
            .lineLimit(1)
    }

    @ViewBuilder
    private var stateChip: some View {
        if state != .unknown {
            StatusChip(text: state.label, systemImage: state.systemImage, tint: state.tint)
        }
    }

    private var titleRowHorizontal: some View {
        HStack(spacing: 8) {
            modelName.layoutPriority(1)
            Spacer(minLength: 8)
            stateChip
        }
    }

    private var titleRowStacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            modelName
            stateChip
        }
    }

    /// Counts down to empty while on battery, and to full while charging.
    private var projectionText: (text: String, symbol: String)? {
        guard let projection = monitor.batteryProjection,
              let text = BatteryRuntimeFormatter.text(for: projection) else { return nil }

        switch projection {
        case .untilEmpty: return (text, "clock")
        case .untilFull: return (text, "bolt.badge.clock")
        }
    }
}
