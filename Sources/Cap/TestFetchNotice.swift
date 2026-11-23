#if CAP_TEST_BUILD
import Foundation
import UserNotifications

/// TEST BUILDS ONLY. A notification every time Cap fetches, so you can see what it is doing and how often.
/// Compiled only with `-Xswiftc -DCAP_TEST_BUILD` (the dev bundle); `scripts/make-dmg.sh` builds without it, so the
/// installer never contains this. Turn it off without rebuilding: `touch ~/.claude_usage_widget/no-fetch-notice`
/// (delete the file to turn it back on).
enum TestFetchNotice {
    private static var offSwitch: URL { StatusLineHook.supportDirectory().appendingPathComponent("no-fetch-notice") }

    static func post(outcome: UsageFetcher.Outcome, intervalSeconds: Int, seconds: TimeInterval, waited: Int) {
        guard !FileManager.default.fileExists(atPath: offSwitch.path), Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        var detail: String
        switch outcome {
        case .reading(let r):
            content.title = "Cap fetched"
            detail = "Session \(UsageFormat.percent(r.sessionPct)) · Week \(UsageFormat.percent(r.weekPct))"
        case .notSignedIn: content.title = "Cap fetch: signed out"; detail = "Claude Code has no login"
        case .sessionExpired: content.title = "Cap fetch: login expired"; detail = "Claude Code's saved login ran out"
        case .noLimits: content.title = "Cap fetch: no limits"; detail = "Call worked, no usage numbers in it"
        case .offline: content.title = "Cap fetch: offline"; detail = "Couldn't reach Claude"
        case .busy: content.title = "Cap fetch: busy"; detail = "Another Claude program was renewing the login"
        case .failed(let why): content.title = "Cap fetch failed"; detail = why
        }
        detail += " · \(String(format: "%.1f", seconds)) s · every \(intervalSeconds) s"
        if waited > 0 { detail += " · waited \(waited)×5 s for another Claude" }
        content.body = detail
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cap.testfetch.\(UUID().uuidString)", content: content, trigger: nil))
    }
}
#endif
