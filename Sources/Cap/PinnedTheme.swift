import AppKit
import SwiftUI

/// Colors and material for the pinned widget, from the design's "Widget styles" table.
///
/// Rows: Default (light/dark), Dark, Clear (light/dark), Tinted (light/dark).
/// Brand color appears only in Default and Dark; Clear and Tinted hand color
/// to the system.
struct PinnedTheme {
    enum Material {
        /// "Opaque system material" (Default, Dark).
        case system
        /// System clear glass.
        case glassClear
        /// System glass; the tint comes from the `bg` overlay.
        case glassRegular
    }

    var material: Material
    var bg: Color
    var border: Color
    var highlight: Color
    var ink: Color
    var muted: Color
    var sub: Color
    var line: Color
    var fill: Color
    var track: Color
    var fig: Color
    var btn: Color
    /// Clear rows add a soft text shadow.
    var textShadow: (color: Color, y: CGFloat, radius: CGFloat)?

    // MARK: Resolution

    static func resolve(style: WidgetStyle, scheme: ColorScheme) -> PinnedTheme {
        switch style.kind {
        case .regular:
            return scheme == .dark ? defaultDark : defaultLight
        case .dark:
            return darkStyle
        case .clear:
            return scheme == .dark ? clearDark : clearLight
        case .tinted:
            return tinted(from: style.tintColor, dark: scheme == .dark)
        }
    }

    // MARK: Helpers

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    private static func hex(_ v: Int, _ a: Double = 1) -> Color {
        rgba(Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF), a)
    }

    // MARK: Default · Light

    private static let defaultLight = PinnedTheme(
        material: .system,
        bg: rgba(250, 247, 244, 0.90),
        border: rgba(255, 255, 255, 0.60),
        highlight: rgba(255, 255, 255, 0.70),
        ink: hex(0x1E1A18),
        muted: rgba(30, 26, 24, 0.60),
        sub: rgba(30, 26, 24, 0.74),
        line: rgba(30, 26, 24, 0.10),
        fill: hex(0xB5532F),
        track: rgba(30, 26, 24, 0.10),
        fig: hex(0xA44A29),
        btn: rgba(30, 26, 24, 0.08),
        textShadow: nil
    )

    // MARK: Default · Dark

    private static let defaultDark = PinnedTheme(
        material: .system,
        bg: rgba(40, 33, 30, 0.90),
        border: rgba(255, 255, 255, 0.10),
        highlight: rgba(255, 255, 255, 0.10),
        ink: hex(0xF4F1EE),
        muted: rgba(244, 241, 238, 0.60),
        sub: rgba(244, 241, 238, 0.78),
        line: rgba(255, 255, 255, 0.10),
        fill: hex(0xD9744C),
        track: rgba(255, 255, 255, 0.12),
        fig: hex(0xE58A64),
        btn: rgba(255, 255, 255, 0.12),
        textShadow: nil
    )

    // MARK: Dark (any appearance)

    private static let darkStyle = PinnedTheme(
        material: .system,
        bg: rgba(14, 12, 11, 0.94),
        border: rgba(255, 255, 255, 0.08),
        highlight: rgba(255, 255, 255, 0.06),
        ink: hex(0xF4F1EE),
        muted: rgba(244, 241, 238, 0.55),
        sub: rgba(244, 241, 238, 0.74),
        line: rgba(255, 255, 255, 0.09),
        fill: hex(0xE89772),
        track: rgba(255, 255, 255, 0.10),
        fig: hex(0xEFA582),
        btn: rgba(255, 255, 255, 0.12),
        textShadow: nil
    )

    // MARK: Clear

    private static let clearLight = PinnedTheme(
        material: .glassClear,
        bg: rgba(255, 255, 255, 0.16),
        border: rgba(255, 255, 255, 0.45),
        highlight: rgba(255, 255, 255, 0.55),
        ink: .white,
        muted: rgba(255, 255, 255, 0.82),
        sub: rgba(255, 255, 255, 0.90),
        line: rgba(255, 255, 255, 0.32),
        fill: .white,
        track: rgba(255, 255, 255, 0.32),
        fig: .white,
        btn: rgba(255, 255, 255, 0.22),
        textShadow: (.black.opacity(0.22), 1, 1)
    )

    private static let clearDark = PinnedTheme(
        material: .glassClear,
        bg: rgba(0, 0, 0, 0.20),
        border: rgba(255, 255, 255, 0.22),
        highlight: rgba(255, 255, 255, 0.25),
        ink: .white,
        muted: rgba(255, 255, 255, 0.72),
        sub: rgba(255, 255, 255, 0.86),
        line: rgba(255, 255, 255, 0.24),
        fill: .white,
        track: rgba(255, 255, 255, 0.26),
        fig: .white,
        btn: rgba(255, 255, 255, 0.18),
        textShadow: (.black.opacity(0.30), 1, 1)
    )

    // MARK: Tinted — every color derived from the user's system tint

    /// The README's blue reference values map to the tint's hue like so:
    ///   light bg  = tint at 42%                         (28,128,250 → .42)
    ///   dark bg   = deep tint (brightness ×0.43) at 58% (8,50,108 → .58)
    ///   tint-light = same hue, saturation ~0.40, full brightness (9ACFFF)
    ///   pale tint  = same hue, saturation ~0.16, full brightness (D6EAFF)
    private static func tinted(from tint: NSColor, dark: Bool) -> PinnedTheme {
        let base = tint.usingColorSpace(.sRGB) ?? .systemBlue
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat, _ alpha: Double = 1) -> Color {
            Color(nsColor: NSColor(calibratedHue: h, saturation: s, brightness: b, alpha: 1)).opacity(alpha)
        }

        if !dark {
            return PinnedTheme(
                material: .glassRegular,
                bg: Color(nsColor: base).opacity(0.42),
                border: rgba(255, 255, 255, 0.45),
                highlight: rgba(255, 255, 255, 0.50),
                ink: .white,
                muted: rgba(255, 255, 255, 0.80),
                sub: rgba(255, 255, 255, 0.90),
                line: rgba(255, 255, 255, 0.30),
                fill: .white,
                track: rgba(255, 255, 255, 0.30),
                fig: .white,
                btn: rgba(255, 255, 255, 0.22),
                textShadow: (Color(nsColor: base).opacity(0.28), 1, 1.5) // faint tint-colored shadow
            )
        }

        let deep = hsb(h, min(1, s * 1.04), b * 0.43, 0.58)
        let tintLight = { (alpha: Double) in hsb(h, min(1, s * 0.45), 1, alpha) }
        let pale = { (alpha: Double) in hsb(h, min(1, s * 0.18), 1, alpha) }
        return PinnedTheme(
            material: .glassRegular,
            bg: deep,
            border: tintLight(0.22),
            highlight: tintLight(0.20),
            ink: pale(1),
            muted: pale(0.70),
            sub: pale(0.84),
            line: tintLight(0.20),
            fill: tintLight(1),
            track: tintLight(0.22),
            fig: pale(1),
            btn: tintLight(0.18),
            textShadow: nil
        )
    }
}
