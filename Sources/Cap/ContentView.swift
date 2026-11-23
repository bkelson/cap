import SwiftUI

/// Thin progress bar. Still used by the pinned floating bar (BarView).
struct UsageBar: View {
    let value: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.25))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat((value ?? 0) / 100))
            }
        }
        .frame(height: 6)
    }

    private var barColor: Color {
        guard let value else { return .gray }
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        return .green
    }
}

private enum Layout {
    /// Gap between the popover edge and the card's 1px border.
    static let cardInset: CGFloat = 12
    /// Gap between the border and the content (dials, figures, footer controls).
    static let contentPadding: CGFloat = 14
    /// Header text and pin sit this much further in than the content edge.
    static let headerIndent: CGFloat = 10
    static let cornerRadius: CGFloat = 12
    /// Width of the bordered card. README's 268pt predates the border and
    /// content padding; at 268 "3h 41m remaining" truncated.
    static let cardWidth: CGFloat = 280
}

/// Brand palette from README-ASSETS.md.
enum Brand {
    static let terracotta = Color(red: 0xC4 / 255, green: 0x64 / 255, blue: 0x3F / 255)

    static func surface(_ s: ColorScheme) -> Color { s == .dark ? hex(0x241E1B) : hex(0xF4F1EE) }
    static func hairline(_ s: ColorScheme) -> Color { s == .dark ? hex(0x3A302B) : hex(0xE4DDD7) }
    static func border(_ s: ColorScheme) -> Color { s == .dark ? hex(0x54463C) : hex(0xD3C9C0) }
    static func track(_ s: ColorScheme) -> Color { s == .dark ? hex(0x413630) : hex(0xE0D7D0) }
    static func ink(_ s: ColorScheme) -> Color { s == .dark ? hex(0xF4F1EE) : hex(0x241E1B) }
    /// Design token `text/muted`. Light is #685D56 (approved 2026-10-26: the old #7E736C missed 4.5:1 on the card and header strip).
    static func muted(_ s: ColorScheme) -> Color { s == .dark ? hex(0xA89D95) : hex(0x685D56) }

    /// Design token `badge/update` = `severity/critical-fill`: the "update available" dot.
    static func updateDot(_ s: ColorScheme) -> Color { s == .dark ? hex(0xFF453A) : hex(0xFF3B30) }

    private static func hex(_ v: Int) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Dial 1b at panel size: hole is 62% of the outer diameter, sweep starts at
/// 6 o'clock and fills clockwise. Same geometry as the menu bar dials.
struct DialView: View {
    let pct: Double?
    let severity: DialRenderer.Severity
    let size: CGFloat
    /// Optional track color (the pinned glass bar has no brand surface behind it).
    var trackOverride: Color? = nil
    /// Optional fill color when no severity applies (default: brand terracotta).
    var fillOverride: Color? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ringWidth = size * (1 - 0.62) / 2
        let fraction = min(max((pct ?? 0) / 100, 0), 1)
        let fill = severity.color.map(Color.init(nsColor:)) ?? fillOverride ?? Brand.terracotta
        let track = severity.color.map { Color(nsColor: $0).opacity(0.30) } ?? trackOverride ?? Brand.track(scheme)

        ZStack {
            Circle().inset(by: ringWidth / 2).stroke(track, lineWidth: ringWidth)
            if fraction > 0 {
                Circle().inset(by: ringWidth / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(fill, style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
                    .rotationEffect(.degrees(90)) // trim starts at 3 o'clock; move to 6
            }
        }
        .frame(width: size, height: size)
    }
}

/// One reading: dial, label + secondary line, and the percentage.
private struct ReadingRow: View {
    let label: String
    let secondary: String
    var tertiary: String? = nil
    let pct: Double?
    let isAccent: Bool
    let stale: Bool
    /// The secondary line is a status ("Getting your first reading…"), not a figure: muted, smaller.
    var mutedSecondary = false

    @Environment(\.colorScheme) private var scheme
    @State private var previousValue: Double?
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseColor: Color?

    private var severity: DialRenderer.Severity { DialRenderer.Severity(pct: pct) }

    /// Severity color wins; otherwise terracotta on the one figure to notice.
    private var percentColor: Color {
        if let t = severity.textColor { return Color(nsColor: t) }
        return isAccent ? Brand.terracotta : Brand.ink(scheme)
    }

