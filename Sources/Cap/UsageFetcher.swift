import Foundation

/// One refresh: a single headless Claude Code call ("Reply with just the word OK") whose reply carries a
/// `rate_limit_event` with both usage windows. Nothing runs between refreshes, and nothing in the user's
/// Claude settings is touched. Needs the same Claude Code sign-in `claude auth status` reports.
enum UsageFetcher {
    struct Reading: Equatable {
        var sessionPct: Double?
        var sessionResetsAt: Double?
        var weekPct: Double?
        var weekResetsAt: Double?
        /// When the saved Claude Code sign-in ends (seconds since 1970). Claude Code 2.1.318 and later report it in every
        /// result (`credential_expires_at`); older versions leave it nil. See `LoginExpiry`.
        var loginEndsAt: Double? = nil
    }

    /// After the answer arrives Cap keeps the program's input open for this long before closing it. A program that exits the
    /// moment its answer is out can be cut off while it is still saving a renewed login (reported against Claude Code
    /// 2.1.299 to 2.1.304: "OAuth refresh still in flight ... exiting without waiting further"); the renewed login is then lost
    /// and the next call finds the old one dead. Holding the program open a few seconds costs nothing and lets it finish.
    nonisolated(unsafe) static var lingerSeconds: TimeInterval = 3   // changed only by tests, before any call starts
    /// If no answer has come after this long, close the input anyway (some versions need that to get going).
    static let closeInputAfterSeconds: TimeInterval = 15

    enum Outcome: Equatable {
        case reading(Reading)
        case notSignedIn
        /// Claude Code's saved login ran out and could not be renewed (an expiry wording). Signed out like `notSignedIn`,
        /// but the user did not choose it, so this one gets the "signed out" notification.
        case sessionExpired
        /// The call worked but reported no usage limits (for example an account without Pro or Max).
        case noLimits
        /// Claude could not be reached (no internet, or the service is down). Says nothing about the login.
        case offline
        /// Claude Code reported that another Claude program is renewing the saved login right now. Try again shortly.
        case busy
        case failed(String)
    }

    /// Blocking (a few seconds): call off the main thread. Every call is also recorded in `RefreshLog`.
    static func fetch(claudePath: String, timeout: TimeInterval = 120, intervalSeconds: Int? = nil) -> Outcome {
        let started = Date()
        let company = ProcessProbe.snapshot()   // taken just before the call, so Cap's own call is not counted
        ClaudeRun.gate.wait()                      // one Cap-started claude at a time
        let (outcome, output, stderrFlags) = run(claudePath: claudePath, timeout: timeout)
        ClaudeRun.gate.signal()
        var entry = logEntry(outcome: outcome, output: output, wallMs: Int(Date().timeIntervalSince(started) * 1000), intervalSeconds: intervalSeconds)
        if !stderrFlags.isEmpty { entry["stderr"] = stderrFlags }   // short fixed words only, never the program's own text
        if let company {
            entry["claude_procs"] = company.claudeProcesses
            entry["desktop_running"] = company.desktopRunning
            entry["busy_others"] = company.busyOthers
        }
        RefreshLog.append(entry)
        return outcome
    }

    /// What the program's own output (standard error) said, boiled down to fixed words so the log never holds its text.
    private static func stderrFlags(_ data: Data) -> [String] {
        let text = String(decoding: data, as: UTF8.self).lowercased()
        var flags: [String] = []
        if text.contains("still in flight") || text.contains("exiting without waiting") { flags.append("refresh-in-flight") }
        if text.contains("expires in") || text.contains("expiring") { flags.append("expiry-warning") }
        if flags.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { flags.append("other") }
        return flags
    }

    /// Collects what the program prints while it is still running, so the main loop can see the answer arrive.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var errData = Data()
        private var sawResult = false
        func add(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
            if !sawResult, String(decoding: data, as: UTF8.self).contains(#""type":"result""#) { sawResult = true }
        }
        func setErr(_ d: Data) { lock.lock(); errData = d; lock.unlock() }
        var gotResult: Bool { lock.lock(); defer { lock.unlock() }; return sawResult }
        var output: Data { lock.lock(); defer { lock.unlock() }; return data }
        var errOutput: Data { lock.lock(); defer { lock.unlock() }; return errData }
    }

