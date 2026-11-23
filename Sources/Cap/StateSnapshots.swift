#if CAP_TEST_BUILD
import AppKit
import SwiftUI

/// `Cap --snapshot-states <folder>` draws the popover and pinned-widget states to PNG files (light and dark) and quits.
/// For checking a design against the real views without driving the app. Uses throwaway settings and made-up numbers.
@MainActor
enum StateSnapshots {
    private struct Scenario {
        let name: String
        let status: BackgroundFeeder.Status
        let hasReading: Bool
        var readingAgeMinutes: Int = 0
        var signedOut = false
        var awaitingFirst = false
        var slow = false
        var signIn: SignInController.State = .idle
        /// Days until the Claude Code sign-in ends (for the renewal strip); nil = no end date known.
        var loginEndsInDays: Double?
    }

    private static let scenarios: [Scenario] = [
        Scenario(name: "live", status: .ok(Date()), hasReading: true),
        Scenario(name: "first-reading", status: .idle, hasReading: false, awaitingFirst: true),
        Scenario(name: "first-reading-slow", status: .idle, hasReading: false, awaitingFirst: true, slow: true),
        Scenario(name: "signed-out", status: .needsSignIn, hasReading: true, signedOut: true),
        Scenario(name: "signed-out-finishing", status: .needsSignIn, hasReading: true, signedOut: true, signIn: .finishing),
        Scenario(name: "offline", status: .offline, hasReading: true, readingAgeMinutes: 12),
        Scenario(name: "no-limits", status: .noLimits, hasReading: false),
        Scenario(name: "claude-missing", status: .claudeMissing, hasReading: true),
        Scenario(name: "renew-5-days", status: .ok(Date()), hasReading: true, loginEndsInDays: 5),
        Scenario(name: "renew-last-hours", status: .ok(Date()), hasReading: true, loginEndsInDays: 0.4),
    ]

    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "ai.kelson.cap.snapshots") ?? .standard
        var written: [String] = []
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .dark ? "dark" : "light"
            for s in scenarios {
                let preferences = Preferences(store: defaults)
                let store = UsageStore()
                let feeder = BackgroundFeeder()
                feeder.debugSet(status: s.status)
                let signIn = SignInController(onSignedIn: {})
                if s.signIn != .idle { signIn.debugSet(s.signIn) }
                let now = Date()
                preferences.loginEndsAt = s.loginEndsInDays.map { now.addingTimeInterval($0 * 86400) }
                if s.hasReading {
                    store.sessionPct = 31; store.sessionResetsAt = now.addingTimeInterval(2 * 3600 + 17 * 60)
                    store.weekPct = 9; store.weekResetsAt = now.addingTimeInterval(3 * 86400)
                    store.liveUpdatedAt = now.addingTimeInterval(-Double(s.readingAgeMinutes) * 60)
                }
                store.now = s.slow ? now.addingTimeInterval(60) : now
                store.signedOut = s.signedOut
                store.awaitingFirstReading = s.awaitingFirst

                let popover = ContentView(store: store, preferences: preferences, feeder: feeder, signIn: signIn,
                                          isPinned: false, onTogglePin: {}, onQuit: {})
                if let f = write(popover, scheme: scheme, to: dir.appendingPathComponent("popover-\(s.name)-\(tag).png")) { written.append(f) }

                // Widgets only for the states that change them.
                guard ["live", "first-reading", "signed-out"].contains(s.name) else { continue }
                for layout in [PinnedLayout.small, .medium, .strip] {
                    preferences.pinnedLayout = layout
                    let styleStore = WidgetStyleStore(preferences: preferences)
                    let widget = PinnedWidgetView(store: store, styleStore: styleStore, preferences: preferences, onClose: {})
                    let size: CGSize = layout == .small ? CGSize(width: 170, height: 170)
                        : layout == .medium ? CGSize(width: 360, height: 138) : CGSize(width: 390, height: 52)
                    let framed = widget.frame(width: size.width, height: size.height).padding(24)
                        .background(scheme == .dark ? Color(white: 0.18) : Color(white: 0.9))
                    if let f = write(framed, scheme: scheme, to: dir.appendingPathComponent("widget-\(layout)-\(s.name)-\(tag).png")) { written.append(f) }
                }
            }
        }
        // The welcome window: step 2 in each of its states, and step 5, light and dark.
        let welcome: [(String, OnboardingModel.ClaudeState, OnboardingModel.AuthState, Int)] = [
            ("looking", .checking, .waiting, 1),
            ("not-installed", .missing, .waiting, 1),
            ("open-claude", .desktopNotReady, .waiting, 1),
            ("finishing", .found(version: nil, viaDesktop: true), .checking, 1),
            ("sign-in-needed", .found(version: nil, viaDesktop: true), .needsSignIn, 1),
            ("signing-in", .found(version: nil, viaDesktop: true), .signingIn, 1),
            ("failed", .found(version: nil, viaDesktop: true), .noPlan, 1),
            ("done", .found(version: nil, viaDesktop: true), .subscription(plan: "pro"), 1),
            ("step4", .found(version: nil, viaDesktop: true), .subscription(plan: "pro"), 3),
            ("step4-expanded", .found(version: nil, viaDesktop: true), .subscription(plan: "pro"), 3),
            ("step5", .found(version: nil, viaDesktop: true), .subscription(plan: "pro"), 4),
        ]
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .dark ? "dark" : "light"
            for (name, claude, auth, step) in welcome {
                let preferences = Preferences(store: defaults)
                let model = OnboardingModel(preferences: preferences, isPreview: false)
                model.debugSet(claude: claude, auth: auth)
                model.step = step
                preferences.showInlineMenuBarStats = name.hasSuffix("expanded")
                let view = OnboardingView(model: model, preferences: preferences)
                if let f = write(view, scheme: scheme, to: dir.appendingPathComponent("welcome-\(name)-\(tag).png")) { written.append(f) }
            }
        }
        // Settings: each pane, light and dark.
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .dark ? "dark" : "light"
            for pane in SettingsView.Pane.allCases {
                let preferences = Preferences(store: defaults)
                let view = SettingsView(preferences: preferences, checker: UpdateChecker(preferences: preferences), initialPane: pane)
                if let f = write(view, scheme: scheme, to: dir.appendingPathComponent("settings-\(pane.rawValue.lowercased())-\(tag).png")) { written.append(f) }
            }
        }
        // About window, light and dark (the sponsor line is hidden until sponsorship is approved).
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .dark ? "dark" : "light"
            if let f = write(AboutView(), scheme: scheme, to: dir.appendingPathComponent("about-\(tag).png")) { written.append(f) }
        }
        // Menu bar item: Compact and Expanded on light and dark bars (template images tinted the way macOS does), with widths.
        let readings: [(String, Double?, Double?, Bool)] = [
            ("compact-31", 31, 5, false), ("expanded-31-5", 31, 5, true), ("expanded-88-88", 88, 88, true),
            ("compact-nil", nil, nil, false), ("compact-warn", 75, 5, false),
        ]
        var widths: [String] = []
        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            let ink: NSColor = dark ? .white : .black
            let bar: NSColor = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.91, alpha: 1)
            var items: [(String, NSImage)] = readings.map { r in
                (r.0, r.3 ? DialRenderer.inlineImage(sessionPct: r.1, weekPct: r.2) : DialRenderer.collapsedImage(sessionPct: r.1))
            }
            items.append(("signed-out", DialRenderer.collapsedImage(sessionPct: nil, signedOut: true)))
            let rowW = items.reduce(CGFloat(24)) { $0 + $1.1.size.width + 24 }
            let scale: CGFloat = 4
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rowW * scale), pixelsHigh: Int(37 * scale), bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            bar.setFill(); NSRect(x: 0, y: 0, width: rowW, height: 37).fill()
            var x: CGFloat = 24
            for (name, image) in items {
                let r = NSRect(x: x, y: (37 - 22) / 2, width: image.size.width, height: 22)
                if image.isTemplate {
                    let tinted = NSImage(size: image.size, flipped: false) { rect in
                        image.draw(in: rect); ink.set(); rect.fill(using: .sourceIn); return true }
                    tinted.draw(in: r)
                } else {
                    // Dynamic colours (labelColor, severity text) resolve against the current drawing appearance.
                    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { image.draw(in: r) }
                }
                widths.append("\(tag) \(name): \(Int(image.size.width)) pt")
                x += image.size.width + 24
            }
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent("menubar-\(tag).png"); try? png.write(to: url); written.append(url.lastPathComponent)
            }
        }
        print(widths.joined(separator: "\n"))
        print("Wrote \(written.count) images to \(outDir)")
        NSApp.terminate(nil)
    }

    private static func write<V: View>(_ view: V, scheme: ColorScheme, to url: URL) -> String? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: url)
        return url.lastPathComponent
    }
}
#endif
