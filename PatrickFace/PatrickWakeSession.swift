import Foundation
import WatchKit

/// Best-effort smart alarm. There is no smart-alarm entitlement in this project,
/// so a failed session leaves the local notification as the real cue.
final class PatrickWakeSession: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = PatrickWakeSession()
    private var session: WKExtendedRuntimeSession?

    func arm(at date: Date) {
        guard date.timeIntervalSinceNow > 1 else { return }
        session?.invalidate()
        let next = WKExtendedRuntimeSession()
        next.delegate = self
        session = next
        next.start(at: date)
    }

    func disarm() {
        session?.invalidate()
        session = nil
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        session = nil
    }
}
