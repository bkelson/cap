import Foundation
import UserNotifications

/// Limit alerts (welcome step 3, Settings). A notification fires once when the session or the week crosses
/// the user's threshold, and is armed again after that window resets.
@MainActor
final class UsageAlerts {
    private let preferences: Preferences
    private let store: UsageStore
    private var timer: Timer?

    init(preferences: Preferences, store: UsageStore) {
        self.preferences = preferences
        self.store = store
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Asks macOS for permission with its own dialog. Calls back on the main actor with whether alerts are allowed.
    static func requestPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else { Task { @MainActor in done(false) }; return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    private func check() {
        guard preferences.notificationsEnabled else { return }
        evaluate(kind: "session", pct: store.sessionPct, resetsAt: store.sessionResetsAt,
                 threshold: preferences.sessionAlertPercent, title: "Session limit")
        evaluate(kind: "week", pct: store.weekPct, resetsAt: store.weekResetsAt,
                 threshold: preferences.weeklyAlertPercent, title: "Weekly limit")
        checkLoginEnd()
    }

    // MARK: Sign-in ending soon

    /// The saved Claude Code sign-in has a built-in end date (see `LoginExpiry`). One notice a week ahead and a firmer one
    /// two days ahead, each sent once per sign-in (keyed by the end date, so a renewed sign-in starts fresh).
    private func checkLoginEnd() {
        guard let end = preferences.loginEndsAt else { return }
        let key = "loginNudge.\(Int(end.timeIntervalSince1970))"
        let done = UserDefaults.standard.integer(forKey: key)
        guard let level = LoginExpiry.notificationDue(daysLeft: LoginExpiry.daysLeft(endsAt: end, now: Date()), done: done) else { return }
        UserDefaults.standard.set(level, forKey: key)
        Self.postLoginEnding(endsAt: end, now: Date())
    }

    /// DRAFT copy (not yet approved). Click opens the popover at the renewal strip.
    static func postLoginEnding(endsAt: Date, now: Date) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your Claude Code sign-in \(LoginExpiry.phrase(endsAt: endsAt, now: now))"
        content.body = "Click here to renew it. It takes about a minute."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cap.loginending", content: content, trigger: nil))
    }

    /// What to do with one reading. Pure, so it can be tested. A notification fires when usage is at or above the
    /// threshold and none has fired yet in this reset window. Once usage is seen BELOW the threshold again (the user
    /// raised it, or a new window began) the alert is armed again, so changing a threshold in Settings works.
    /// `firedWindow` is the reset time of the window an alert last fired in (0 = none).
    static func decide(pct: Double?, resetsAt: Date?, threshold: Int, firedWindow: Int) -> (fire: Bool, firedWindow: Int) {
        guard let pct, let resetsAt else { return (false, firedWindow) }
        let windowID = Int(resetsAt.timeIntervalSince1970)
        if pct < Double(threshold) { return (false, firedWindow == windowID ? 0 : firedWindow) }   // below: re-arm
        if firedWindow == windowID { return (false, firedWindow) }                                  // already told them
        return (true, windowID)
    }

    // MARK: Signed-out notice

    enum SignInEvent { case lost, recovered, other }

    /// One notice per lapse. `lost` tells the user once; `recovered` (a good reading again) arms it for the next lapse;
    /// anything else (a first launch, a one-off failure) changes nothing, so restarting Cap while still signed out
    /// does not repeat the notice.
    static func decideSignedOut(_ event: SignInEvent, alreadyNotified: Bool) -> (fire: Bool, notified: Bool) {
        switch event {
        case .lost: return (!alreadyNotified, true)
        case .recovered: return (false, false)
        case .other: return (false, alreadyNotified)
        }
    }

    /// Called when the refresh status changes. Uses the same notification permission and the same on/off switch as the limit alerts.
    /// A new Cap release exists (once per version; the caller checks the notifications switch). Click opens Settings → Updates.
    static func postUpdateAvailable(version: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Cap \(version) is available"           // approved copy (T7), 2026-10-28
        content.body = "Click here to see what's new."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cap.update", content: content, trigger: nil))
    }

    func signInChanged(_ event: SignInEvent) {
        let key = "signedOutNotified"
        if event == .lost && !preferences.notificationsEnabled { return }
        let result = Self.decideSignedOut(event, alreadyNotified: UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.set(result.notified, forKey: key)
        guard result.fire, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Signed out of Claude Code"                                  // approved copy (A11), 2026-10-26
        content.body = "Your numbers are paused. Click here to sign in again."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cap.signedout", content: content, trigger: nil))
    }

    private func evaluate(kind: String, pct: Double?, resetsAt: Date?, threshold: Int, title: String) {
        let key = "alertFired.\(kind)"
        let result = Self.decide(pct: pct, resetsAt: resetsAt, threshold: threshold,
                                 firedWindow: UserDefaults.standard.integer(forKey: key))
        UserDefaults.standard.set(result.firedWindow, forKey: key)
        guard result.fire, let pct, let resetsAt else { return }
        let windowID = Int(resetsAt.timeIntervalSince1970)
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "You've used \(Int(pct.rounded()))% (alert set at \(threshold)%)."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "cap.\(kind).\(windowID)", content: content, trigger: nil))
    }
}
