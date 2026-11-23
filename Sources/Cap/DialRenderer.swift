import AppKit

/// Draws the Dial 1b progress meters for the menu bar item.
///
/// Geometry comes from README-ASSETS.md: the hole is 62% of the outer
/// diameter, the sweep starts at 6 o'clock and fills clockwise, and the
/// track is drawn at 30% alpha.
///
/// Hybrid color rule: below 70% the item is a template image, so macOS tints
/// it for light/dark/highlighted. A dial at 70%+ is orange, at 90%+ red; since
/// a template can't hold color, the whole image then becomes non-template and
/// its text follows the menu bar's appearance through dynamic NSColors.
enum DialRenderer {
    enum Severity {
        case normal, warning, critical

        init(pct: Double?) {
            guard let pct else { self = .normal; return }
            if pct >= 90 { self = .critical }
            else if pct >= 70 { self = .warning }
            else { self = .normal }
        }

        var color: NSColor? {
            switch self {
            case .normal: return nil
            case .warning: return .systemOrange
            case .critical: return .systemRed
            }
        }

        /// Text needs more contrast than the dial fill: brighter on a dark
        /// menu bar, deeper on a light one.
        var textColor: NSColor? {
            switch self {
            case .normal: return nil
            case .warning: return Severity.dynamic(dark: (1.00, 0.72, 0.30), light: (0.76, 0.38, 0.00))
            case .critical: return Severity.dynamic(dark: (1.00, 0.42, 0.40), light: (0.80, 0.08, 0.10))
            }
        }

        private static func dynamic(dark: (CGFloat, CGFloat, CGFloat), light: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let c = isDark ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }
    }

    private static let imageHeight: CGFloat = 22
    private static let holeRatio: CGFloat = 0.62
    private static let trackAlpha: CGFloat = 0.30

    // MARK: Public

    // The menu bar item (design "MenuBar item" 2a Tint capsule / 3a Compact + Week): the dial and the figures sit inside
    // one 18 pt capsule filled with the menu bar ink at 14% (20% with Reduce transparency). The capsule is drawn into the
    // same image as the dial and text, so while the item is a template macOS tints all of it together.
    private static let capsuleHeight: CGFloat = 18
    private static let capsulePad: CGFloat = 6
    private static let dialSize: CGFloat = 14
    private static let dialFigureGap: CGFloat = 4
    private static let groupGap: CGFloat = 8
    private static let imageInset: CGFloat = 1
    static let capsuleAlpha: CGFloat = 0.14
    static let capsuleAlphaSolid: CGFloat = 0.12   // was 0.20: Brian found it too dark in light mode with Reduce transparency (Pass F, 2026-10-29)

    /// "—%" until there is a reading.
    private static func figureText(_ pct: Double?) -> String { pct == nil ? "—%" : UsageFormat.percent(pct) }

    /// Compact item: capsule [dial, 4 pt, figure]. `signedOut`: Claude Code has no login, so old numbers would mislead;
    /// an empty dial and "Sign in" take their place.
    static func collapsedImage(sessionPct: Double?, signedOut: Bool = false) -> NSImage {
        let sessionPct = signedOut ? nil : sessionPct
        let severity = Severity(pct: sessionPct)
        let isTemplate = severity == .normal
        let text = NSAttributedString(string: signedOut ? "Sign in" : figureText(sessionPct), attributes: [
            .font: figureFont, .foregroundColor: isTemplate ? NSColor.black : (severity.textColor ?? NSColor.labelColor),
        ])
        let capsuleWidth = ceil(capsulePad + dialSize + dialFigureGap + text.size().width + capsulePad)
        return makeImage(width: capsuleWidth + 2 * imageInset, isTemplate: isTemplate) { _ in
            drawCapsule(x: imageInset, width: capsuleWidth, isTemplate: isTemplate)
            let x = imageInset + capsulePad
            drawDial(pct: sessionPct, severity: severity, in: CGRect(x: x, y: (imageHeight - dialSize) / 2, width: dialSize, height: dialSize), isTemplate: isTemplate)
            drawCentered(text, x: x + dialSize + dialFigureGap)
        }
    }

