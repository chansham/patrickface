import Foundation

/// One pending local notification for a companion countdown.
/// Scheduling and cancellation live in the app; this value is the decision.
struct PatrickCountdownNotice: Equatable, Sendable {
    var identifier: String
    var fireAt: Date
    var title: String
    var body: String
    var playsSound: Bool
    /// Alarms may ask for a time-sensitive presentation. Other countdowns never do.
    var breaksQuietFocus: Bool
}

/// A phone or watch timer that is not the experience activity.
/// Kept separate so the watch target does not need the phone timer model.
struct PatrickCountdownLegacy: Equatable, Sendable {
    var id: UUID
    var running: Bool
    var endsAt: Date?
    var title: String
}

enum PatrickCountdownPlanner {
    static let prefix = "patrick.countdown."

    static func identifier(for id: UUID) -> String { prefix + id.uuidString }

    /// The desired pending set. Empty means cancel. A new fire date reuses the
    /// activity identifier so the system replaces the previous request.
    static func notices(
        activity: PatrickLocalActivity?,
        breakSession: PatrickBreakSession?,
        legacy: PatrickCountdownLegacy?,
        settings: PatrickExperienceSettings,
        now: Date,
        calendar: Calendar = .current,
        isAlarm: Bool = false,
        contextQuiet: Bool = false
    ) -> [PatrickCountdownNotice] {
        if let activity {
            return notice(for: activity, breakSession: breakSession, settings: settings, now: now,
                          calendar: calendar, isAlarm: isAlarm, contextQuiet: contextQuiet).map { [$0] } ?? []
        }
        guard let legacy, legacy.running, let end = legacy.endsAt, end > now else { return [] }
        return [make(id: legacy.id, fireAt: end, kind: nil, restBreak: false, settings: settings,
                      calendar: calendar, isAlarm: isAlarm, contextQuiet: contextQuiet, fallback: "計時結束了。我還在這裡。")]
    }

    private static func notice(
        for activity: PatrickLocalActivity,
        breakSession: PatrickBreakSession?,
        settings: PatrickExperienceSettings,
        now: Date,
        calendar: Calendar,
        isAlarm: Bool,
        contextQuiet: Bool
    ) -> PatrickCountdownNotice? {
        guard activity.status == .running, let end = activity.endsAt, end > now else { return nil }
        let restBreak = breakSession?.breakActivityID == activity.id
        return make(id: activity.id, fireAt: end, kind: activity.kind, restBreak: restBreak, settings: settings,
                    calendar: calendar, isAlarm: isAlarm, contextQuiet: contextQuiet, fallback: "陪伴時間到了。我還在。")
    }

    private static func make(
        id: UUID,
        fireAt: Date,
        kind: PatrickActivityKind?,
        restBreak: Bool,
        settings: PatrickExperienceSettings,
        calendar: Calendar,
        isAlarm: Bool,
        contextQuiet: Bool,
        fallback: String
    ) -> PatrickCountdownNotice {
        let sleepQuiet = settings.scene == .sleeping || settings.isSleepTime(fireAt, calendar: calendar)
        let quiet = settings.quietAlerts != .allowSound && sleepQuiet
        let hidden = quiet && settings.quietAlerts == .hideExceptAlarms && !isAlarm
        // A meeting, commute, focus, nap or workout keeps the banner and drops the sound.
        let sound = isAlarm || (!quiet && !contextQuiet)
        let body: String
        if isAlarm {
            body = "時間到了。我輕輕叫你。"
        } else if restBreak {
            body = "休息好了。想回去的時候，跟我說一聲。"
        } else if let kind {
            switch kind {
            case .focus: body = "專注時間到了。我在這，慢慢回來就好。"
            case .breathing: body = "呼吸結束了。肩膀可以放下來了。"
            case .exercise, .walking, .running, .strength:
                body = "這段陪伴到了。我先待在這，你也歇一下。"
            }
        } else {
            body = fallback
        }
        return PatrickCountdownNotice(
            identifier: identifier(for: id),
            fireAt: hidden ? .distantPast : fireAt,
            title: "派大星",
            body: body,
            playsSound: sound && !hidden,
            breaksQuietFocus: isAlarm
        )
    }
}

extension PatrickCountdownPlanner {
    /// Hidden notices use a distant fire date so callers can drop them.
    static func pending(_ notices: [PatrickCountdownNotice], now: Date) -> [PatrickCountdownNotice] {
        notices.filter { $0.fireAt > now }
    }
}

/// Smart Stack score. Higher while a countdown is running, then sleep and birthday.
struct PatrickStackRelevance: Equatable, Sendable {
    var score: Float
    var duration: TimeInterval

    static func make(experience: PatrickExperienceState, at date: Date, calendar: Calendar = .current) -> Self {
        if let activity = experience.activity, activity.status == .running,
           let end = activity.endsAt, end > date {
            return Self(score: 90, duration: max(60, end.timeIntervalSince(date)))
        }
        if experience.settings.scene == .sleeping || experience.settings.isSleepTime(date, calendar: calendar) {
            return Self(score: 45, duration: 30 * 60)
        }
        let parts = calendar.dateComponents([.month, .day], from: date)
        let mmdd = String(format: "%02d-%02d", parts.month ?? 0, parts.day ?? 0)
        if experience.settings.birthdayMMDD == mmdd {
            return Self(score: 70, duration: 60 * 60)
        }
        return Self(score: 10, duration: 15 * 60)
    }
}
