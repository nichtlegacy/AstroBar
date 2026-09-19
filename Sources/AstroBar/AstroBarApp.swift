import SwiftUI

@main
struct AstroBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The settings window is managed by SettingsWindowController; this
        // scene only satisfies the App protocol. Replacing .appSettings keeps
        // Cmd+, routed to the custom window instead of an empty scene.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        appDelegate.showSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .appInfo) {
                    Button("About AstroBar") {
                        appDelegate.showSettings(.about)
                    }
                    Button("Check for Updates…") {
                        UpdaterManager.shared.checkForUpdates()
                    }
                }
            }
    }
}