    var body: some View {
        HStack(spacing: 14) {
            DialView(pct: pct, severity: severity, size: 34)
            // The label runs across the full width (design: grid column 2 to 3), so a long label like
            // "ALL MODELS · WEEK" stays on one line however wide the figure is. The figure sits beside the lines below it.
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(10.5 * 0.1)
                    .foregroundStyle(Brand.muted(scheme))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(secondary)
                            .font(.system(size: mutedSecondary ? 12 : 15))
                            .foregroundStyle(mutedSecondary ? Brand.muted(scheme) : Brand.ink(scheme))
                            .lineLimit(mutedSecondary ? 2 : 1)
                            .minimumScaleFactor(0.85)
                        if let tertiary {
                            Text(tertiary)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Brand.muted(scheme))
                                .lineLimit(1)
                                .padding(.top, 1)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(pct == nil ? "—%" : UsageFormat.percent(pct))   // no reading: "—%" (design: text/empty-figure)
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .foregroundStyle(pct == nil ? Brand.muted(scheme).opacity(0.6) : (pulseColor ?? percentColor))
                        .scaleEffect(pulseScale, anchor: .trailing)
                        .fixedSize()
                        // Keeps the row as tall as before when there is only one line beside the figure.
                        .frame(height: 20)
                        .onChange(of: pct) { newValue in
                            defer { previousValue = newValue }
                            guard let old = previousValue, let new = newValue, old != new else { return }
                            pulseColor = new > old ? .orange : .green
                            withAnimation(.easeOut(duration: 0.12)) { pulseScale = 1.16 }
                            withAnimation(.easeInOut(duration: 1.1).delay(0.45)) {
                                pulseScale = 1.0
                                pulseColor = nil
                            }
                        }
                }
            }
        }
        .opacity(stale ? 0.55 : 1)
        .padding(.horizontal, Layout.contentPadding)
        .padding(.vertical, 12)
    }
}

/// Faint 45° hatch for the footer, running top-left to bottom-right. Drawn one
/// device pixel wide so it stays crisp and quiet.
private struct DiagonalHatch: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    /// Horizontal distance between neighboring lines.
    private let spacing: CGFloat = 4
    /// Tuned separately: light-on-dark lines read fainter than dark-on-light ones.
    private var opacity: Double { scheme == .dark ? 0.18 : 0.10 }

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += spacing
            }
            context.stroke(path, with: .color(Brand.ink(scheme).opacity(opacity)), lineWidth: 1 / max(displayScale, 1))
        }
        .allowsHitTesting(false)
    }
}

