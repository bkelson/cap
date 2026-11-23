import Foundation
import Network

/// Whether this Mac has a route to the internet right now (macOS's own path monitor; no packages, no permission box).
/// With no route, Claude Code does not report an error: it keeps retrying until Cap's time limit, which showed up as
/// "took too long" and a generic Stale label (Pass C, C.7/C.8). Asking this first lets Cap say "offline" at once and
/// skip the call.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ai.kelson.cap.network")
    private let lock = NSLock()
    private var online = true            // assume online until the first report (a moment after start)
    private var started = false
    private var handler: (@Sendable (Bool) -> Void)?
    private let firstReport = DispatchSemaphore(value: 0)

    var isOnline: Bool { lock.lock(); defer { lock.unlock() }; return online }

    /// Called (off the main thread) whenever the route comes or goes.
    func start(onChange: @escaping @Sendable (Bool) -> Void) {
        lock.lock(); handler = onChange
        let alreadyStarted = started; started = true
        lock.unlock()
        guard !alreadyStarted else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let up = path.status == .satisfied
            self.lock.lock(); let changed = self.online != up; self.online = up; let h = self.handler; self.lock.unlock()
            self.firstReport.signal()
            if changed { h?(up) }
        }
        monitor.start(queue: queue)
        // The first report normally arrives within milliseconds; wait briefly so a Mac that starts offline is not
        // treated as online for its first refresh.
        _ = firstReport.wait(timeout: .now() + 0.5)
    }
}
