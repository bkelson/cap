import AppKit
import SwiftUI

// MARK: - Small pieces

func mono(_ text: String) -> Text {
    Text(text).font(.system(size: 11.5, design: .monospaced))
}

/// Uppercase 10pt semibold label, 0.12em tracking.
private struct CapsLabel: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

private struct Headline: View {
    let text: String
    let palette: OnboardingPalette
    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .bold))
            .tracking(-0.52)
            .foregroundStyle(palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BodyText: View {
    let text: String
    let palette: OnboardingPalette
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(3)
            .foregroundStyle(palette.muted)
            .frame(maxWidth: 520, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Headline + body, with the fixed 84pt minimum height steps 2-4 share so the content below never moves.
private struct StepHeader: View {
    let headline: String
    let text: String
    let palette: OnboardingPalette
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Headline(text: headline, palette: palette)
            BodyText(text: text, palette: palette)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
    }
}

/// A dial drawn with the app's one dial view; colors come from the welcome palette.
func dial(_ pct: Double, size: CGFloat, fill: Color, track: Color) -> some View {
    DialView(pct: pct, severity: .normal, size: size, trackOverride: track, fillOverride: fill)
}

struct PrimaryButton: View {
    let title: String
    let palette: OnboardingPalette
    var enabled = true
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: small ? 12.5 : 13, weight: .semibold))
                .foregroundStyle(enabled ? palette.primaryText : palette.muted)
                .padding(.horizontal, small ? 14 : 18)
                .padding(.vertical, small ? 7 : 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(enabled ? palette.primaryFill : palette.chip))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    let palette: OnboardingPalette
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: small ? 12.5 : 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, small ? 12 : 16)
                .padding(.vertical, small ? 6 : 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.card))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.border, lineWidth: 1))
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 1 · Welcome

private struct WelcomeStep: View {
    let palette: OnboardingPalette

    /// Cap's own icon file, so it can never fall back to a generic icon.
    private static var appIcon: NSImage {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 88, height: 88)
                .padding(.leading, -6)
            VStack(alignment: .leading, spacing: 10) {
                Headline(text: "Hi. I'm Cap.", palette: palette)
                BodyText(text: "A tiny usage tracker thingy for Claude. I live in your menu bar and tell you how much of your limit is left, so you find out before hitting a wall.", palette: palette)
            }
            HStack(spacing: 12) {
                card(pct: 31, label: "Session", line: "Your current window, and when it resets.")
                card(pct: 9, label: "All Models", line: "Your weekly limit across every model.")
            }
        }
    }

    private func card(pct: Double, label: String, line: String) -> some View {
        HStack(spacing: 14) {
            dial(pct, size: 34, fill: palette.accent, track: palette.track)
            VStack(alignment: .leading, spacing: 3) {
                CapsLabel(text: label, color: palette.muted)
                Text(line)
                    .font(.system(size: 12.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }
}

// MARK: - "Checked, still no" feedback

/// A damped sideways shake. `animatableData` is a counter: each +1 plays one shake that
/// settles back to rest, so the row never ends up offset.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 6
    var wobbles: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = animatableData - floor(animatableData)
        let x = travel * (1 - progress) * sin(progress * wobbles * 2 * .pi)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

/// The Reduce Motion alternative: the row dims briefly and comes back, with no movement.
private struct DimPulse: ViewModifier, Animatable {
    var animatableData: CGFloat
    func body(content: Content) -> some View {
        let progress: Double = Double(animatableData - floor(animatableData))
        return content.opacity(1 - 0.45 * sin(progress * Double.pi))
    }
}

private struct CheckFeedback: ViewModifier {
    let counter: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content.modifier(DimPulse(animatableData: CGFloat(counter)))
            } else {
                content.modifier(ShakeEffect(animatableData: CGFloat(counter)))
            }
        }
        .animation(.linear(duration: reduceMotion ? 0.35 : 0.42), value: counter)
    }
}

// MARK: - Step 2 · Connect

private struct ChecklistRow: View {
    enum Icon { case done, pending, warning, busy }

    let icon: Icon
    let title: String
    /// Nil for rows that say nothing under the title (a finished row, or one that is waiting).
    var subtitle: Text? = nil
    let palette: OnboardingPalette
    /// Rows that can't be acted on yet: dimmed, dashed circle.
    var dimmed = false
    var trailing: AnyView? = nil
    /// Buttons shown under the text (the design's failure states).
    var actions: AnyView? = nil
    /// Bumped to play the "checked, still not fixed" shake.
    var feedback = 0
    /// When this row turned green while the window was behind other apps: a green wash fades out and the check pops in.
    var cue: Date? = nil

