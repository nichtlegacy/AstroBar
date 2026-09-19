import AstroBarCore
import SwiftUI

/// Tracks how many times the panel has been closed.
///
/// The panel window is only ordered out, so its SwiftUI state would otherwise
/// survive: reopening it would still show whatever sections were expanded last
/// time. Rebuilding the tree on each close collapses them back.
@MainActor
@Observable
final class PanelSession {
    private(set) var generation = 0

    func reset() {
        generation &+= 1
    }
}

/// The panel window's root: the menu content over menu vibrancy, clipped to the
/// window's rounded corners. Kept separate from `MenuPanelView` so previews and
/// render tests get the bare content.
struct MenuBarPanelView: View {
    let monitor: A50Monitor
    let session: PanelSession
    var onOpenSettings: () -> Void = {}

    var body: some View {
        MenuPanelView(monitor: monitor, onOpenSettings: onOpenSettings)
            .id(session.generation)
            .background(PanelBackground(cornerRadius: Theme.panelCornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }
}

/// Root content of the menu bar window. Never scrolls; the panel sizes itself
/// to its content (the EQ section expands/collapses inline).
struct MenuPanelView: View {
    let monitor: A50Monitor
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            BatteryHeaderView(monitor: monitor)
            body(for: monitor.status)
        }
        // Fixed width: a menu panel that changes width when a section expands
        // reads as a glitch.
        .frame(width: Theme.panelWidth)
    }

    @ViewBuilder
    private func body(for status: ConnectionStatus) -> some View {
        switch status {
        case .connected:
            VStack(spacing: 10) {
                OutputVolumeView(monitor: monitor)
                EqualizerView(monitor: monitor)
                MixView(monitor: monitor)
                MicrophoneView(monitor: monitor)
                StreamMixView(monitor: monitor)
                FooterView(monitor: monitor, onOpenSettings: onOpenSettings)
            }
            .padding(12)
        case .cableMode:
            disconnected(
                icon: "cable.connector",
                message: "The headset is plugged in by USB cable. Place it on the base station to read battery and adjust the equalizer.")
        case .scanning:
            disconnected(icon: "magnifyingglass", message: "Searching for the Astro A50 base station…")
        case .disconnected:
            disconnected(icon: "headphones.slash", message: "No Astro A50 base station found. Connect it over USB.")
        }
    }

    private func disconnected(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            FooterView(monitor: monitor, onOpenSettings: onOpenSettings)
        }
        .padding(12)
    }
}
