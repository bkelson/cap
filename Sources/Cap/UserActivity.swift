import CoreGraphics
import Foundation

/// How long since the person last touched the keyboard or mouse. Needs no
/// permissions (it reads the system's own idle counter, not the events).
enum UserActivity {
    static var secondsIdle: TimeInterval {
        // ~0 = "any input event type".
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static func isIdle(after threshold: TimeInterval) -> Bool {
        secondsIdle >= threshold
    }
}