    @State private var washOpacity = 0.0
    @State private var checkScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: actions == nil ? .center : .top, spacing: 14) {
            iconView
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    if let subtitle {
                        subtitle
                            .font(.system(size: 12))
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(dimmed ? 0.55 : 1)
                if let actions { actions }
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(palette.successTint.opacity(washOpacity))
        .modifier(CheckFeedback(counter: feedback))
        .onChange(of: cue) { _ in playCue() }
        // The "done" row is a new view the moment the state flips, so it may be created after the cue was set.
        .onAppear { if let c = cue, Date().timeIntervalSince(c) < 3 { playCue() } }
    }

    /// 1.6 s fade of the green wash; the check scales 0.6 → 1 with a small overshoot (Reduce Motion: the fade only).
    private func playCue() {
        // Set the start values first and animate on the next turn of the run loop, otherwise SwiftUI folds both
        // changes into one and nothing is seen (Pass E, E.8: the row just switched to green).
        washOpacity = 1
        if !reduceMotion { checkScale = 0.6 }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 1.6)) { washOpacity = 0 }
            if !reduceMotion { withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { checkScale = 1 } }
        }
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.success)
                .scaleEffect(checkScale)
                .frame(width: 22, height: 22)
                .background(Circle().fill(palette.successTint))
        case .warning:
            ExclamationMark()
                .stroke(palette.amber, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .background(Circle().fill(palette.amberTint))
        case .pending:
            Circle()
                .strokeBorder(palette.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.4]))
                .frame(width: 22, height: 22)
                .opacity(dimmed ? 0.6 : 1)
        case .busy:
            BreathingDot(palette: palette)
        }
    }
}

/// "Working": a quiet circle with a dot that breathes (0.3 → 1 → 0.3 over 1.6 s). Reduce Motion: the dot stays still.
private struct BreathingDot: View {
    let palette: OnboardingPalette
    @State private var bright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().strokeBorder(palette.border, lineWidth: 1.5)
            Circle().fill(palette.muted).frame(width: 8, height: 8)
                .opacity(reduceMotion ? 0.6 : (bright ? 1 : 0.3))
        }
        .frame(width: 22, height: 22)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { bright = true }
        }
    }
}

/// The amber "!" (12×12 viewBox from the design).
private struct ExclamationMark: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 12
        var p = Path()
        p.move(to: CGPoint(x: 6 * k, y: 3 * k))
        p.addLine(to: CGPoint(x: 6 * k, y: 6.6 * k))
        p.move(to: CGPoint(x: 6 * k, y: 9 * k))
        p.addLine(to: CGPoint(x: 6 * k, y: 9.05 * k))
        return p
    }
}

/// "Get Claude for Mac": the filled action in the failure state.
private struct FilledActionButton: View {
    let title: String
    let palette: OnboardingPalette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.primaryFill))
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// "Check again": bordered, reads "Checking…" while it runs.
private struct CheckAgainButton: View {
    @ObservedObject var model: OnboardingModel
    let palette: OnboardingPalette
    var body: some View {
        Button { model.checkAgain() } label: {
            Text(model.rechecking ? "Checking…" : "Check again")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(palette.border, lineWidth: 1))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(model.rechecking)
    }
}

