import AppKit
import SwiftUI

// MARK: - Icons (paths from the design source, 12×12 / 10×10 viewBoxes)

/// Corner radius shared by the two squares in the Always-on-top icon.
private let squareRadius: CGFloat = 1.5

/// Back square outline for the *on* state: open path, stops short of the front square.
private struct BackOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 12
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        var path = Path()
        path.move(to: p(3, 8))
        path.addArc(tangent1End: p(1, 8), tangent2End: p(1, 1), radius: squareRadius * k)
        path.addArc(tangent1End: p(1, 1), tangent2End: p(8, 1), radius: squareRadius * k)
        path.addArc(tangent1End: p(8, 1), tangent2End: p(8, 3), radius: squareRadius * k)
        path.addLine(to: p(8, 3))
        return path
    }
}

/// Back square for the *off* state: filled, with the overlap cut out so the
/// front square's inside shows the button background.
private struct BackFilled: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 12
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        var path = Path()
        path.move(to: p(2.5, 1))
        path.addArc(tangent1End: p(8, 1), tangent2End: p(8, 2.8), radius: squareRadius * k)
        path.addLine(to: p(8, 2.8))
        path.addLine(to: p(2.8, 2.8))
        path.addLine(to: p(2.8, 8))
        path.addArc(tangent1End: p(1, 8), tangent2End: p(1, 1), radius: squareRadius * k)
        path.addArc(tangent1End: p(1, 1), tangent2End: p(2.5, 1), radius: squareRadius * k)
        path.closeSubpath()
        return path
    }
}

private struct AlwaysOnTopGlyph: View {
    let isOn: Bool
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isOn {
                // Front square filled, back square outlined.
                BackOutline()
                    .stroke(color, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                RoundedRectangle(cornerRadius: squareRadius, style: .continuous)
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .offset(x: 4, y: 4)
            } else {
                // Back square filled, front square outlined.
                BackFilled().fill(color)
                RoundedRectangle(cornerRadius: squareRadius, style: .continuous)
                    .inset(by: 0.55)
                    .stroke(color, lineWidth: 1.1)
                    .frame(width: 6.9 + 1.1, height: 6.9 + 1.1)
                    .offset(x: 4.05 - 0.55, y: 4.05 - 0.55)
            }
        }
        .frame(width: 12, height: 12, alignment: .topLeading)
    }
}

private struct CloseGlyph: View {
    let color: Color

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 2)); p.addLine(to: CGPoint(x: 8, y: 8))
            p.move(to: CGPoint(x: 8, y: 2)); p.addLine(to: CGPoint(x: 2, y: 8))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        .frame(width: 10, height: 10, alignment: .topLeading)
    }
}

