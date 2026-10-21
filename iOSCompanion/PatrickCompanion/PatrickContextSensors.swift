import CoreMotion
import EventKit
import Foundation

/// iPhone signals for the context gate. Calendar and motion are asked the first
/// time the companion becomes active, not at process launch. A denial leaves
/// the flag false. Commute is sampled while this app is open; there is no
/// background motion mode.
@MainActor
final class PatrickContextSensors {
    static let shared = PatrickContextSensors()
    private let events = EKEventStore()
    private let motion = CMMotionActivityManager()
    private var lastMeeting: Bool?
    private var lastCommute: Bool?
    private var lastFocus: Bool?

    func refresh(into apply: @escaping @MainActor (Bool, Bool, Bool) -> Void) {
        Task {
            let focus = await PatrickFocusFilterIntent.refreshStoredFlag()
            let meeting = await currentMeeting()
            let commute = await currentCommute()
            guard meeting != lastMeeting || commute != lastCommute || focus != lastFocus else { return }
            lastMeeting = meeting
            lastCommute = commute
            lastFocus = focus
            apply(meeting, commute, focus)
        }
    }

    private func currentMeeting() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        let granted: Bool
        switch status {
        case .fullAccess: granted = true
        case .notDetermined:
            granted = await withCheckedContinuation { continuation in
                events.requestFullAccessToEvents { ok, _ in continuation.resume(returning: ok) }
            }
        default: granted = false
        }
        guard granted else { return false }
        let now = Date()
        let end = now.addingTimeInterval(60)
        let predicate = events.predicateForEvents(withStart: now.addingTimeInterval(-60), end: end, calendars: nil)
        return events.events(matching: predicate).contains { event in
            !event.isAllDay && event.startDate <= now && event.endDate > now
        }
    }

    private func currentCommute() async -> Bool {
        guard CMMotionActivityManager.isActivityAvailable() else { return false }
        let status = CMMotionActivityManager.authorizationStatus()
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { continuation in
            motion.queryActivityStarting(from: Date().addingTimeInterval(-180), to: Date(), to: .main) { activities, _ in
                let riding = activities?.contains { $0.automotive && $0.confidence != .low } ?? false
                continuation.resume(returning: riding)
            }
        }
    }
}
