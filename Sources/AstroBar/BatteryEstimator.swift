import Foundation

/// The situation a charge-movement rate was measured in.
///
/// These behave differently enough that one shared average would be useless:
/// the base station charges a resting headset far faster than the headset
/// refills over its cable while it is still playing audio, and neither has
/// anything to do with how fast it drains. Each keeps its own learned rate.
enum BatteryProfile: String, CaseIterable, Sendable {
    /// Running on battery.
    case discharging
    /// Sitting on the base station, taking charge.
    case chargingOnBase
    /// Powered on and linked, charging over its own cable at the same time.
    case chargingInUse

    var isCharging: Bool { self != .discharging }
}

/// Estimates how long the headset will keep running, or how long it still needs
/// to fill up.
///
/// The A50 reports nothing but a 0-100 percentage, so both figures have to be
/// derived from how fast that percentage moves. The estimator anchors on the
/// first reading of a run and measures the change against elapsed time.
///
/// A single run is noisy — the reported percentage moves in coarse steps and a
/// fresh run has no slope at all — so each run's rate is blended into a
/// long-lived average, kept per profile and surviving app restarts. That average
/// is what carries the estimate through the first minutes after launch.
struct BatteryEstimator {
    /// Rate of change in percent per hour, always positive.
    struct Rate: Equatable {
        var percentPerHour: Double
        /// True while the value still comes from previous runs only.
        var isLearned: Bool
    }

    /// What the remaining time counts down to.
    enum Projection: Equatable {
        case untilEmpty(TimeInterval)
        case untilFull(TimeInterval)

        var seconds: TimeInterval {
            switch self {
            case .untilEmpty(let seconds), .untilFull(let seconds): seconds
            }
        }
    }

    /// Guard rails per direction. A run outside these is noise — a reconnect, a
    /// stale anchor, a firmware hiccup — not a rate worth learning.
    ///
    /// Discharge: the headset runs for hours, so anything above 60 %/h is bogus.
    /// Charge: the base refills it in a few hours, and charging while in use is
    /// much slower, so the band has to be wide.
    private static func plausibleRange(for profile: BatteryProfile) -> ClosedRange<Double> {
        profile.isCharging ? 2 ... 120 : 1.5 ... 60
    }

    /// A run needs this much evidence before its own slope is trusted.
    private static let minimumChange = 2
    private static let minimumElapsed: TimeInterval = 10 * 60

    /// An anchor older than this is assumed to span a period the app did not
    /// observe (machine asleep, headset off) and is dropped.
    private static let maximumAnchorAge: TimeInterval = 24 * 60 * 60

    /// Weight given to the newest run when folding it into the average.
    private static let learningWeight = 0.3

    private let store: Store
    private var anchor: Anchor?

    struct Anchor: Equatable, Sendable {
        var date: Date
        var percent: Int
        var profile: BatteryProfile
    }

    init(store: Store) {
        self.store = store
        self.anchor = store.loadAnchor()
    }

    // MARK: - Input

    /// Feeds one poll result. `profile` is nil when nothing can be measured —
    /// the headset is off, full, or the reading is stale.
    mutating func record(percent: Int, profile: BatteryProfile?, now: Date = Date()) {
        guard let profile else {
            clearAnchor()
            return
        }

        guard let current = anchor else {
            setAnchor(Anchor(date: now, percent: percent, profile: profile))
            return
        }

        // A different situation means a different rate, so the run restarts.
        if current.profile != profile {
            setAnchor(Anchor(date: now, percent: percent, profile: profile))
            return
        }

        // The charge moved the wrong way for this profile, or the anchor is from
        // a run we stopped watching: start over rather than divide by nonsense.
        let movedWrongWay = profile.isCharging ? percent < current.percent : percent > current.percent
        if movedWrongWay || now.timeIntervalSince(current.date) > Self.maximumAnchorAge {
            setAnchor(Anchor(date: now, percent: percent, profile: profile))
            return
        }

        if let rate = runRate(from: current, percent: percent, now: now) {
            store.saveLearnedRate(blend(rate, into: store.loadLearnedRate(profile)), profile)
        }
    }

    /// Drops the current run. Called when the headset goes away.
    mutating func reset() {
        clearAnchor()
    }

    // MARK: - Output

