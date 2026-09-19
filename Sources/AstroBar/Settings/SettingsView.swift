import SwiftUI

/// Root of the settings window: sidebar navigation + the selected pane over a
/// window-background material.
struct SettingsView: View {
    @Bindable var monitor: A50Monitor
    @Bindable var settings: AppSettings
    @Bindable var selection: SettingsSelection
    var onSelectionChange: (SettingsTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: Binding(
                get: { selection.tab },
                set: { selection.tab = $0; onSelectionChange($0) }))
                .frame(width: 188)
                .frame(maxHeight: .infinity)

            MaterialBackground(material: .windowBackground)
                .overlay(alignment: .topLeading) {
                    detailView
                        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                }
        }
        .frame(minWidth: 620, minHeight: 440)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection.tab {
        case .general: GeneralPane(settings: settings)
        case .menuBar: MenuBarPane(settings: settings)
        case .notifications: NotificationsPane(settings: settings)
        case .device: DevicePane(monitor: monitor)
        case .about: AboutPane()
        }
    }
}
