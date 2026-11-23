import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Nil during the very first welcome window: Cap does not appear in the menu bar until the user clicks Done
    /// (or closes the window), so the setup is not competing with a live item (Brian, 2026-10-28).
    private var statusItem: NSStatusItem?
    private var popover: NSPopover!
    /// The little "It's me. Click for details." bubble shown under the menu bar item right after setup.
    private var helloBubble: NSPopover?
    private var finishedWithDone = false
    private let store = UsageStore()
    /// A preview (`--onboarding-preview`) uses its own throwaway settings, so acting out a scenario never changes real ones.
    private let preferences = CommandLine.arguments.contains("--onboarding-preview")
        ? Preferences(store: UserDefaults(suiteName: "ai.kelson.cap.preview") ?? .standard)
        : Preferences()
    private let backgroundFeeder = BackgroundFeeder()
    private lazy var signInController = SignInController(onSignedIn: { [weak self] in self?.backgroundFeeder.refreshNow() })
    private lazy var widgetStyle = WidgetStyleStore(preferences: preferences)
    private var floatingBar: PinnedWidgetController!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingModel: OnboardingModel?
    private var onboardingCloseObserver: NSObjectProtocol?
    private var statusItemTimer: Timer?
    private var preferencesSubscription: AnyCancellable?
    private var feederSubscription: AnyCancellable?
    private var lastStatusImageKey: String?
    private var alerts: UsageAlerts?
    private lazy var updateChecker = UpdateChecker(preferences: preferences)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if CAP_TEST_BUILD
        // Test builds only: `Cap --login-item on|off|status` switches Cap's own "Open at login" item from Terminal and
        // prints the result, then quits. Works beside a running Cap (it runs before the one-copy check).
        if let i = CommandLine.arguments.firstIndex(of: "--login-item") {
            let word = CommandLine.arguments.dropFirst(i + 1).first ?? "status"
            if word == "on" || word == "off" {
                do { try LoginItem.setEnabled(word == "on") } catch { print("error: \(error)") }
            }
            print("login item: enabled=\(LoginItem.isEnabled) needsApproval=\(LoginItem.needsApproval)")
            exit(0)
        }
        #endif
        NSApp.setActivationPolicy(.accessory)

        // Started from inside the installer disk image: ask the user to drag it to Applications first.
        if InstallerCleanup.isRunningFromDiskImage && !CommandLine.arguments.contains("--onboarding-preview") {
            InstallerCleanup.warnAndQuit()
            return
        }

        // `Cap --popover-preview` (CAP_PREVIEW_STATE=signedout|signingin|failed, CAP_PREVIEW_APPEARANCE=light|dark):
        // the popover's signed-out strip in a plain window, so it can be looked at without breaking a real login.
        if CommandLine.arguments.contains("--popover-preview") { showPopoverPreview(); return }
        // Test builds only (swift build -Xswiftc -DCAP_TEST_BUILD): `Cap --snapshot-states <folder>` writes PNGs of the popover and widget states (light and dark), then quits.
        #if CAP_TEST_BUILD
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-states"), let dir = CommandLine.arguments.dropFirst(i + 1).first {
            StateSnapshots.run(outDir: dir); return
        }
        #endif

        // `Cap --onboarding-preview` (with CAP_HOME set) shows only the welcome window,
        // working on a throwaway home folder so real settings are never touched.
        if CommandLine.arguments.contains("--onboarding-preview") {
            showOnboarding(preview: true)
            return
        }

        // One Cap at a time: a login item and a LaunchAgent (or a double-click) must not
        // start a second copy, which would run a second feeder and a second menu bar item.
        let me = NSRunningApplication.current
        if let bundleID = me.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != me.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }

        // The popover must exist before the menu bar item: the item's first redraw looks at it (build 25/26 crashed
        // at launch for anyone who had finished setup, because this order was reversed).
        popover = NSPopover()
        popover.behavior = .transient

        // Setup not done yet (first launch): no menu bar item until Done. Everyone else gets it straight away.
        if preferences.hasCompletedOnboarding { installStatusItem() }

        rebuildContent()

        floatingBar = PinnedWidgetController(
            store: store, styleStore: widgetStyle, preferences: preferences,
            statusItemFrame: { [weak self] in self?.statusItem?.button?.window?.frame },
            onClose: { [weak self] in self?.setPinned(false) }
        )
        // Clicking the widget's "Sign in" plate starts the browser sign-in and opens the popover (design A9).
        floatingBar.onSignIn = { [weak self] in
            guard let self else { return }
            if case .idle = self.signInController.state { self.signInController.start() }
            self.showPopover()
        }
        // Clicking Cap's signed-out notification opens the popover at the sign-in strip (design A11).
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        updateStatusItemAppearance()

        // Show after the menu bar item has its final size, so the widget's first
        // position can hang beneath the item's left edge.
        if preferences.isPinned {
            DispatchQueue.main.async { [weak self] in self?.floatingBar.show() }
        }
        statusItemTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItemAppearance() }
        }
        preferencesSubscription = preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItemAppearance() }
        }

        backgroundFeeder.refreshIntervalProvider = {
            TimeInterval(Preferences.fixedRefreshIntervalSeconds)
        }
        alerts = UsageAlerts(preferences: preferences, store: store)
        alerts?.start()
        // Claude Code 2.1.318+ says when the saved sign-in ends: keep that date so the popover and a notification can offer a
        // renewal before it lapses (nil clears it when signed out).
        backgroundFeeder.onLoginEnd = { [weak self] end in
            guard let self, self.preferences.loginEndsAt != end else { return }
            self.preferences.loginEndsAt = end
        }
        // Signed out (or back in): the menu bar item and the widget switch state, and the user is told once per lapse.
        feederSubscription = backgroundFeeder.$status.sink { [weak self] status in
            guard let self else { return }
            self.store.signedOut = (status == .needsSignIn)
            self.store.awaitingFirstReading = (status == .idle)
            if status != .idle { self.signInController.refreshDone() }
            switch status {
            // Only an expired login is a surprise worth a notification; a plain "Not logged in" (the user signed out) is not.
            case .needsSignIn: self.alerts?.signInChanged(self.backgroundFeeder.signOutIsExpiry ? .lost : .other)
            case .ok: self.alerts?.signInChanged(.recovered)
            default: self.alerts?.signInChanged(.other)
            }
        }
        store.start()
        widgetStyle.start()
        backgroundFeeder.start()

        // First launch, or the status hook has gone missing: show the welcome window.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Right after install: if the installer disk is still mounted, offer to eject it and
            // move the downloaded file to the Trash (before anything else, as people expect).
            InstallerCleanup.offerEjectAndDelete()
            if !self.preferences.hasCompletedOnboarding {
                self.showOnboarding(preview: false)
            }
        }
    }

    /// Quit. A refresh that is already running gets up to 3 seconds to finish and save a renewed login, but the wait
    /// happens with the app still responsive (`terminateLater`), not by blocking the main thread: blocking it showed the
    /// spinning wheel and could leave Cap half-quit (Pass F, 2026-10-29).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.stop()
        widgetStyle.stop()
        backgroundFeeder.stop()
        statusItemTimer?.invalidate()
        guard backgroundFeeder.isRefreshing else { return .terminateNow }
        Task { @MainActor in
            let end = Date().addingTimeInterval(3)
            while self.backgroundFeeder.isRefreshing && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func rebuildContent() {
        let view = ContentView(
            store: store,
            preferences: preferences,
            feeder: backgroundFeeder,
            signIn: signInController,
            isPinned: preferences.isPinned,
            onTogglePin: { [weak self] in self?.setPinned(!(self?.preferences.isPinned ?? false)) },
            onShowAbout: { [weak self] in self?.showAbout() },
            onShowSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    /// Creates Cap's menu bar item. Safe to call more than once.
    private func installStatusItem() {
        guard statusItem == nil else { return }
        // Software updates: ask GitHub once a day (the first check waits until the welcome window is done).
        updateChecker.onNewVersion = { [weak self] version in
            guard let self, self.preferences.notificationsEnabled else { return }
            UsageAlerts.postUpdateAvailable(version: version)
        }
        updateChecker.start()
        // The capsule is lighter or heavier with "Reduce transparency"; redraw when that setting changes.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lastStatusImageKey = nil; self?.updateStatusItemAppearance() }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
        lastStatusImageKey = nil
        updateStatusItemAppearance()
        if preferences.isPinned { DispatchQueue.main.async { [weak self] in self?.floatingBar?.show() } }
    }

    /// "It's me. Click for details." under the live menu bar item, once, right after the welcome window's Done.
    /// Stays for 60 seconds (Brian: long enough to encourage a first click), or until the user clicks the menu bar item; then it goes away.
    private func showHelloBubble() {
        // A brand-new menu bar item has no position for a moment. Showing the bubble too early put it far from the menu bar
        // (Pass E), or not at all. So wait until the item's window sits at the top of a screen, then give it a beat to settle.
        Task { @MainActor [weak self] in
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if self?.statusItemIsPlaced() == true { break }
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.presentHelloBubble()
        }
    }

    /// The menu bar item has a real window on a screen, near the top edge, with a width.
    private func statusItemIsPlaced() -> Bool {
        guard let window = statusItem?.button?.window, let screen = window.screen else { return false }
        return window.isVisible && window.frame.width > 4 && window.frame.maxY >= screen.frame.maxY - 60
    }

    private func presentHelloBubble() {
        guard let button = statusItem?.button, statusItemIsPlaced(), !popover.isShown else { return }
        let bubble = NSPopover()
        bubble.behavior = .applicationDefined   // stays put (clicks elsewhere do not close it) so a first-time user has time to try it
        bubble.animates = true
        // Clicking the bubble does what it says: it goes away and the popover opens.
        let label = Text("It's me. Click for details.")
            .font(.system(size: 13, weight: .medium))
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { [weak self] in self?.dismissHelloBubble(); self?.showPopover() }
        // Cap is a menu bar app and the bubble's window is not key, so by default the first click only makes it key
        // (the bubble turned "selected" and did nothing, Pass F and H). `FirstMouseHostingView` lets that click through.
        let hostingView = FirstMouseHostingView(rootView: label)
        let controller = NSViewController()
        controller.view = hostingView
        bubble.contentViewController = controller
        bubble.contentSize = hostingView.fittingSize   // sized to the words, not left to guess (it looked deformed)
        bubble.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        helloBubble = bubble
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.dismissHelloBubble() }   // no interaction in a minute: it goes away
    }

    private func dismissHelloBubble() {
        helloBubble?.performClose(nil)
        helloBubble = nil
    }

    private var aboutWindow: NSWindow?

    private func showAbout() {
        popover.performClose(nil)
        if aboutWindow == nil {
            let hosting = NSHostingView(rootView: AboutView())
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "About Cap"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = hosting
            window.center()
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Popover preview

    private var popoverPreviewWindow: NSWindow?

    private func showPopoverPreview() {
        let env = ProcessInfo.processInfo.environment
        backgroundFeeder.debugSet(status: .needsSignIn)
        switch env["CAP_PREVIEW_STATE"] {
        case "signingin": signInController.debugSet(.signingIn)
        case "failed": signInController.debugSet(.failed("That sign-in didn't finish, or the account has no Pro or Max plan."))
        default: break
        }
        store.start()
        let view = ContentView(store: store, preferences: preferences, feeder: backgroundFeeder, signIn: signInController,
                               isPinned: false, onTogglePin: {}, onQuit: { NSApp.terminate(nil) })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "PREVIEW · popover, signed out"
        window.styleMask = [.titled, .closable]
        if let a = env["CAP_PREVIEW_APPEARANCE"] { window.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua) }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        popoverPreviewWindow = window
    }

    // MARK: Welcome window

    private func showOnboarding(preview: Bool) {
        if let window = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        var claudeHome: URL?
        var applicationFolders: [URL]?
        if preview, let home = ProcessInfo.processInfo.environment["CAP_HOME"] {
            applicationFolders = [URL(fileURLWithPath: home).appendingPathComponent("Applications")]
            claudeHome = URL(fileURLWithPath: home)   // look for Claude Code only in the throwaway home
        }
        let model = OnboardingModel(
            preferences: preferences,
            claudeHome: claudeHome,
            applicationFolders: applicationFolders,
            isPreview: preview,
            onHighlightStatusItem: { [weak self] in self?.pulseStatusItem() },
            onNeedsAttention: { [weak self] in self?.bringOnboardingToFront() },
            onSignedIn: { [weak self] in if !preview { self?.backgroundFeeder.refreshNow() } },
            onFinish: { [weak self] in
                if !preview { self?.backgroundFeeder.refreshNow() }
                self?.finishedWithDone = true
                self?.onboardingWindow?.close()

                if preview { NSApp.terminate(nil) }
            }
        )

        var previewAppearance: NSAppearance?
        // Preview only: CAP_PREVIEW_STEP=n opens on step n (1-5).
        if preview {
            let env = ProcessInfo.processInfo.environment
            if let n = env["CAP_PREVIEW_STEP"].flatMap(Int.init), (1...OnboardingModel.stepCount).contains(n) { model.step = n - 1 }
            previewAppearance = env["CAP_PREVIEW_APPEARANCE"].flatMap { $0 == "light" ? NSAppearance(named: .aqua) : $0 == "dark" ? NSAppearance(named: .darkAqua) : nil }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false   // never brought back by macOS at the next launch
        let hosting = NSHostingView(rootView: OnboardingView(model: model, preferences: preferences))
        hosting.sizingOptions = []   // the window stays exactly the size set below, whatever the content asks for
        window.contentView = hosting
        // The design's 680 × 620 includes the titlebar area, but a titled window adds its titlebar to contentRect.
        var frame = window.frame
        frame.size = NSSize(width: 680, height: 620)
        window.setFrame(frame, display: false)
        if let previewAppearance { window.appearance = previewAppearance }   // preview only: look at the other appearance
        window.center()

        onboardingCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.onboardingModel?.stop()
                self?.onboardingModel = nil
                self?.onboardingWindow = nil
                if preview { NSApp.terminate(nil) }
                // The welcome window is gone: now Cap appears in the menu bar. After Done it says hello; if the window was
                // just closed, the item still appears (otherwise Cap would be running with nothing to click).
                if !preview, self?.statusItem == nil {
                    self?.installStatusItem()
                    if self?.finishedWithDone == true { self?.showHelloBubble() }
                }
            }
        }
        onboardingModel = model
        onboardingWindow = window
        model.start()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Raises the welcome window above other apps without taking keyboard focus (so it can't swallow what the
    /// user is typing elsewhere), restoring it first if it was minimized. If macOS doesn't let it come forward,
    /// the menu bar item pulses instead.
    private func bringOnboardingToFront() {
        guard let window = onboardingWindow else { return }   // closed on purpose: leave it closed
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        if !window.isVisible || !window.isOnActiveSpace { pulseStatusItem() }
    }

    /// A short pulse on the real menu bar item so people can see where Cap lives.
    private func pulseStatusItem() {
        guard let button = statusItem?.button else { return }
        // `button.highlight(_:)` drew nothing on macOS 27 (Pass B and C: no flashes seen), so flash the item's own layer
        // with a brand-colour backing three times instead (DRAFT look).
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        let on = NSColor(Brand.terracotta).withAlphaComponent(0.55).cgColor
        let off = NSColor(Brand.terracotta).withAlphaComponent(0).cgColor
        let flash = CAKeyframeAnimation(keyPath: "backgroundColor")
        flash.values = [off, on, off, on, off, on, off]
        flash.keyTimes = [0, 0.17, 0.33, 0.5, 0.67, 0.83, 1]
        flash.duration = 2.1
        layer.add(flash, forKey: "capPulse")
    }

    private func showSettings(pane: SettingsView.Pane = .general) {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: SettingsView.windowSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Cap Settings"
            window.isRestorable = false   // macOS must not bring the Settings window back by itself at the next launch
            window.titlebarAppearsTransparent = true   // the sidebar runs up under the traffic lights
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(
            preferences: preferences, checker: updateChecker,
            onShowWelcome: { [weak self] in self?.showOnboarding(preview: false) }, initialPane: pane))
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func setPinned(_ pinned: Bool) {
        preferences.isPinned = pinned
        if pinned {
            popover.performClose(nil)
            floatingBar.show()
        } else {
            floatingBar.hide()
        }
        rebuildContent()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        let sessionPct = store.sessionPct
        let weekPct = store.weekPct
        let inline = preferences.showInlineMenuBarStats

        // Only rebuild the image when something visible changed.
        let signedOut = store.signedOut
        let key = "\(inline)|\(signedOut)|\(UsageFormat.percent(sessionPct))|\(UsageFormat.percent(weekPct))|\(DialRenderer.Severity(pct: sessionPct))|\(DialRenderer.Severity(pct: weekPct))"
        if key == lastStatusImageKey { return }
        lastStatusImageKey = key

        button.title = ""
        button.imagePosition = .imageOnly
        if signedOut {
            button.image = DialRenderer.collapsedImage(sessionPct: nil, signedOut: true)
            reanchorPopoverIfShown()
            button.setAccessibilityLabel("Signed out of Claude Code. Open Cap to sign in.")
            return
        }
        button.image = inline
            ? DialRenderer.inlineImage(sessionPct: sessionPct, weekPct: weekPct)
            : DialRenderer.collapsedImage(sessionPct: sessionPct)
        reanchorPopoverIfShown()
        button.setAccessibilityLabel("Claude usage: session \(UsageFormat.percent(sessionPct)), all models \(UsageFormat.percent(weekPct))")
    }

    /// The status item changes width when "Show in menu bar" flips, but an open
    /// popover keeps the anchor rect it was shown with. Re-point it at the
    /// button's new bounds once the item has laid out.
    private func reanchorPopoverIfShown() {
        guard let popover, popover.isShown else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard let self, self.popover.isShown, let button = self.statusItem?.button else { return }
            self.popover.positioningRect = button.bounds
        }
    }

    /// Opens the popover under the menu bar item (from a notification or the widget), if it is not open already.
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard !popover.isShown else { return }
        rebuildContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        completionHandler()
        if id == "cap.signedout" || id == "cap.loginending" { Task { @MainActor in self.showPopover() } }
        if id == "cap.update" { Task { @MainActor in self.showSettings(pane: .updates) } }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        dismissHelloBubble()
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            rebuildContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

/// A SwiftUI view in a window that is not key still receives the very first click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
