import SwiftUI

/// Cap's Settings window (design "Settings Window v5"): a sidebar and one pane at a time, fixed at 680 × 516 pt.
/// Colours come from the same table as the welcome window, so light and dark follow macOS.
struct SettingsView: View {
    static let windowSize = CGSize(width: 680, height: 516)

    enum Pane: String, CaseIterable {
        case general = "General", notifications = "Notifications", widget = "Widget", updates = "Updates"

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .notifications: return "bell"
            case .widget: return "square.grid.2x2"
            case .updates: return "arrow.down.circle"
            }
        }
    }

    @ObservedObject var preferences: Preferences
    @ObservedObject var checker: UpdateChecker
    var onShowWelcome: () -> Void = {}

    @State private var pane: Pane
    @State private var hookState = ClaudeSettingsInstaller().state()
    @State private var disconnectError: String?
    @StateObject private var access = NotificationAccess()
    @Environment(\.colorScheme) private var scheme

    init(preferences: Preferences, checker: UpdateChecker, onShowWelcome: @escaping () -> Void = {}, initialPane: Pane = .general) {
        self.preferences = preferences
        self.checker = checker
        self.onShowWelcome = onShowWelcome
        _pane = State(initialValue: initialPane)
    }

    private var palette: OnboardingPalette { .resolve(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: 44, alignment: .leading)
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 13))
        .foregroundStyle(palette.ink)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(palette.shell)
        .onAppear { access.startPolling() }
        .onDisappear { access.stopPolling() }
        // Back from System Settings (where the user may have just allowed notifications): look again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in access.refresh() }
        // macOS turned Cap's notifications off: the switch follows, instead of staying on and doing nothing.
        .onChange(of: access.denied) { denied in if denied { preferences.notificationsEnabled = false } }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 2) {
            Color.clear.frame(height: 44)   // room for the window's traffic lights
            ForEach(Pane.allCases, id: \.self) { item in
                Button { pane = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol).font(.system(size: 13)).foregroundStyle(palette.muted).frame(width: 16)
                        Text(item.rawValue).fontWeight(item == pane ? .semibold : .regular)
                        Spacer(minLength: 0)
                        if item == .updates && preferences.updateAvailable {
                            Circle().fill(Brand.updateDot(scheme)).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 9).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item == pane ? palette.chip : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .updates && preferences.updateAvailable ? "Updates, update available" : item.rawValue)
                .accessibilityAddTraits(item == pane ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .frame(width: 176)
        .background(palette.strip)
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .general: general
        case .notifications: notifications
        case .widget: widget
        case .updates: updates
        }
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .medium)).tracking(1.05)
            .foregroundStyle(palette.muted)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }

    /// A picture card that is selected with a 2 pt accent border (the padding drops 1 pt so nothing moves).
    private func choiceCard<Content: View>(selected: Bool, label: String, action: @escaping () -> Void,
                                           @ViewBuilder _ content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .padding(selected ? 11 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? palette.primaryFill : palette.border, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func well(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.shell)
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.hairline, lineWidth: 1))
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Menu bar")
                HStack(spacing: 10) {
                    menuBarCard(title: "Compact", expanded: false)
                    menuBarCard(title: "Expanded", expanded: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Welcome window")
                card {
                    HStack(spacing: 16) {
                        Text("Go through setup again")
                        Spacer(minLength: 0)
                        SecondaryButton(title: "Show welcome again", palette: palette, action: onShowWelcome)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
    }

    private func menuBarCard(title: String, expanded: Bool) -> some View {
        choiceCard(selected: preferences.showInlineMenuBarStats == expanded, label: title,
                   action: { preferences.showInlineMenuBarStats = expanded }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).fontWeight(.semibold)
                MenuBarPreview(expanded: expanded, palette: palette)
            }
        }
    }

    /// Only on a Mac where an earlier version of Cap added its status hook.
    @ViewBuilder private var legacyHookRow: some View {
        if hookState == .installed || hookState == .needsRepair || hookState == .legacy {
            card {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("An earlier version of me added a status hook to Claude's settings. I don't need it any more.")
                            .font(.system(size: 12.5)).foregroundStyle(palette.muted)
                        if let disconnectError { Text(disconnectError).font(.system(size: 12)).foregroundStyle(palette.muted) }
                    }
                    Spacer(minLength: 0)
                    SecondaryButton(title: "Remove", palette: palette) {
                        do { try ClaudeSettingsInstaller().uninstall(); disconnectError = nil }
                        catch { disconnectError = "I couldn't change ~/.claude/settings.json." }
                        hookState = ClaudeSettingsInstaller().state()
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    // MARK: Notifications

    private var notifications: some View {
        let on = preferences.notificationsEnabled
        return card {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications").fontWeight(.semibold)
                        Text("Limits, sign-outs and new versions.").font(.system(size: 12)).foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 0)
                    CapSwitch(isOn: on, palette: palette, label: "Notifications") {
                        if !on { UsageAlerts.requestPermission { preferences.notificationsEnabled = $0; access.refresh() } }
                        else { preferences.notificationsEnabled = false }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Rectangle().fill(palette.hairline).frame(height: 1)
                if access.denied {
                    // Approved copy (A12, 2026-10-26): macOS blocks Cap's notifications, so the switch cannot turn on.
                    HStack(spacing: 12) {
                        Text("macOS has notifications turned off for Cap.").font(.system(size: 12.5))
                        Spacer(minLength: 0)
                        SecondaryButton(title: "Open System Settings", palette: palette, small: true) { NotificationAccess.openSystemSettings() }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(palette.modeFill)
                } else {
                    HStack(spacing: 16) {
                        alertColumn("Session usage reaches", $preferences.sessionAlertPercent)
                        Rectangle().fill(palette.hairline).frame(width: 1, height: 55)
                        alertColumn("Weekly usage reaches", $preferences.weeklyAlertPercent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .opacity(on ? 1 : 0.35)
                    .allowsHitTesting(on)
                }
            }
        }
    }

    private func alertColumn(_ label: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Text(label).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PercentField(value: value, palette: palette).fixedSize().layoutPriority(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Widget

    private var widget: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Layout")
                HStack(alignment: .top, spacing: 10) {
                    layoutCard(.small).frame(width: 151)   // columns 1 : 2 of the 464 pt content width
                    layoutCard(.medium).frame(width: 303)
                }
                layoutCard(.strip)
            }
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Placement")
                HStack(spacing: 10) {
                    placementCard(onTop: true, title: "On top", line: "Stays above your windows.")
                    placementCard(onTop: false, title: "Behind windows", line: "Behaves like a normal window.")
                }
            }
            Text("The widget follows System Settings → Appearance → Icon & widget style.")
                .font(.system(size: 12)).foregroundStyle(palette.muted)
        }
    }

    // MARK: Updates

    private var updates: some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(updateStatusLine).font(.system(size: 15)).fontWeight(preferences.updateAvailable ? .semibold : .regular)
                            HStack(spacing: 6) {
                                Text(updateSubLine)
                                if preferences.updateAvailable {
                                    Text("·")
                                    Button("What's new") { openLatest(preferNotes: true) }
                                        .buttonStyle(.plain).foregroundStyle(palette.primaryFill)
                                }
                            }
                            .font(.system(size: 12)).foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 0)
                        if preferences.updateAvailable {
                            PrimaryButton(title: "Download", palette: palette) { openLatest(preferNotes: false) }
                        } else {
                            SecondaryButton(title: checker.isChecking ? "Checking…" : "Check now", palette: palette) { checker.check() }
                                .opacity(checker.isChecking ? 0.5 : 1)
                                .allowsHitTesting(!checker.isChecking)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    Rectangle().fill(palette.hairline).frame(height: 1)
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for updates automatically")
                            Text("When on, Cap asks GitHub once a day for the latest version. GitHub sees your IP address, like any website.")
                                .font(.system(size: 12)).foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 0)
                        CapSwitch(isOn: preferences.checkForUpdatesAutomatically, palette: palette, label: "Check for updates automatically") {
                            preferences.checkForUpdatesAutomatically.toggle()
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
                }
            }
            legacyHookRow
        }
        .onAppear { preferences.updateSeenVersion = preferences.latestVersion }
    }

    private var updateStatusLine: String {
        if preferences.updateAvailable, let v = preferences.latestVersion { return "Version \(v) is available" }
        if preferences.lastUpdateCheckFailed { return "I couldn't check just now." }
        if preferences.lastUpdateCheck == nil { return "I haven't checked yet." }
        return "You're up to date · Cap \(UpdateChecker.currentVersion)"
    }

    private var updateSubLine: String {
        if preferences.updateAvailable { return "You have Cap \(UpdateChecker.currentVersion)" }
        guard let last = preferences.lastUpdateCheck else {
            // Never had an answer: say when the last try was, if there was one, rather than nothing.
            if preferences.lastUpdateCheckFailed, let tried = preferences.lastUpdateAttempt {
                return "Last tried " + Self.lastCheckedText(tried, now: Date())
            }
            return "You have Cap \(UpdateChecker.currentVersion)"
        }
        return "Last checked " + Self.lastCheckedText(last, now: Date())
    }

    /// "today, 11:20" · "yesterday, 11:20" · "3 days ago".
    static func lastCheckedText(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDate(date, inSameDayAs: now) { return "today, \(time)" }
        if cal.isDateInYesterday(date) { return "yesterday, \(time)" }
        let days = max(2, cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 2)
        return "\(days) days ago"
    }

    private func openLatest(preferNotes: Bool) {
        let raw = preferNotes ? preferences.latestReleaseURL : (preferences.latestDownloadURL ?? preferences.latestReleaseURL)
        if let raw, let url = URL(string: raw) { NSWorkspace.shared.open(url) }
    }

    private func layoutCard(_ layout: PinnedLayout) -> some View {
        let size: CGSize = layout == .small ? CGSize(width: 170, height: 170)
            : layout == .medium ? CGSize(width: 360, height: 138) : CGSize(width: 390, height: 52)
        let scale: CGFloat = 0.6
        let preview = WidgetPreview(layout: layout)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        return choiceCard(selected: preferences.pinnedLayout == layout, label: layout.title,
                          action: { preferences.pinnedLayout = layout }) {
            if layout == .strip {
                HStack(spacing: 12) {
                    Text(layout.title).fontWeight(.semibold).frame(width: 64, alignment: .leading)
                    ZStack { well(height: 46); preview }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack { well(height: 112); preview }
                    Text(layout.title).fontWeight(.semibold)
                }
            }
        }
    }

    private func placementCard(onTop: Bool, title: String, line: String) -> some View {
        choiceCard(selected: preferences.alwaysOnTop == onTop, label: title,
                   action: { preferences.alwaysOnTop = onTop }) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    well(height: 66)
                    // A window and the widget: in front of it ("On top") or tucked behind it.
                    ZStack {
                        if onTop { windowSketch; widgetSketch } else { widgetSketch; windowSketch }
                    }
                    .frame(width: 140, height: 56)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold)
                    Text(line).font(.system(size: 12)).foregroundStyle(palette.muted)
                }
            }
        }
    }

    private var windowSketch: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.card)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.border, lineWidth: 1))
            .overlay(alignment: .top) {
                Rectangle().fill(palette.strip).frame(height: 9).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .frame(width: 92, height: 56)
            .offset(x: -24)
    }

    private var widgetSketch: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(palette.card)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(palette.border, lineWidth: 1))
            .overlay(dial(31, size: 22, fill: palette.ink, track: palette.ink.opacity(0.22)))
            .frame(width: 44, height: 44)
            .offset(x: 34, y: -6)
    }
}

