import Foundation

struct LiveUsage: Decodable {
    let updated_at: Double?
    let session_used_pct: Double?
    let session_resets_at: Double?
    let week_used_pct: Double?
    let week_resets_at: Double?
    let session_cost_usd: Double?
    let model: String?
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var sessionPct: Double?
    @Published var sessionResetsAt: Date?
    @Published var weekPct: Double?
    @Published var weekResetsAt: Date?
    @Published var liveUpdatedAt: Date?
    @Published var model: String?
    /// The last refresh found Claude Code signed out; the menu bar item and the pinned widget say so instead of showing old numbers.
    @Published var signedOut = false
    /// No refresh has finished yet since Cap started: the pinned widget says it is getting the first reading.
    @Published var awaitingFirstReading = true

    @Published var now: Date = Date()

    private let liveURL = URL(fileURLWithPath: NSString(string: "~/.claude_usage_widget/live.json").expandingTildeInPath)

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        now = Date()
        loadLive()
    }

    private func loadLive() {
        guard let data = try? Data(contentsOf: liveURL) else { return }
        guard let decoded = try? JSONDecoder().decode(LiveUsage.self, from: data) else { return }
        sessionPct = decoded.session_used_pct
        sessionResetsAt = decoded.session_resets_at.map { Date(timeIntervalSince1970: $0) }
        weekPct = decoded.week_used_pct
        weekResetsAt = decoded.week_resets_at.map { Date(timeIntervalSince1970: $0) }
        liveUpdatedAt = decoded.updated_at.map { Date(timeIntervalSince1970: $0) }
        model = decoded.model
    }
}

enum UsageFormat {
    static func percent(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    static func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "resetting…" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "resets in \(hours)h \(minutes)m"
    }

    /// "3h 42m remaining" — used for the 5-hour session row in the popover.
    static func remaining(to date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Resetting…" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m remaining" : "\(minutes)m remaining"
    }

    /// "Resets Thursday" — used for the weekly row. Says "today"/"tomorrow" when
    /// close, and "next Thu" when the reset falls on today's weekday a
    /// week out, so a bare weekday name is never ambiguous.
    static func resetDay(of date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Resets today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "Resets tomorrow"
        }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEEE")
        let weekday = fmt.string(from: date)
        let sameWeekdayAsToday = cal.component(.weekday, from: date) == cal.component(.weekday, from: now)
        if sameWeekdayAsToday {
            // "Resets next Thursday" is too wide for the 268pt panel; abbreviate.
            let short = DateFormatter()
            short.setLocalizedDateFormatFromTemplate("EEE")
            return "Resets next \(short.string(from: date))"
        }
        return "Resets \(weekday)"
    }

    /// "Resets at 9:41 PM" — wall-clock reset time in the user's own locale/12-24h setting.
    static func resetTime(of date: Date?, from now: Date) -> String? {
        guard let date, date.timeIntervalSince(now) > 0 else { return nil }
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return "Resets at \(fmt.string(from: date))"
    }

    /// "2h 17m left" — pinned widget wording.
    static func left(to date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Resetting…" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m left" : "\(minutes)m left"
    }

    /// "2:40 PM" — bare wall-clock reset time, in the user's own time format.
    static func clockTime(of date: Date?, from now: Date) -> String? {
        guard let date, date.timeIntervalSince(now) > 0 else { return nil }
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    /// "Next Thu" — weekly reset in the pinned widget ("Today"/"Tomorrow" when close).
    static func nextDay(of date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEE")
        return "Next \(fmt.string(from: date))"
    }
}
