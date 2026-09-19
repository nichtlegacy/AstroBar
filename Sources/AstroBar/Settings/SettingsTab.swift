import Foundation
import Observation
import SwiftUI

/// The settings window's navigation tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case notifications
    case device
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .notifications: "Notifications"
        case .device: "Device"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .notifications: "bell.badge"
        case .device: "headphones"
        case .about: "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .blue
        case .menuBar: .indigo
        case .notifications: .orange
        case .device: .teal
        case .about: .gray
        }
    }

}

/// Selected settings tab. Deliberately not persisted: the window always opens on
/// General unless the caller asks for a specific pane (the About menu item).
@MainActor
@Observable
final class SettingsSelection {
    var tab: SettingsTab = .general
}
