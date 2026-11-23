import Foundation
import AppKit

var failures = 0
func check(_ ok: Bool, _ name: String) { print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1 } }
func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
final class Counter2: @unchecked Sendable { private let l = NSLock(); private var c = 0; func bump() { l.lock(); c += 1; l.unlock() }; var n: Int { l.lock(); defer { l.unlock() }; return c } }
func waitUntil(_ timeout: Double, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end { if cond() { return true }; spin(0.1) }
    return cond()
}

let SIGNED_IN = #"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"pro"}"#
let SIGNED_OUT = #"{"loggedIn":false}"#
func fakeBody(login: String) -> String { """
#!/bin/sh
D="$(dirname "$0")"
case "$*" in *" -p"*|"-p"*)
  read -r _l
  if grep -q '"loggedIn":true' "$D/auth.json"; then
    echo '{"type":"system","subtype":"init"}'
    echo '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.25,"resetsAt":4102444800},"seven_day":{"utilization":0.5,"resetsAt":4102444800}}}}'
    echo '{"type":"result","subtype":"success","is_error":false,"result":"OK"}'
  else
    echo '{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}'
  fi
  exit 0 ;;
esac
if [ "$1" = "--version" ]; then echo "9.9.9 (Claude Code)"; exit 0; fi
if [ "$1" = "auth" ] && [ "$2" = "login" ]; then
  case "\(login)" in
    hang) sleep 600; exit 1 ;;
    fail) sleep 1; exit 1 ;;
    *)    sleep 2; echo '\(SIGNED_IN)' > "$D/auth.json"; exit 0 ;;
  esac
fi
if [ "$1" = "auth" ]; then cat "$D/auth.json"; exit 0; fi
exit 0
""" }

