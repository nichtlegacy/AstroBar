import AppKit
import SwiftUI

/// Owns the settings window: full-size content view for the modern edge-to-
/// edge look, sidebar routing via `SettingsSelection`, remembered frame, and
/// activation-policy management so the accessory (menu-bar-only) app comes to
/// the foreground with a Dock icon while settings are open.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let defaultSize = NSSize(width: 720, height: 500)
    static let minimumSize = NSSize(width: 620, height: 440)

    private let selection: SettingsSelection

    init(monitor: A50Monitor, settings: AppSettings) {
        let selection = SettingsSelection()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        let rootView = SettingsView(
            monitor: monitor,
            settings: settings,
            selection: selection,
            onSelectionChange: { [weak window] tab in
                window?.title = tab.title
            })

        self.selection = selection

        window.title = selection.tab.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .none
        window.contentMinSize = Self.minimumSize
        // A settings window is not a fullscreen surface; keep the green button
        // on zoom instead of offering Full Screen.
        window.collectionBehavior.insert(.fullScreenNone)
        window.identifier = NSUserInterfaceItemIdentifier("astrobar.settings-window-v2")
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        // Never let macOS restore this window at launch; it opens on request only.
        window.isRestorable = false

        super.init(window: window)

        window.delegate = self
        window.setFrameAutosaveName("astrobar.settings-window-v2")
        if !window.setFrameUsingName("astrobar.settings-window-v2") {
            // The hosting controller shrinks the window to the content's minimum
            // size, so the default has to be applied after it is installed.
            window.setContentSize(Self.defaultSize)
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(tab: SettingsTab? = nil) {
        let target = tab ?? .general
        selection.tab = target
        window?.title = target.title
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