/// The 9pt circular arrow that marks a reset time.
private struct ResetGlyph: View {
    var body: some View {
        Path { p in
            // Arc: center (5,5), r 3.6, from (8.6,5.4) the long way round to (7.5,2.4).
            let start = atan2(0.4, 3.6), end = atan2(-2.6, 2.5) + 2 * .pi
            let steps = 40
            for i in 0...steps {
                let a = start + (end - start) * CGFloat(i) / CGFloat(steps)
                let pt = CGPoint(x: 5 + 3.6 * cos(a), y: 5 + 3.6 * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            // Arrowhead.
            p.move(to: CGPoint(x: 8.4, y: 0.9))
            p.addLine(to: CGPoint(x: 8.4, y: 3.0))
            p.addLine(to: CGPoint(x: 6.3, y: 3.0))
        }
        .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        .frame(width: 10, height: 10, alignment: .topLeading)
        .scaleEffect(0.9, anchor: .topLeading)
        .frame(width: 9, height: 9, alignment: .topLeading)
    }
}

// MARK: - Controls

private struct WidgetControls: View {
    let theme: PinnedTheme
    let isCircle: Bool
    @ObservedObject var preferences: Preferences
    let onClose: () -> Void

    private var size: CGFloat { isCircle ? 26 : 20 }

    var body: some View {
        HStack(spacing: isCircle ? 4 : 6) {
            button(help: "Always on top") {
                preferences.alwaysOnTop.toggle()
            } label: {
                AlwaysOnTopGlyph(isOn: preferences.alwaysOnTop, color: theme.ink)
            }
            button(help: "Close", action: onClose) {
                CloseGlyph(color: theme.ink)
            }
        }
    }

    private func button<L: View>(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .background(
                    Group {
                        if isCircle { Circle().fill(theme.btn) }
                        else { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.btn) }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(help == "Always on top" && preferences.alwaysOnTop ? .isSelected : [])
    }
}

// MARK: - Shared text styles

private extension View {
    func capsLabel(_ size: CGFloat, color: Color) -> some View {
        self.font(.system(size: size, weight: .semibold))
            .tracking(size * 0.12)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    func figure(_ size: CGFloat, color: Color, tracking: CGFloat = 0) -> some View {
        self.font(.system(size: size, weight: .semibold).monospacedDigit())
            .tracking(tracking)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// "⟳ 2:40 PM"
private struct ResetStamp: View {
    let text: String
    let theme: PinnedTheme

    var body: some View {
        HStack(spacing: 3) {
            ResetGlyph()
            Text(text).font(.system(size: 10.5, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(theme.sub)
        .opacity(0.78)
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - The widget

struct PinnedWidgetView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var styleStore: WidgetStyleStore
    @ObservedObject var preferences: Preferences
    let onClose: () -> Void
    /// Clicking the "Sign in" plate when signed out: start the browser sign-in and open the popover.
    var onSignIn: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    private var theme: PinnedTheme { .resolve(style: styleStore.style, scheme: scheme) }

    /// First refresh not finished yet and nothing has ever been read.
    private var firstReadingNow: Bool { store.awaitingFirstReading && store.liveUpdatedAt == nil && !store.signedOut }

    /// Under the "Sign in" pill: Small "Signed out", Medium "Signed out. Numbers paused.", Strip none.
    private var signedOutCaption: String? {
        switch preferences.pinnedLayout {
        case .small: return "Signed out"
        case .medium: return "Signed out. Numbers paused."
        case .strip: return nil
        }
    }

    /// First reading: Small "Getting numbers…", Medium "Getting your first reading…", Strip shows only "—%".
    private var firstReadingCaption: String? {
        switch preferences.pinnedLayout {
        case .small: return "Getting numbers…"
        case .medium: return "Getting your first reading…"
        case .strip: return nil
        }
    }

    var body: some View {
        let t = theme
        let r = Self.cornerRadius(for: preferences.pinnedLayout)

        Group {
            switch preferences.pinnedLayout {
            case .small: SmallLayout(store: store, theme: t, preferences: preferences, onClose: onClose)
            case .medium: MediumLayout(store: store, theme: t, preferences: preferences, onClose: onClose)
            case .strip: StripLayout(store: store, theme: t, preferences: preferences, onClose: onClose)
            }
        }
        // Signed out of Claude Code (design A9, approved 2026-10-26): content at 0.55, a "Sign in" pill, and a short
        // caption under it on Small and Medium. First reading (A3): same dimming with a caption instead of a pill.
        // Dimmed well below the usual stale 0.55 (Brian, 2026-10-26) so the figures do not compete with the words on top.
        .opacity(store.signedOut ? 0.22 : (firstReadingNow ? 0.35 : 1))
        .overlay {
            if store.signedOut {
                // One frosted plate holds the pill and its caption, so the faded figures behind never run through the words.
                Button(action: onSignIn) {
                VStack(spacing: 3) {
                    Text("Sign in")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(t.ink)
                    if let caption = signedOutCaption {
                        Text(caption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(t.sub)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: signedOutCaption == nil ? 14 : 12, style: .continuous))
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign in to Claude Code")
            } else if firstReadingNow, let caption = firstReadingCaption {
                Text(caption)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(t.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .shadow(color: t.textShadow?.color ?? .clear, radius: t.textShadow?.radius ?? 0, x: 0, y: t.textShadow?.y ?? 0)
        .background(t.bg)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        // 1pt inner top highlight: strongest at the top edge, fading within the corner.
        .overlay(
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [t.highlight, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14)),
                    lineWidth: 1
                )
                .padding(1)
        )
        .contextMenu {
            Picker("Layout", selection: $preferences.pinnedLayout) {
                ForEach(PinnedLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        }
    }

    static func cornerRadius(for layout: PinnedLayout) -> CGFloat {
        layout == .strip ? 26 : 22
    }
}

// MARK: - Shared reading data

@MainActor
private struct Reading {
    let sessionPct: Double?
    let weekPct: Double?
    let sessionLeft: String
    let sessionReset: String?
    let weekReset: String

    init(_ store: UsageStore) {
        sessionPct = store.sessionPct
        weekPct = store.weekPct
        sessionLeft = UsageFormat.left(to: store.sessionResetsAt, from: store.now)
        sessionReset = UsageFormat.clockTime(of: store.sessionResetsAt, from: store.now)
        weekReset = UsageFormat.nextDay(of: store.weekResetsAt, from: store.now)
    }
}

/// Dial + figure colors for one reading, keeping the orange/red warnings in every style.
private struct Tone {
    let severity: DialRenderer.Severity
    let theme: PinnedTheme

    init(_ pct: Double?, theme: PinnedTheme) {
        severity = DialRenderer.Severity(pct: pct)
        self.theme = theme
    }

    func figure(default base: Color) -> Color {
        severity.textColor.map(Color.init(nsColor:)) ?? base
    }
}

private func dial(_ pct: Double?, _ size: CGFloat, _ theme: PinnedTheme) -> some View {
    DialView(
        pct: pct,
        severity: DialRenderer.Severity(pct: pct),
        size: size,
        trackOverride: theme.track,
        fillOverride: theme.fill
    )
}

// MARK: - Small (170 × 170)

private struct SmallLayout: View {
    @ObservedObject var store: UsageStore
    let theme: PinnedTheme
    @ObservedObject var preferences: Preferences
    let onClose: () -> Void

    var body: some View {
        let d = Reading(store)
        let session = Tone(d.sessionPct, theme: theme)
        let week = Tone(d.weekPct, theme: theme)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SESSION").capsLabel(10, color: theme.muted)
                Spacer(minLength: 0)
                WidgetControls(theme: theme, isCircle: false, preferences: preferences, onClose: onClose)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                dial(d.sessionPct, 56, theme)
                Text(UsageFormat.percent(d.sessionPct))
                    .figure(30, color: session.figure(default: theme.ink), tracking: -0.6)
            }

            Spacer(minLength: 0)

            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Text(d.sessionLeft)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let reset = d.sessionReset { ResetStamp(text: reset, theme: theme) }
                }
                Rectangle().fill(theme.line).frame(height: 1)
                HStack(spacing: 7) {
                    dial(d.weekPct, 13, theme)
                    Text("ALL MODELS").capsLabel(9.5, color: theme.muted)
                    Spacer(minLength: 0)
                    Text(UsageFormat.percent(d.weekPct))
                        .figure(12, color: week.figure(default: theme.ink))
                }
            }
        }
        .padding(14)
        .frame(width: 170, height: 170)
    }
}

// MARK: - Medium (360 wide)

private struct MediumLayout: View {
    @ObservedObject var store: UsageStore
    let theme: PinnedTheme
    @ObservedObject var preferences: Preferences
    let onClose: () -> Void

    var body: some View {
        let d = Reading(store)
        let session = Tone(d.sessionPct, theme: theme)
        let week = Tone(d.weekPct, theme: theme)

        VStack(spacing: 9) {
            HStack {
                Text("Cap")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.muted)
                Spacer(minLength: 0)
                WidgetControls(theme: theme, isCircle: false, preferences: preferences, onClose: onClose)
            }

            HStack(spacing: 16) {
                column(label: "SESSION", pct: d.sessionPct, color: session.figure(default: theme.fig))
                Rectangle().fill(theme.line).frame(width: 1, height: 44)
                column(label: "ALL MODELS", pct: d.weekPct, color: week.figure(default: theme.ink))
            }

            Rectangle().fill(theme.line).frame(height: 1)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text(d.sessionLeft)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let reset = d.sessionReset { ResetStamp(text: reset, theme: theme) }
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(width: 1, height: 1) // keeps the footer columns aligned with the readings above

                HStack {
                    Spacer(minLength: 0)
                    ResetStamp(text: d.weekReset, theme: theme)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
        .frame(width: 360)
    }

    private func column(label: String, pct: Double?, color: Color) -> some View {
        HStack(spacing: 12) {
            dial(pct, 48, theme)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).capsLabel(9.5, color: theme.muted)
                Text(UsageFormat.percent(pct))
                    .figure(26, color: color, tracking: -0.52)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Strip (52 tall pill)

private struct StripLayout: View {
    @ObservedObject var store: UsageStore
    let theme: PinnedTheme
    @ObservedObject var preferences: Preferences
    let onClose: () -> Void

    var body: some View {
        let d = Reading(store)
        let session = Tone(d.sessionPct, theme: theme)
        let week = Tone(d.weekPct, theme: theme)

        HStack(spacing: 16) {
            group(label: "5H", pct: d.sessionPct, color: session.figure(default: theme.ink))
            Rectangle().fill(theme.line).frame(width: 1, height: 18)
            group(label: "WEEK", pct: d.weekPct, color: week.figure(default: theme.ink))
            WidgetControls(theme: theme, isCircle: true, preferences: preferences, onClose: onClose)
        }
        .padding(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 10))
        .frame(height: 52)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func group(label: String, pct: Double?, color: Color) -> some View {
        HStack(spacing: 9) {
            dial(pct, 20, theme)
            Text(label).capsLabel(10, color: theme.muted)
            Text(UsageFormat.percent(pct)).figure(15, color: color)
        }
    }
}
