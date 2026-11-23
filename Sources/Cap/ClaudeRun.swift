import Foundation

/// Shared rules for every time Cap starts the user's `claude` program (the refresh, `auth status`, sign-in).
/// Claude Code keeps one saved login that every Claude program renews; reports say overlapping renewals, and a program
/// that is cut off before it has saved the renewed login, are how logins get lost. So Cap runs its own calls one at a time,
/// measures time in a way that sleep cannot skew, and never hands the program a stray key from the environment.
enum ClaudeRun {
    /// One Cap-started `claude` at a time (the refresh and `auth status` take turns).
    static let gate = DispatchSemaphore(value: 1)

    /// Seconds since boot, NOT counting time the Mac was asleep. A deadline measured on the wall clock would expire the moment
    /// the Mac wakes from a sleep that began mid-call, and Cap would cut the program off in the middle of renewing the login.
    static func uptime() -> TimeInterval { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000 }

    /// Settings that would send Claude Code somewhere other than the user's Pro/Max login: an API key (the call would be billed
    /// per token and carry no usage limits) or a pasted token. A shell may export these; a login item does not. Removed either way.
    static let overridingVariables = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"]

    static func cleanEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in overridingVariables { env.removeValue(forKey: key) }
        return env
    }
}
