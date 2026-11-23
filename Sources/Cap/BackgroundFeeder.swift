import AppKit
import Foundation

/// Keeps live.json fresh with Cap's own headless refreshes (see `UsageFetcher`). Replaces the old hidden
/// Claude session: nothing keeps running between refreshes, and nothing in the user's Claude settings is touched.
@MainActor
final class BackgroundFeeder: ObservableObject {
    enum Status: Equatable {
        case idle                       // nothing fetched yet
        case ok(Date)                   // last successful reading
        case needsSignIn               // Claude Code isn't signed in
        case offline                    // Claude couldn't be reached; says nothing about the login
        case noLimits                   // signed in, but the account reports no usage limits
        case claudeMissing              // Claude Code can't be found on this Mac (the app moved or was deleted)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle {
        didSet { writeStatusFile() }
    }

    /// Where to look for Claude Code (a test can point this at a throwaway home).
    private let claudeHome: URL
    /// A test can swap in a canned fetch.
    private let fetcher: @Sendable (String, Int) -> UsageFetcher.Outcome

    /// How many other Claude programs are in a busy moment right now (see `ProcessProbe`). A test can swap in a canned answer.
    private let busyOthers: @Sendable () -> Int
    /// Whether the Mac has a route to the internet (see `NetworkMonitor`). A test can swap in a canned answer.
    private let reachable: @Sendable () -> Bool
    /// Asks the user's login shell where `claude` is (slow, so off the main thread). A test can swap in a canned answer.
    private let shellLookup: @Sendable (URL) -> String?
    /// Looks in the usual install places (quick). A test can swap in a canned answer.
    private let locate: @Sendable (URL) -> String?

    /// The last "signed out" came from an expiry wording (the saved login ran out), not from a plain "Not logged in".
    /// Only an expiry is the user's surprise, so only an expiry sends the signed-out notification.
    private(set) var signOutIsExpiry = false

