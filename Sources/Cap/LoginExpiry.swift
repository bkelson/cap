import Foundation

/// When the saved Claude Code sign-in ends.
///
/// Measured 2026-11-12 (research/login-expiry): a claude.ai sign-in has a built-in lifetime of about 28 days. Right after
/// signing in, the saved login said it ends 28.14 days later, and the previous login lapsed 28 days after it was made.
/// Using the login does not move that date. No amount of careful refreshing can stop it, but it can be seen coming:
/// Claude Code 2.1.318 and later put the end date in every `claude -p` result as `credential_expires_at` (an ISO 8601 date).
/// That is official output and needs no token, so Cap can warn in good time and offer a one-click renewal before the
/// login ends, instead of the numbers stopping without warning.
enum LoginExpiry {
    /// Cap starts offering to renew this many days before the end. Claude Code's own startup warning begins at 3 days
    /// (documented) or 10 days (2.1.318 print mode); a week leaves room to pick a convenient moment.
    static let renewOfferDays: Double = 7
    /// A second, firmer notification this many days before the end.
    static let finalNoticeDays: Double = 2

    /// "2026-12-10T11:59:07.138Z" to seconds since 1970. Nil when it isn't a date.
    static func parse(_ text: String) -> Double? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: text) { return d.timeIntervalSince1970 }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)?.timeIntervalSince1970
    }

    /// Days left (fractional); nil when the end date is not known.
    static func daysLeft(endsAt: Date?, now: Date) -> Double? {
        endsAt.map { $0.timeIntervalSince(now) / 86_400 }
    }

    /// The popover offers a renewal once the end is within `renewOfferDays` (and keeps offering it until it has passed).
    static func shouldOfferRenewal(endsAt: Date?, now: Date) -> Bool {
        guard let left = daysLeft(endsAt: endsAt, now: now) else { return false }
        return left <= renewOfferDays && left > 0
    }

    /// "ends in 5 days" / "ends tomorrow" / "ends today" (whole days, rounded up, so it never says 0 days with time left).
    static func phrase(endsAt: Date, now: Date) -> String {
        let left = endsAt.timeIntervalSince(now) / 86_400
        let days = Int(left.rounded(.up))
        if days <= 0 { return "ends today" }
        if days == 1 { return "ends tomorrow" }
        return "ends in \(days) days"
    }

    /// Which notification, if any, is due. `done` is the highest level already sent for this sign-in
    /// (0 none, 1 the week-ahead notice, 2 the final notice). Returns the level to send now.
    static func notificationDue(daysLeft: Double?, done: Int) -> Int? {
        guard let left = daysLeft, left > 0 else { return nil }
        if left <= finalNoticeDays && done < 2 { return 2 }
        if left <= renewOfferDays && done < 1 { return 1 }
        return nil
    }
}