private struct ConnectStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: Preferences
    let palette: OnboardingPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // DRAFT copy: the design's version of this step is being redone. The headline is the design's;
            // the body no longer says Claude Code is "already signed in", which isn't true for everyone.
            StepHeader(headline: "I borrow Claude Code's numbers.",
                       text: "I ask Claude Code how much of your limit is left. I never see your password.",
                       palette: palette)

            VStack(spacing: 0) {
                claudeRow
                Rectangle().fill(palette.hairline).frame(height: 1).padding(.horizontal, 16)
                authRow
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // Rows (Batch B, approved 2026-10-26/28) ----------------------------
    // The row titles never change; only the detail line, the icon and the action do.

    @ViewBuilder private var claudeRow: some View {
        switch model.claude {
        case .found, .desktopNotReady:
            ChecklistRow(icon: .done, title: "Claude Code installed", palette: palette, cue: model.claudeCue)
        case .checking:
            ChecklistRow(icon: .busy, title: "Looking for Claude Code…", palette: palette)
        case .missing:
            ChecklistRow(icon: .pending, title: "Claude Code isn't installed",
                         subtitle: Text("I need it to read your usage. Install the Claude app for Mac, then come back here and I'll look again."),
                         palette: palette,
                         actions: AnyView(FilledActionButton(title: "Get Claude for Mac", palette: palette) { model.openClaudeDownload() }))
        }
    }

    private var authTitle: String { "Signed in to Pro or Max" }

    @ViewBuilder private var authRow: some View {
        switch model.auth {
        case .subscription:
            ChecklistRow(icon: .done, title: authTitle, palette: palette, cue: model.authCue)
        case .waiting:
            if model.claude == .desktopNotReady {
                if model.openedClaude {
                    ChecklistRow(icon: .busy, title: authTitle, subtitle: Text("Finishing setup…"), palette: palette)
                } else {
                    ChecklistRow(icon: .pending, title: authTitle,
                                 subtitle: Text("Open Claude and sign in. I'll notice when you're done."), palette: palette,
                                 actions: AnyView(FilledActionButton(title: "Open Claude", palette: palette) { model.openClaudeCodeTab() }))
                }
            } else {
                ChecklistRow(icon: .pending, title: authTitle, palette: palette, dimmed: true)   // waiting for row 1
            }
        case .checking:
            ChecklistRow(icon: .busy, title: authTitle, subtitle: Text("Finishing setup…"), palette: palette)
        case .needsSignIn, .notSignedIn:
            ChecklistRow(icon: .pending, title: authTitle,
                         subtitle: Text("One more step: sign in so I can read your usage. Signing in opens your browser, and I never see your password."),
                         palette: palette,
                         actions: AnyView(FilledActionButton(title: "Sign in to Claude Code", palette: palette) { model.signIn() }))
        case .signingIn:
            ChecklistRow(icon: .busy, title: authTitle,
                         subtitle: Text("Waiting for you in your browser. It may email you a link."), palette: palette,
                         actions: AnyView(CancelButton(palette: palette) { model.cancelSignIn() }))
        case .signInFailed, .noPlan:
            ChecklistRow(icon: .warning, title: authTitle,
                         subtitle: Text("That didn't work. Sign in with a Pro or Max account and try again."), palette: palette,
                         actions: AnyView(FilledActionButton(title: "Try again", palette: palette) { model.signIn() }))
        case .failed:
            ChecklistRow(icon: .warning, title: authTitle,
                         subtitle: Text("That didn't work. Sign in with a Pro or Max account and try again."), palette: palette,
                         actions: AnyView(FilledActionButton(title: "Try again", palette: palette) { model.checkAgain() }))
        }
    }
}

/// "Cancel" next to a sign-in that is waiting on the browser.
private struct CancelButton: View {
    let palette: OnboardingPalette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Cancel")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(palette.border, lineWidth: 1))
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3 · Preferences

/// What the alert-percent box accepts: digits only, one or two of them, and a third only when it completes "100".
/// Anything else is dropped as it is typed or pasted ("109" becomes "10", "1000" becomes "100", letters vanish).
enum PercentInput {
    static func sanitize(_ text: String) -> String {
        var out = ""
        for ch in text where ch.isASCII && ch.isNumber {
            if out.count < 2 { out.append(ch) }
            else if out == "10" && ch == "0" { out.append(ch) }
        }
        return out
    }
}

/// Digits only, 1 to 100.
struct PercentField: View {
    @Binding var value: Int
    let palette: OnboardingPalette
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.ink)
                .focused($focused)
                .frame(width: 68, height: 55)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.shell))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(palette.border, lineWidth: 1))
                .onAppear { text = String(value) }
                .onChange(of: text) { new in
                    let digits = PercentInput.sanitize(new)
                    if digits != new { text = digits }
                    if let n = Int(digits), (1...100).contains(n) { value = n }
                }
                .onChange(of: focused) { isFocused in
                    if !isFocused { text = String(value) }   // an empty or out-of-range entry snaps back
                }
            Text("%").font(.system(size: 24, weight: .bold)).foregroundStyle(palette.ink)
        }
    }
}