    private static func run(claudePath: String, timeout: TimeInterval) -> (Outcome, Data, [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: claudePath)
        // The lean call (measured 2026-10-10): a tiny system prompt and no tools send about 740 tokens instead of
        // Claude Code's own ~27,000-token prompt, and the usage event still arrives. No settings are loaded (so none of
        // the user's hooks run) and no session file is written. `--bare` is NOT used: it skips the saved login.
        task.arguments = ["--output-format", "stream-json", "--input-format", "stream-json", "--verbose",
                          "--model", "haiku", "--no-chrome", "--strict-mcp-config", "--disable-slash-commands",
                          "--no-session-persistence", "--setting-sources", "",
                          "--system-prompt", "Reply with the single word OK.", "--tools", "", "-p"]
        // A small, empty folder, so Claude Code's startup has nothing broad to scan (and never reaches
        // other apps' protected folders, which would trigger macOS permission prompts).
        let workspace = NSString(string: "~/.claude_usage_widget/feeder_workspace").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true)
        task.currentDirectoryURL = URL(fileURLWithPath: workspace)
        task.environment = ClaudeRun.cleanEnvironment()
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        task.standardInput = inPipe
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch { return (.failed("I couldn't start Claude Code."), Data(), []) }
        let message = #"{"type":"user","message":{"role":"user","content":"Reply with just the word OK."}}"# + "\n"
        inPipe.fileHandleForWriting.write(Data(message.utf8))
        // The input stays open for now (see `lingerSeconds`): it is closed a few seconds after the answer has arrived.

