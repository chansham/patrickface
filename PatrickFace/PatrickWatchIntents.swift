import AppIntents
import Foundation
import WatchKit

extension Notification.Name {
    static let patrickWatchSpokenIntent = Notification.Name("com.chans.patrickface.watch-spoken-intent")
}

/// Watch Siri uses the same phrases as the phone. The app name token becomes
/// the watch display name, so “派大星陪伴晚安” resolves here.
struct PatrickWatchGoodNightIntent: AppIntent {
    static var title: LocalizedStringResource = "派大星晚安"
    static var description = IntentDescription("對派大星說晚安，進入睡前。不切換系統睡眠專注，也不設定鬧鐘。睡前倒數保持安靜，鬧鐘除外。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await PatrickWatchSpokenPerformer.apply { PatrickSpokenActions.sayGoodNight(&$0) }.text
        if #available(watchOS 11.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickWatchStartRestIntent: AppIntent {
    static var title: LocalizedStringResource = "派大星開始休息"
    static var description = IntentDescription("開始休息。若已有陪伴倒數，先保存進度再休息；否則開始一段呼吸陪伴。不是健身訓練。")
    static var openAppWhenRun = false
    @Parameter(title: "分鐘", default: 3) var minutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await PatrickWatchSpokenPerformer.apply { PatrickSpokenActions.startRest(&$0, minutes: minutes) }
        if outcome.armedCountdown { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
        if #available(watchOS 11.0, *) { _ = try? await donate() }
        return .result(dialog: "\(outcome.text)")
    }
}

struct PatrickWatchFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "餵派大星"
    static var description = IntentDescription("餵食已經收起來了。舊的飽足還在存檔裡，不再增加。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await PatrickWatchSpokenPerformer.apply { PatrickSpokenActions.feed(&$0) }.text
        return .result(dialog: "\(text)")
    }
}

struct PatrickWatchRecordMindIntent: AppIntent {
    static var title: LocalizedStringResource = "記錄我的心情"
    static var description = IntentDescription("把你的心情寫進健康的心境。派大星的表情仍然只跟著今天，不跟著這筆記。")
    static var openAppWhenRun = false
    @Parameter(title: "心情", default: .neutral) var mood: PatrickMindChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let choice = mood
        let text = await PatrickWatchSpokenPerformer.apply { PatrickSpokenActions.recordMind(&$0, raw: choice.rawValue, title: choice.title) }.text
        if #available(watchOS 11.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickWatchPetIntent: AppIntent {
    static var title: LocalizedStringResource = "摸摸派大星"
    static var description = IntentDescription("摸摸派大星。這是照顧記錄，不會震動。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await PatrickWatchSpokenPerformer.apply { PatrickSpokenActions.pet(&$0) }.text
        if #available(watchOS 11.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickWatchMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "看看派大星心情"
    static var description = IntentDescription("看看派大星跟著今天的表情。不讀飽足或親密。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run {
            PatrickSpokenActions.moodLine(PatrickExperienceState.load(from: PatrickSharedStore.defaults))
        }
        if #available(watchOS 11.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PatrickWatchGoodNightIntent(), phrases: [
            "\(.applicationName)晚安",
            "跟\(.applicationName)說晚安"
        ], shortTitle: "晚安", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: PatrickWatchStartRestIntent(), phrases: [
            "\(.applicationName)開始休息",
            "\(.applicationName)开始休息"
        ], shortTitle: "開始休息", systemImageName: "pause.circle")
        AppShortcut(intent: PatrickWatchRecordMindIntent(), phrases: [
            "用\(.applicationName)記錄我的心情"
        ], shortTitle: "記錄我的心情", systemImageName: "heart.text.square")
        AppShortcut(intent: PatrickWatchPetIntent(), phrases: [
            "摸摸\(.applicationName)"
        ], shortTitle: "摸摸", systemImageName: "hand.tap.fill")
        AppShortcut(intent: PatrickWatchMoodIntent(), phrases: [
            "看看\(.applicationName)心情",
            "\(.applicationName)心情怎麼樣"
        ], shortTitle: "看看心情", systemImageName: "face.smiling")
        AppShortcut(intent: PatrickWatchButlerIntent(), phrases: [
            "\(.applicationName) \(\.$choice)"
        ], shortTitle: "一句話", systemImageName: "bubble.left.fill")
    }
}

struct PatrickWatchButlerIntent: AppIntent {
    static var title: LocalizedStringResource = "派大星一句話"
    static var description = IntentDescription("用一句話告訴派大星你出門、回來、要午睡、晚安或累了。手錶用固定的一句話，不連線。")
    static var openAppWhenRun = false
    @Parameter(title: "想說的話") var choice: PatrickButlerChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let phrase = choice.phrase
        let text = await PatrickWatchSpokenPerformer.apply { PatrickSpokenActions.butler(&$0, phrase: phrase, modelText: nil) }.text
        if #available(watchOS 11.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

@MainActor enum PatrickWatchSpokenPerformer {
    struct Outcome {
        var text: String
        var armedCountdown: Bool
    }

    static func apply(_ mutation: (inout PatrickExperienceState) -> String) -> Outcome {
        var state = PatrickExperienceState.load(from: PatrickSharedStore.defaults)
        let previous = state.revision
        let previousID = state.activity?.id
        let text = mutation(&state)
        let armed = state.activity?.status == .running && state.activity?.id != previousID
        if state.revision != previous {
            state.save(to: PatrickSharedStore.defaults)
            PatrickWatchReceiver.shared.sendSnapshot(theme: PatrickSharedStore.load().theme, experience: state)
            NotificationCenter.default.post(name: .patrickWatchSpokenIntent, object: nil)
            let activity = state.activity
            let session = state.breakSession
            let settings = state.settings
            let worn = WKExtension.shared().applicationState == .active
            let quiet = state.contextSnapshot().suppressesProactive
            let role: PatrickWakeRole = worn ? .watch : .none
            Task {
                await PatrickCountdownNotifier.shared.sync(activity: activity, breakSession: session, legacy: nil, settings: settings, schedules: worn, contextQuiet: quiet)
                let cues = PatrickDayPlan.wakeCues(settings: settings, napEndsAt: activity?.nap == true && activity?.status == .running ? activity?.endsAt : nil, role: role, now: .now)
                await PatrickWakeNotifier.shared.sync(cues: cues)
            }
        }
        return Outcome(text: text, armedCountdown: armed)
    }
}