@MainActor func run() {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capflow2-\(UUID().uuidString.prefix(6))")
    func suite() -> Preferences {
        let name = "ai.kelson.cap.test.\(UUID().uuidString.prefix(6))"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name)
        return Preferences(store: d)
    }
    func home(_ n: String) -> URL {
        let h = tmp.appendingPathComponent(n)
        try! fm.createDirectory(at: h.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let cap = h.appendingPathComponent("Cap.app/Cap"); try! fm.createDirectory(at: cap.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: cap.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return h
    }
    func installStandalone(_ h: URL, auth: String, login: String = "ok") {
        let dir = h.appendingPathComponent(".local/bin"); try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fm.createFile(atPath: dir.appendingPathComponent("claude").path, contents: Data(fakeBody(login: login).utf8), attributes: [.posixPermissions: 0o755])
        try! auth.write(to: dir.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
    }
    func installDesktopApp(_ h: URL) { try! fm.createDirectory(at: h.appendingPathComponent("Applications/Claude.app"), withIntermediateDirectories: true) }
    func installBuiltIn(_ h: URL, auth: String, login: String = "ok") {
        let dir = h.appendingPathComponent("Library/Application Support/Claude/claude-code/9.9.9/abc/claude.app/Contents/MacOS")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fm.createFile(atPath: dir.appendingPathComponent("claude").path, contents: Data(fakeBody(login: login).utf8), attributes: [.posixPermissions: 0o755])
        try! auth.write(to: dir.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
    }
    func model(_ h: URL, prefs: Preferences, attention: @escaping () -> Void = {}, signedIn: @escaping () -> Void = {}) -> OnboardingModel {
        OnboardingModel(preferences: prefs, claudeHome: h,
                        applicationFolders: [h.appendingPathComponent("Applications")], isPreview: true,
                        onNeedsAttention: attention, onSignedIn: signedIn)
    }
    func check1(_ m: OnboardingModel) { m.refresh(); spin(1.2) }

    func isSub(_ m: OnboardingModel) -> Bool { if case .subscription = m.auth { return true }; return false }
    func isFailedSignIn(_ m: OnboardingModel) -> Bool { if case .signInFailed = m.auth { return true }; return false }
    // 1. Desktop-only walk: nothing -> app -> built-in Claude Code (no login of its own) -> sign in
    do {
        let h = home("walk"); var attention = 0, ready = 0
        let m = model(h, prefs: suite(), attention: { attention += 1 }, signedIn: { ready += 1 }); m.step = 1
        check1(m)
        check(m.claude == .missing && m.auth == .waiting && !m.row1Green && !m.row2Green, "nothing installed: row 1 missing, row 2 waiting")
        check(attention == 0, "no bring-to-front on the first check")
        installDesktopApp(h); check1(m)
        check(m.claude == .desktopNotReady && m.row1Green && !m.row2Green, "Claude app installed: row 1 green, row 2 still waiting")
        check(attention == 1, "row 1 turning green brings the window forward (once)")
        check1(m); check(attention == 1, "no repeat while nothing changes")
        installBuiltIn(h, auth: SIGNED_OUT); check1(m)
        check(m.auth == .needsSignIn && !m.row2Green && !m.canContinue, "built-in Claude Code present but no login of its own: needs sign-in, Continue blocked")
        m.signIn()
        check(m.auth == .signingIn, "Sign in to Claude Code starts the browser sign-in")
        _ = waitUntil(15) { isSub(m) }
        check(isSub(m) && m.row2Green && m.canContinue, "sign-in done: row 2 green, Continue enabled")
        check(attention >= 2 && ready == 1, "window brought forward again; the first refresh was triggered once")
        m.stop()
    }
    // 2. Standalone claude: signed out -> sign in with the button
    do {
        let h = home("standalone"); var attention = 0
        installStandalone(h, auth: SIGNED_OUT)
        let m = model(h, prefs: suite(), attention: { attention += 1 }); m.step = 1
        check1(m)
        check(m.auth == .notSignedIn && m.row1Green && !m.row2Green, "standalone, signed out: amber 'not signed in'")
        m.signIn(); _ = waitUntil(15) { isSub(m) }
        check(isSub(m) && attention == 1, "Sign in to Claude Code works here too, and brings the window forward")
        m.stop()
    }
    // 3. Already signed in through Terminal: nothing to do
    do {
        let h = home("terminal"); installStandalone(h, auth: SIGNED_IN); var ready = 0
        let m = model(h, prefs: suite(), signedIn: { ready += 1 }); m.step = 1; check1(m)
        check(isSub(m) && m.canContinue, "Terminal login: both rows green, no extra step")
        m.stop()
    }
    // 4. Sign-in failure, then retry
    do {
        let h = home("fail"); installDesktopApp(h); installBuiltIn(h, auth: SIGNED_OUT, login: "fail")
        let m = model(h, prefs: suite()); m.step = 1; check1(m)
        m.signIn(); _ = waitUntil(15) { isFailedSignIn(m) }
        check(isFailedSignIn(m) && !m.canContinue && m.step == 1, "failed sign-in: message shown, stays on step 2, Continue blocked")
        installBuiltIn(h, auth: SIGNED_OUT, login: "ok")
        m.signIn(); _ = waitUntil(15) { isSub(m) }
        check(isSub(m), "Try again succeeds")
        m.stop()
    }
    // 5. Cancel while the browser step hangs
    do {
        let h = home("hang"); installDesktopApp(h); installBuiltIn(h, auth: SIGNED_OUT, login: "hang")
        let m = model(h, prefs: suite()); m.step = 1; check1(m)
        m.signIn(); spin(1.0); check(m.auth == .signingIn, "hanging sign-in is running")
        m.cancelSignIn(); _ = waitUntil(5) { m.auth == .needsSignIn }
        check(m.auth == .needsSignIn, "Cancel returns the row to 'needs sign-in'")
        spin(0.5)
        let leftover = Process(); leftover.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); leftover.arguments = ["-f", "capflow2-.*hang.*auth login"]
        let pipe = Pipe(); leftover.standardOutput = pipe; try? leftover.run(); leftover.waitUntilExit()
        check(pipe.fileHandleForReading.readDataToEndOfFile().isEmpty, "no sign-in process left running")
        m.signIn(); spin(1.0); m.goBack(); _ = waitUntil(5) { m.auth == .needsSignIn }
        check(m.auth == .needsSignIn && m.step == 0, "Back also cancels a running sign-in")
        m.stop()
    }
    // 6. Five steps, Continue gated on step 2
    do {
        let h = home("steps"); installStandalone(h, auth: SIGNED_IN)
        let p = suite(); let m = model(h, prefs: p); m.step = 1; check1(m)
        m.advance(); check(m.step == 2, "step 2 → step 3 when signed in")
        m.advance(); check(m.step == 3, "→ step 4")
        m.advance(); check(m.step == 4 && m.primaryTitle == "Done", "→ step 5, button reads Done")
        var done = false
        let m2 = OnboardingModel(preferences: p, claudeHome: h, isPreview: true, onFinish: { done = true })
        m2.step = 4; m2.advance(); check(done && p.hasCompletedOnboarding, "Done finishes and sets hasCompletedOnboarding")
        check(OnboardingModel.stepCount == 5, "five steps")
        let h2 = home("steps2"); installDesktopApp(h2)
        let m3 = model(h2, prefs: suite()); m3.step = 1; check1(m3); m3.advance()
        check(m3.step == 1, "step 2 does not advance before the sign-in")
        m3.stop()
    }
    // 8. Notifications: denied (no bundle in this harness, so macOS can't grant) turns the switch back off
    do {
        let p = suite(); let m = model(home("notif"), prefs: p)
        m.setNotifications(true); spin(0.5)
        check(!p.notificationsEnabled && m.notificationsDenied == 1, "permission denied → switch back off")
        p.notificationsEnabled = true; m.setNotifications(false); check(!p.notificationsEnabled, "switch off → disabled")
    }
    // 9. Preferences migration and clamping
    do {
        func prefs(_ setup: (UserDefaults) -> Void) -> Preferences {
            let name = "ai.kelson.cap.test.\(UUID().uuidString.prefix(6))"
            let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name); setup(d); return Preferences(store: d)
        }
        check(prefs { $0.set(10, forKey: "refreshIntervalMinutes") }.refreshIntervalSeconds == 600, "10 min (old setting) → 600 s")
        check(prefs { $0.set(5, forKey: "refreshIntervalMinutes") }.refreshIntervalSeconds == 300, "5 min → 300 s")
        check(prefs { $0.set(30, forKey: "refreshIntervalMinutes") }.refreshIntervalSeconds == 600, "30 min (above the new range) → clamped to 600 s")
        check(prefs { _ in }.refreshIntervalSeconds == 300, "fresh install → 300 s")
        check(prefs { $0.set(100, forKey: "refreshIntervalSeconds") }.refreshIntervalSeconds == 105, "100 s snaps to the 15 s grid (105)")
        check(prefs { $0.set(3, forKey: "refreshIntervalSeconds") }.refreshIntervalSeconds == 15, "3 s clamps up to 15 s")
        let a = prefs { _ in }; check(a.sessionAlertPercent == 80 && a.weeklyAlertPercent == 75 && !a.notificationsEnabled, "alert defaults 80 / 75 / off")
    }
    // 10. Cost labels
    check(RefreshCost.intervalLabel(300) == "5m" && RefreshCost.intervalLabel(45) == "45s" && RefreshCost.intervalLabel(135) == "2m 15s", "interval labels 5m / 45s / 2m 15s")
    check(RefreshCost.percentLabel(1.5600001) == "≈1.56" && RefreshCost.percentLabel(12.34) == "≈12.3", "percent labels: 2 decimals, 1 from 10%")
    check(abs(RefreshCost.sessionPercent(everySeconds: 300) - 0.03) < 0.0001 && abs(RefreshCost.weeklyPercent(everySeconds: 300) - 0.048) < 0.0001, "estimated cost at 5 min: 0.03% / 0.048% (NOT FINAL, re-measure before launch)")

    // 11. Signed-out wording and the popover's own sign-in button
    do {
        func resultLine(_ text: String) -> Data { Data(#"{"type":"result","is_error":true,"result":"\#(text)"}"#.utf8) }
        check(UsageFetcher.parse(resultLine("Not logged in · Please run /login")) == .notSignedIn, "wording 1 (never signed in) → signed out")
        check(UsageFetcher.parse(resultLine("Failed to authenticate: OAuth session expired and could not be refreshed")) == .sessionExpired, "wording 2 (expired session, seen live 12 Oct) → signed out (expiry)")
        check(UsageFetcher.parse(resultLine("Some other failure")) != .notSignedIn && UsageFetcher.parse(resultLine("Some other failure")) != .sessionExpired, "an unrelated error is not mistaken for signed out")
        let signed = Counter2()
        let ok = SignInController(resolveClaude: { "/fake/claude" }, runSignIn: { _, _ in .signedIn }, onSignedIn: { signed.bump() })
        ok.start(); check(ok.state == .signingIn, "button press → signing in")
        _ = waitUntil(3) { ok.state == .finishing }
        check(ok.state == .finishing && signed.n == 1, "sign-in done → 'getting your numbers' (no button flash), refresh triggered once")
        ok.refreshDone()
        check(ok.state == .idle, "the first refresh answered → back to idle")
        ok.refreshDone()
        check(ok.state == .idle, "an extra refreshDone changes nothing")
        let bad = SignInController(resolveClaude: { "/fake/claude" }, runSignIn: { _, _ in .failed("nope") }, onSignedIn: { signed.bump() })
        bad.start(); _ = waitUntil(3) { bad.state != .signingIn }
        check(bad.state == .failed("nope") && signed.n == 1, "failed sign-in → message shown, no refresh")
        let none = SignInController(resolveClaude: { nil }, runSignIn: { _, _ in .signedIn }, onSignedIn: {})
        none.start(); _ = waitUntil(3) { none.state != .signingIn }
        if case .failed = none.state { check(true, "Claude Code not found → failure message") } else { check(false, "not found") }
        let hang = SignInController(resolveClaude: { "/fake/claude" }, runSignIn: { _, cancelled in while !cancelled() { Thread.sleep(forTimeInterval: 0.05) }; return .cancelled }, onSignedIn: {})
        hang.start(); spin(0.3); hang.start()   // a second press while waiting changes nothing
        check(hang.state == .signingIn, "second press while waiting is ignored")
        hang.cancel(); _ = waitUntil(3) { hang.state == .idle }
        check(hang.state == .idle, "Cancel → idle")
    }

    // 12. Limit alerts: fire once per window, re-arm when the threshold is raised above usage
    do {
        let w1 = Date(timeIntervalSince1970: 1_800_000_000), w2 = Date(timeIntervalSince1970: 1_800_018_000)
        var fired = 0
        var r = UsageAlerts.decide(pct: 10, resetsAt: w1, threshold: 5, firedWindow: fired)
        check(r.fire, "usage 10% at a 5% threshold: alert fires"); fired = r.firedWindow
        r = UsageAlerts.decide(pct: 11, resetsAt: w1, threshold: 5, firedWindow: fired)
        check(!r.fire, "same window, still above: no second alert"); fired = r.firedWindow
        r = UsageAlerts.decide(pct: 11, resetsAt: w1, threshold: 80, firedWindow: fired)
        check(!r.fire && r.firedWindow == 0, "threshold raised above usage: re-armed, no alert yet"); fired = r.firedWindow
        r = UsageAlerts.decide(pct: 80, resetsAt: w1, threshold: 80, firedWindow: fired)
        check(r.fire, "usage then reaches the new threshold: alert fires (the B.19 case)"); fired = r.firedWindow
        r = UsageAlerts.decide(pct: 82, resetsAt: w1, threshold: 80, firedWindow: fired)
        check(!r.fire, "no repeat in the same window")
        r = UsageAlerts.decide(pct: 85, resetsAt: w2, threshold: 80, firedWindow: fired)
        check(r.fire, "a new window arms it again")
        check(!UsageAlerts.decide(pct: nil, resetsAt: nil, threshold: 80, firedWindow: 0).fire, "no reading: nothing happens")
    }

    // Signed-out notice: once per lapse, not repeated by a restart, armed again by a good reading.
    do {
        var r = UsageAlerts.decideSignedOut(.lost, alreadyNotified: false)
        check(r.fire && r.notified, "signed-out notice: fires when the login is lost")
        r = UsageAlerts.decideSignedOut(.lost, alreadyNotified: r.notified)
        check(!r.fire && r.notified, "signed-out notice: not repeated while still signed out")
        r = UsageAlerts.decideSignedOut(.other, alreadyNotified: r.notified)
        check(!r.fire && r.notified, "signed-out notice: a restart or one-off failure does not re-arm it")
        r = UsageAlerts.decideSignedOut(.recovered, alreadyNotified: r.notified)
        check(!r.fire && !r.notified, "signed-out notice: a good reading re-arms it")
        r = UsageAlerts.decideSignedOut(.lost, alreadyNotified: r.notified)
        check(r.fire, "signed-out notice: fires again on the next lapse")
    }

    // Percent box: digits only, a third digit only to make "100"
    do {
        check(PercentInput.sanitize("5") == "5" && PercentInput.sanitize("75") == "75" && PercentInput.sanitize("100") == "100", "percent box: 5, 75 and 100 are accepted")
        check(PercentInput.sanitize("109") == "10", "percent box: a third digit other than 0 is rejected (109 → 10)")
        check(PercentInput.sanitize("101") == "10" && PercentInput.sanitize("999") == "99" && PercentInput.sanitize("756") == "75", "percent box: 101, 999, 756 lose their third digit")
        check(PercentInput.sanitize("1000") == "100", "percent box: nothing after 100")
        check(PercentInput.sanitize("a7b5") == "75" && PercentInput.sanitize("٣٤") == "" && PercentInput.sanitize("") == "", "percent box: letters and non-ASCII digits rejected")
        check(PercentInput.sanitize("75") != "100" && PercentInput.sanitize("20") == "20" && PercentInput.sanitize("200") == "20", "percent box: 200 → 20 (third digit only after 10)")
    }

    // Which Claude programs are running (refresh-log context, and the collision wait).
    do {
        let ps = """
              05:12:40 /sbin/launchd
            1-02:00:03 /Users/x/.local/bin/claude
                 00:05 /Users/x/Library/Application Support/Claude/claude-code/2.1.295/claude --output-format stream-json --verbose
                 03:10 /Users/x/.local/bin/claude -p --model haiku
                 20:00 /Users/x/.local/bin/claude --print hello
              2-00:00:10 /Applications/Claude.app/Contents/MacOS/Claude
              2-00:00:09 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper
                 10:00 /usr/bin/claude-notes
                 00:01 node /opt/lib/claude-code/cli.js
            """
        let s = ProcessProbe.parse(ps)
        check(s.claudeProcesses == 4, "process probe: counts only programs named claude, spaces in paths ok (\(s.claudeProcesses))")
        check(s.desktopRunning, "process probe: sees the Claude app")
        check(s.busyOthers == 3, "process probe: busy = just started (5 s) or headless (-p, --print); an idle old session is not (\(s.busyOthers))")
        let none = ProcessProbe.parse("  05:12:40 /sbin/launchd\n  00:02 /usr/bin/ssh host\n")
        check(none.claudeProcesses == 0 && !none.desktopRunning && none.busyOthers == 0, "process probe: nothing running")
        check(ProcessProbe.seconds(fromElapsed: "05:12") == 312 && ProcessProbe.seconds(fromElapsed: "01:02:03") == 3723 && ProcessProbe.seconds(fromElapsed: "2-00:00:10") == 172810, "process probe: elapsed-time formats")
        check(ProcessProbe.snapshot() != nil, "process probe: the real process list can be read")
    }

    // Software updates (UpdateChecker): version maths, GitHub reply parsing, once-per-version notice, failure stays neutral.
    do {
        check(UpdateChecker.isNewer("1.1.0", than: "1.0.0") && UpdateChecker.isNewer("v1.0.1", than: "1.0.0") && UpdateChecker.isNewer("2.0", than: "1.9.9"), "updates: newer versions are newer")
        check(!UpdateChecker.isNewer("1.0.0", than: "1.0.0") && !UpdateChecker.isNewer("1.0", than: "1.0.0") && !UpdateChecker.isNewer("0.9.9", than: "1.0.0") && !UpdateChecker.isNewer("1.10.0", than: "1.10.1"), "updates: same or older is not an update")
        check(!UpdateChecker.isNewer("beta", than: "1.0.0") && UpdateChecker.parts("1.x") == nil, "updates: junk is never an update")
        let json = #"{"tag_name":"v1.1.0","html_url":"https://github.com/o/cap/releases/tag/v1.1.0","assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"},{"name":"Cap-1.1.0.dmg","browser_download_url":"https://x/Cap-1.1.0.dmg"}]}"#
        let rel = try? UpdateChecker.parse(Data(json.utf8))
        check(rel?.version == "1.1.0" && rel?.downloadURL == "https://x/Cap-1.1.0.dmg" && rel?.releaseURL.hasSuffix("v1.1.0") == true, "updates: release parsed, direct installer link picked")
        check((try? UpdateChecker.parse(Data(#"{"tag_name":"nightly","html_url":"u"}"#.utf8))) == nil, "updates: a non-version tag is refused")

        let suite = UserDefaults(suiteName: "cap.harness.updates")!; suite.removePersistentDomain(forName: "cap.harness.updates")
        let prefs = Preferences(store: suite)
        check(!prefs.checkForUpdatesAutomatically && prefs.lastUpdateCheck == nil && !prefs.updateAvailable && !prefs.updateDotVisible, "updates: off by default (asks first), nothing known yet")
        var reply: Result<UpdateChecker.Release, Error> = .success(.init(version: "99.0.0", releaseURL: "https://r", downloadURL: nil))
        let checker = UpdateChecker(preferences: prefs, fetch: { try reply.get() })
        let notices = Counter2()
        checker.onNewVersion = { _ in notices.bump() }
        checker.check()
        check(waitUntil(3) { !checker.isChecking && prefs.lastUpdateCheck != nil }, "updates: a check finishes and stamps the time")
        check(prefs.updateAvailable && prefs.updateDotVisible && notices.n == 1, "updates: newer version -> dot and one notice")
        checker.check(); _ = waitUntil(1) { !checker.isChecking }; spin(0.3)
        check(notices.n == 1, "updates: the same version is announced once")
        prefs.updateSeenVersion = prefs.latestVersion
        check(prefs.updateAvailable && !prefs.updateDotVisible, "updates: opening the Updates pane clears the dot, the update stays")
        reply = .success(.init(version: "100.0.0", releaseURL: "https://r2", downloadURL: nil))
        checker.check(); _ = waitUntil(3) { prefs.latestVersion == "100.0.0" }; spin(0.3)
        check(notices.n == 2 && prefs.updateDotVisible, "updates: the next new version is announced again, dot returns")
        let stamp = prefs.lastUpdateCheck
        reply = .failure(URLError(.notConnectedToInternet))
        checker.check(); check(waitUntil(3) { prefs.lastUpdateCheckFailed }, "updates: offline -> failed flag, quietly")
        check(prefs.lastUpdateCheck == stamp && prefs.latestVersion == "100.0.0", "updates: a failed check keeps the last good answer")
        suite.removePersistentDomain(forName: "cap.harness.updates")
    }


    try? fm.removeItem(at: tmp)
    print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}
MainActor.assumeIsolated { run() }
