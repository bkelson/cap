import Foundation

/// What one background refresh costs, as a share of the user's limits.
/// ESTIMATE, NOT FINAL (2026-10-12): scaled from the old placeholder (0.026 / 0.004, from the ~27,000-token call) by
/// token count, because the lean call sends ~540 tokens (about 2%). Consistent with the refresh log, which only proves
/// an upper bound (under 0.062 of a point per refresh, whole-percent resolution). MUST be re-measured with
/// scripts/measure-refresh-cost.sh 300 in a quiet 20-minute window before launch, then update these two numbers
/// and the matching checks in scripts/harness-model.swift.
enum RefreshCost {
    static let sessionPercentPerRefresh = 0.0005
    static let weeklyPercentPerRefresh = 0.0001

    /// The design's assumption for the weekly figure: 40 hours of use a week.
    static let activeSecondsPerWeek = 144_000.0
    static let secondsPerSession = 18_000.0

    /// About how much of one 5-hour session the refreshes use at a given interval.
    static func sessionPercent(everySeconds seconds: Int) -> Double {
        secondsPerSession / Double(max(seconds, 1)) * sessionPercentPerRefresh
    }

    /// About how much of the weekly limit the refreshes use, over a typical week.
    static func weeklyPercent(everySeconds seconds: Int) -> Double {
        activeSecondsPerWeek / Double(max(seconds, 1)) * weeklyPercentPerRefresh
    }

    /// "5m", "45s", "2m 15s".
    static func intervalLabel(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if m == 0 { return "\(s)s" }
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }

    /// "≈0.13" with two decimals, one decimal from 10% up.
    static func percentLabel(_ value: Double) -> String {
        value >= 10 ? String(format: "≈%.1f", value) : String(format: "≈%.2f", value)
    }
}
