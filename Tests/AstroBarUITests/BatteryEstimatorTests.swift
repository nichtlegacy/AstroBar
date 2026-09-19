import AstroBarCore
import Foundation
import Testing
@testable import AstroBar

@Suite("Battery estimation")
struct BatteryEstimatorTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func minutes(_ count: Double) -> Date {
        start.addingTimeInterval(count * 60)
    }

    // MARK: - Discharging

    @Test("No estimate before the run has any slope")
    func needsEvidence() {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 90, profile: .discharging, now: start)
        estimator.record(percent: 89, profile: .discharging, now: minutes(30))

        // One percent of change is below the minimum, so nothing is claimed yet.
        #expect(estimator.rate(percent: 89, profile: .discharging, now: minutes(30)) == nil)
        #expect(estimator.projection(percent: 89, profile: .discharging, now: minutes(30)) == nil)
    }

    @Test("Measured discharge rate drives the estimate")
    func measuresDischarge() throws {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 100, profile: .discharging, now: start)
        estimator.record(percent: 90, profile: .discharging, now: minutes(60))

        let rate = try #require(estimator.rate(percent: 90, profile: .discharging, now: minutes(60)))
        #expect(rate.percentPerHour == 10)
        #expect(rate.isLearned == false)

        // 90 percent left at 10 percent per hour.
        let projection = try #require(estimator.projection(percent: 90, profile: .discharging, now: minutes(60)))
        #expect(projection == .untilEmpty(9 * 3600))
    }

    @Test("Implausible discharge slopes are ignored")
    func rejectsDischargeNoise() {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 100, profile: .discharging, now: start)
        // 80 points in 15 minutes is 320 percent per hour — a bad reading.
        estimator.record(percent: 20, profile: .discharging, now: minutes(15))
        #expect(estimator.rate(percent: 20, profile: .discharging, now: minutes(15)) == nil)
    }

    @Test("A charge that rises while discharging re-anchors")
    func reanchorsOnRise() {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 50, profile: .discharging, now: start)
        estimator.record(percent: 70, profile: .discharging, now: minutes(60))
        #expect(estimator.rate(percent: 70, profile: .discharging, now: minutes(60)) == nil)

        estimator.record(percent: 60, profile: .discharging, now: minutes(120))
        #expect(estimator.rate(percent: 60, profile: .discharging, now: minutes(120))?.percentPerHour == 10)
    }

    // MARK: - Charging

    @Test("Charging counts up to full, not down to empty")
    func measuresCharge() throws {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 20, profile: .chargingOnBase, now: start)
        estimator.record(percent: 40, profile: .chargingOnBase, now: minutes(60))

        let rate = try #require(estimator.rate(percent: 40, profile: .chargingOnBase, now: minutes(60)))
        #expect(rate.percentPerHour == 20)

        // 60 points still to go at 20 percent per hour.
        let projection = try #require(estimator.projection(percent: 40, profile: .chargingOnBase, now: minutes(60)))
        #expect(projection == .untilFull(3 * 3600))
    }

    @Test("A full battery has nothing left to project")
    func noProjectionWhenFull() {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 80, profile: .chargingOnBase, now: start)
        estimator.record(percent: 100, profile: .chargingOnBase, now: minutes(60))
        #expect(estimator.projection(percent: 100, profile: .chargingOnBase, now: minutes(60)) == nil)
    }

    @Test("A charge that falls while charging re-anchors")
    func reanchorsOnFallWhileCharging() {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 50, profile: .chargingOnBase, now: start)
        estimator.record(percent: 30, profile: .chargingOnBase, now: minutes(60))
        #expect(estimator.rate(percent: 30, profile: .chargingOnBase, now: minutes(60)) == nil)
    }

    @Test("Charging on the base and charging in use are learned separately")
    func profilesDoNotBleed() throws {
        let store = BatteryEstimator.Store.inMemory()

        // A fast run on the base…
        var docked = BatteryEstimator(store: store)
        docked.record(percent: 20, profile: .chargingOnBase, now: start)
        docked.record(percent: 50, profile: .chargingOnBase, now: minutes(60))

        // …and a slow one while the headset is in use.
        var inUse = BatteryEstimator(store: store)
        inUse.record(percent: 50, profile: .chargingInUse, now: minutes(120))
        inUse.record(percent: 60, profile: .chargingInUse, now: minutes(180))

        let onBase = try #require(inUse.rate(percent: 60, profile: .chargingOnBase, now: minutes(180)))
        let whileUsed = try #require(inUse.rate(percent: 60, profile: .chargingInUse, now: minutes(180)))
        #expect(onBase.percentPerHour == 30)
        #expect(whileUsed.percentPerHour == 10)
    }

    @Test("Taking the headset off the base restarts the run")
    func profileChangeReanchors() {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 20, profile: .chargingOnBase, now: start)
        // Lifted off the base 40 minutes in; the rate it had on the dock says
        // nothing about the rate it has now.
        estimator.record(percent: 40, profile: .chargingInUse, now: minutes(40))
        #expect(estimator.rate(percent: 40, profile: .chargingInUse, now: minutes(40)) == nil)
    }

    // MARK: - Shared behaviour

    @Test("A nil profile ends the run")
    func nilProfileResets() {
        var estimator = BatteryEstimator(store: .inMemory())
        estimator.record(percent: 100, profile: .discharging, now: start)
        estimator.record(percent: 90, profile: nil, now: minutes(60))

        // The anchor is gone, so the next reading starts a fresh run with no slope.
        estimator.record(percent: 90, profile: .discharging, now: minutes(61))
        #expect(estimator.rate(percent: 90, profile: .discharging, now: minutes(61)) == nil)
    }

    @Test("A learned rate carries the estimate across restarts")
    func learnedRateSurvives() throws {
        let store = BatteryEstimator.Store.inMemory()

        var first = BatteryEstimator(store: store)
        first.record(percent: 100, profile: .discharging, now: start)
        first.record(percent: 90, profile: .discharging, now: minutes(60))
        first.record(percent: 90, profile: nil, now: minutes(61))

        // Fresh process, fresh anchor: the estimate has to come from history.
        var second = BatteryEstimator(store: store)
        second.record(percent: 88, profile: .discharging, now: minutes(120))

        let rate = try #require(second.rate(percent: 88, profile: .discharging, now: minutes(121)))
        #expect(rate.percentPerHour == 10)
        #expect(rate.isLearned)
    }

    @Test("Successive runs are blended, not replaced")
    func blendsRuns() throws {
        let store = BatteryEstimator.Store.inMemory()

        var first = BatteryEstimator(store: store)
        first.record(percent: 100, profile: .discharging, now: start)
        first.record(percent: 90, profile: .discharging, now: minutes(60))
        first.record(percent: 90, profile: nil, now: minutes(61))

        var second = BatteryEstimator(store: store)
        second.record(percent: 100, profile: .discharging, now: minutes(120))
        second.record(percent: 80, profile: .discharging, now: minutes(180))

        // 10 %/h blended with 20 %/h at a 0.3 weight for the newer run. Read
        // from the store rather than `rate`, which prefers the live measurement
        // while a run is still in progress.
        let stored = try #require(store.loadLearnedRate(.discharging))
        #expect(abs(stored - 13) < 0.0001)
    }
}

