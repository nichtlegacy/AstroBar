import Foundation

/// One-shot low-battery alerting with hysteresis.
///
/// Crossing the threshold fires a single notification; it re-arms only after
/// the charge recovers past `threshold + hysteresis` or charging starts, so a
/// battery hovering around the threshold doesn't spam.
struct LowBatteryAlarm {
    let threshold: Int
    /// Percent above the threshold required to re-arm.
    let hysteresis: Int

    private var armed = true

    init(threshold: Int, hysteresis: Int = 3) {
        self.threshold = threshold
        self.hysteresis = hysteresis
    }

    /// Feed the latest reading; returns true when a notification should fire now.
    mutating func update(chargePercent: Int, isCharging: Bool) -> Bool {
        if isCharging {
            armed = true
            return false
        }
        if chargePercent <= threshold {
            if armed {
                armed = false
                return true
            }
        } else if chargePercent > threshold + hysteresis {
            armed = true
        }
        return false
    }
}
