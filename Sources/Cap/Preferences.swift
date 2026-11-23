import Foundation
import Combine
import CoreGraphics

enum PinnedLayout: String, CaseIterable {
    case small, medium, strip

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .strip: return "Strip"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    @Published var showInlineMenuBarStats: Bool {
        didSet { store.set(showInlineMenuBarStats, forKey: "showInlineMenuBarStats") }
    }

    @Published var isPinned: Bool {
        didSet { store.set(isPinned, forKey: "isPinned") }
    }

    @Published var pinnedLayout: PinnedLayout {
        didSet { store.set(pinnedLayout.rawValue, forKey: "pinnedLayout") }
    }

    /// On: the pinned widget floats above app windows on all Spaces.
    /// Off: it sits at normal window level, behind active windows.
    @Published var alwaysOnTop: Bool {
        didSet { store.set(alwaysOnTop, forKey: "alwaysOnTop") }
    }

    /// Set when the first-run welcome window has been finished.
    @Published var hasCompletedOnboarding: Bool {
        didSet { store.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    /// How often the background feeder refreshes the numbers, in seconds .
    /// How often Cap asks Claude Code for the numbers while you are at the Mac. Fixed (Brian, 2026-10-29): there is no
    /// setting for it, because the cost is negligible. `refreshIntervalSeconds` below is the old setting, kept only so
    /// older saved values still load; nothing reads it for scheduling any more.
    static let fixedRefreshIntervalSeconds = 15
    static let refreshIntervalRange = 15...600
    static let refreshIntervalStep = 15
    static let defaultRefreshIntervalSeconds = 300
    @Published var refreshIntervalSeconds: Int {
        didSet { store.set(refreshIntervalSeconds, forKey: "refreshIntervalSeconds") }
    }

    /// Limit alerts (welcome step 3 / Settings). Off until the user turns them on and macOS allows them.
    @Published var notificationsEnabled: Bool {
        didSet { store.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var sessionAlertPercent: Int {
        didSet { store.set(sessionAlertPercent, forKey: "sessionAlertPercent") }
    }
    @Published var weeklyAlertPercent: Int {
        didSet { store.set(weeklyAlertPercent, forKey: "weeklyAlertPercent") }
    }

    /// Software updates (Settings → Updates). The check asks GitHub for the latest release once a day; off until the user turns it on.
    @Published var checkForUpdatesAutomatically: Bool {
        didSet { store.set(checkForUpdatesAutomatically, forKey: "checkForUpdatesAutomatically") }
    }
    /// When the last *successful* check finished.
    @Published var lastUpdateCheck: Date? {
        didSet { store.set(lastUpdateCheck, forKey: "lastUpdateCheck") }
    }
    /// When the last attempt (successful or not) ran.
    @Published var lastUpdateAttempt: Date? {
        didSet { store.set(lastUpdateAttempt, forKey: "lastUpdateAttempt") }
    }
    /// Whether the most recent attempt failed (offline, GitHub down). Neutral in the UI.
    @Published var lastUpdateCheckFailed: Bool {
        didSet { store.set(lastUpdateCheckFailed, forKey: "lastUpdateCheckFailed") }
    }
    @Published var latestVersion: String? {
        didSet { store.set(latestVersion, forKey: "latestVersion") }
    }
    @Published var latestReleaseURL: String? {
        didSet { store.set(latestReleaseURL, forKey: "latestReleaseURL") }
    }
    @Published var latestDownloadURL: String? {
        didSet { store.set(latestDownloadURL, forKey: "latestDownloadURL") }
    }
    /// The newest version whose "is available" notification has been sent (once per version).
    var lastNotifiedVersion: String? {
        get { store.string(forKey: "lastNotifiedVersion") }
        set { store.set(newValue, forKey: "lastNotifiedVersion") }
    }
    /// The version the user has already looked at in Settings → Updates; the gear's dot clears for it.
    @Published var updateSeenVersion: String? {
        didSet { store.set(updateSeenVersion, forKey: "updateSeenVersion") }
    }

    /// When the saved Claude Code sign-in ends, as last reported by Claude Code 2.1.318 or later (nil when unknown or signed out).
    /// Only a date; see `LoginExpiry`.
    @Published var loginEndsAt: Date? {
        didSet { store.set(loginEndsAt, forKey: "loginEndsAt") }
    }

    /// A newer version than the running one is known.
    var updateAvailable: Bool { latestVersion.map { UpdateChecker.isNewer($0, than: UpdateChecker.currentVersion) } ?? false }
    /// The red dot on the popover's Settings icon.
    var updateDotVisible: Bool { updateAvailable && updateSeenVersion != latestVersion }

    /// Snaps a number of seconds onto the slider's grid (15 s steps, 15 s to 10 min).
    static func snappedInterval(_ seconds: Int) -> Int {
        let clamped = min(max(seconds, refreshIntervalRange.lowerBound), refreshIntervalRange.upperBound)
        return Int((Double(clamped) / Double(refreshIntervalStep)).rounded()) * refreshIntervalStep
    }

    /// Top-left corner of the pinned widget, remembered per display.
    func pinnedTopLeft(display: String) -> CGPoint? {
        guard let all = store.dictionary(forKey: "pinnedTopLeft") as? [String: [Double]],
              let xy = all[display], xy.count == 2 else { return nil }
        return CGPoint(x: xy[0], y: xy[1])
    }

    func setPinnedTopLeft(_ point: CGPoint, display: String) {
        var all = (store.dictionary(forKey: "pinnedTopLeft") as? [String: [Double]]) ?? [:]
        all[display] = [point.x, point.y]
        store.set(all, forKey: "pinnedTopLeft")
    }

    /// Where settings live. The welcome-window preview passes its own throwaway store so it can never change real settings.
    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        showInlineMenuBarStats = store.bool(forKey: "showInlineMenuBarStats")
        isPinned = store.bool(forKey: "isPinned")
        pinnedLayout = PinnedLayout(rawValue: store.string(forKey: "pinnedLayout") ?? "") ?? .medium
        alwaysOnTop = store.bool(forKey: "alwaysOnTop")
        // The widget always follows the system now; drop any earlier "Custom" choice so nobody is stuck on it.
        for key in ["useCustomWidgetAppearance", "customWidgetStyle", "customWidgetMode", "customWidgetTint"] { store.removeObject(forKey: key) }
        hasCompletedOnboarding = store.bool(forKey: "hasCompletedOnboarding")
        checkForUpdatesAutomatically = store.object(forKey: "checkForUpdatesAutomatically") as? Bool ?? false   // off until the user turns it on
        lastUpdateCheck = store.object(forKey: "lastUpdateCheck") as? Date
        lastUpdateCheckFailed = store.bool(forKey: "lastUpdateCheckFailed")
        lastUpdateAttempt = store.object(forKey: "lastUpdateAttempt") as? Date
        latestVersion = store.string(forKey: "latestVersion")
        latestReleaseURL = store.string(forKey: "latestReleaseURL")
        latestDownloadURL = store.string(forKey: "latestDownloadURL")
        updateSeenVersion = store.string(forKey: "updateSeenVersion")
        loginEndsAt = store.object(forKey: "loginEndsAt") as? Date
        let defaults = store
        // Older builds stored whole minutes; carry that choice over as seconds.
        if defaults.object(forKey: "refreshIntervalSeconds") != nil {
            refreshIntervalSeconds = Preferences.snappedInterval(defaults.integer(forKey: "refreshIntervalSeconds"))
        } else if defaults.object(forKey: "refreshIntervalMinutes") != nil {
            refreshIntervalSeconds = Preferences.snappedInterval(defaults.integer(forKey: "refreshIntervalMinutes") * 60)
        } else {
            refreshIntervalSeconds = Preferences.defaultRefreshIntervalSeconds
        }
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        sessionAlertPercent = defaults.object(forKey: "sessionAlertPercent") == nil ? 80 : defaults.integer(forKey: "sessionAlertPercent")
        weeklyAlertPercent = defaults.object(forKey: "weeklyAlertPercent") == nil ? 75 : defaults.integer(forKey: "weeklyAlertPercent")
    }
}