    /// Expanded item: the compact capsule plus "Week 5%" (the dial is the session, so only the week gets a label).
    static func inlineImage(sessionPct: Double?, weekPct: Double?) -> NSImage {
        let sevS = Severity(pct: sessionPct)
        let sevW = Severity(pct: weekPct)
        let isTemplate = sevS == .normal && sevW == .normal

        func figure(_ v: Double?, _ sev: Severity) -> NSAttributedString {
            NSAttributedString(string: figureText(v), attributes: [
                .font: figureFont, .foregroundColor: isTemplate ? NSColor.black : (sev.textColor ?? NSColor.labelColor)])
        }
        // Every glyph is drawn at 100% alpha (contrast fix 2026-10-30): "Week" is told apart from the figures by size and
        // weight, not by opacity. Non-template mode uses labelColor so it stays legible next to an orange or red figure.
        let weekLabel = NSAttributedString(string: "Week", attributes: [
            .font: labelFont, .foregroundColor: isTemplate ? NSColor.black : NSColor.labelColor])
        let sessText = figure(sessionPct, sevS), weekText = figure(weekPct, sevW)

        let g1 = dialSize + dialFigureGap + ceil(sessText.size().width)
        let g2 = ceil(weekLabel.size().width) + dialFigureGap + ceil(weekText.size().width)
        let capsuleWidth = ceil(capsulePad + g1 + groupGap + g2 + capsulePad)

        return makeImage(width: capsuleWidth + 2 * imageInset, isTemplate: isTemplate) { _ in
            drawCapsule(x: imageInset, width: capsuleWidth, isTemplate: isTemplate)
            let x = imageInset + capsulePad
            drawDial(pct: sessionPct, severity: sevS, in: CGRect(x: x, y: (imageHeight - dialSize) / 2, width: dialSize, height: dialSize), isTemplate: isTemplate)
            drawCentered(sessText, x: x + dialSize + dialFigureGap)
            let x2 = x + g1 + groupGap
            drawCentered(weekLabel, x: x2)
            drawCentered(weekText, x: x2 + ceil(weekLabel.size().width) + dialFigureGap)
        }
    }

    /// The menu bar item's width in points for a given reading (for the width budget: Compact <= 72, Expanded <= 140 plus
    /// the 6 pt highlight padding macOS adds).
    static func itemWidth(expanded: Bool, sessionPct: Double?, weekPct: Double?) -> CGFloat {
        (expanded ? inlineImage(sessionPct: sessionPct, weekPct: weekPct) : collapsedImage(sessionPct: sessionPct)).size.width
    }

    private static func drawCapsule(x: CGFloat, width: CGFloat, isTemplate: Bool) {
        let alpha = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? capsuleAlphaSolid : capsuleAlpha
        let rect = NSRect(x: x, y: (imageHeight - capsuleHeight) / 2, width: width, height: capsuleHeight)
        (isTemplate ? NSColor.black : NSColor.labelColor).withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: capsuleHeight / 2, yRadius: capsuleHeight / 2).fill()
    }

    // MARK: Drawing

    private static var labelFont: NSFont { .systemFont(ofSize: 11.5, weight: .semibold) }
    private static var figureFont: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .medium) }

    private static func makeImage(width: CGFloat, isTemplate: Bool, draw: @escaping (CGSize) -> Void) -> NSImage {
        let size = NSSize(width: width, height: imageHeight)
        // The handler re-runs whenever the image is drawn, so dynamic colors
        // resolve against the menu bar's current appearance.
        let image = NSImage(size: size, flipped: false) { _ in
            draw(size)
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    private static func drawCentered(_ s: NSAttributedString, x: CGFloat) {
        let h = s.size().height
        s.draw(at: NSPoint(x: x, y: (imageHeight - h) / 2))
    }

    private static func drawDial(pct: Double?, severity: Severity, in rect: CGRect, isTemplate: Bool) {
        let color: NSColor = severity.color ?? (isTemplate ? .black : .labelColor)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width / 2
        let inner = outer * holeRatio

        // Track: full ring, 30% alpha.
        let track = NSBezierPath()
        track.windingRule = .evenOdd
        track.appendOval(in: rect)
        track.appendOval(in: NSRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
        color.withAlphaComponent(trackAlpha).setFill()
        track.fill()

        // Fill: starts at 6 o'clock (-90°), sweeps clockwise.
        guard let pct, pct > 0 else { return }
        let fraction = min(max(pct / 100, 0), 1)
        let start: CGFloat = -90
        if fraction >= 0.9999 {
            color.setFill()
            let full = NSBezierPath()
            full.windingRule = .evenOdd
            full.appendOval(in: rect)
            full.appendOval(in: NSRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
            full.fill()
            return
        }
        let end = start - CGFloat(fraction) * 360
        let sweep = NSBezierPath()
        sweep.appendArc(withCenter: center, radius: outer, startAngle: start, endAngle: end, clockwise: true)
        sweep.appendArc(withCenter: center, radius: inner, startAngle: end, endAngle: start, clockwise: false)
        sweep.close()
        color.setFill()
        sweep.fill()
    }
}
