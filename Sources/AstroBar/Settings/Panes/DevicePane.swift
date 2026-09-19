import AstroBarCore
import SwiftUI

struct DevicePane: View {
    @Bindable var monitor: A50Monitor

    var body: some View {
        Form {
            Section {
                HStack {
                    SettingsStatusDot(
                        color: statusColor,
                        label: statusText)
                    Spacer()
                }
                .listRowBackground(Color.clear)

                LabeledContent("Connection", value: connectionText)
                if let info = monitor.deviceInfo {
                    LabeledContent("USB id", value: info.description)
                }
                if let base = monitor.baseFirmware {
                    LabeledContent("Base firmware", value: base.description)
                }
                if let headset = monitor.headsetFirmware {
                    LabeledContent("Headset firmware", value: headset.description)
                }
                if let timer = monitor.autoShutoffTimer {
                    LabeledContent("Auto-shutoff timer", value: timer == 0 ? "Off" : "\(timer) min")
                }
            } header: {
                Text("Astro A50 (Gen 4)")
            } footer: {
                Text("The headset only reports values while running through the base station. Plugged in by USB cable it charges but exposes no control interface.")
            }
        }
        .settingsFormStyle()
    }

    private var statusColor: Color {
        switch monitor.status {
        case .connected: .green
        case .cableMode: .orange
        case .scanning, .disconnected: .gray
        }
    }

    private var statusText: String {
        switch monitor.status {
        case .connected: "Base station connected"
        case .cableMode: "USB cable (charging only)"
        case .scanning: "Searching…"
        case .disconnected: "Not connected"
        }
    }

    private var connectionText: String {
        switch monitor.status {
        case .connected: "Base station"
        case .cableMode: "USB cable"
        case .scanning: "Scanning…"
        case .disconnected: "Disconnected"
        }
    }
}
