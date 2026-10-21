import Foundation

/// Dialog and state changes shared by iPhone and watch App Intents.
enum PatrickSpokenActions {
    static func sayGoodNight(_ state: inout PatrickExperienceState, at date: Date = .now) -> String {
        if state.settings.scene != .sleeping {
            state.settings.scene = .sleeping
            state.record("晚安", at: date)
            state.changed(at: date)
        }
        return "派大星把燈調暗了。晚安。睡前我會安靜，只有鬧鐘會出聲。"
    }

    /// Saves a running activity for a short rest, or starts a breathing countdown
    /// when nothing else is occupying the single timer slot.
    static func startRest(_ state: inout PatrickExperienceState, minutes: Int = 3, at date: Date = .now) -> String {
        let bounded = min(15, max(1, minutes))
        if state.breakSession == nil, let activity = state.activity,
           activity.status == .running || activity.status == .paused,
           activity.remaining(at: date) > 0 {
            return state.manageBreak(.begin(minutes: bounded), at: date).message
        }
        return state.requestActivityStart(.breathing, minutes: bounded, at: date).message
    }

    static func feed(_ state: inout PatrickExperienceState, at date: Date = .now) -> String {
        _ = state.perform(.feed, at: date)
        return "餵食已經收起來了。我還是會陪你。"
    }

    static func pet(_ state: inout PatrickExperienceState, at date: Date = .now) -> String {
        _ = state.perform(.pet, at: date)
        return "摸了摸。"
    }

    static func moodLine(_ state: PatrickExperienceState, at date: Date = .now) -> String {
        let mood = state.displayedMood(at: date)
        return "我現在是\(mood.title)。表情跟著你的一天，不是你選的。"
    }

    static func recordMind(_ state: inout PatrickExperienceState, raw: String, title: String, at date: Date = .now) -> String {
        state.settings.pendingMindRaw = raw
        state.record("心情：\(title)", at: date)
        state.changed(at: date)
        return "記下了：\(title)。手錶會在可以寫入健康時放進心境。"
    }
}