private struct PreferencesStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: Preferences
    let palette: OnboardingPalette
    /// Whether macOS blocks Cap's notifications; looked at again whenever the window comes back to the front.
    @StateObject private var access = NotificationAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(headline: "Now, a house rule.",
                       text: "When should I tap you on the shoulder? This lives in Settings too.",
                       palette: palette)
            notificationsCard
        }
        .onAppear { access.startPolling() }
        .onDisappear { access.stopPolling() }
        .onChange(of: model.notificationsDenied) { _ in access.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in access.refresh() }
        // macOS turned Cap's notifications off: the switch follows, as in Settings, instead of staying on and doing nothing
        // (build 34 test, 2026-11-15).
        .onChange(of: access.denied) { denied in if denied { preferences.notificationsEnabled = false } }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }

    // Card B -----------------------------------------------------------

    private var notificationsCard: some View {
        let on = preferences.notificationsEnabled
        return card {
            VStack(spacing: 0) {
                HStack {
                    Text("Should I tell you when you hit a limit?")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.ink)
                    Spacer(minLength: 8)
                    Text("Turn on notifications").font(.system(size: 12)).foregroundStyle(palette.muted)
                    Button { model.setNotifications(!on) } label: {
                        ZStack(alignment: on ? .trailing : .leading) {
                            Capsule().fill(on ? palette.primaryFill : palette.chip).frame(width: 38, height: 22)
                            Circle().fill(Color.white).frame(width: 18, height: 18)
                                .shadow(color: .black.opacity(0.25), radius: 1, y: 1).padding(2)
                        }
                        .frame(width: 38, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Turn on notifications")
                    .accessibilityValue(on ? "On" : "Off")
                }
                .padding(.vertical, 14).padding(.horizontal, 18)
                Rectangle().fill(palette.hairline).frame(height: 1)
                if access.denied {
                    // Blocked in macOS (Batch B, same wording as Settings): neutral, never amber, and a way to fix it.
                    HStack(spacing: 12) {
                        Text("macOS has notifications turned off for Cap.")
                            .font(.system(size: 12)).foregroundStyle(palette.muted)
                        Spacer(minLength: 8)
                        SecondaryButton(title: "Open System Settings", palette: palette, small: true) { NotificationAccess.openSystemSettings() }
                    }
                    .padding(.vertical, 12).padding(.horizontal, 18)
                    .background(palette.modeFill)
                } else {
                    HStack(spacing: 18) {
                        alertColumn("Tell me when my session usage reaches", $preferences.sessionAlertPercent)
                        Rectangle().fill(palette.hairline).frame(width: 1, height: 55)
                        alertColumn("Tell me when my weekly usage reaches", $preferences.weeklyAlertPercent)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 18)
                    .opacity(on ? 1 : 0.15)
                    .allowsHitTesting(on)
                }
            }
        }
    }

    private func alertColumn(_ sentence: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Text(sentence).font(.system(size: 13)).lineSpacing(2).foregroundStyle(palette.ink)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PercentField(value: value, palette: palette)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 4 · Menu bar

private struct MenuBarStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: Preferences
    let palette: OnboardingPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(headline: "How much of me do you want to see?",
                       text: "Pick how I look in the menu bar. You can switch any time from the popover.",
                       palette: palette)
            HStack(spacing: 12) {
                choice(title: "Compact", line: "Just the dial and your session.", expanded: false)
                choice(title: "Expanded", line: "Your session and your week.", expanded: true)
            }
            loginRow
        }
    }

    private func choice(title: String, line: String, expanded: Bool) -> some View {
        let selected = preferences.showInlineMenuBarStats == expanded
        return Button { preferences.showInlineMenuBarStats = expanded } label: {
            VStack(alignment: .leading, spacing: 14) {
                preview(expanded: expanded)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.ink)
                    Text(line).font(.system(size: 12)).foregroundStyle(palette.muted)
                }
            }
            .padding(selected ? 15 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? palette.primaryFill : palette.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func preview(expanded: Bool) -> some View {
        MenuBarPreview(expanded: expanded, palette: palette)
    }

    private var loginRow: some View {
        Button { model.launchAtLogin.toggle() } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open Cap at login").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.ink)
                    Text("So I'm already keeping count when you start work.").font(.system(size: 12)).lineSpacing(12 * 0.45 - 2).foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
                ZStack(alignment: model.launchAtLogin ? .trailing : .leading) {
                    Capsule().fill(model.launchAtLogin ? palette.primaryFill : palette.chip).frame(width: 38, height: 22)
                    Circle().fill(Color.white).frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .padding(2)
                }
                .frame(width: 38, height: 22)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Cap at login")
        .accessibilityValue(model.launchAtLogin ? "On" : "Off")
    }
}

