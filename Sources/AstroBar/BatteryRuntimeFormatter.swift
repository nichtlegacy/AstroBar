import Foundation

/// Formats an estimated battery time for display.
///
/// The app ships English only, so the duration is pinned to an English locale
/// rather than picking up the system language and producing a German string in
/// an otherwise English panel.
enum BatteryRuntimeFormatter {
    /// Beyond these the estimate says more about a noisy rate than about the
    /// headset, which neither runs nor charges this long.
    static let dischargeLimit: TimeInterval = 24 * 3600
    static let chargeLimit: TimeInterval = 12 * 3600

    /// `"≈ 5h 20m left"` or `"≈ 1h 40m to full"`, or nil when the estimate is
    /// not worth showing.
    static func text(for projection: BatteryEstimator.Projection) -> String? {
        let limit: TimeInterval
        let suffix: String
        switch projection {
        case .untilEmpty:
            limit = dischargeLimit
            suffix = "left"
        case .untilFull:
            limit = chargeLimit
            suffix = "to full"
        }

        let seconds = projection.seconds
        guard seconds > 60, seconds <= limit else { return nil }
        guard let formatted = formatter.string(from: seconds) else { return nil }
        return "≈ \(formatted) \(suffix)"
    }

    private static let formatter: DateComponentsFormatter = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}
