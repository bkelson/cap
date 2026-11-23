import Foundation

/// The "Sign in to Claude Code" button outside the welcome window: shown in the popover when a refresh finds Claude Code
/// signed out (for example its saved login expired after days of not being used). Same browser sign-in as step 2
/// (`ActiveSignIn`); Cap never sees a password. Only ever started by the user pressing the button.
@MainActor
final class SignInController: ObservableObject {
    enum State: Equatable {
        case idle
        case signingIn
        /// Sign-in worked; waiting for the first refresh to answer, so the strip doesn't flash the button again.
        case finishing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let resolveClaude: @Sendable () -> String?
    private let runSignIn: @Sendable (String, @escaping () -> Bool) -> ActiveSignIn.Outcome
    private let onSignedIn: () -> Void
    private let cancelFlag = CancelFlag()

    init(resolveClaude: @escaping @Sendable () -> String? = {
             ClaudeLocator.find(home: FileManager.default.homeDirectoryForCurrentUser, askShell: true, withVersion: false, preferNewest: true)?.path
         },
         runSignIn: @escaping @Sendable (String, @escaping () -> Bool) -> ActiveSignIn.Outcome = { ActiveSignIn.run(claudePath: $0, shouldCancel: $1) },
         onSignedIn: @escaping () -> Void) {
        self.resolveClaude = resolveClaude
        self.runSignIn = runSignIn
        self.onSignedIn = onSignedIn
    }

    func start() {
        guard state != .signingIn else { return }
        state = .signingIn
        cancelFlag.value = false
        let cancel = cancelFlag, resolve = resolveClaude, run = runSignIn
        Task {
            let outcome: ActiveSignIn.Outcome = await Task.detached {
                guard let path = resolve() else { return .failed("I couldn't find Claude Code to sign in with.") }
                return run(path) { cancel.value }
            }.value
            switch outcome {
            case .signedIn:
                state = .finishing
                onSignedIn()
                // Safety net: never stay on "getting your numbers" for long if no answer comes back.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    self?.refreshDone()
                }
            case .cancelled: state = .idle
            case .timedOut: state = .failed("That took too long. Try again when you're ready.")   // DRAFT copy
            case .failed(let why): state = .failed(why)
            }
        }
    }

    func cancel() { cancelFlag.value = true }

    /// The refresh that followed the sign-in has answered (with numbers or with a problem).
    func refreshDone() { if state == .finishing { state = .idle } }

    /// Preview only.
    func debugSet(_ state: State) { self.state = state }
}
