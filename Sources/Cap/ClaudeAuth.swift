import Foundation

/// Whether Claude Code is signed in, and how — via the program's own
/// `claude auth status --json`. Cap never sees a password or token.
enum ClaudeAuth {
    enum Status: Equatable {
        case signedOut
        /// Signed in, but through the Anthropic Console (API billing), which has no usage limits to read.
        case apiBilling
        case subscription(plan: String?)
        case unknown(String)
    }

    /// Blocking (up to ~10 s): call off the main thread.
    static func status(claudePath: String) -> Status {
        // Take turns with Cap's refresh (never two Cap-started claude programs at once). If a refresh is taking long,
        // give up waiting rather than freeze the window that asked.
        guard ClaudeRun.gate.wait(timeout: .now() + 20) == .success else { return .unknown("Claude Code is busy right now.") }
        defer { ClaudeRun.gate.signal() }
        guard let output = ClaudeLocator.run(claudePath, ["auth", "status", "--json"], timeout: 15, environment: ClaudeRun.cleanEnvironment()),
              let data = output.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .unknown("I couldn't read Claude Code's sign-in status.")
        }
        guard json["loggedIn"] as? Bool == true else { return .signedOut }
        guard json["authMethod"] as? String == "claude.ai" else { return .apiBilling }
        // Signed in with a Claude account, but only a paid plan has Claude Code (and so usage limits to
        // read). A free account — or one with no plan listed — is treated like "not signed in to Pro or Max".
        let plan = (json["subscriptionType"] as? String)?.trimmingCharacters(in: .whitespaces)
        guard let plan, !plan.isEmpty, plan.lowercased() != "free" else { return .apiBilling }
        return .subscription(plan: plan)
    }
}