@Suite("Battery time formatting")
struct BatteryRuntimeFormatterTests {
    @Test("Discharging counts down to empty")
    func dischargeText() {
        #expect(BatteryRuntimeFormatter.text(for: .untilEmpty(5 * 3600 + 20 * 60)) == "≈ 5h 20m left")
    }

    @Test("Charging counts up to full")
    func chargeText() {
        #expect(BatteryRuntimeFormatter.text(for: .untilFull(3600 + 40 * 60)) == "≈ 1h 40m to full")
    }

    @Test("Absurd estimates are withheld rather than shown")
    func rejectsOutOfRange() {
        // Longer than the headset can possibly run or charge.
        #expect(BatteryRuntimeFormatter.text(for: .untilEmpty(48 * 3600)) == nil)
        #expect(BatteryRuntimeFormatter.text(for: .untilFull(20 * 3600)) == nil)
        // Under a minute is noise.
        #expect(BatteryRuntimeFormatter.text(for: .untilFull(30)) == nil)
    }

    @Test("Charging tolerates a longer estimate than discharging does not")
    func limitsDifferPerDirection() {
        // 20 hours is plausible runtime but not a plausible charge time.
        #expect(BatteryRuntimeFormatter.text(for: .untilEmpty(20 * 3600)) != nil)
        #expect(BatteryRuntimeFormatter.text(for: .untilFull(20 * 3600)) == nil)
    }
}

