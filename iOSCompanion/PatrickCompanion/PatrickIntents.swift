import AppIntents
import Foundation
import WidgetKit

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
        return .result(dialog: "Opening Patrick to play the theme cue.")
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
    case focus, breathing, exercise
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "陪伴種類")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.focus: "專注", .breathing: "呼吸休息", .exercise: "運動陪伴"]
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
@MainActor private enum PatrickExperienceIntentExecutor {
    static func care(_ action: PatrickCareAction) -> Bool {
        var state = PatrickSharedStore.shared.loadExperience()
        guard state.perform(action) else { return false }
        send(state, action: action); return true
    }
    static func change(_ mutation: (inout PatrickExperienceState) -> Void) {
        var state = PatrickSharedStore.shared.loadExperience()
        mutation(&state); state.changed(); send(state)
    }
    private static func send(_ state: PatrickExperienceState, action: PatrickCareAction? = nil) {
        let store = PatrickSharedStore.shared
        store.saveExperience(state)
        let settings = store.updateSettings { $0.experience = state }
        WatchSyncService.shared.send(command: PatrickCommandPayload(name: .updateExperience, careAction: action), settings: settings)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .patrickExperienceChanged, object: nil)
    }
}
extension Notification.Name {
    static let patrickExperienceChanged = Notification.Name("com.chans.patrickface.experience-changed")
}
