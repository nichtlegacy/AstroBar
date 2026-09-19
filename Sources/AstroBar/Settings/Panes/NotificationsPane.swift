import SwiftUI
import UserNotifications

struct NotificationsPane: View {
    @Bindable var settings: AppSettings
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                SettingsToggle(
                    "Low-battery alert",
                    subtitle: "Notify once when the headset battery drops below the threshold.",
                    isOn: $settings.lowBatteryNotify)
                    .onChange(of: settings.lowBatteryNotify) { _, enabled in
                        if enabled { enableNotifications() }
                    }

                Picker(selection: $settings.lowBatteryThreshold) {
                    ForEach(AppSettings.lowBatteryThresholds, id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                } label: {
                    SettingsRowLabel(
                        title: "Alert at",
                        subtitle: "Re-arms after charging or recovering past the threshold.")
                }
                .pickerStyle(.menu)
                .disabled(!settings.lowBatteryNotify)

                if notificationsDenied {
                    Label(
                        "Notifications are disabled for AstroBar. Enable them in System Settings → Notifications.",
                        systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Battery")
            } footer: {
                Text("AstroBar asks for notification permission the first time the alert is enabled.")
            }
        }
        .settingsFormStyle()
        .task { await refreshNotificationStatus() }
    }

    private func enableNotifications() {
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if !granted {
                settings.lowBatteryNotify = false
            }
            await refreshNotificationStatus()
        }
    }

    private func refreshNotificationStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        notificationsDenied = settings.lowBatteryNotify && status == .denied
        if status == .denied { settings.lowBatteryNotify = false }
    }
}