@Suite("Headset power state")
struct HeadsetPowerStateTests {
    @Test("Docked and charging reads as charging on the base")
    func dockedCharging() {
        let state = HeadsetPowerState.resolve(
            status: .connected,
            headset: HeadsetStatus(isLinked: true, isDocked: true),
            battery: BatteryStatus(isCharging: true, chargePercent: 60))
        #expect(state == .chargingOnBase)
        #expect(state.batteryProfile == .chargingOnBase)
        #expect(state.showsRuntime == false)
    }

    @Test("Docked and full reads as charged")
    func dockedCharged() {
        let state = HeadsetPowerState.resolve(
            status: .connected,
            headset: HeadsetStatus(isLinked: false, isDocked: true),
            battery: BatteryStatus(isCharging: false, chargePercent: 100))
        #expect(state == .chargedOnBase)
        #expect(state.batteryProfile == nil)
    }

    @Test("Off the base and powered on reads as in use")
    func inUse() {
        let state = HeadsetPowerState.resolve(
            status: .connected,
            headset: HeadsetStatus(isLinked: true, isDocked: false),
            battery: BatteryStatus(isCharging: false, chargePercent: 55))
        #expect(state == .inUse)
        #expect(state.batteryProfile == .discharging)
        #expect(state.showsRuntime)
    }

    @Test("Off the base but charging reads as charging in use")
    func chargingInUse() {
        // Observed on hardware: 12 percent, charging, linked, undocked — the
        // headset on its own cable while the radio link stays up.
        let state = HeadsetPowerState.resolve(
            status: .connected,
            headset: HeadsetStatus(isLinked: true, isDocked: false),
            battery: BatteryStatus(isCharging: true, chargePercent: 12))
        #expect(state == .chargingInUse)
        #expect(state.batteryProfile == .chargingInUse)
        #expect(state.isCharging)
        #expect(state.placement(status: .connected) == "Base Station · Wireless")
    }

    @Test("Off the base and powered down reads as off")
    func off() {
        let state = HeadsetPowerState.resolve(
            status: .connected,
            headset: HeadsetStatus(isLinked: false, isDocked: false),
            battery: BatteryStatus(isCharging: false, chargePercent: 55))
        #expect(state == .off)
        #expect(state.batteryProfile == nil)
    }

    @Test("Cable mode wins over everything else")
    func cable() {
        let state = HeadsetPowerState.resolve(status: .cableMode, headset: nil, battery: nil)
        #expect(state == .chargingOverCable)
        #expect(state.placement(status: .cableMode) == "USB Cable")
        // Cable mode exposes no HID values, so there is nothing to measure.
        #expect(state.batteryProfile == nil)
    }

    @Test("No headset reading yields unknown")
    func unknown() {
        #expect(HeadsetPowerState.resolve(status: .scanning, headset: nil, battery: nil) == .unknown)
        #expect(HeadsetPowerState.resolve(status: .connected, headset: nil, battery: nil) == .unknown)
    }
}