    /// The rate used for the current estimate, or nil when nothing is known yet.
    func rate(percent: Int, profile: BatteryProfile, now: Date = Date()) -> Rate? {
        if let anchor, anchor.profile == profile,
           let measured = runRate(from: anchor, percent: percent, now: now) {
            return Rate(percentPerHour: measured, isLearned: false)
        }
        if let learned = store.loadLearnedRate(profile) {
            return Rate(percentPerHour: learned, isLearned: true)
        }
        return nil
    }

    /// Seconds until the battery is empty or full, or nil while the rate is
    /// still unknown.
    func projection(percent: Int, profile: BatteryProfile, now: Date = Date()) -> Projection? {
        guard let rate = rate(percent: percent, profile: profile, now: now),
              rate.percentPerHour > 0 else { return nil }

        if profile.isCharging {
            let remaining = max(0, 100 - percent)
            guard remaining > 0 else { return nil }
            return .untilFull(Double(remaining) / rate.percentPerHour * 3600)
        }
        return .untilEmpty(Double(percent) / rate.percentPerHour * 3600)
    }

    // MARK: - Maths

    /// Slope of the current run, or nil while it is too short to mean anything.
    private func runRate(from anchor: Anchor, percent: Int, now: Date) -> Double? {
        let change = abs(percent - anchor.percent)
        let elapsed = now.timeIntervalSince(anchor.date)
        guard change >= Self.minimumChange, elapsed >= Self.minimumElapsed else { return nil }

        let rate = Double(change) / (elapsed / 3600)
        guard Self.plausibleRange(for: anchor.profile).contains(rate) else { return nil }
        return rate
    }

    private func blend(_ rate: Double, into previous: Double?) -> Double {
        guard let previous else { return rate }
        return previous * (1 - Self.learningWeight) + rate * Self.learningWeight
    }

    private mutating func setAnchor(_ newAnchor: Anchor) {
        anchor = newAnchor
        store.saveAnchor(newAnchor)
    }

    private mutating func clearAnchor() {
        guard anchor != nil else { return }
        anchor = nil
        store.clearAnchor()
    }
}

extension BatteryEstimator {
    /// Where the anchor and the learned rates live between launches.
    struct Store {
        var loadAnchor: () -> Anchor?
        var saveAnchor: (Anchor) -> Void
        var clearAnchor: () -> Void
        var loadLearnedRate: (BatteryProfile) -> Double?
        var saveLearnedRate: (Double, BatteryProfile) -> Void

        /// Backed by `UserDefaults`, so an estimate survives quitting the app
        /// while the headset keeps running or charging.
        static func userDefaults(_ defaults: UserDefaults = .standard) -> Store {
            let anchorDate = "battery.anchorDate"
            let anchorPercent = "battery.anchorPercent"
            let anchorProfile = "battery.anchorProfile"
            func rateKey(_ profile: BatteryProfile) -> String {
                "battery.rate.\(profile.rawValue)"
            }

            return Store(
                loadAnchor: {
                    guard let date = defaults.object(forKey: anchorDate) as? Date,
                          let percent = defaults.object(forKey: anchorPercent) as? Int,
                          let raw = defaults.string(forKey: anchorProfile),
                          let profile = BatteryProfile(rawValue: raw) else { return nil }
                    return Anchor(date: date, percent: percent, profile: profile)
                },
                saveAnchor: { anchor in
                    defaults.set(anchor.date, forKey: anchorDate)
                    defaults.set(anchor.percent, forKey: anchorPercent)
                    defaults.set(anchor.profile.rawValue, forKey: anchorProfile)
                },
                clearAnchor: {
                    defaults.removeObject(forKey: anchorDate)
                    defaults.removeObject(forKey: anchorPercent)
                    defaults.removeObject(forKey: anchorProfile)
                },
                loadLearnedRate: { defaults.object(forKey: rateKey($0)) as? Double },
                saveLearnedRate: { defaults.set($0, forKey: rateKey($1)) })
        }

        /// In-memory store for tests and previews.
        static func inMemory() -> Store {
            final class Box: @unchecked Sendable {
                var anchor: Anchor?
                var rates: [BatteryProfile: Double] = [:]
            }
            let box = Box()
            return Store(
                loadAnchor: { box.anchor },
                saveAnchor: { box.anchor = $0 },
                clearAnchor: { box.anchor = nil },
                loadLearnedRate: { box.rates[$0] },
                saveLearnedRate: { box.rates[$1] = $0 })
        }
    }
}