        // Read on side threads so a full pipe can never stall the process, and enforce the timeout.
        let collector = Collector()
        let reader = Thread {
            let handle = outPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData       // blocks until something arrives; empty at the end of the output
                if chunk.isEmpty { break }
                collector.add(chunk)
            }
        }
        reader.start()
        let errReader = Thread { collector.setErr(errPipe.fileHandleForReading.readDataToEndOfFile()) }
        errReader.start()
        // Measured in time the Mac was awake (see ClaudeRun.uptime), and long enough that a slow renewal is not cut off.
        let began = ClaudeRun.uptime()
        let deadline = began + timeout
        var inputClosed = false
        var answeredAt: TimeInterval?
        func closeInput() { if !inputClosed { try? inPipe.fileHandleForWriting.close(); inputClosed = true } }
        while task.isRunning && ClaudeRun.uptime() < deadline {
            let now = ClaudeRun.uptime()
            if !inputClosed {
                if collector.gotResult {
                    if answeredAt == nil { answeredAt = now }
                    if now - (answeredAt ?? now) >= lingerSeconds { closeInput() }
                } else if now - began >= closeInputAfterSeconds {
                    closeInput()
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if task.isRunning { task.terminate(); closeInput(); return (.failed("Claude Code took too long to answer."), Data(), []) }
        task.waitUntilExit()
        closeInput()
        while reader.isExecuting || errReader.isExecuting { Thread.sleep(forTimeInterval: 0.01) }
        let output = collector.output
        return (parse(output), output, stderrFlags(collector.errOutput))
    }

    /// One numbers-only line for the refresh log.
    static func logEntry(outcome: Outcome, output: Data, wallMs: Int, intervalSeconds: Int?) -> [String: Any] {
        var e: [String: Any] = ["wall_ms": wallMs, "variant": "lean"]
        if let intervalSeconds { e["interval_s"] = intervalSeconds }
        switch outcome {
        case .reading(let r):
            e["outcome"] = "reading"
            e["five_pct"] = r.sessionPct.map { (($0 * 100).rounded()) / 100 } as Any? ?? NSNull()
            e["seven_pct"] = r.weekPct.map { (($0 * 100).rounded()) / 100 } as Any? ?? NSNull()
            e["five_resets"] = r.sessionResetsAt as Any? ?? NSNull()
            e["seven_resets"] = r.weekResetsAt as Any? ?? NSNull()
            // A date only (when the sign-in ends), so the log can show whether it stays fixed while the short token rotates.
            if let end = r.loginEndsAt { e["login_ends"] = Int(end) }
        case .notSignedIn: e["outcome"] = "not-signed-in"
        case .sessionExpired: e["outcome"] = "session-expired"
        case .noLimits: e["outcome"] = "no-limits"
        case .offline: e["outcome"] = "offline"
        case .busy: e["outcome"] = "busy"
        case .failed(let why): e["outcome"] = "failed"; e["why"] = why
        }
        for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  obj["type"] as? String == "result" else { continue }
            let usage = obj["usage"] as? [String: Any] ?? [:]
            e["in_tokens"] = usage["input_tokens"] as Any? ?? NSNull()
            e["cache_write_tokens"] = usage["cache_creation_input_tokens"] as Any? ?? NSNull()
            e["cache_read_tokens"] = usage["cache_read_input_tokens"] as Any? ?? NSNull()
            e["out_tokens"] = usage["output_tokens"] as Any? ?? NSNull()
            e["cost_usd"] = obj["total_cost_usd"] as Any? ?? NSNull()
            e["api_ms"] = obj["duration_api_ms"] as Any? ?? NSNull()
        }
        return e
    }

    /// What Claude Code says (CONFIRMED live) when there is no usable login. Two wordings so far: a login that was never
    /// made or was removed ("Not logged in · Please run /login"), and one whose saved session expired and could not be
    /// renewed ("Failed to authenticate: OAuth session expired and could not be refreshed", seen 2026-10-12 after
    /// 43 idle hours). Both need the same fix, the user signing in again, so both mean "signed out".
    static let signedOutPhrases = ["not logged in", "please run /login"]
    /// Expiry wordings: the saved login ran out. These (and the vague "failed to authenticate") are `.sessionExpired`.
    /// "time limit" and "claude setup-token" are the wording of Claude Code 2.1.318 and later when a stored claude.ai login
    /// reaches its end date (REPORTED in the changelog: the print-mode failure "now names `claude auth login` and
    /// `claude setup-token`"). The exact sentence has not been seen live yet; both are safe to match on, because they only
    /// appear in that failure.
    static let expiredPhrases = ["login expired", "oauth session expired", "could not be refreshed", "time limit", "claude setup-token",
                                      // a token or login that Claude no longer accepts (revoked, or the account changed)
                                      "invalid bearer", "token has expired", "token has been revoked", "token revoked"]
    /// "Failed to authenticate" alone is vague (it can also come with a network problem), so it only counts as signed out
    /// when nothing says the network is the cause.
    static let vagueSignedOutPhrases = ["failed to authenticate"]
    /// REPORTED wordings when Claude cannot be reached (not confirmed live yet).
    static let offlinePhrases = ["unable to connect", "connection refused", "no internet route", "network is unreachable",
                                 "could not resolve host", "enotfound", "econnreset", "etimedout", "fetch failed"]
    /// DOCUMENTED (Claude Code error reference): another Claude program is renewing the saved login.
    static let busyPhrases = ["another claude code process", "exited mid-refresh"]

    /// Reads the stream of JSON lines. Separate from `fetch` so it can be tested with canned output.
    static func parse(_ output: Data) -> Outcome {
        var reading: Reading?
        var loginEnd: Double?
        var notLoggedIn = false, expired = false, offline = false, busy = false
        for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "rate_limit_event":
                if let info = obj["rate_limit_info"] as? [String: Any] { reading = readingFrom(info) ?? reading }
            case "result":
                // Claude Code 2.1.318+: the date the saved sign-in ends. Read whether or not the call worked.
                if let text = obj["credential_expires_at"] as? String { loginEnd = LoginExpiry.parse(text) ?? loginEnd }
                guard obj["is_error"] as? Bool == true, let text = (obj["result"] as? String)?.lowercased() else { break }
                func has(_ phrases: [String]) -> Bool { phrases.contains { text.contains($0) } }
                if has(expiredPhrases) { expired = true }
                else if has(signedOutPhrases) { notLoggedIn = true }
                else if has(offlinePhrases) { offline = true }
                else if has(busyPhrases) { busy = true }
                else if has(vagueSignedOutPhrases) { expired = true }
            default: break
            }
        }
        if expired { return .sessionExpired }
        if notLoggedIn { return .notSignedIn }
        if var reading { reading.loginEndsAt = loginEnd; return .reading(reading) }
        if offline { return .offline }
        if busy { return .busy }
        return .noLimits
    }

    private static func readingFrom(_ info: [String: Any]) -> Reading? {
        func window(_ dict: Any?) -> (pct: Double, resetsAt: Double?)? {
            guard let d = dict as? [String: Any], let u = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return (u * 100, (d["resetsAt"] as? NSNumber)?.doubleValue)
        }
        var r = Reading()
        if let windows = info["unifiedWindows"] as? [String: Any] {
            if let five = window(windows["five_hour"]) { r.sessionPct = five.pct; r.sessionResetsAt = five.resetsAt }
            if let seven = window(windows["seven_day"]) { r.weekPct = seven.pct; r.weekResetsAt = seven.resetsAt }
        }
        // Older shape: one window named by `rateLimitType` at the top level.
        if r.sessionPct == nil && r.weekPct == nil, let w = window(info) {
            switch info["rateLimitType"] as? String {
            case "five_hour": r.sessionPct = w.pct; r.sessionResetsAt = w.resetsAt
            case "seven_day": r.weekPct = w.pct; r.weekResetsAt = w.resetsAt
            default: break
            }
        }
        return (r.sessionPct == nil && r.weekPct == nil) ? nil : r
    }
}
