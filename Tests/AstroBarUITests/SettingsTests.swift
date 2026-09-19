import Foundation
import Testing
@testable import AstroBar

@MainActor
@Suite("Settings")
struct SettingsTests {
    private func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "astrobar-tests-\(name)")!
        suite.removePersistentDomain(forName: "astrobar-tests-\(name)")
        return suite
    }

    @Test("Tabs are General, Menu Bar, Notifications, Device, About")
    func tabs() {
        #expect(SettingsTab.allCases == [.general, .menuBar, .notifications, .device, .about])
    }

    @Test("Every tab has a title and an SF Symbol")
    func tabsAreComplete() {
        for tab in SettingsTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.icon.isEmpty)
        }
    }

    @Test("Settings open on General")
    func opensOnGeneral() {
        #expect(SettingsSelection().tab == .general)
    }

    @Test("Low-battery thresholds are sorted and plausible")
    func thresholdChoices() {
        let choices = AppSettings.lowBatteryThresholds
        #expect(choices == choices.sorted())
        #expect(choices.first ?? 0 >= 5)
        #expect(choices.last ?? 100 <= 50)
    }

    @Test("A stored threshold that is not on the list snaps to the nearest one")
    func migratesOffListThreshold() {
        let store = defaults("threshold")
        // 35 came from the old stepper, which allowed any multiple of five.
        store.set(35, forKey: "lowBatteryThreshold")

        let settings = AppSettings(defaults: store)
        #expect(AppSettings.lowBatteryThresholds.contains(settings.lowBatteryThreshold))
        #expect(settings.lowBatteryThreshold == 30 || settings.lowBatteryThreshold == 40)
    }

    @Test("A threshold already on the list is left alone")
    func keepsValidThreshold() {
        let store = defaults("valid-threshold")
        store.set(25, forKey: "lowBatteryThreshold")
        #expect(AppSettings(defaults: store).lowBatteryThreshold == 25)
    }

    @Test("Defaults are sensible on a fresh install")
    func freshDefaults() {
        let settings = AppSettings(defaults: defaults("fresh"))
        #expect(settings.lowBatteryThreshold == 15)
        #expect(settings.showBatteryPercent)
        #expect(settings.iconStyle == .headphones)
    }
}

/// Guards the packaged app bundle.
///
/// A downloaded copy has no source tree and no `.build` directory to fall back
/// on, so anything missing from `Contents/Resources` is broken for everyone
/// except whoever built it. Skipped unless the bundle has been packaged.
@Suite("App bundle")
struct AppBundleTests {
    private var appURL: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AstroBarUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("AstroBar.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @Test("The packaged bundle carries its icon and no stray resource bundle")
    func bundleShipsItsResources() throws {
        guard let appURL else { return }
        let resources = appURL.appendingPathComponent("Contents/Resources")
        let contents = try FileManager.default.contentsOfDirectory(atPath: resources.path)

        #expect(contents.contains("AppIcon.icns"))
        // A SwiftPM resource bundle here would never be found at runtime.
        #expect(!contents.contains { $0.hasSuffix(".bundle") })
    }

    @Test("The packaged bundle is set up for Sparkle")
    func bundleIsUpdatable() throws {
        guard let appURL else { return }
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist) as? [String: Any])

        #expect((info["SUFeedURL"] as? String)?.hasSuffix("appcast.xml") == true)
        #expect((info["SUPublicEDKey"] as? String)?.isEmpty == false)

        let framework = appURL.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
        #expect(FileManager.default.fileExists(atPath: framework.path))
    }
}
