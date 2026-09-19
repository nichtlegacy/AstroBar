import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for the low-battery alert.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
    }

    /// Ask for permission. Returns true if granted.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func sendLowBattery(percent: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Astro A50 battery low"
        content.body = "\(percent)% remaining — time to charge."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "astrobar.lowbattery",
            content: content,
            trigger: nil)
        center.add(request)
    }

    // Show the banner even while the (accessory) app is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