/// Two-state control for the menu bar item: Compact (Session dial + %) or
/// Expanded (both readings).
private struct MenuBarModePill: View {
    @Binding var expanded: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            segment("Compact", selected: !expanded) { expanded = false }
            segment("Expanded", selected: expanded) { expanded = true }
        }
        .padding(2)
        // Solid surface fill so the footer's hatch doesn't show through the pill.
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Brand.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Brand.hairline(scheme), lineWidth: 1)
        )
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(Brand.ink(scheme).opacity(selected ? 1 : 0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Brand.track(scheme) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var feeder: BackgroundFeeder
    @ObservedObject var signIn: SignInController
    var isPinned: Bool
    var onTogglePin: () -> Void
    var onShowAbout: () -> Void = {}
    var onShowSettings: () -> Void = {}
    var onQuit: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// `size` is per symbol on purpose: at one shared font size the pin draws
    /// 15pt tall and the info circle 13pt. Measured sizes below give both a 14pt ink height.
    private func headerButton(_ symbol: String, size: CGFloat, help: String, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 16, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.ink(scheme).opacity(0.75))
        .help(help)
        .accessibilityLabel(label ?? help)
    }

    private var neverLoaded: Bool { store.liveUpdatedAt == nil }

    /// How old the reading may get before it is called stale: Cap refreshes on the user's interval (up to 10 minutes),
    /// so "stale" means two intervals have gone by (plus the few seconds a refresh takes), never a fixed 8 seconds.
    /// A reading older than this is "stale". Refreshes pause while you are away, so this stays a generous 10 minutes
    /// rather than following the 15 s refresh rhythm.
    private var staleAfter: TimeInterval { 620 }

    private var liveIsStale: Bool {
        guard let updated = store.liveUpdatedAt else { return true }
        return store.now.timeIntervalSince(updated) > staleAfter
    }

    /// "12m ago", "2h ago".
    private var lastReadingAge: String {
        guard let updated = store.liveUpdatedAt else { return "" }
        let minutes = max(1, Int(store.now.timeIntervalSince(updated) / 60))
        return minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago"
    }

    /// "12 min ago", "2 h ago" (the offline line reads "Showing your reading from 12 min ago.").
    private var lastReadingAgeLong: String {
        guard let updated = store.liveUpdatedAt else { return "" }
        let minutes = max(1, Int(store.now.timeIntervalSince(updated) / 60))
        return minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago"
    }

    /// Account is signed in but reports no usage limits (free plan): rows say so, no numbers.
    private var noLimits: Bool { feeder.status == .noLimits }

    /// Claude Code is not on this Mac any more (the app moved or was deleted).
    private var claudeMissing: Bool { feeder.status == .claudeMissing }

    /// No reading yet and nothing else explains why: Cap is still fetching the first one.
    private var firstReading: Bool {
        guard neverLoaded else { return false }
        switch feeder.status {
        case .needsSignIn, .offline, .noLimits, .claudeMissing: return false
        default: return true
        }
    }

    /// The first reading has taken longer than 30 s (Claude is slow). A hint, not an error.
    private var firstReadingSlow: Bool {
        firstReading && store.now.timeIntervalSince(feeder.launchedAt) > 30
    }

    /// Terracotta goes on whichever figure is higher (Session wins ties).
    private var sessionIsAccent: Bool {
        guard let s = store.sessionPct else { return false }
        return s >= (store.weekPct ?? -1)
    }

    private var weekIsAccent: Bool {
        guard let w = store.weekPct else { return false }
        return !sessionIsAccent && w >= 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar: fills the card's top edge (the card clips it to the
            // rounded corners). Text and pin are indented from the content edge.
            HStack {
                Text("Cap™ - a usage tracker thingy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.muted(scheme))
                    .lineLimit(1)
                Spacer()
                // Left to right: About, then Pin — the pin stays last (far right).
                HStack(spacing: 13.7) {
                    headerButton("info.circle", size: 14, help: "About Cap", action: onShowAbout)
                    headerButton(isPinned ? "pin.fill" : "pin", size: 12,
                                 help: isPinned ? "Hide floating bar" : "Pin as a floating bar under the menu bar",
                                 label: isPinned ? "Unpin floating bar" : "Pin floating bar",
                                 action: onTogglePin)
                }
            }
            // Title keeps its indent; the icons mirror the footer's gear + power:
            // same right edge and the same visible gap (measured, hence the odd numbers).
            .padding(.leading, Layout.contentPadding + Layout.headerIndent)
            .padding(.trailing, 12.3)
            .frame(height: 30)
            .background(Brand.hairline(scheme))

            // Signed out with an old reading on screen: dial and figure dim (same 0.55 as stale).
            let dimmed = (liveIsStale && !neverLoaded) || ((feeder.status == .needsSignIn || claudeMissing) && !neverLoaded)

            ReadingRow(
                label: "SESSION · 5H",
                secondary: noLimits ? "No limit reported"
                    : firstReading ? "Getting your first reading…"
                    : UsageFormat.remaining(to: store.sessionResetsAt, from: store.now),
                tertiary: (noLimits || firstReading) ? nil : UsageFormat.resetTime(of: store.sessionResetsAt, from: store.now),
                pct: noLimits ? nil : store.sessionPct,
                isAccent: sessionIsAccent && !noLimits,
                stale: dimmed,
                mutedSecondary: noLimits || firstReading
            )

            Rectangle().fill(Brand.hairline(scheme)).frame(height: 1)

            ReadingRow(
                label: "ALL MODELS · WEEK",
                secondary: noLimits ? "No limit reported"
                    : firstReading ? "Usually a few seconds"
                    : UsageFormat.resetDay(of: store.weekResetsAt, from: store.now),
                pct: noLimits ? nil : store.weekPct,
                isAccent: weekIsAccent && !noLimits,
                stale: dimmed,
                mutedSecondary: noLimits || firstReading
            )

            Rectangle().fill(Brand.hairline(scheme)).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                if feeder.status == .needsSignIn {
                    SignedOutStrip(signIn: signIn, hasOldReading: !neverLoaded)
                } else if feeder.status == .offline {
                    StateStrip(text: "Can't reach Claude right now.",
                               detail: neverLoaded ? nil : "Showing your reading from \(lastReadingAgeLong).")
                } else if claudeMissing {
                    StateStrip(text: "I can't find Claude Code on this Mac any more.",
                               detail: "If Claude is still installed, open it once and I'll find it again.",
                               actionTitle: "Get Claude for Mac") { NSWorkspace.shared.open(OnboardingModel.downloadURL) }
                } else if noLimits {
                    StateStrip(text: "Your account doesn't report usage limits.",
                               detail: "Limits only show on Claude Pro and Max plans.")
                } else if firstReadingSlow {
                    StateStrip(text: "Claude is slow to answer. I'll keep trying.", detail: nil)
                } else if firstReading {
                    EmptyView()   // first reading, first 30 s: the rows say it; no strip
                } else if let end = preferences.loginEndsAt, LoginExpiry.shouldOfferRenewal(endsAt: end, now: store.now) {
                    RenewStrip(signIn: signIn, endsAt: end, now: store.now)   // the sign-in has a built-in end date: renew before it lapses
                } else if liveIsStale {
                    Text("Showing your reading from \(lastReadingAgeLong).")   // v1: one line, same wording as Offline (Brian, 2026-10-28)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.muted(scheme))
                }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MENU BAR")
                            .font(.system(size: 9.5, weight: .medium))
                            .tracking(9.5 * 0.1)
                            .foregroundStyle(Brand.muted(scheme))
                        MenuBarModePill(expanded: $preferences.showInlineMenuBarStats)
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: onShowSettings) {
                            Image(systemName: "gearshape")
                                .frame(width: 16, alignment: .trailing)
                                .overlay(alignment: .topTrailing) {
                                    // A new version is out (design T7): a small red dot, until Settings → Updates has been opened.
                                    if preferences.updateDotVisible {
                                        Circle().fill(Brand.updateDot(scheme)).frame(width: 7, height: 7)
                                            .overlay(Circle().stroke(Brand.surface(scheme), lineWidth: 1.5))
                                            .offset(x: 4, y: -3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                        .accessibilityLabel(preferences.updateDotVisible ? "Settings, update available" : "Settings")
                        Button(action: onQuit) {
                            Image(systemName: "power")
                                .frame(width: 16, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .help("Quit Cap")
                        .accessibilityLabel("Quit Cap")
                    }
                    .padding(.bottom, 5)
                }
                .foregroundStyle(Brand.ink(scheme).opacity(0.75))
            }
            .padding(.horizontal, Layout.contentPadding)
            .padding(.vertical, 10)
            .background { DiagonalHatch() }
        }
        .frame(width: Layout.cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(Brand.border(scheme), lineWidth: 1)
        )
        .padding(Layout.cardInset)
        .background(Brand.surface(scheme))
    }
}


/// A neutral state strip for the popover footer (design "Popover strip", tone neutral): one line, an optional muted detail.
/// No amber or red for problems.
struct StateStrip: View {
    let text: String
    let detail: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Brand.ink(scheme).opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.terracotta))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 4)
    }
}

