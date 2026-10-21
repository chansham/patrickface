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

    struct CompanionDay: Sendable {
        var meeting = false
        var commute = false
        var focus = false
        var events: [PatrickCalendarInterval] = []
        var sittingMinutes: Int?
        var stationarySinceMS: Double?
    }

    func refreshCompanion(stationarySinceMS: Double?, into apply: @escaping @MainActor (CompanionDay) -> Void) {
        Task {
            let focus = await PatrickFocusFilterIntent.refreshStoredFlag()
            let granted = await ensureCalendarAccess()
            let meeting = granted ? currentMeetingEvents() : false
            let commute = await currentCommute()
            let upcoming: [PatrickCalendarInterval] = granted ? upcomingEvents() : []
            let sitting = await sitting(sinceMS: stationarySinceMS)
            var day = CompanionDay(meeting: meeting, commute: commute, focus: focus, events: upcoming)
            day.sittingMinutes = sitting.minutes
            day.stationarySinceMS = sitting.sinceMS
            apply(day)
        }
    }

    private func ensureCalendarAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                events.requestFullAccessToEvents { ok, _ in continuation.resume(returning: ok) }
            }
        default: return false
        }
    }

    private func currentMeetingEvents() -> Bool {
        let now = Date()
        let predicate = events.predicateForEvents(withStart: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), calendars: nil)
        return events.events(matching: predicate).contains { event in
            !event.isAllDay && event.startDate <= now && event.endDate > now
        }
    }

    private func upcomingEvents() -> [PatrickCalendarInterval] {
        let now = Date()
        let predicate = events.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3 * 3600), calendars: nil)
        return events.events(matching: predicate).filter { !$0.isAllDay }.map {
            PatrickCalendarInterval(start: $0.startDate, end: $0.endDate, title: $0.title)
        }
    }

    private func sitting(sinceMS: Double?) async -> (minutes: Int?, sinceMS: Double?) {
        guard CMMotionActivityManager.isActivityAvailable() else { return (nil, sinceMS) }
        let status = CMMotionActivityManager.authorizationStatus()
        if status == .denied || status == .restricted { return (nil, sinceMS) }
        let sample: (moving: Bool, stationary: Bool) = await withCheckedContinuation { continuation in
            motion.queryActivityStarting(from: Date().addingTimeInterval(-180), to: Date(), to: .main) { activities, _ in
                let moving = activities?.contains { ($0.walking || $0.running || $0.cycling || $0.automotive) && $0.confidence != .low } ?? false
                let stationary = activities?.contains { $0.stationary && $0.confidence != .low } ?? false
                continuation.resume(returning: (moving, stationary))
            }
        }
        if sample.moving { return (nil, nil) }
        guard sample.stationary else { return (nil, sinceMS) }
        let since = sinceMS ?? (Date().timeIntervalSince1970 * 1000).rounded()
        let minutes = Int(Date().timeIntervalSince(Date(timeIntervalSince1970: since / 1000)) / 60)
        return (max(0, minutes), since)
    }
}
