import AppKit
import UserNotifications

/// Whether macOS currently blocks Cap's notifications (turned off in System Settings → Notifications). When it does,
/// asking again shows no dialog and the switch in Settings silently stays off, so Settings explains it instead.
@MainActor
final class NotificationAccess: ObservableObject {
    @Published private(set) var denied = false
    private var timer: Timer?

    /// Looks again every 1.5 s while a window that shows the state is on screen. (A timer created inside a SwiftUI
    /// body is rebuilt on every redraw and could miss its tick; this one lives with the object.)
    func startPolling() {
        stopPolling()
        refresh()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let isDenied = settings.authorizationStatus == .denied
            Task { @MainActor in self.denied = isDenied }
        }
    }

    /// Opens System Settings → Notifications, straight to Cap's own entry when macOS understands the app id (ASSUMED
    /// to work on macOS 13+; if it does not, macOS still lands on the Notifications list).
    static func openSystemSettings() {
        let base = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let target = Bundle.main.bundleIdentifier.map { "\(base)?id=\($0)" } ?? base
        if let url = URL(string: target) ?? URL(string: base) { NSWorkspace.shared.open(url) }
    }
}
