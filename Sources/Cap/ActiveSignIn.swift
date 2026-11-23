import Foundation

/// The one extra sign-in Active mode needs: Claude Desktop hands its own copy of Claude Code a private
/// token each time it starts it, so Cap's separate hidden session has nothing to read until it is signed in too.
/// This runs Claude Code's own `claude auth login`, which opens the normal Claude sign-in page in the
/// user's browser. Cap never sees a password or token; it only asks `claude auth status` afterwards.
/// Only ever started by the user pressing Continue with Active selected.
enum ActiveSignIn {
    enum Outcome: Equatable {
        case signedIn
        case cancelled
        case timedOut
        case failed(String)
    }

    /// How long to wait for the user to finish in the browser.
    static let timeout: TimeInterval = 300

    /// Starts the browser sign-in and waits until the account shows as a Pro/Max subscription (or it fails).
    /// `shouldCancel` is polled about twice a second. Blocking: call off the main thread.
    static func run(claudePath: String, shouldCancel: @escaping () -> Bool) -> Outcome {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: claudePath)
        task.arguments = ["auth", "login", "--claudeai"]
        task.environment = ClaudeRun.cleanEnvironment()
        task.standardInput = Pipe()          // never written to, never closed: nothing for it to read
        let sink = Pipe()
        task.standardOutput = sink
        task.standardError = sink
        // The same empty folder the hidden session uses, so the program has nothing broad to scan.
        let workspace = NSString(string: "~/.claude_usage_widget/feeder_workspace").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true)
        task.currentDirectoryURL = URL(fileURLWithPath: workspace)
        do { try task.run() } catch { return .failed("I couldn't start the sign-in.") }

        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning {
            if shouldCancel() { task.terminate(); return .cancelled }
            if Date() > deadline { task.terminate(); return .timedOut }
            Thread.sleep(forTimeInterval: 0.5)
        }
        task.waitUntilExit()
        if case .subscription = ClaudeAuth.status(claudePath: claudePath) { return .signedIn }
        return .failed("That sign-in didn't finish, or the account has no Pro or Max plan.")
    }
}