    init(claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser,
         fetcher: @escaping @Sendable (String, Int) -> UsageFetcher.Outcome = { UsageFetcher.fetch(claudePath: $0, intervalSeconds: $1) },
         busyOthers: @escaping @Sendable () -> Int = { ProcessProbe.snapshot()?.busyOthers ?? 0 },
         reachable: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isOnline },
         shellLookup: @escaping @Sendable (URL) -> String? = { ClaudeLocator.find(home: $0, askShell: true, withVersion: false, preferNewest: true)?.path },
         locate: @escaping @Sendable (URL) -> String? = { ClaudeLocator.find(home: $0, askShell: false, withVersion: false, preferNewest: true)?.path }) {
        self.claudeHome = claudeHome
        self.fetcher = fetcher
        self.busyOthers = busyOthers
        self.reachable = reachable
        self.shellLookup = shellLookup
        self.locate = locate
    }

    /// The route to the internet came or went. When it comes back, catch up at once (unless the Mac has only just
    /// woken: the wake hold exists so Cap does not refresh the login at the same moment as everyone else).
    func networkChanged(online: Bool) {
        RefreshLog.append(["event": online ? "network-up" : "network-down"])
        guard online, status == .offline else { return }
        if let hold = wakeHoldUntil, Date() < hold { return }
        tick(force: true)
    }

    /// Claude Code's saved login is renewed by whichever Claude program gets there first, and reports say two at once can lose
    /// it. If another one is starting up or running a one-shot call, wait a few seconds for it to finish. Bounded: after this
    /// many waits Cap goes ahead anyway, so a refresh is never held back for long.
    var collisionWait: TimeInterval = 5
    var collisionMaxWaits = 4

    /// Seconds between refreshes (the Settings / welcome slider).
    var refreshIntervalProvider: () -> TimeInterval = { 300 }
    private var refreshInterval: TimeInterval { refreshIntervalProvider() }

    /// When Cap started: the popover says "Claude is slow to answer" if the first reading takes more than 30 s after this.
    let launchedAt = Date()

    private var timer: Timer?
    private var lastAttempt: Date?
    private var inFlight = false
    private var pausedForIdle = false
    private var hasFetchedOnce = false
    private var wakeObservers: [NSObjectProtocol] = []
    private var claudePath: String?
    private var shellLookupInFlight = false
    private var stopping = false
    /// After the Mac wakes, Cap holds off until this time before refreshing. Waking is when every Claude program renews its
    /// login at once, and a lost renewal is the leading suspect for logins that die over a weekend.
    private var wakeHoldUntil: Date?
    var wakeDelayRange: ClosedRange<TimeInterval> = 60...120

    /// No keyboard or mouse for this long = nobody is looking at the numbers, so don't spend usage refreshing them.
    var idleThreshold: TimeInterval = 10 * 60
    /// While signed out (or on an account with no limits) don't try more than once a minute.
    var problemBackoff: TimeInterval = 60

    private let liveURL = URL(fileURLWithPath: NSString(string: "~/.claude_usage_widget/live.json").expandingTildeInPath)

    /// Told after every refresh what Claude Code says about when the saved sign-in ends (a date, or nil when it signs out or
    /// the installed Claude Code is too old to say). Set by the app.
    var onLoginEnd: ((Date?) -> Void)?

    // Sleep detection that does not depend on the system's wake notice. On 2026-11-09 Cap's first call after a 23 h sleep ran
    // BEFORE the wake notice was handled (the log shows the call, then the "wake" event 3 s later), so the wake hold did not
    // protect it. The wall clock keeps running through sleep and `ClaudeRun.uptime()` does not, so the difference between how
    // much each moved since the last tick is the time the Mac spent asleep.
    private var lastTickWall: Date?
    private var lastTickUptime: TimeInterval?
    private func noticeSleepGap() {
        let wall = Date(), up = ClaudeRun.uptime()
        defer { lastTickWall = wall; lastTickUptime = up }
        guard let wall0 = lastTickWall, let up0 = lastTickUptime else { return }
        let slept = wall.timeIntervalSince(wall0) - (up - up0)
        guard slept > 20, wakeHoldUntil.map({ wall >= $0 }) ?? true else { return }
        let hold = Double.random(in: wakeDelayRange)
        wakeHoldUntil = wall.addingTimeInterval(hold)
        RefreshLog.append(["event": "wake-gap", "slept_s": Int(slept), "hold_s": Int(hold.rounded())])
    }

    func start() {
        NetworkMonitor.shared.start { [weak self] up in Task { @MainActor in self?.networkChanged(online: up) } }
        // Once a second, so a 15 s interval really is about 15 s; tick() only does work when something is due.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Refresh right away when the Mac wakes instead of waiting for the next tick.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let now = Date()
                    if self.wakeHoldUntil.map({ now >= $0 }) ?? true {   // the Mac sends two wake notices; the second must not extend the hold
                        let hold = Double.random(in: self.wakeDelayRange)
                        self.wakeHoldUntil = now.addingTimeInterval(hold)
                        RefreshLog.append(["event": "wake", "hold_s": Int(hold.rounded())])
                    }
                }
            }
            wakeObservers.append(token)
        }
        tick(force: true)
    }

    func stop() {
        stopping = true
        timer?.invalidate(); timer = nil
        wakeObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        wakeObservers.removeAll()
    }

    /// On quit: give a refresh that is already running time to finish, so the program is not cut off before it has saved
    /// a renewed login. Spins the run loop (the refresh reports back on the main thread). Returns whether it finished.
    var isRefreshing: Bool { inFlight }

    @discardableResult
    func waitForInFlight(timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while inFlight && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return !inFlight
    }

    /// Preview only: show a given state without running a refresh.
    func debugSet(status: Status) { suppressStatusFile = true; self.status = status }
    /// Set by `debugSet` so a preview never overwrites the real refresh-status.json that diagnostics read.
    private var suppressStatusFile = false

    /// Refreshes right now (after sign-in, or when the user asks).
    func refreshNow() { tick(force: true) }

    private func tick(force: Bool = false) {
        noticeSleepGap()
        guard !inFlight, !stopping else { return }
        if !force, let hold = wakeHoldUntil, Date() < hold { return }   // just woke: let the other Claude programs go first
        let sinceLast = lastAttempt.map { Date().timeIntervalSince($0) } ?? .infinity
        var wait = refreshInterval
        switch status {
        case .needsSignIn, .noLimits, .failed, .offline: wait = max(wait, problemBackoff)
        // Claude Code missing is a local file lookup (no network call), so look again every minute whatever the interval is:
        // Cap finds Claude again soon after it is back (Pass D measured 197 s at a 5-minute interval).
        case .claudeMissing: wait = problemBackoff
        default: break
        }
        // A known reset time has passed (what is on screen is no longer true): refresh soon, but not in a
        // tight loop if the answer doesn't clear it (signed out, no limits).
        var resetDue = false
        if case .ok = status, sinceLast >= 10 { resetDue = resetBoundaryHasPassed() }
        else if status == .idle, sinceLast >= 10 { resetDue = resetBoundaryHasPassed() }
        let due = sinceLast >= wait || resetDue
        guard force || due else { return }
        // Nobody at the keyboard: leave the numbers alone and catch up as soon as they are back
        // (the very first refresh always happens, so there is a first reading).
        if !force && hasFetchedOnce && UserActivity.isIdle(after: idleThreshold) {
            if !pausedForIdle { pausedForIdle = true; RefreshLog.append(["event": "idle-pause"]) }
            return
        }
        if pausedForIdle { pausedForIdle = false; RefreshLog.append(["event": "idle-resume"]) }
        guard let claude = resolveClaude() else { return }
        // No route to the internet: say so now and skip the call (it would only hang until the time limit).
        if !reachable() {
            lastAttempt = Date()
            hasFetchedOnce = true
            if status != .offline { RefreshLog.append(["event": "offline-skip"]); status = .offline }
            return
        }
        inFlight = true
        lastAttempt = Date()
        let fetcher = fetcher
        let intervalSeconds = Int(refreshInterval)
        let busyOthers = busyOthers, waitSeconds = collisionWait, maxWaits = collisionMaxWaits
        Task {
            var waits = 0
            while waits < maxWaits, !stopping {
                let busy = await Task.detached { busyOthers() }.value
                if busy == 0 { break }
                waits += 1
                RefreshLog.append(["event": "collision-wait", "busy_others": busy, "wait_n": waits])
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
            }
            if stopping { inFlight = false; return }      // Cap is quitting: start nothing new
            #if CAP_TEST_BUILD
            let fetchBegan = Date()
            #endif
            let outcome = await Task.detached { fetcher(claude, intervalSeconds) }.value
            #if CAP_TEST_BUILD
            TestFetchNotice.post(outcome: outcome, intervalSeconds: intervalSeconds, seconds: Date().timeIntervalSince(fetchBegan), waited: waits)
            #endif
            inFlight = false
            hasFetchedOnce = true
            switch outcome {
            case .reading(let r):
                StatusLineHook.record(sessionPct: r.sessionPct, sessionResetsAt: r.sessionResetsAt,
                                      weekPct: r.weekPct, weekResetsAt: r.weekResetsAt)
                if let end = r.loginEndsAt { onLoginEnd?(Date(timeIntervalSince1970: end)) }
                status = .ok(Date())
            case .notSignedIn: signOutIsExpiry = false; onLoginEnd?(nil); status = .needsSignIn
            case .sessionExpired: signOutIsExpiry = true; onLoginEnd?(nil); status = .needsSignIn
            case .noLimits: status = .noLimits
            case .offline: status = .offline
            case .busy: status = .failed("Another Claude program was renewing the sign-in; trying again shortly.")
            case .failed(let why): status = reachable() ? .failed(why) : .offline   // a call that hung with no route is "offline"
            }
        }
    }

    /// A tiny status file for diagnostics (no account details): what the last refresh did, and when.
    private func writeStatusFile() {
        guard !suppressStatusFile else { return }
        let word: String
        switch status {
        case .idle: word = "idle"
        case .ok: word = "ok"
        case .needsSignIn: word = "needs-sign-in"
        case .noLimits: word = "no-limits"
        case .claudeMissing: word = "claude-missing"
        case .offline: word = "offline"
        case .failed(let why): word = "failed: \(why)"
        }
        let url = StatusLineHook.supportDirectory().appendingPathComponent("refresh-status.json")
        let json: [String: Any] = ["status": word, "at": Date().timeIntervalSince1970, "interval_seconds": refreshInterval]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A known reset time has passed, so what is on screen is no longer true.
    private func resetBoundaryHasPassed() -> Bool {
        guard let data = try? Data(contentsOf: liveURL),
              let decoded = try? JSONDecoder().decode(LiveUsage.self, from: data) else { return false }
        let now = Date()
        if let t = decoded.session_resets_at, Date(timeIntervalSince1970: t) <= now { return true }
        if let t = decoded.week_resets_at, Date(timeIntervalSince1970: t) <= now { return true }
        return false
    }

    private func markClaudeMissing() {
        guard !stopping else { return }
        lastAttempt = Date()
        hasFetchedOnce = true
        if status != .claudeMissing { RefreshLog.append(["event": "claude-missing"]); status = .claudeMissing }
    }

    /// Where `claude` was found. launchd gives apps a minimal PATH, so a bare `claude` isn't found when Cap
    /// starts at login; resolve a full path instead.
    private func resolveClaude() -> String? {
        if let claudePath, FileManager.default.isExecutableFile(atPath: claudePath) { return claudePath }
        claudePath = nil
        if let found = locate(claudeHome) {
            claudePath = found
            return found
        }
        // Not in any usual place: ask the login shell off the main thread (an nvm or custom-prefix install). If it does not
        // know either, Claude Code is gone (the app moved or was deleted): say so. This runs again on every slow retry
        // (at most once a minute while missing), so Cap finds Claude again by itself once it is back.
        if !shellLookupInFlight {
            shellLookupInFlight = true
            Task {
                let home = claudeHome, lookup = shellLookup
                let found = await Task.detached { lookup(home) }.value
                self.claudePath = found
                self.shellLookupInFlight = false
                if found == nil { self.markClaudeMissing() }
                else if self.status == .claudeMissing { self.tick(force: true) }
            }
        }
        return nil
    }
}
