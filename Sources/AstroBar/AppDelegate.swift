import AppKit
import AstroBarCore
import Observation
import SwiftUI

/// Borderless window that hosts the menu content.
///
/// `NSPopover` animates every content-size change, which made expanding a
/// section (Equalizer, Stream Output) look sluggish, and it swallows the click
/// on our own status item while it holds key, so the item couldn't toggle it
/// shut. A panel resizes instantly and leaves event handling to us.
final class MenuBarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .none
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
    }

    /// Needed so the preset-name text field can take focus.
    override var canBecomeKey: Bool { true }
}

/// Drives the status-bar item, the menu panel, and the settings window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let monitor = A50Monitor()
    let settings = AppSettings()

    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel!
    private var outsideClickMonitor: Any?
    private var localEventMonitor: Any?
    private var settingsController: SettingsWindowController?
    private let panelSession = PanelSession()
    /// Blocks the re-open that a status-item click would otherwise trigger right
    /// after the same click closed the panel.
    private var reopenBlockedUntil = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.settings = settings
        NotificationManager.shared.configure()
        monitor.start()
        configurePanel()
        configureStatusItem()
        trackButtonAppearance()
        closeRestoredWindows()
        configureUpdater()
    }

    /// Sparkle's windows are ordinary app windows. As an accessory app we have
    /// to come forward, and the panel floats above everything, so it goes away
    /// before an update window appears.
    private func configureUpdater() {
        UpdaterManager.shared.willPresentUpdateUI = { [weak self] in
            self?.hidePanel()
            NSApp.activate(ignoringOtherApps: true)
        }
        UpdaterManager.shared.start()
    }

    /// A menu-bar-only app shows nothing until asked. macOS window restoration
    /// otherwise puts the settings window back on screen at launch just because
    /// it was open when the app last quit.
    private func closeRestoredWindows() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.isVisible && window.canBecomeMain {
                window.close()
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Panel

    private func configurePanel() {
        let host = NSHostingController(
            rootView: MenuBarPanelView(monitor: monitor, session: panelSession, onOpenSettings: { [weak self] in
                self?.showSettings()
            })
            .environment(\.dismissMenuPanel) { [weak self] in
                self?.hidePanel()
            })
        host.sizingOptions = [.preferredContentSize]

        panel = MenuBarPanel()
        panel.contentViewController = host
        panel.delegate = self
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Theme.panelCornerRadius
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.imagePosition = .imageLeading
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("AstroBar")
    }

    /// Left click toggles the panel; right click opens the short menu Mac users
    /// expect on a status item.
    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showStatusMenu() {
        hidePanel()
        let menu = NSMenu()
        // Enablement is set per item below; the responder-chain default would
        // undo the explicit state on the status line and the update check.
        menu.autoenablesItems = false

        menu.addItem(statusLineItem())
        menu.addItem(.separator())

        if monitor.status == .connected {
            addPresetItems(to: menu)
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "About AstroBar", action: #selector(openAboutFromMenu), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = UpdaterManager.shared.canCheckForUpdates
        menu.addItem(updateItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit AstroBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        // Attaching the menu and re-clicking is the supported way to pop a menu
        // from a status item that also has an action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Non-interactive first row: charge, what the headset is doing, and the
    /// estimated time, in the smaller secondary style macOS uses for menu
    /// headers.
    private func statusLineItem() -> NSMenuItem {
        let item = NSMenuItem(title: statusLineText(), action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: statusLineText(),
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        item.isEnabled = false
        return item
    }

    private func statusLineText() -> String {
        guard monitor.status == .connected, let battery = monitor.battery else {
            return monitor.powerState.placement(status: monitor.status)
        }

        var parts = ["\(battery.chargePercent)%", monitor.powerState.label]
        if let projection = monitor.batteryProjection,
           let formatted = BatteryRuntimeFormatter.text(for: projection) {
            parts.append(formatted)
        }
        return parts.joined(separator: "  ·  ")
    }

    /// The three EQ slots, checkmarked on the active one, so the preset can be
    /// switched without opening the panel.
    private func addPresetItems(to menu: NSMenu) {
        for preset in A50Limits.eqPresets {
            let item = NSMenuItem(
                title: monitor.name(for: preset),
                action: #selector(selectPresetFromMenu(_:)),
                keyEquivalent: "")
            item.target = self
            item.tag = preset
            item.state = monitor.activePreset == preset ? .on : .off
            item.isEnabled = true
            menu.addItem(item)
        }
    }

    @objc private func selectPresetFromMenu(_ sender: NSMenuItem) {
        monitor.setActivePreset(sender.tag)
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func openAboutFromMenu() {
        showSettings(.about)
    }

    @objc private func checkForUpdatesFromMenu() {
        UpdaterManager.shared.checkForUpdates()
    }

    private func showPanel() {
        guard Date() >= reopenBlockedUntil else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.isHighlighted = true
        installOutsideClickMonitor()
        installLocalEventMonitor()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        statusItem.button?.isHighlighted = false
        removeEventMonitors()
        reopenBlockedUntil = Date().addingTimeInterval(0.2)
        // Collapse expanded sections while the panel is off screen, so it opens
        // in its resting state next time.
        panelSession.reset()
    }

    /// Anchors the panel under the status item, keeping its top edge fixed so it
    /// grows downwards when a section expands.
    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 5)

        let anchorCenter = NSPoint(x: anchor.midX, y: anchor.midY)
        let hostScreen = NSScreen.screens.first { $0.frame.contains(anchorCenter) }
            ?? buttonWindow.screen
            ?? NSScreen.main
        if let screen = hostScreen {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    func windowDidResize(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        positionPanel()
        panel.invalidateShadow()
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
    }

    /// Escape closes the panel, and a click on the status item closes it like a
    /// system menu. The click is consumed so the button action can't re-open it.
    private func installLocalEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.hidePanel() }
                return event
            }
            if event.window === self.statusItem.button?.window {
                self.hidePanel()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    // MARK: - Settings

    func showSettings(_ tab: SettingsTab? = nil) {
        hidePanel()
        if settingsController == nil {
            settingsController = SettingsWindowController(monitor: monitor, settings: settings)
        }
        settingsController?.show(tab: tab)
    }

    // MARK: - Status button rendering

    private func trackButtonAppearance() {
        withObservationTracking {
            renderButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackButtonAppearance() }
        }
    }

    private func renderButton() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(systemSymbolName: symbolName(), accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        button.toolTip = buttonDescription()
        button.setAccessibilityLabel(buttonDescription())

        if settings.showBatteryPercent, let battery = monitor.battery {
            let bolt = battery.isCharging ? "⚡︎" : ""
            button.title = " \(bolt)\(battery.chargePercent)%"
        } else {
            button.title = ""
        }
    }

    private func buttonDescription() -> String {
        guard monitor.status == .connected, let battery = monitor.battery else {
            return "AstroBar"
        }
        var text = "ASTRO A50 — \(battery.chargePercent)%, \(monitor.powerState.label.lowercased())"
        if let projection = monitor.batteryProjection,
           let formatted = BatteryRuntimeFormatter.text(for: projection) {
            text += " (\(formatted))"
        }
        return text
    }

    private func symbolName() -> String {
        if monitor.status == .cableMode { return "cable.connector" }
        guard settings.iconStyle == .battery, let battery = monitor.battery else {
            return "headphones"
        }
        if battery.isCharging { return "battery.100.bolt" }
        switch battery.chargePercent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
