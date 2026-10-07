import AppIntents
import Foundation
import WidgetKit
import UIKit

enum PatrickSleepIntentChoice: String, AppEnum {
    case automatic
    case on
    case off

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sleep Mode")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Automatic",
        .on: "On",
        .off: "Off",
    ]

    var mode: PatrickSleepMode {
        switch self {
        case .automatic: .automatic
        case .on: .on
        case .off: .off
        }
    }
}

struct SetPatrickSleepModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Patrick Sleep Mode"
    static var description = IntentDescription(
        "Sets automatic, on, or off sleep behavior in the Patrick apps."
    )

    @Parameter(title: "Mode")
    var mode: PatrickSleepIntentChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Set Patrick sleep mode to \(\.$mode)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = await PatrickIntentExecutor.setSleepMode(mode.mode)
        return .result(
            dialog: "Patrick sleep mode is \(settings.sleepMode.displayName)."
        )
    }
}

struct PlayPatrickThemeSoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Patrick Theme Sound"
    static var description = IntentDescription(
        "Opens the app and plays its short, locally generated theme cue."
    )
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PatrickIntentExecutor.queueForegroundAction(.playThemeSound)
        return .result(dialog: "已開啟派大星；音效會遵守前景與靜音設定。")
    }
}

struct OpenPatrickWatchFaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Patrick Watch Face"
    static var description = IntentDescription(
        "Opens the custom Patrick face in the app and asks the paired watch app to show it."
    )
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PatrickIntentExecutor.queueForegroundAction(.openWatchFace)
        return .result(dialog: "Opening the in-app Patrick face.")
    }
}

struct PatrickAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PatrickCareIntent(), phrases: ["照顧\(.applicationName)"], shortTitle: "照顧派大星", systemImageName: "heart.fill")
        AppShortcut(intent: PatrickSceneIntent(), phrases: ["設定\(.applicationName)情境"], shortTitle: "陪伴情境", systemImageName: "moon.stars.fill")
        AppShortcut(intent: PatrickMoodIntent(), phrases: ["設定\(.applicationName)心情"], shortTitle: "角色心情", systemImageName: "face.smiling")
        AppShortcut(intent: PatrickTimerIntent(), phrases: ["開始\(.applicationName)陪伴計時"], shortTitle: "陪伴計時", systemImageName: "timer")
        AppShortcut(intent: PatrickTimerControlIntent(), phrases: ["控制\(.applicationName)陪伴計時"], shortTitle: "控制陪伴計時", systemImageName: "pause.circle")
        AppShortcut(intent: PatrickAutomationIntent(), phrases: ["向\(.applicationName)回報起床"], shortTitle: "起床與鬧鐘回報", systemImageName: "sun.max.fill")

        AppShortcut(
            intent: SetPatrickSleepModeIntent(),
            phrases: [
                "Set Patrick sleep mode in \(.applicationName)",
            ],
            shortTitle: "Patrick Sleep Mode",
            systemImageName: "moon.zzz.fill"
        )

        AppShortcut(
            intent: PlayPatrickThemeSoundIntent(),
            phrases: [
                "Play Patrick sound in \(.applicationName)",
            ],
            shortTitle: "Patrick Sound",
            systemImageName: "speaker.wave.2.fill"
        )

        AppShortcut(
            intent: OpenPatrickWatchFaceIntent(),
            phrases: [
                "Open Patrick face in \(.applicationName)",
            ],
            shortTitle: "Open Patrick Face",
            systemImageName: "applewatch"
        )
    }
}

private enum PatrickIntentExecutor {
    static let store = PatrickSharedStore.shared

    static func setSleepMode(_ mode: PatrickSleepMode) async -> PatrickSettings {
        var experience = store.loadExperience()
        experience.settings.scene = mode == .automatic ? .automatic : (mode == .on ? .sleeping : .awake)
        experience.changed(); store.saveExperience(experience)
        let settings = store.updateSettings { $0.sleepMode = mode; $0.experience = experience }
        await MainActor.run {
            WatchSyncService.shared.send(
                command: PatrickCommandPayload(
                    name: .setSleepMode,
                    sleepMode: mode,
                    deepLink: PatrickDeepLinkRoute.setSleepMode(mode).url
                ),
                settings: settings
            )
            WidgetCenter.shared.reloadAllTimelines()
        }
        return settings
    }

