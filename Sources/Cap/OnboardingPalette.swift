import SwiftUI

/// Colors for the first-run welcome window: the popover's light/dark colour table from the design,
/// plus two exceptions (primary button and success green). Kept separate from `Brand`
/// (the locked popover's palette), which differs slightly from this table.
struct OnboardingPalette {
    let shell: Color        // window background
    let card: Color         // cards and the checklist
    let strip: Color        // header strip / selected segment / chip
    let border: Color
    let hairline: Color     // row dividers and the footer's top rule
    let chip: Color         // chips and the switch's off state
    let muted: Color
    let ink: Color
    let track: Color        // dial track
    let accent: Color       // terracotta
    let primaryFill: Color
    let primaryText: Color
    let success: Color
    let successTint: Color
    let amber: Color
    let amberTint: Color
    let modeFill: Color     // the darker data-mode section at the bottom of the checklist card

    static func resolve(_ scheme: ColorScheme) -> OnboardingPalette {
        func hex(_ v: Int, _ a: Double = 1) -> Color {
            Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
        }
        if scheme == .dark {
            return OnboardingPalette(
                shell: hex(0x2A2321), card: hex(0x231D1B), strip: hex(0x3A322D), border: hex(0x463C36),
                hairline: hex(0x3A312C), chip: hex(0x3A322D),
                muted: hex(0xA89D95), ink: hex(0xF4F1EE), track: hex(0x3E3530), accent: hex(0xC4643F),
                primaryFill: hex(0xD9744C), primaryText: hex(0x1E1A18),
                success: hex(0x7BC79A), successTint: hex(0x7BC79A, 0.14),
                amber: hex(0xF0B45A), amberTint: hex(0xF0B45A, 0.14),
                modeFill: hex(0x1C1716)
            )
        }
        return OnboardingPalette(
            shell: hex(0xF8F5F2), card: hex(0xF4F0EC), strip: hex(0xE4DCD5), border: hex(0xDCD3CC),
            hairline: hex(0xE0D8D1), chip: hex(0xE2D9D2),
            // README §2 says #7E736C; the prototype uses this darker value for body text and labels.
            muted: hex(0x6F645D), ink: hex(0x1E1A18), track: hex(0xE2D9D2), accent: hex(0xC4643F),
            primaryFill: hex(0xB5532F), primaryText: .white,
            success: hex(0x2F7D4F), successTint: hex(0x2F7D4F, 0.12),
            amber: hex(0x9A5B00), amberTint: hex(0xB26A00, 0.13),
            modeFill: hex(0xECE5DF)
        )
    }
}
