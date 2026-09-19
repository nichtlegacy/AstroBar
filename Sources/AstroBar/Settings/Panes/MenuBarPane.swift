import SwiftUI

struct MenuBarPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                SettingsToggle(
                    "Show battery percentage",
                    subtitle: "Display the headset charge next to the menu bar icon.",
                    isOn: $settings.showBatteryPercent)

                Picker(selection: $settings.iconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                } label: {
                    SettingsRowLabel(
                        title: "Icon",
                        subtitle: "Battery shows a charge-level icon while connected.")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("While charging, the battery icon shows a bolt and the percentage is prefixed with ⚡︎.")
            }
        }
        .settingsFormStyle()
    }
}