    static func queueForegroundAction(_ action: PendingPatrickAction.Kind) async {
        if action == .playThemeSound {
            let active = await MainActor.run {
                UIApplication.shared.applicationState == .active
                    && !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            guard active else { return }
        }
        store.enqueue(action)
        let settings = store.loadSettings()
        let command: PatrickCommandPayload
        switch action {
        case .playThemeSound:
            command = PatrickCommandPayload(
                name: .playThemeSound,
                theme: settings.theme,
                deepLink: PatrickDeepLinkRoute.playThemeSound.url
            )
        case .openWatchFace:
            command = PatrickCommandPayload(
                name: .openWatchFace,
                deepLink: PatrickDeepLinkRoute.openWatchFace.url
            )
        }
        await MainActor.run {
            WatchSyncService.shared.send(command: command, settings: settings)
        }
    }
}


enum PatrickCareChoice: String, AppEnum {
    case pet, feed, rest
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "照顧")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.pet: "摸摸", .feed: "餵一口", .rest: "陪牠休息"]
}
enum PatrickSceneChoice: String, AppEnum {
    case auto, awake, sleeping, charging, exercise, focus, bath, celebrate
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "情境")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.auto: "依時間", .awake: "清醒", .sleeping: "睡前", .charging: "充電小劇場", .exercise: "運動陪伴", .focus: "專注", .bath: "泡澡小劇場", .celebrate: "慶祝"]
}
enum PatrickMoodChoice: String, AppEnum {
    case calm, happy, serious, tired, grumpy, low
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "角色心情")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.calm: "平靜", .happy: "開心", .serious: "認真", .tired: "睏倦", .grumpy: "有點不耐煩", .low: "低落"]
}
enum PatrickActivityChoice: String, AppEnum {
    case focus, breathing, exercise, walking, running, strength
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "陪伴種類")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.focus: "專注", .breathing: "呼吸休息", .exercise: "運動陪伴", .walking: "散步陪伴", .running: "跑步陪伴", .strength: "肌力陪伴"]
}
enum PatrickActivityControlChoice: String, AppEnum {
    case pause, resume, cancel
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "計時控制")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.pause: "暫停", .resume: "繼續", .cancel: "結束"]
}
struct PatrickCareIntent: AppIntent {
    static var title: LocalizedStringResource = "照顧派大星"
    static var description = IntentDescription("記錄一次照顧，並傳給已配對的手錶；延遲抵達不補播動作。")
    @Parameter(title: "動作") var action: PatrickCareChoice
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await PatrickExperienceIntentExecutor.care(PatrickCareAction(rawValue: action.rawValue)!)
        return .result(dialog: result ? "已記下這次照顧。" : "牠剛剛收到照顧，稍等一下。")
    }
}
struct PatrickSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "設定派大星情境"
    static var description = IntentDescription("可接在iPhone NFC、睡眠或充電個人自動化之後；情境是你設定的，不表示手錶偵測到泡澡等事件。")
    @Parameter(title: "情境") var scene: PatrickSceneChoice
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PatrickExperienceIntentExecutor.change { $0.settings.scene = PatrickExperienceScene(rawValue: scene.rawValue)! }
        return .result(dialog: "已設定陪伴情境。")
    }
}
struct PatrickMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "設定派大星心情"
    @Parameter(title: "心情") var mood: PatrickMoodChoice
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PatrickExperienceIntentExecutor.change { $0.settings.mood = PatrickMood(rawValue: mood.rawValue)! }
        return .result(dialog: "已設定角色心情。")
    }
}
struct PatrickTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "開始派大星陪伴計時"
    static var description = IntentDescription("本機陪伴倒數，不是HealthKit健身訓練。")
    static var openAppWhenRun = true
    @Parameter(title: "種類") var kind: PatrickActivityChoice
    @Parameter(title: "分鐘", default: 5) var minutes: Int
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PatrickExperienceIntentExecutor.change { $0.start(PatrickActivityKind(rawValue: kind.rawValue)!, minutes: minutes) }
        return .result(dialog: "陪伴倒數已開始。")
    }
}
struct PatrickTimerControlIntent: AppIntent {
    static var title: LocalizedStringResource = "控制派大星陪伴計時"
    static var description = IntentDescription("暫停、繼續或結束現有陪伴倒數，並同步至配對手錶；不啟動或結束Apple健身訓練。")
    // The phone app reconciles its local Live Activity while opening. There is
    // no promise that a Shortcuts process can keep the app alive in background.
    static var openAppWhenRun = true
    @Parameter(title: "操作") var action: PatrickActivityControlChoice
    static var parameterSummary: some ParameterSummary { Summary("\(\.$action)派大星陪伴計時") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await PatrickExperienceIntentExecutor.control(PatrickActivityControl(rawValue: action.rawValue)!)
        return .result(dialog: "\(result.message)")
    }
}
@MainActor private enum PatrickExperienceIntentExecutor {
    static func automation(_ kind: PatrickAutomationEvent.Kind) -> Bool {
        let event = PatrickAutomationEvent(kind: kind, source: .shortcut)
        var state = PatrickSharedStore.shared.loadExperience()
        guard state.recordAutomation(event) else { return false }
        send(state, automationEvent: event)
        // No persisted playback queue and no forced opening of either app.
        NotificationCenter.default.post(name: .patrickAutomationReceived, object: event)
        return true
    }
    static func care(_ action: PatrickCareAction) -> Bool {
        var state = PatrickSharedStore.shared.loadExperience()
        guard state.perform(action) else { return false }
        send(state, action: action); return true
    }
    static func change(_ mutation: (inout PatrickExperienceState) -> Void) {
        var state = PatrickSharedStore.shared.loadExperience()
        mutation(&state); state.changed(); send(state)
    }
    static func control(_ command: PatrickActivityControl) -> PatrickActivityControlResult {
        var state = PatrickSharedStore.shared.loadExperience()
        let previousRevision = state.revision
        let result = state.controlActivity(command)
        if state.revision != previousRevision { send(state) }
        return result
    }
    private static func send(_ state: PatrickExperienceState, action: PatrickCareAction? = nil, automationEvent: PatrickAutomationEvent? = nil) {
        let store = PatrickSharedStore.shared
        store.saveExperience(state)
        let settings = store.updateSettings { $0.experience = state }
        WatchSyncService.shared.send(command: PatrickCommandPayload(name: .updateExperience, careAction: action, automationEvent: automationEvent), settings: settings)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .patrickExperienceChanged, object: nil)
    }
}

enum PatrickAutomationChoice: String, AppEnum {
    case alarmStopped = "alarm-stopped"
    case wakeUp = "wake-up"
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "回報事件")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.alarmStopped: "鬧鐘已停止", .wakeUp: "我起床了"]
}

struct PatrickAutomationIntent: AppIntent {
    static var title: LocalizedStringResource = "回報派大星起床事件"
    static var description = IntentDescription("接在捷徑的鬧鐘停止或起床自動化之後；只回報事件，不讀取或停止系統鬧鐘。動作只在當下可見的App播放，背景不補播。")
    static var openAppWhenRun = false
    @Parameter(title: "事件", default: .wakeUp) var event: PatrickAutomationChoice
    static var parameterSummary: some ParameterSummary { Summary("回報\(\.$event)給派大星") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorded = await PatrickExperienceIntentExecutor.automation(PatrickAutomationEvent.Kind(rawValue: event.rawValue)!)
        return .result(dialog: recorded ? "已記下回報；當下可見時才播放起床動作。" : "這次回報未能記錄。")
    }
}
extension Notification.Name {
    static let patrickExperienceChanged = Notification.Name("com.chans.patrickface.experience-changed")
}