/// The real menu bar item (the same image the app draws) at sample numbers on a neutral wallpaper, for the Compact / Expanded cards.
/// The wallpaper is the same in light and dark, as in the design: the item is always drawn white on it.
struct MenuBarPreview: View {
    let expanded: Bool
    let palette: OnboardingPalette

    var body: some View {
        let image = expanded ? DialRenderer.inlineImage(sessionPct: 31, weekPct: 5) : DialRenderer.collapsedImage(sessionPct: 31)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.42, blue: 0.57), Color(red: 0.40, green: 0.50, blue: 0.64)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(nsImage: image).renderingMode(.template).foregroundStyle(.white)
        }
        .frame(height: 50)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The real pinned widget at sample numbers, for the layout cards.
private struct WidgetPreview: View {
    let layout: PinnedLayout
    @StateObject private var store = WidgetPreview.sampleStore()
    @StateObject private var preferences = Preferences(store: UserDefaults(suiteName: "ai.kelson.cap.settings-preview") ?? .standard)
    @StateObject private var styleStore = WidgetStyleStore(style: WidgetStyle())

    var body: some View {
        PinnedWidgetView(store: store, styleStore: styleStore, preferences: preferences, onClose: {})
            .onAppear { preferences.pinnedLayout = layout }
    }

    private static func sampleStore() -> UsageStore {
        let s = UsageStore()
        let now = Date()
        s.sessionPct = 31; s.sessionResetsAt = now.addingTimeInterval(2 * 3600 + 17 * 60)
        s.weekPct = 9; s.weekResetsAt = now.addingTimeInterval(3 * 86400)
        s.liveUpdatedAt = now
        return s
    }
}

/// The 38 × 22 on/off switch used across the welcome window and Settings.
struct CapSwitch: View {
    let isOn: Bool
    let palette: OnboardingPalette
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? palette.primaryFill : palette.chip).frame(width: 38, height: 22)
                Circle().fill(Color.white).frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1).padding(2)
            }
            .frame(width: 38, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
