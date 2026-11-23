import AppKit
import Combine

/// The user's "Icon & widget style" choice from System Settings → Appearance.
///
/// macOS keeps it in the global preferences domain (undocumented, found by
/// observation on macOS 27):
///   AppleIconAppearanceTheme  = <Style><Mode>, e.g. RegularAutomatic, RegularDark,
///                               ClearAutomatic, ClearLight, TintedLight
///   AppleIconAppearanceTintColor = a preset name (Red, Yellow, …), only for Tinted
/// "Default" appears as RegularAutomatic or as the key being absent.
/// Anything unrecognized falls back to Default.
struct WidgetStyle: Equatable {
    /// regular = "Default"; dark = the "Dark" icon style (dark forced).
    enum Kind { case regular, dark, clear, tinted }
    enum Mode { case automatic, light, dark }

    var kind: Kind = .regular
    var mode: Mode = .automatic
    var tintName: String? = nil

    /// Clear and Tinted render as monochrome (white) content, like system widgets.
    var isMonochrome: Bool { kind == .clear || kind == .tinted }

    var appearance: NSAppearance? {
        switch mode {
        case .automatic: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var tintColor: NSColor {
        switch tintName?.lowercased() {
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "graphite", "gray", "grey": return .systemGray
        default: return .systemBlue // unknown name — only the ones above were seen/assumed
        }
    }

    static func read() -> WidgetStyle {
        // Fresh read of the global domain; avoids a stale per-process cache.
        func global(_ key: String) -> String? {
            CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
            return CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        }
        guard let theme = global("AppleIconAppearanceTheme") else { return WidgetStyle() }

        var s = WidgetStyle()
        if theme.hasPrefix("Clear") { s.kind = .clear }
        else if theme.hasPrefix("Tinted") { s.kind = .tinted }
        else if theme == "RegularDark" { s.kind = .dark }
        else { s.kind = .regular }

        if theme.hasSuffix("Light") { s.mode = .light }
        else if theme.hasSuffix("Dark") { s.mode = .dark }
        else { s.mode = .automatic }

        if s.kind == .tinted { s.tintName = global("AppleIconAppearanceTintColor") }
        return s
    }
}

/// The style the pinned widget uses: always the system's "Icon & widget style" (there is no appearance setting).
/// Polls once a second (Cap already polls live.json at 1 Hz) so changes in
/// System Settings show up without needing a notification name.
@MainActor
final class WidgetStyleStore: ObservableObject {
    @Published private(set) var style: WidgetStyle
    private let preferences: Preferences?
    private var timer: Timer?
    private var subscription: AnyCancellable?

    init(style: WidgetStyle? = nil, preferences: Preferences? = nil) {
        self.preferences = preferences
        self.style = style ?? Self.effective(preferences)
    }

    private static func effective(_ preferences: Preferences?) -> WidgetStyle { WidgetStyle.read() }

    private func refresh() {
        let latest = Self.effective(preferences)
        if latest != style { style = latest }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Settings changes should apply immediately, not on the next tick.
        subscription = preferences?.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        subscription = nil
    }
}
