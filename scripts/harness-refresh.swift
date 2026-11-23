import Foundation
import AppKit
var failures = 0
func check(_ ok: Bool, _ name: String) { print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1 } }
func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

final class Counter: @unchecked Sendable { private let l = NSLock(); private var n = 0; func bump() { l.lock(); n += 1; l.unlock() }; func reset() { l.lock(); n = 0; l.unlock() }; var value: Int { l.lock(); defer { l.unlock() }; return n } }

@MainActor func run() {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("capfeed-\(UUID().uuidString.prefix(6))")
    try! fm.createDirectory(at: tmp.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
    setenv("CAP_HOME", tmp.path, 1)          // live.json goes to the throwaway home, never the real one
    func lines(_ s: String) -> Data { Data(s.utf8) }

    // 1. Parsing what Claude Code prints
    let both = lines("""
    {"type":"system","subtype":"init"}
    {"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1792047600,"rateLimitType":"seven_day","utilization":0.28,"unifiedWindows":{"five_hour":{"utilization":0.24,"resetsAt":1791517800},"seven_day":{"utilization":0.28,"resetsAt":1792047600}}}}
    {"type":"result","subtype":"success","is_error":false,"result":"OK"}
    """)
    if case .reading(let r) = UsageFetcher.parse(both) {
        check(abs((r.sessionPct ?? 0) - 24) < 0.001 && abs((r.weekPct ?? 0) - 28) < 0.001 && r.sessionResetsAt == 1791517800 && r.weekResetsAt == 1792047600, "both windows parsed (0.24 → 24%, 0.28 → 28%, reset times)")
    } else { check(false, "both windows parsed") }
    let single = lines(#"{"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.5,"resetsAt":100}}"#)
    if case .reading(let r) = UsageFetcher.parse(single) { check(r.sessionPct == 50 && r.weekPct == nil, "older single-window shape → session only") } else { check(false, "single-window shape") }
    check(UsageFetcher.parse(lines(#"{"type":"result","is_error":true,"result":"Not logged in · Please run /login"}"#)) == .notSignedIn, "'Not logged in' → needs sign-in")
    check(UsageFetcher.parse(lines(#"{"type":"result","is_error":false,"result":"OK"}"#)) == .noLimits, "ran fine but no usage event → no limits reported")
    check(UsageFetcher.parse(lines("garbage\n\n{broken")) == .noLimits, "garbage output → no limits (no crash)")

    // 2. The real fetch, against a fake claude
    func fake(_ body: String) -> String {
        let path = tmp.appendingPathComponent(".local/bin/claude").path
        fm.createFile(atPath: path, contents: Data(body.utf8), attributes: [.posixPermissions: 0o755]); return path
    }
    let okPath = fake("""
    #!/bin/sh
    read -r _l
    echo '{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.31,"resetsAt":4102444800},"seven_day":{"utilization":0.09,"resetsAt":4102444800}}}}'
    echo '{"type":"result","is_error":false,"result":"OK"}'
    """)
    let t0 = Date()
    if case .reading(let r) = UsageFetcher.fetch(claudePath: okPath) { check(abs((r.sessionPct ?? 0) - 31) < 0.001 && abs((r.weekPct ?? 0) - 9) < 0.001, "real fetch against a fake claude reads 31% / 9%") } else { check(false, "real fetch") }
    check(Date().timeIntervalSince(t0) < 5, "fetch returns promptly")
    let slowPath = fake("#!/bin/sh\nsleep 30\n")
    let t1 = Date()
    let out = UsageFetcher.fetch(claudePath: slowPath, timeout: 1)
    if case .failed = out { check(Date().timeIntervalSince(t1) < 4, "a hung claude is cut off at the timeout") } else { check(false, "timeout → failed") }
    check(UsageFetcher.fetch(claudePath: "/nonexistent/claude") != .noLimits, "missing program → failure, not 'no limits'")

    // 3. Recording to live.json and the newest-wins merge
    StatusLineHook.record(sessionPct: 31, sessionResetsAt: 4102444800, weekPct: 9, weekResetsAt: 4102444800)
    let live = tmp.appendingPathComponent(".claude_usage_widget/live.json")
    var j = (try? JSONSerialization.jsonObject(with: Data(contentsOf: live))) as? [String: Any] ?? [:]
    check(j["session_used_pct"] as? Double == 31 && j["week_used_pct"] as? Double == 9, "live.json written (31 / 9)")
    check(((try? fm.attributesOfItem(atPath: live.path))?[.posixPermissions] as? Int) == 0o600, "live.json is private (0600)")
    StatusLineHook.record(sessionPct: 20, sessionResetsAt: 4102444800, weekPct: 9, weekResetsAt: 4102444800)
    j = (try? JSONSerialization.jsonObject(with: Data(contentsOf: live))) as? [String: Any] ?? [:]
    check(j["session_used_pct"] as? Double == 31, "an older, lower reading in the same window doesn't overwrite a newer one")
    StatusLineHook.record(sessionPct: 5, sessionResetsAt: 4102444800 + 18000, weekPct: 9, weekResetsAt: 4102444800)
    j = (try? JSONSerialization.jsonObject(with: Data(contentsOf: live))) as? [String: Any] ?? [:]
    check(j["session_used_pct"] as? Double == 5, "a newer window replaces the old one")

    // 4. The refresher: timing, backoff, no work when Claude isn't there
    let calls = Counter()
    var nextOutcome: UsageFetcher.Outcome = .reading(.init(sessionPct: 40, sessionResetsAt: 4102444800, weekPct: 12, weekResetsAt: 4102444800))
    let outcomeBox = NSLock()
    final class Box: @unchecked Sendable { var o: UsageFetcher.Outcome; let l = NSLock(); init(_ o: UsageFetcher.Outcome) { self.o = o }; func get() -> UsageFetcher.Outcome { l.lock(); defer { l.unlock() }; return o }; func set(_ x: UsageFetcher.Outcome) { l.lock(); o = x; l.unlock() } }
    _ = outcomeBox
    let box = Box(nextOutcome)
    _ = nextOutcome; nextOutcome = .noLimits
    let f = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in calls.bump(); return box.get() }, busyOthers: { 0 })
    f.refreshIntervalProvider = { 15 }
    f.idleThreshold = .infinity     // this Mac may well be idle right now; idle behaviour is tested separately
    f.start(); spin(1.5)
    check(calls.value == 1, "start → one refresh straight away")
    if case .ok = f.status { check(true, "status ok after a reading") } else { check(false, "status ok after a reading (\(f.status))") }
    spin(17)
    check(calls.value == 2, "15 s interval → exactly one more refresh after ~17 s (calls=\(calls.value))")
    f.refreshNow(); spin(1)
    check(calls.value == 3, "refreshNow() refreshes immediately")
    box.set(.notSignedIn); f.refreshNow(); spin(1)
    check(f.status == .needsSignIn, "signed out → status needsSignIn")
    let before = calls.value
    spin(20)
    check(calls.value == before, "while signed out it backs off (no retry within 20 s at a 15 s interval; calls=\(calls.value - before) extra)")
    // recovery and failure behaviour (offline, a hung call, signing back in)
    box.set(.failed("Claude Code took too long to answer.")); f.refreshNow(); spin(1)
    if case .failed = f.status { check(true, "offline/hung call → status failed (not 'signed out')") } else { check(false, "failed status (\(f.status))") }
    let beforeFail = calls.value
    spin(20)
    check(calls.value == beforeFail, "after a failure it backs off instead of retrying every interval (extra calls=\(calls.value - beforeFail))")
    box.set(.reading(.init(sessionPct: 55, sessionResetsAt: 4102444800, weekPct: 20, weekResetsAt: 4102444800))); f.refreshNow(); spin(1)
    if case .ok = f.status { check(true, "network back / signed in again → refreshNow() recovers to ok") } else { check(false, "recovery (\(f.status))") }
    box.set(.noLimits); f.refreshNow(); spin(1)
    check(f.status == .noLimits, "account without limits → status noLimits")
    let overHundred = lines(#"{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":1.01,"resetsAt":4102444800}}}}"#)
    if case .reading(let r) = UsageFetcher.parse(overHundred) { check(r.sessionPct.map { abs($0 - 101) < 0.001 } == true, "reading above 100% parses as 101 (UI must clamp; see cleanup list)") } else { check(false, "over 100%") }
    let statusJSON = try? Data(contentsOf: StatusLineHook.supportDirectory().appendingPathComponent("refresh-status.json"))
    check(statusJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["status"] as? String == "no-limits", "refresh-status.json mirrors the status (diagnostics rely on it)")
    f.stop()
    // idle: after the first reading, a Mac nobody is using is left alone (a forced refresh still works)
    let calls3 = Counter()
    let h = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in calls3.bump(); return box.get() }, busyOthers: { 0 })
    box.set(.reading(.init(sessionPct: 1, sessionResetsAt: 4102444800, weekPct: 1, weekResetsAt: 4102444800)))
    h.refreshIntervalProvider = { 15 }; h.idleThreshold = 0     // 0 = always counts as idle
    h.start(); spin(1.5); spin(17)
    check(calls3.value == 1, "idle: only the first refresh happens (calls=\(calls3.value))")
    h.refreshNow(); spin(1)
    check(calls3.value == 2, "idle: refreshNow() still works")
    h.stop()
    // collision wait: another Claude program in a busy moment delays Cap's refresh a little, never for long
    let probes = Counter(), fetches = Counter()
    let w = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in fetches.bump(); return box.get() },
                             busyOthers: { probes.bump(); return probes.value <= 2 ? 1 : 0 })   // busy for the first two looks, then clear
    w.collisionWait = 0.3; w.collisionMaxWaits = 4; w.refreshIntervalProvider = { 15 }; w.idleThreshold = .infinity
    w.start(); spin(0.4)
    check(fetches.value == 0, "collision: refresh waits while another Claude program is busy (fetches=\(fetches.value), looks=\(probes.value))")
    spin(1.5)
    check(fetches.value == 1 && probes.value == 3, "collision: refreshes as soon as it clears (fetches=\(fetches.value), looks=\(probes.value))")
    w.stop()
    let probes2 = Counter(), fetches2 = Counter()
    let z = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in fetches2.bump(); return box.get() }, busyOthers: { probes2.bump(); return 3 })   // never clears
    z.collisionWait = 0.2; z.collisionMaxWaits = 3; z.refreshIntervalProvider = { 15 }; z.idleThreshold = .infinity
    z.start(); spin(2.0)
    check(fetches2.value == 1 && probes2.value == 3, "collision: never held back for ever, refreshes after the last wait (fetches=\(fetches2.value), looks=\(probes2.value))")
    z.stop()
    // Phase 1 (login safety, 2026-10-22)
    func errLine(_ t: String) -> Data { lines(#"{"type":"result","is_error":true,"result":"\#(t)"}"#) }
    check(UsageFetcher.parse(errLine("API Error: Unable to connect to API (ConnectionRefused)")) == .offline, "offline wording → offline (not 'no limits')")
    check(UsageFetcher.parse(errLine("Failed to authenticate. Unable to connect to API")) == .offline, "network trouble phrased as 'failed to authenticate' → offline, not signed out")
    check(UsageFetcher.parse(errLine("Failed to authenticate: OAuth session expired and could not be refreshed")) == .sessionExpired, "expired session (seen live) → signed out, as an expiry")
    check(UsageFetcher.parse(errLine("Failed to authenticate")) == .sessionExpired, "a bare 'failed to authenticate' still → signed out (expiry)")
    check(UsageFetcher.parse(errLine("Login expired · Please run /login")) == .sessionExpired, "'Login expired' → signed out (expiry beats the 'please run /login' part)")
    check(UsageFetcher.parse(errLine("Not logged in · Please run /login")) == .notSignedIn, "plain 'Not logged in' → signed out, but not an expiry (no notification)")
    check(UsageFetcher.parse(errLine("Another Claude Code process is refreshing it or exited mid-refresh")) == .busy, "lock contention → busy (try again shortly)")
    check(UsageFetcher.parse(errLine("Some other failure")) == .noLimits, "an unknown error is still not mistaken for any of these")

    setenv("ANTHROPIC_API_KEY", "sk-test", 1); setenv("CLAUDE_CODE_OAUTH_TOKEN", "tok-test", 1)
    let envPath = fake("""
    #!/bin/sh
    read -r _l
    if [ -n "$ANTHROPIC_API_KEY$CLAUDE_CODE_OAUTH_TOKEN$ANTHROPIC_AUTH_TOKEN" ]; then echo '{"type":"result","is_error":true,"result":"LEAK"}'; exit 0; fi
    echo '{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.1,"resetsAt":4102444800},"seven_day":{"utilization":0.2,"resetsAt":4102444800}}}}'
    echo '{"type":"result","is_error":false,"result":"OK"}'
    """)
    if case .reading = UsageFetcher.fetch(claudePath: envPath) { check(true, "an API key or token in the environment never reaches claude") } else { check(false, "environment scrub") }
    unsetenv("ANTHROPIC_API_KEY"); unsetenv("CLAUDE_CODE_OAUTH_TOKEN")

    let slowTwo = fake("""
    #!/bin/sh
    read -r _l
    sleep 1
    echo '{"type":"result","is_error":false,"result":"OK"}'
    """)
    let tTwo = Date(); let grp = DispatchGroup()
    for _ in 0..<2 { grp.enter(); DispatchQueue.global().async { _ = UsageFetcher.fetch(claudePath: slowTwo); grp.leave() } }
    grp.wait()
    check(Date().timeIntervalSince(tTwo) >= 1.9, "two Cap-started claude calls take turns (took \(String(format: "%.1f", Date().timeIntervalSince(tTwo))) s for two 1 s calls)")

    // After a wake, Cap holds off; a forced refresh (user action) is not held
    box.set(.reading(.init(sessionPct: 1, sessionResetsAt: 4102444800, weekPct: 1, weekResetsAt: 4102444800)))
    let wc = Counter()
    let wf = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in wc.bump(); return box.get() }, busyOthers: { 0 })
    wf.refreshIntervalProvider = { 1 }; wf.idleThreshold = .infinity; wf.wakeDelayRange = 3...3
    wf.start(); spin(1.3)
    check(wc.value >= 2, "wake hold: refreshes normally before a wake (n=\(wc.value))")
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    spin(0.3); let n1 = wc.value
    spin(2.2)
    check(wc.value == n1, "wake hold: no refresh while the hold lasts (n=\(n1) → \(wc.value))")
    wf.refreshNow(); spin(0.6)
    check(wc.value == n1 + 1, "wake hold: a user-forced refresh still goes through")
    spin(2.4)
    check(wc.value > n1 + 1, "wake hold: refreshing resumes after the hold (n=\(wc.value))")
    wf.stop()

    // Offline: no route to the internet means no call, status 'offline', and a catch-up the moment the route returns
    final class Flag: @unchecked Sendable { private let l = NSLock(); private var v: Bool; init(_ v: Bool) { self.v = v }; var value: Bool { get { l.lock(); defer { l.unlock() }; return v } set { l.lock(); v = newValue; l.unlock() } } }
    let route = Flag(false)
    let oc = Counter()
    let of = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in oc.bump(); return box.get() }, busyOthers: { 0 }, reachable: { route.value })
    of.refreshIntervalProvider = { 15 }; of.idleThreshold = .infinity
    of.start(); spin(1.5)
    check(oc.value == 0 && of.status == .offline, "offline: no call is made and the status says offline (calls=\(oc.value))")
    let offlineStatus = try? Data(contentsOf: StatusLineHook.supportDirectory().appendingPathComponent("refresh-status.json"))
    check(offlineStatus.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["status"] as? String == "offline", "offline: refresh-status.json says offline (diagnostics read it)")
    route.value = true
    of.networkChanged(online: true); spin(1.2)
    check(oc.value == 1, "offline: the moment the route returns, Cap refreshes (calls=\(oc.value))")
    if case .ok = of.status { check(true, "offline: status is ok again") } else { check(false, "offline: status back to ok") }
    of.stop()
    // a call that hangs with no route is 'offline', not a failure
    let hangRoute = Flag(true)
    let hf = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in hangRoute.value = false; return .failed("Claude Code took too long to answer.") }, busyOthers: { 0 }, reachable: { hangRoute.value })
    hf.refreshIntervalProvider = { 15 }; hf.idleThreshold = .infinity
    hf.start(); spin(1.2)
    check(hf.status == .offline, "offline: a timed-out call with no route reads as offline")
    hf.stop()

    // Quit: a running refresh gets time to finish, nothing new starts
    let qc = Counter()
    let qf = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in qc.bump(); Thread.sleep(forTimeInterval: 1.5); return box.get() }, busyOthers: { 0 })
    qf.refreshIntervalProvider = { 300 }; qf.idleThreshold = .infinity
    qf.start(); spin(0.3)
    qf.stop()
    let q0 = Date(); let finished = qf.waitForInFlight(timeout: 5); let waited = Date().timeIntervalSince(q0)
    check(finished && waited > 0.8 && waited < 3, "quit: waits for the running refresh to finish (waited \(String(format: "%.1f", waited)) s)")
    let qBefore = qc.value; qf.refreshNow(); spin(0.5)
    check(qc.value == qBefore, "quit: no new refresh starts after stop()")

    // Claude Code missing (B10): Cap says so, makes no call, and recovers by itself once Claude is back
    box.set(.reading(.init(sessionPct: 5, sessionResetsAt: 4102444800, weekPct: 5, weekResetsAt: 4102444800)))
    let present = Counter(); let mc = Counter()
    let mf = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in mc.bump(); return box.get() }, busyOthers: { 0 },
                              shellLookup: { _ in present.value > 0 ? "/bin/echo" : nil },
                              locate: { _ in present.value > 0 ? "/bin/echo" : nil })
    mf.refreshIntervalProvider = { 300 }; mf.idleThreshold = .infinity
    mf.start(); spin(1.5)
    check(mf.status == .claudeMissing && mc.value == 0, "claude missing: status claudeMissing, no call made (status=\(mf.status), calls=\(mc.value))")
    present.bump()
    mf.refreshNow(); spin(1.5)
    if case .ok = mf.status { check(true, "claude missing: recovers to ok once Claude is found again (no restart)") } else { check(false, "claude missing recovery (\(mf.status))") }
    mf.stop()
    // ...and it looks again every problemBackoff seconds by itself, not once per refresh interval (300 s here)
    present.reset()
    let mc2 = Counter()
    let mg = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in mc2.bump(); return box.get() }, busyOthers: { 0 },
                              shellLookup: { _ in present.value > 0 ? "/bin/echo" : nil },
                              locate: { _ in present.value > 0 ? "/bin/echo" : nil })
    mg.refreshIntervalProvider = { 300 }; mg.idleThreshold = .infinity; mg.problemBackoff = 3
    mg.start(); spin(1.5)
    check(mg.status == .claudeMissing, "claude missing (retry test): status claudeMissing")
    present.bump(); spin(5.5)
    if case .ok = mg.status { check(true, "claude missing: found again within about problemBackoff seconds, with a 300 s refresh interval") } else { check(false, "claude missing self-retry (\(mg.status))") }
    mg.stop()

    // Signed out: only an expired login counts as a lapse the user did not choose (the notification depends on it)
    let ec = Counter()
    let ef = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in ec.bump(); return .sessionExpired }, busyOthers: { 0 })
    ef.refreshIntervalProvider = { 300 }; ef.idleThreshold = .infinity
    ef.start(); spin(1.5)
    check(ef.status == .needsSignIn && ef.signOutIsExpiry, "expired login → needsSignIn, marked as an expiry")
    ef.stop()
    let pf = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in .notSignedIn }, busyOthers: { 0 })
    pf.refreshIntervalProvider = { 300 }; pf.idleThreshold = .infinity
    pf.start(); spin(1.5)
    check(pf.status == .needsSignIn && !pf.signOutIsExpiry, "plain 'Not logged in' → needsSignIn, NOT an expiry (no notification)")
    pf.stop()

    // Login end date (research/login-expiry, 2026-11-12): Claude Code 2.1.318+ reports when the saved sign-in ends
    let withEnd = lines("""
    {"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.1,"resetsAt":4102444800},"seven_day":{"utilization":0.2,"resetsAt":4102444800}}}}
    {"type":"result","subtype":"success","is_error":false,"result":"OK","credential_expires_at":"2026-12-10T11:59:07.138Z"}
    """)
    if case .reading(let r) = UsageFetcher.parse(withEnd) { check(r.loginEndsAt.map { abs($0 - 1796903947.138) < 0.01 } == true, "login end date: credential_expires_at is read (2026-12-10 11:59:07 UTC)") } else { check(false, "login end date parse") }
    if case .reading(let r) = UsageFetcher.parse(both) { check(r.loginEndsAt == nil, "login end date: an older Claude Code that does not report it leaves it unknown") } else { check(false, "older claude") }
    check(UsageFetcher.parse(errLine("Your claude.ai login has reached its time limit. Run claude auth login, or claude setup-token for scripts")) == .sessionExpired, "login time limit (2.1.318+ wording) → signed out as an expiry")
    check(LoginExpiry.parse("2026-12-10T11:59:07Z") == 1796903947, "login end date: plain ISO 8601 (no fraction) also parses")
    check(LoginExpiry.parse("not a date") == nil, "login end date: junk is not a date")
    let end = Date(timeIntervalSince1970: 1796903947)
    func at(_ days: Double) -> Date { end.addingTimeInterval(-days * 86_400) }
    check(!LoginExpiry.shouldOfferRenewal(endsAt: end, now: at(8)), "renewal offer: not 8 days before the end")
    check(LoginExpiry.shouldOfferRenewal(endsAt: end, now: at(6.9)), "renewal offer: shown 6.9 days before the end")
    check(LoginExpiry.shouldOfferRenewal(endsAt: end, now: at(0.2)), "renewal offer: still shown the last hours")
    check(!LoginExpiry.shouldOfferRenewal(endsAt: end, now: at(-1)), "renewal offer: not after the end (the signed-out strip takes over)")
    check(!LoginExpiry.shouldOfferRenewal(endsAt: nil, now: at(3)), "renewal offer: nothing when the end date is unknown")
    check(LoginExpiry.phrase(endsAt: end, now: at(5.2)) == "ends in 6 days" && LoginExpiry.phrase(endsAt: end, now: at(0.5)) == "ends tomorrow" && LoginExpiry.phrase(endsAt: end, now: at(-0.1)) == "ends today", "renewal wording: rounds up, never says 0 days with time left")
    check(LoginExpiry.notificationDue(daysLeft: 8, done: 0) == nil, "renewal notice: none 8 days ahead")
    check(LoginExpiry.notificationDue(daysLeft: 6.5, done: 0) == 1, "renewal notice: one a week ahead")
    check(LoginExpiry.notificationDue(daysLeft: 5, done: 1) == nil, "renewal notice: not repeated")
    check(LoginExpiry.notificationDue(daysLeft: 1.5, done: 1) == 2, "renewal notice: a firmer one two days ahead")
    check(LoginExpiry.notificationDue(daysLeft: 1.0, done: 2) == nil, "renewal notice: nothing after the firm one")
    check(LoginExpiry.notificationDue(daysLeft: 1.5, done: 0) == 2, "renewal notice: if Cap first sees it late, the firm notice is sent once, not two")
    check(LoginExpiry.notificationDue(daysLeft: -1, done: 0) == nil, "renewal notice: none after the end")
    // the feeder reports the end date, and clears it when the sign-in is gone
    let endBox = Box(.reading(.init(sessionPct: 5, sessionResetsAt: 4102444800, weekPct: 5, weekResetsAt: 4102444800, loginEndsAt: 1796903947)))
    final class DateBox: @unchecked Sendable { private let l = NSLock(); private var seen: [Date?] = []; func add(_ d: Date?) { l.lock(); seen.append(d); l.unlock() }; var all: [Date?] { l.lock(); defer { l.unlock() }; return seen } }
    let seenEnds = DateBox()
    let lf = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in endBox.get() }, busyOthers: { 0 })
    lf.refreshIntervalProvider = { 300 }; lf.idleThreshold = .infinity
    lf.onLoginEnd = { seenEnds.add($0) }
    lf.start(); spin(1.5)
    check(seenEnds.all.last == Date(timeIntervalSince1970: 1796903947), "feeder: the login end date is passed on after a reading")
    endBox.set(.sessionExpired); lf.refreshNow(); spin(1)
    check(seenEnds.all.last == .some(nil), "feeder: the end date is cleared when the sign-in is gone")
    lf.stop()

    // The program is held open for a few seconds after its answer, so it can finish saving a renewed login
    let marker = tmp.appendingPathComponent("finished-saving")
    let lingerPath = fake("""
    #!/bin/sh
    read -r _l
    echo '{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.3,"resetsAt":4102444800},"seven_day":{"utilization":0.4,"resetsAt":4102444800}}}}'
    echo '{"type":"result","is_error":false,"result":"OK"}'
    cat >/dev/null
    sleep 0.5
    touch "\(marker.path)"
    """)
    UsageFetcher.lingerSeconds = 1.0
    let tl = Date()
    let lingerOut = UsageFetcher.fetch(claudePath: lingerPath)
    let lingerTook = Date().timeIntervalSince(tl)
    if case .reading(let r) = lingerOut { check(abs((r.sessionPct ?? 0) - 30) < 0.001, "linger: the reading still arrives (30%)") } else { check(false, "linger: reading") }
    check(lingerTook > 1.3 && lingerTook < 5, "linger: the program is held open about a second after its answer (took \(String(format: "%.1f", lingerTook)) s)")
    check(fm.fileExists(atPath: marker.path), "linger: the program is allowed to finish its own work after answering (not cut off)")
    // a program that never answers is still closed off and cut at the timeout; one that exits straight away adds no delay
    let quickPath = fake("""
    #!/bin/sh
    read -r _l
    echo '{"type":"result","is_error":false,"result":"OK"}'
    """)
    let tq = Date(); _ = UsageFetcher.fetch(claudePath: quickPath)
    check(Date().timeIntervalSince(tq) < 1.0 + 0.9, "linger: a program that exits by itself is not kept waiting (took \(String(format: "%.1f", Date().timeIntervalSince(tq))) s)")
    UsageFetcher.lingerSeconds = 3

    // Which Claude Code to run: the newest one available (the Claude app's own copy can be newer than a standalone install)
    func makeHome(standalone: String?, bundled: String?) -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("caploc-\(UUID().uuidString.prefix(6))")
        if let v = standalone {
            let real = home.appendingPathComponent(".local/share/claude/versions/\(v)")
            try! fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: real.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
            try! fm.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
            try! fm.createSymbolicLink(atPath: home.appendingPathComponent(".local/bin/claude").path, withDestinationPath: real.path)
        }
        if let v = bundled {
            let exe = home.appendingPathComponent("Library/Application Support/Claude/claude-code/\(v)/abc123/claude.app/Contents/MacOS/claude")
            try! fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: exe.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        }
        return home
    }
    let h1 = makeHome(standalone: "2.1.306", bundled: "2.1.321")
    check(ClaudeLocator.find(home: h1, askShell: false, withVersion: false, preferNewest: true)?.isDesktopBundle == true, "newest: the Claude app's 2.1.321 is chosen over a standalone 2.1.306")
    check(ClaudeLocator.find(home: h1, askShell: false, withVersion: false)?.isDesktopBundle == false, "newest: without the preference the standalone install is still what the welcome window finds")
    let h2 = makeHome(standalone: "2.1.330", bundled: "2.1.321")
    check(ClaudeLocator.find(home: h2, askShell: false, withVersion: false, preferNewest: true)?.isDesktopBundle == false, "newest: a newer standalone install is kept")
    let h3 = makeHome(standalone: "2.1.321", bundled: "2.1.321")
    check(ClaudeLocator.find(home: h3, askShell: false, withVersion: false, preferNewest: true)?.isDesktopBundle == false, "newest: the same version keeps the standalone install")
    let h4 = makeHome(standalone: nil, bundled: "2.1.321")
    check(ClaudeLocator.find(home: h4, askShell: false, withVersion: false, preferNewest: true)?.isDesktopBundle == true, "newest: only the Claude app's copy exists → that one")
    let h5 = makeHome(standalone: "2.1.306", bundled: nil)
    check(ClaudeLocator.find(home: h5, askShell: false, withVersion: false, preferNewest: true)?.path.hasSuffix(".local/bin/claude") == true, "newest: no Claude app copy → the standalone install")
    check(ClaudeLocator.versionFromPath("/nonexistent/bin/claude") == nil, "newest: a path with no version folder gives no version (the standalone copy is left alone)")
    for h in [h1, h2, h3, h4, h5] { try? fm.removeItem(at: h) }

    // ===== Sign-in mode: an expired sign-in is believed at once =====
    let nf = BackgroundFeeder(claudeHome: tmp, fetcher: { _, _ in .sessionExpired }, busyOthers: { 0 })
    nf.refreshIntervalProvider = { 300 }; nf.idleThreshold = .infinity
    nf.start(); spin(1.5)
    check(nf.status == .needsSignIn, "login mode: an expired sign-in is believed at once (as before)")
    nf.stop()

    try? fm.removeItem(at: tmp)
    print(failures == 0 ? "ALL PASS" : "\(failures) FAILED"); exit(failures == 0 ? 0 : 1)
}
MainActor.assumeIsolated { run() }
