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
        guard state.perform(.feed, at: date) else { return "牠還飽著，稍等一下再餵。" }
        return "吃了一口。飽足 \(Int(state.care.satiety.rounded()))。"
    }

    static func pet(_ state: inout PatrickExperienceState, at date: Date = .now) -> String {
        guard state.perform(.pet, at: date) else { return "牠剛剛被摸過，稍等一下。" }
        return "摸了摸。親密 \(state.care.bond)。"
    }

    static func moodLine(_ state: PatrickExperienceState) -> String {
        let satiety = Int(state.care.satiety.rounded())
        return "我現在是\(state.settings.mood.title)。飽足 \(satiety)，親密 \(state.care.bond)。"
    }
}
