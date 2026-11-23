import Foundation

/// `Cap --statusline [--then <shell command>]`
///
/// Claude Code runs this once a second as its statusLine command. It reads the
/// session JSON on stdin, writes the account-wide usage fields to
/// ~/.claude_usage_widget/live.json (atomically), and prints a compact status
/// line — the same job scripts/statusline.py did, without needing Python.
///
/// If the user already had a statusLine of their own, the installer chains it
/// with `--then`: the original command receives the same stdin and its output
/// is what Claude Code shows, so their footer is unchanged.
///
/// Runs before any AppKit setup, so there is no Dock icon or menu bar item.
/// `CAP_HOME` overrides the home folder (for tests).
enum StatusLineHook {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--statusline") else { return }

        let input = FileHandle.standardInput.readDataToEndOfFile()
        let ours = process(input: input)

        if let i = args.firstIndex(of: "--then"), i + 1 < args.count {
            print(runOriginal(args[i + 1], stdin: input) ?? ours, terminator: "")
        } else {
            print(ours)
        }
        exit(0)
    }

    static func supportDirectory() -> URL {
        let home = ProcessInfo.processInfo.environment["CAP_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude_usage_widget", isDirectory: true)
    }

    /// Writes live.json and returns the status line text.
    static func process(input: Data) -> String {
        let data = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let limits = data["rate_limits"] as? [String: Any] ?? [:]
        let five = limits["five_hour"] as? [String: Any] ?? [:]
        let seven = limits["seven_day"] as? [String: Any] ?? [:]
        let cost = (data["cost"] as? [String: Any])?["total_cost_usd"] as? Double
        let model = (data["model"] as? [String: Any])?["display_name"] as? String
        let ctx = (data["context_window"] as? [String: Any])?["used_percentage"] as? Double

        func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        let session = number(five["used_percentage"])
        let week = number(seven["used_percentage"])

        record(sessionPct: session, sessionResetsAt: number(five["resets_at"]),
               weekPct: week, weekResetsAt: number(seven["resets_at"]), cost: cost, model: model)

        func bar(_ pct: Double, width: Int = 10) -> String {
            let filled = Int((pct / 100 * Double(width)).rounded())
            return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
        }
        var parts: [String] = []
        if let model { parts.append("[\(model)]") }
        if let session { parts.append("session \(bar(session)) \(Int(session.rounded()))%") }
        if let week { parts.append("week \(bar(week)) \(Int(week.rounded()))%") }
        if let ctx { parts.append("ctx \(Int(ctx.rounded()))%") }
        if let cost { parts.append(String(format: "$%.2f", cost)) }
        return parts.isEmpty ? "claude usage widget: waiting for data..." : parts.joined(separator: " ")
    }

    /// Writes one reading to live.json (atomically, 0600), keeping whichever of the new and old reading is
    /// newer for each window. Used by the hook (old installs) and by Cap's own refresh.
    static func record(sessionPct: Double?, sessionResetsAt: Double?, weekPct: Double?, weekResetsAt: Double?,
                       cost: Double? = nil, model: String? = nil) {
        // context_window is per-conversation, so it is deliberately not stored.
        let dir = supportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("live.json")

        // More than one thing can write this file (the hook of an older install, long-lived Claude sessions, Cap's
        // own refresh), and a long-lived session keeps the usage it saw when it started. So the newest data
        // must win, not the latest writer: within one window usage only goes up, and a newer window beats an older one.
        func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        let old = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        let now = Date().timeIntervalSince1970
        let mergedSession = newest(pct: sessionPct, resetsAt: sessionResetsAt,
                                   oldPct: number(old["session_used_pct"]), oldResetsAt: number(old["session_resets_at"]), now: now)
        let mergedWeek = newest(pct: weekPct, resetsAt: weekResetsAt,
                                oldPct: number(old["week_used_pct"]), oldResetsAt: number(old["week_resets_at"]), now: now)
        let out: [String: Any] = [
            "updated_at": now,
            "session_used_pct": mergedSession?.pct as Any? ?? NSNull(),
            "session_resets_at": mergedSession?.resetsAt as Any? ?? NSNull(),
            "week_used_pct": mergedWeek?.pct as Any? ?? NSNull(),
            "week_resets_at": mergedWeek?.resetsAt as Any? ?? NSNull(),
            "session_cost_usd": cost as Any? ?? NSNull(),
            "model": model as Any? ?? NSNull(),
        ]
        if let json = try? JSONSerialization.data(withJSONObject: out) {
            try? json.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Picks the newer of two usage readings for one window. A window whose reset time
    /// has passed is over and is dropped; a later reset time means a newer window; within
    /// the same window the higher percentage is the later reading.
    static func newest(pct: Double?, resetsAt: Double?, oldPct: Double?, oldResetsAt: Double?, now: Double) -> (pct: Double, resetsAt: Double)? {
        var candidates: [(resetsAt: Double, pct: Double)] = []
        if let pct, let resetsAt, resetsAt > now { candidates.append((resetsAt, pct)) }
        if let oldPct, let oldResetsAt, oldResetsAt > now { candidates.append((oldResetsAt, oldPct)) }
        guard let best = candidates.max(by: { ($0.resetsAt, $0.pct) < ($1.resetsAt, $1.pct) }) else { return nil }
        return (best.pct, best.resetsAt)
    }

    /// Runs the user's original statusLine command with the same stdin.
    private static func runOriginal(_ command: String, stdin: Data) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        let inPipe = Pipe(), outPipe = Pipe()
        task.standardInput = inPipe
        task.standardOutput = outPipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        inPipe.fileHandleForWriting.write(stdin)
        try? inPipe.fileHandleForWriting.close()
        let output = outPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: output, encoding: .utf8)
    }
}
