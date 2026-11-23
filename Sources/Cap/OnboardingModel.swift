import AppKit
import Combine
import SwiftUI

/// State and actions for the first-run welcome window (ONBOARDING.md).
/// A flag the sign-in's background thread can read while the window sets it.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); flag = newValue; lock.unlock() }
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    enum ClaudeState: Equatable {
        case checking
        case found(version: String?, viaDesktop: Bool)
        case missing
        /// The Claude app is installed, but it hasn't downloaded its built-in Claude Code yet (it only does
        /// that once someone is signed in to the app and opens its Code tab). Shown to the user as a normal
        /// "installed" row 1 and a waiting row 2, never as a problem.
        case desktopNotReady
    }

    enum AuthState: Equatable {
        case waiting                    // Claude Code isn't there yet, so there's nothing to check
        case checking
        case subscription(plan: String?)
        /// Claude Desktop's built-in Claude Code exists (so the user is signed in to the app), but Claude Code itself
        /// has no saved login Cap can use: Desktop hands its login only to the copy it starts itself.
        case needsSignIn
        /// A standalone Claude Code that is signed out, or signed in with API billing (no Pro/Max limits to read).
        case notSignedIn
        /// Signed in, but on a plan with no usage limits to read (API billing or a free plan): signing in again will not fix it.
        case noPlan
        case signingIn
        case signInFailed(String)
        case failed(String)             // the sign-in status couldn't be read
    }

    static let stepCount = 5
    static let downloadURL = URL(string: "https://claude.ai/download")!
    /// Opens Claude's Code tab (a link the app registers); if the app can't, it just opens the app.
    static let codeTabURL = URL(string: "claude://code/new")!

    @Published var step = 0
    @Published private(set) var claude: ClaudeState = .checking { didSet { if claude != oldValue { log("claude → \(claude)") } } }
    @Published private(set) var auth: AuthState = .waiting { didSet { if auth != oldValue { log("auth → \(auth)") } } }
    /// True while a "Check again" is running, so its button can read "Checking…".
    @Published private(set) var rechecking = false
    /// Bumped each time the user presses "Check again" and that row is still failing; the row reacts with a small shake.
    @Published private(set) var claudeShake = 0
    @Published private(set) var authShake = 0
    /// Off until the user turns it on (Brian, 2026-11-15; see docs/DECISIONS.md). Cap never adds itself as a login item unasked.
    @Published var launchAtLogin = false
    /// The user pressed "Open Claude" (so row 2 can say "Finishing setup…" instead of asking again).
    @Published private(set) var openedClaude = false
    /// Bumped when a row turns green while the window is behind other apps: the row plays its "it's done" cue (Batch B).
    @Published private(set) var claudeCue: Date?
    @Published private(set) var authCue: Date?
    /// The very first look at Claude takes at least 0.6 s, so "Looking for Claude Code…" never just flashes (Batch B).
    private var didFirstCheck = false
    /// Bumped when the notification switch is turned back off because macOS didn't allow alerts.
    @Published private(set) var notificationsDenied = 0
    /// Preview mode only: says the window is acting out a scenario, so it can't be mistaken for the real thing.
    let previewNote: String?

    let preferences: Preferences
    /// When set (preview mode), Claude Code is looked for only under this folder.
    private let claudeHome: URL?
    /// Where to look for the Claude app (preview mode points this at the throwaway home).
    private let applicationFolders: [URL]
    private let isPreview: Bool
    private let onFinish: () -> Void
    private let onHighlightStatusItem: () -> Void
    /// Called when a step 2 row turns green while the window may be hidden behind other apps.
    private let onNeedsAttention: () -> Void
    /// Claude Code is signed in: the first refresh can happen now.
    private let onSignedIn: () -> Void

    private var pollTimer: Timer?
    private var checking = false
    private let cancelFlag = CancelFlag()

    init(preferences: Preferences,
         claudeHome: URL? = nil,
         applicationFolders: [URL]? = nil,
         isPreview: Bool = false,
         onHighlightStatusItem: @escaping () -> Void = {},
         onNeedsAttention: @escaping () -> Void = {},
         onSignedIn: @escaping () -> Void = {},
         onFinish: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.claudeHome = claudeHome
        self.applicationFolders = applicationFolders ?? [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        self.previewNote = isPreview ? ProcessInfo.processInfo.environment["CAP_PREVIEW_NOTE"] : nil
        self.isPreview = isPreview
        self.onHighlightStatusItem = onHighlightStatusItem
        self.onNeedsAttention = onNeedsAttention
        self.onSignedIn = onSignedIn
        self.onFinish = onFinish
    }

    /// For previews and tests: put the model into a given state without running detection.
    func debugSet(claude: ClaudeState, auth: AuthState) {
        self.claude = claude
        self.auth = auth
    }

    /// Preview mode only: appends to `$CAP_HOME/onboarding-preview.log` so a test can see what the window did.
    private func log(_ line: String) {
        guard isPreview, let home = ProcessInfo.processInfo.environment["CAP_HOME"] else { return }
        let url = URL(fileURLWithPath: home).appendingPathComponent("onboarding-preview.log")
        let stamp = String(format: "%.1f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        let data = Data("[\(stamp)] \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(data); try? handle.close() }
        else { try? data.write(to: url) }
    }

    // MARK: Lifecycle

    func start() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        cancelFlag.value = true
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Detection

    /// Looks for Claude Code, then (only if found) checks the sign-in.
    func refresh() {
        Task { await performChecks() }
    }

    private func performChecks() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }

        let before = (row1Green, row2Green, claude == .checking)
        let home = claudeHome ?? FileManager.default.homeDirectoryForCurrentUser
        let askShell = claudeHome == nil
        let began = Date()
        let found = await Task.detached { ClaudeLocator.find(home: home, askShell: askShell, withVersion: true) }.value
        if !didFirstCheck {
            didFirstCheck = true
            let spent = Date().timeIntervalSince(began)
            if spent < 0.6 { try? await Task.sleep(nanoseconds: UInt64((0.6 - spent) * 1_000_000_000)) }
        }

        if let found {
            claude = .found(version: found.version, viaDesktop: found.isDesktopBundle)
            // Don't overwrite a sign-in the user is in the middle of.
            if auth != .signingIn {
                if auth == .waiting { auth = .checking }
                let status = await Task.detached { ClaudeAuth.status(claudePath: found.path) }.value
                if auth != .signingIn {
                    switch status {
                    case .subscription(let plan): auth = .subscription(plan: plan)
                    // Claude Desktop's built-in copy only exists once someone has signed in to the app and
                    // opened its Code tab; what it lacks is a login of its own for Cap to use.
                    case .signedOut: auth = found.isDesktopBundle ? .needsSignIn : .notSignedIn
                    case .apiBilling: auth = .noPlan
                    case .unknown(let why): auth = .failed(why)
                    }
                }
            }
        } else {
            claude = ClaudeLocator.desktopAppInstalled(in: applicationFolders) ? .desktopNotReady : .missing
            if auth != .signingIn { auth = .waiting }
        }

        // A row just turned green while the window may be behind other apps (the user went off to install
        // or sign in): bring it back so they can carry on. Not on the very first check.
        let after = (row1Green, row2Green)
        let windowInBackground = !(NSApp?.isActive ?? true)   // no NSApplication (a test): treat as in front
        if !before.2 && ((after.0 && !before.0) || (after.1 && !before.1)) { onNeedsAttention() }
        if !before.2 && windowInBackground {
            if after.0 && !before.0 { claudeCue = Date() }
            if after.1 && !before.1 { authCue = Date() }
        }
        if after.1 && !before.1 { onSignedIn() }
    }

    /// Row 1: Claude is on this Mac (the Claude app is enough; it needn't have been opened yet).
    var row1Green: Bool {
        switch claude {
        case .found, .desktopNotReady: return true
        case .checking, .missing: return false
        }
    }

    /// Row 2: Claude Code is signed in to a paid plan, so Cap can read the limits.
    var row2Green: Bool {
        if case .subscription = auth { return true }
        return false
    }

    // MARK: Actions

    func openClaudeDownload() {
        NSWorkspace.shared.open(Self.downloadURL)
    }

    /// Opens the Claude app on its Code tab so it can finish setting up Claude Code.
    func openClaudeCodeTab() {
        openedClaude = true
        if !NSWorkspace.shared.open(Self.codeTabURL),
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.open(app)
        }
    }

    /// "Check again": re-runs detection. The button reads "Checking…" for at least a
    /// moment so the click visibly does something, even though the check is quick.
    func checkAgain() {
        guard !rechecking else { return }
        log("Check again pressed")
        rechecking = true
        let started = Date()
        let claudeWasMissing = claude == .missing || claude == .desktopNotReady
        let authWasFailing: Bool = { if case .notSignedIn = auth { return true }; if case .failed = auth { return true }; return false }()
        Task {
            while checking { try? await Task.sleep(nanoseconds: 50_000_000) }
            await performChecks()
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.7 { try? await Task.sleep(nanoseconds: UInt64((0.7 - elapsed) * 1_000_000_000)) }
            rechecking = false
            // Checked, and it is still not fixed: say so with a shake instead of nothing.
            if claudeWasMissing && (claude == .missing || claude == .desktopNotReady) { claudeShake += 1 }
            let authStillFailing: Bool = { if case .notSignedIn = auth { return true }; if case .failed = auth { return true }; return false }()
            if authWasFailing && authStillFailing { authShake += 1 }
            log("Check again finished: claude=\(claude) auth=\(auth) shakes=\(claudeShake)/\(authShake)")
        }
    }

    /// "Sign in to Claude Code": Claude Code's own browser sign-in (`ActiveSignIn`). Only ever started by
    /// the user pressing the button. A failure isn't designed yet, so for now the row just says what happened.
    func signIn() {
        guard auth != .signingIn else { return }
        let path: String? = {
            let home = claudeHome ?? FileManager.default.homeDirectoryForCurrentUser
            return ClaudeLocator.find(home: home, askShell: claudeHome == nil, withVersion: false, preferNewest: true)?.path
        }()
        guard let path else { auth = .signInFailed("I couldn't find Claude Code to sign in with."); return }
        auth = .signingIn
        cancelFlag.value = false
        let cancel = cancelFlag
        log("sign-in started")
        Task {
            let outcome = await Task.detached {
                ActiveSignIn.run(claudePath: path) { cancel.value }
            }.value
            log("sign-in outcome: \(outcome)")
            switch outcome {
            case .signedIn:
                // The re-check turns row 2 green, which brings the window forward and starts the first refresh.
                auth = .checking
                await performChecks()
            case .cancelled: auth = .needsSignInOrNot(for: claude)
            case .timedOut: auth = .signInFailed("That took too long. Try again when you're ready.")
            case .failed(let why): auth = .signInFailed(why)
            }
        }
    }

    func cancelSignIn() { cancelFlag.value = true }

    /// The notification switch on step 3: macOS gets asked; if it says no, the switch goes back off.
    func setNotifications(_ on: Bool) {
        guard on else { preferences.notificationsEnabled = false; return }
        UsageAlerts.requestPermission { [weak self] granted in
            guard let self else { return }
            self.preferences.notificationsEnabled = granted
            if !granted { self.notificationsDenied += 1 }
        }
    }

    // MARK: Navigation

    var primaryTitle: String {
        switch step {
        case 0: return "Let's go"
        case 4: return "Done"
        default: return "Continue"
        }
    }

    /// Step 2 stays blocked until Claude Code is there and signed in.
    var canContinue: Bool {
        guard step == 1 else { return true }
        return row1Green && row2Green
    }

    func goBack() {
        if auth == .signingIn { cancelFlag.value = true }
        if step > 0 { step -= 1 }
    }
    func jump(to index: Int) { if auth == .signingIn { cancelFlag.value = true }; if index <= step { step = index } }

    func advance() {
        guard canContinue else { return }
        if step < Self.stepCount - 1 {
            step += 1
            if step == 4 { highlightStatusItem() }
        } else {
            finish()
        }
    }

    func finish() {
        preferences.hasCompletedOnboarding = true
        if launchAtLogin && !isPreview { try? LoginItem.setEnabled(true) }
        stop()
        onFinish()
    }

    /// A short pulse on the real menu bar item so people can see where Cap lives.
    func highlightStatusItem() { onHighlightStatusItem() }
}

private extension OnboardingModel.AuthState {
    /// After a cancelled sign-in, go back to the state the row was in before it.
    static func needsSignInOrNot(for claude: OnboardingModel.ClaudeState) -> OnboardingModel.AuthState {
        if case .found(_, let viaDesktop) = claude { return viaDesktop ? .needsSignIn : .notSignedIn }
        return .waiting
    }
}
