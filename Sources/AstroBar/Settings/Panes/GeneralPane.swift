import SwiftUI

struct GeneralPane: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginFailed = false

    var body: some View {
        Form {
            Section {
                SettingsToggle(
                    "Launch at login",
                    subtitle: "Start AstroBar automatically when you log in.",
                    isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                        launchAtLoginFailed = enabled && !LaunchAtLogin.isEnabled
                    }
                if launchAtLoginFailed {
                    Label(
                        "Launch at login could not be enabled. Make sure AstroBar runs from /Applications.",
                        systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("System")
            } footer: {
                Text("AstroBar lives in the menu bar and keeps running in the background.")
            }
        }
        .settingsFormStyle()
    }
}
