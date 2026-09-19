import Testing
@testable import AstroBar

@Suite("Low-battery alarm hysteresis")
struct LowBatteryAlarmTests {
    @Test("Crossing the threshold fires exactly once")
    func firesOnce() {
        var alarm = LowBatteryAlarm(threshold: 15)
        #expect(alarm.update(chargePercent: 20, isCharging: false) == false)
        #expect(alarm.update(chargePercent: 14, isCharging: false) == true)
        #expect(alarm.update(chargePercent: 13, isCharging: false) == false)
        #expect(alarm.update(chargePercent: 10, isCharging: false) == false)
    }

    @Test("Hovering around the threshold does not re-fire")
    func noFlapping() {
        var alarm = LowBatteryAlarm(threshold: 15)
        #expect(alarm.update(chargePercent: 14, isCharging: false) == true)
        // Oscillate inside the hysteresis band.
        #expect(alarm.update(chargePercent: 16, isCharging: false) == false)
        #expect(alarm.update(chargePercent: 15, isCharging: false) == false)
        #expect(alarm.update(chargePercent: 17, isCharging: false) == false)
    }

    @Test("Re-arms only after recovery past threshold + hysteresis")
    func rearmsAfterRecovery() {
        var alarm = LowBatteryAlarm(threshold: 15)
        _ = alarm.update(chargePercent: 14, isCharging: false)
        // 18 is inside the hysteresis band (needs > 15 + 3): no re-arm.
        #expect(alarm.update(chargePercent: 18, isCharging: false) == false)
        #expect(alarm.update(chargePercent: 14, isCharging: false) == false)
        #expect(alarm.update(chargePercent: 19, isCharging: false) == false)
        #expect(alarm.update(chargePercent: 14, isCharging: false) == true)
    }

    @Test("Charging re-arms without firing")
    func chargingReArms() {
        var alarm = LowBatteryAlarm(threshold: 15)
        #expect(alarm.update(chargePercent: 5, isCharging: false) == true)
        #expect(alarm.update(chargePercent: 5, isCharging: true) == false)
        // Unplug while still low: fires again, since charge never recovered.
        #expect(alarm.update(chargePercent: 5, isCharging: false) == true)
    }
}