/// The footer-style 135° hatch used on the preview tiles (1pt lines every 6pt).
struct HatchLines: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6 * 1.41421356
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
    }
}

// MARK: - Step 5 · Find me

private struct FindMeStep: View {
    @ObservedObject var preferences: Preferences
    let palette: OnboardingPalette
    /// "Open Cap at login" is on: macOS will show its own background-activity banner, so say it is expected.
    let launchAtLogin: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            mockDesktop
            VStack(alignment: .leading, spacing: 10) {
                Headline(text: "That's me. Click for details.", palette: palette)
                BodyText(text: "Want me on your desktop too? Click the pin in the popover.", palette: palette)
                if launchAtLogin {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 12))
                        Text("macOS will say I can run in the background. That's expected.").font(.system(size: 12))
                    }
                    .foregroundStyle(palette.muted)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var barInk: Color { scheme == .dark ? Color(red: 0.957, green: 0.945, blue: 0.933) : Color(red: 0.118, green: 0.102, blue: 0.094) }

    private var mockDesktop: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.169, green: 0.141, blue: 0.188), Color(red: 0.290, green: 0.227, blue: 0.235), Color(red: 0.110, green: 0.094, blue: 0.125)]
                        : [Color(red: 0.788, green: 0.722, blue: 0.682), Color(red: 0.902, green: 0.839, blue: 0.792), Color(red: 0.702, green: 0.620, blue: 0.573)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            menuBar
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            capItem
            Image(systemName: "wifi").font(.system(size: 11, weight: .semibold))
            Image(systemName: "battery.100").font(.system(size: 12))
            Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(barInk)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(scheme == .dark ? Color(red: 0.16, green: 0.13, blue: 0.12).opacity(0.82) : Color(red: 0.965, green: 0.949, blue: 0.933).opacity(0.82))
    }

    private var capItem: some View {
        let image = preferences.showInlineMenuBarStats
            ? DialRenderer.inlineImage(sessionPct: 31, weekPct: 5) : DialRenderer.collapsedImage(sessionPct: 31)
        return Image(nsImage: image).renderingMode(.template).foregroundStyle(barInk)
            .overlay(alignment: .bottom) {
                callout.alignmentGuide(.bottom) { d in d[.top] - 8 }
            }
    }

    private var callout: some View {
        VStack(spacing: 0) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 7)); p.addLine(to: CGPoint(x: 7, y: 0)); p.addLine(to: CGPoint(x: 14, y: 7)); p.closeSubpath()
            }
            .fill(palette.shell)
            .frame(width: 14, height: 7)
            Text("That's me. Click for details.")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.shell))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
        }
        .fixedSize()
        .allowsHitTesting(false)
    }
}

// MARK: - Window content

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var scheme

    private var palette: OnboardingPalette { .resolve(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 40) // titlebar: the traffic lights sit here

            let centered = model.step == 0 || model.step == 4
            Group {
                switch model.step {
                case 0: WelcomeStep(palette: palette)
                case 1: ConnectStep(model: model, preferences: preferences, palette: palette)
                case 2: PreferencesStep(model: model, preferences: preferences, palette: palette)
                case 3: MenuBarStep(model: model, preferences: preferences, palette: palette)
                default: FindMeStep(preferences: preferences, palette: palette, launchAtLogin: model.launchAtLogin)
                }
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .top)

            footer
        }
        .frame(width: 680, height: 620)
        .background(palette.shell)
        .ignoresSafeArea()   // the titlebar's inset would otherwise add 32pt: the window is exactly 680 × 620
        .overlay(alignment: .topTrailing) {
            if let note = model.previewNote {
                Text(note)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(palette.chip))
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(0..<OnboardingModel.stepCount, id: \.self) { i in
                    Button { model.jump(to: i) } label: {
                        Capsule()
                            .fill(palette.primaryFill)
                            .frame(width: i == model.step ? 22 : 6, height: 6)
                            .opacity(i <= model.step ? 1 : 0.28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step \(i + 1)")
                }
                Text("\(model.step + 1) of \(OnboardingModel.stepCount)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.muted)
                    .padding(.leading, 8)
            }
            Spacer()
            HStack(spacing: 10) {
                if model.step > 0 {
                    SecondaryButton(title: "Back", palette: palette) { model.goBack() }
                }
                PrimaryButton(title: model.primaryTitle, palette: palette, enabled: model.canContinue) { model.advance() }
            }
        }
        .padding(.leading, 56)
        .padding(.trailing, 24)
        .frame(height: 72)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }
}
