import AppKit
import Combine
import Foundation
import os
import Sparkle

/// Wraps Sparkle's updater controller.
///
/// Uses `ObservableObject` rather than `@Observable` because `canCheckForUpdates`
/// is bridged from Sparkle's KVO property through a Combine publisher.
@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    /// Invoked before Sparkle shows any window. A menu bar app runs as
    /// `.accessory` and would otherwise present the update panel behind every
    /// other app, with the menu panel floating on top of it.
    var willPresentUpdateUI: (() -> Void)?

    private let controller: SPUStandardUpdaterController
    private let logger = Logger(subsystem: "de.nichtlegacy.astrobar", category: "Updater")

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Nil when the bundle carries no `SUFeedURL`, which is the case for
    /// `swift run` and test builds.
    var feedURL: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    private override init() {
        // startingUpdater: false — start() is called explicitly once the app has
        // finished launching.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        super.init()

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }

    /// Begins Sparkle's scheduled background checks. Call from
    /// `applicationDidFinishLaunching`.
    func start() {
        #if DEBUG
        logger.info("updater disabled in debug builds")
        #else
        guard feedURL != nil else {
            logger.notice("no SUFeedURL in bundle, updater stays idle")
            return
        }
        controller.startUpdater()
        logger.info("updater started")
        #endif
    }

    /// User-triggered check. Shows Sparkle's UI even when no update is available.
    func checkForUpdates() {
        #if DEBUG
        logger.info("update check skipped in debug builds")
        #else
        willPresentUpdateUI?()
        controller.checkForUpdates(nil)
        #endif
    }
}