/// Shown in the popover in the last week before the saved Claude Code sign-in reaches its built-in end date (see `LoginExpiry`):
/// one click renews it, so the numbers never stop. DRAFT copy, not yet approved; the waiting and failure lines are the same as the signed-out strip's.
struct RenewStrip: View {
    @ObservedObject var signIn: SignInController
    let endsAt: Date
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if signIn.state != .finishing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Claude Code sign-in \(LoginExpiry.phrase(endsAt: endsAt, now: now)).")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.ink(scheme).opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    if case .idle = signIn.state {
                        Text("Renew it now so Cap keeps working. It takes about a minute.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Brand.muted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            switch signIn.state {
            case .idle:
                button("Renew sign-in") { signIn.start() }
            case .signingIn:
                HStack(spacing: 10) {
                    Text("Waiting for you in your browser. If it asks, check your email for a link.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancel") { signIn.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Brand.ink(scheme).opacity(0.75))
                }
            case .finishing:
                Text("Signed in. Getting your numbers…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let why):
                Text(why)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                button("Try again") { signIn.start() }
            }
        }
        .padding(.bottom, 4)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.terracotta))
        }
        .buttonStyle(.plain)
    }
}

/// Shown in the popover when a refresh finds Claude Code signed out (its saved login expired, or was removed).
/// Copy approved 2026-10-26 (design A4, A8).
struct SignedOutStrip: View {
    @ObservedObject var signIn: SignInController
    let hasOldReading: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Right after sign-in (A8) the success line replaces this text in place, so the two never show together.
            if signIn.state != .finishing {
            VStack(alignment: .leading, spacing: 4) {
                Text(hasOldReading ? "I've been signed out of Claude Code, so your numbers are paused."
                                   : "I've been signed out of Claude Code, so I can't read your usage yet.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.ink(scheme).opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if case .idle = signIn.state {
                    Text("Signing in opens your browser.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.muted(scheme))
                }
            }
            }
            switch signIn.state {
            case .idle:
                button("Sign in to Claude Code") { signIn.start() }
            case .signingIn:
                HStack(spacing: 10) {
                    Text("Waiting for you in your browser. If it asks, check your email for a link.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancel") { signIn.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Brand.ink(scheme).opacity(0.75))
                }
            case .finishing:
                Text("Signed in. Getting your numbers…")   // approved wording (A8)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let why):
                Text(why)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                button("Try again") { signIn.start() }
            }
        }
        .padding(.bottom, 4)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.terracotta))
        }
        .buttonStyle(.plain)
    }
}
