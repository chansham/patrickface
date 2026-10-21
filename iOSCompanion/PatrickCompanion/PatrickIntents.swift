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
    static var openAppWhenRun = false

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

struct PatrickGoodNightIntent: AppIntent {
    static var title: LocalizedStringResource = "派大星晚安"
    static var description = IntentDescription("對派大星說晚安。角色進入睡前，睡前倒數保持安靜，鬧鐘除外。不切換系統睡眠專注，也不設定鬧鐘。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run { PatrickSpokenIntentBridge.goodNight() }
        if #available(iOS 18.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickStartRestIntent: AppIntent {
    static var title: LocalizedStringResource = "派大星開始休息"
    static var description = IntentDescription("開始休息。已有陪伴倒數時先保存進度；否則開始呼吸陪伴。不是 HealthKit 健身訓練。")
    static var openAppWhenRun = false
    @Parameter(title: "分鐘", default: 3) var minutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await MainActor.run { PatrickSpokenIntentBridge.rest(minutes: minutes) }
        if outcome.armedCountdown { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
        if #available(iOS 18.0, *) { _ = try? await donate() }
        return .result(dialog: "\(outcome.text)")
    }
}

struct PatrickFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "餵派大星"
    static var description = IntentDescription("餵派大星一口。剛餵過會稍等，不會連續加飽足。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run { PatrickSpokenIntentBridge.feed() }
        if #available(iOS 18.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickPetIntent: AppIntent {
    static var title: LocalizedStringResource = "摸摸派大星"
    static var description = IntentDescription("摸摸派大星並記下照顧。不會因為摸頭而震動。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run { PatrickSpokenIntentBridge.pet() }
        if #available(iOS 18.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickCheckMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "看看派大星心情"
    static var description = IntentDescription("看看派大星現在的心情、飽足和親密。心情是你選的，不是從健康資料推測。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run { PatrickSpokenActions.moodLine(PatrickSharedStore.shared.loadExperience()) }
        if #available(iOS 18.0, *) { _ = try? await donate() }
        return .result(dialog: "\(text)")
    }
}

struct PatrickAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PatrickGoodNightIntent(), phrases: [
            "\(.applicationName)晚安",
            "跟\(.applicationName)說晚安"
        ], shortTitle: "晚安", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: PatrickStartRestIntent(), phrases: [
            "\(.applicationName)開始休息",
            "\(.applicationName)开始休息",
            "讓\(.applicationName)休息 \(\.$minutes) 分鐘"
        ], shortTitle: "開始休息", systemImageName: "pause.circle")
        AppShortcut(intent: PatrickFeedIntent(), phrases: [
            "餵\(.applicationName)",
            "給\(.applicationName)吃一口"
        ], shortTitle: "餵一口", systemImageName: "fork.knife")
        AppShortcut(intent: PatrickPetIntent(), phrases: [
            "摸摸\(.applicationName)"
        ], shortTitle: "摸摸", systemImageName: "hand.tap.fill")
        AppShortcut(intent: PatrickCheckMoodIntent(), phrases: [
            "看看\(.applicationName)心情",
            "\(.applicationName)心情怎麼樣"
        ], shortTitle: "看看心情", systemImageName: "face.smiling")
        AppShortcut(intent: PatrickMoodIntent(), phrases: ["設定\(.applicationName)心情"], shortTitle: "角色心情", systemImageName: "face.smiling")
        AppShortcut(intent: PatrickTimerIntent(), phrases: ["開始\(.applicationName)陪伴計時"], shortTitle: "陪伴計時", systemImageName: "timer")
        AppShortcut(intent: PatrickTimerControlIntent(), phrases: ["控制\(.applicationName)陪伴計時"], shortTitle: "控制陪伴計時", systemImageName: "timer")
        AppShortcut(intent: PatrickAutomationIntent(), phrases: ["向\(.applicationName)回報起床"], shortTitle: "起床與鬧鐘回報", systemImageName: "sun.max.fill")
        AppShortcut(intent: PatrickLifestyleIntent(), phrases: ["套用\(.applicationName)生活流程"], shortTitle: "生活流程", systemImageName: "sun.and.horizon.fill")
    }
}

@MainActor enum PatrickSpokenIntentBridge {
    struct Outcome { var text: String; var armedCountdown: Bool }

    static func goodNight() -> String {
        var state = PatrickSharedStore.shared.loadExperience()
        let text = PatrickSpokenActions.sayGoodNight(&state)
        PatrickSharedStore.shared.saveExperience(state)
        _ = PatrickIntentExecutor.setSleepMode(.on)
        patrickSyncCountdownAlerts(from: PatrickSharedStore.shared.loadExperience())
        return text
    }

    static func rest(minutes: Int) -> Outcome { mutate { PatrickSpokenActions.startRest(&$0, minutes: minutes) } }
    static func feed() -> String { mutate { PatrickSpokenActions.feed(&$0) }.text }
    static func pet() -> String { mutate { PatrickSpokenActions.pet(&$0) }.text }

    private static func mutate(_ mutation: (inout PatrickExperienceState) -> String) -> Outcome {
        var state = PatrickSharedStore.shared.loadExperience()
        let previous = state.revision
        let previousID = state.activity?.id
        let text = mutation(&state)
        let armed = state.activity?.status == .running && state.activity?.id != previousID
        if state.revision != previous { PatrickExperienceIntentExecutor.send(state) }
        return Outcome(text: text, armedCountdown: armed)
    }
}

/// One state transition for both the legacy sleep action and composed routines.
/// No event, reward, timer control, sound request or fixed-outfit override.
enum PatrickSleepModeMutation {
    static func applying(_ mode: PatrickSleepMode, to settings: PatrickSettings,
                         experience: PatrickExperienceState, at date: Date = .now) -> PatrickSettings? {
        let scene: PatrickExperienceScene = mode == .automatic ? .automatic : (mode == .on ? .sleeping : .awake)
        var nextExperience = experience
        if nextExperience.settings.scene != scene {
            nextExperience.settings.scene = scene
            nextExperience.changed(at: date)
        }
        guard settings.sleepMode != mode || settings.experience != nextExperience else { return nil }
        var next = settings
        next.sleepMode = mode
        next.experience = nextExperience
        return next.nextRevision(at: date)
    }
}

enum PatrickIntentExecutor {
    static let store = PatrickSharedStore.shared

    @MainActor static func setSleepMode(_ mode: PatrickSleepMode, using store: PatrickSharedStore = .shared,
                                       retrySnapshot: ((PatrickSettings) -> Void)? = nil) -> PatrickSettings {
        let current = store.loadSettings()
        guard let settings = PatrickSleepModeMutation.applying(mode, to: current, experience: store.loadExperience())
        else {
            // An explicit repeat can retry a state that was saved before WC
            // activated. It must not create another action, event or revision.
            if let retrySnapshot { retrySnapshot(current) }
            else { WatchSyncService.shared.syncSnapshot(settings: current) }
            return current
        }
        if let experience = settings.experience { store.saveExperience(experience) }
        store.saveSettings(settings)
        WatchSyncService.shared.send(
            command: PatrickCommandPayload(name: .setSleepMode, sleepMode: mode),
            settings: settings
        )
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .patrickExperienceChanged, object: nil)
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

enum PatrickLifestyleChoice: String, AppEnum {
    case goodNight, goodMorning, restoreSchedule
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "生活流程")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .goodNight: "晚安", .goodMorning: "早安", .restoreSchedule: "恢復原作息"
    ]
    var sleepMode: PatrickSleepMode {
        switch self {
        case .goodNight: .on
        case .goodMorning: .off
        case .restoreSchedule: .automatic
        }
    }
}

struct PatrickLifestyleIntent: AppIntent {
    static var title: LocalizedStringResource = "套用派大星生活流程"
    static var description = IntentDescription("接在你自己的組合捷徑裡：晚安套用睡前，早安保持清醒至下次設定，恢復原作息則依原有時段。只設定派大星，不切換系統專注、不設鬧鐘、不取消計時；保留固定服裝與音效偏好，不要求播放或強制開啟 App。")
    static var openAppWhenRun = false
    @Parameter(title: "流程", default: .goodNight) var flow: PatrickLifestyleChoice
    static var parameterSummary: some ParameterSummary { Summary("套用派大星\(\.$flow)流程") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = await PatrickIntentExecutor.setSleepMode(flow.sleepMode)
        let message: String
        switch flow {
        case .goodNight:
            message = "派大星準備好了；系統睡眠專注由組合捷徑設定。"
        case .goodMorning:
            message = "派大星已設為清醒，會保持至下次設定；需要依原有時段切換時，請選恢復原作息。系統睡眠專注由組合捷徑關閉。"
        case .restoreSchedule:
            message = "派大星已恢復原作息；系統睡眠專注仍由你或組合捷徑設定。"
        }
        return .result(dialog: "\(message)")
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
enum PatrickActivityControlChoice: String, AppEnum, Sendable {
    // Keep the existing raw values so saved Shortcuts keep working.
    case pause, resume, cancel, takeBreak, returnToActivity
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "計時控制")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .pause: "暫停", .resume: "繼續", .cancel: "結束",
        .takeBreak: "休息一下", .returnToActivity: "返回原活動"
    ]
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
    static var description = IntentDescription("開始本機陪伴倒數；已有進行中或暫停的活動時保留原進度並回報，不自動替換或繼續。不是HealthKit健身訓練。")
    static var openAppWhenRun = true
    @Parameter(title: "種類") var kind: PatrickActivityChoice
    @Parameter(title: "分鐘", default: 5) var minutes: Int
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await PatrickExperienceIntentExecutor.start(PatrickActivityKind(rawValue: kind.rawValue)!, minutes: minutes)
        if case .started = result { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
        return .result(dialog: "\(result.message)")
    }
}
struct PatrickTimerControlIntent: AppIntent {
    static var title: LocalizedStringResource = "控制派大星陪伴計時"
    static var description = IntentDescription("暫停、繼續、結束，或保存原活動去休息1至15分鐘。休息結束不會自動返回；選返回原活動才接續原倒數，原本暫停的活動仍保持暫停。結果先儲存在iPhone並送出同步，不代表手錶已收到。不啟動或結束Apple健身訓練。")
    // The phone app reconciles its local Live Activity while opening. There is
    // no promise that a Shortcuts process can keep the app alive in background.
    static var openAppWhenRun = true
    @Parameter(title: "操作") var action: PatrickActivityControlChoice
    @Parameter(title: "休息分鐘", default: 3) var breakMinutes: Int
    static var parameterSummary: some ParameterSummary {
        Switch(\.$action) {
            Case(.takeBreak) {
                Summary("保存派大星陪伴進度，\(\.$action)\(\.$breakMinutes)分鐘")
            }
            DefaultCase() { Summary("\(\.$action)派大星陪伴計時") }
        }
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await PatrickTimerControlIntentExecutor.control(action, breakMinutes: breakMinutes)
        return .result(dialog: "\(result.message)")
    }
}

enum PatrickTimerControlIntentResult: Equatable, Sendable {
    case activity(PatrickActivityControlResult)
    case rest(PatrickBreakResult)

    var message: String {
        switch self {
        case .activity(let result): result.message
        case .rest(let result): result.message
        }
    }
}

/// Shortcuts uses the same break state machine as TimerControlView. An explicit
/// store and delivery seam lets tests exercise persisted commands without a
/// WatchConnectivity session. Delivery is a request, never a Watch acknowledgement.
@MainActor enum PatrickTimerControlIntentExecutor {
    static func control(_ action: PatrickActivityControlChoice, breakMinutes: Int = 3,
                        using store: PatrickSharedStore = .shared, at date: Date = .now,
                        deliver: ((PatrickSettings) -> Void)? = nil) -> PatrickTimerControlIntentResult {
        var state = store.loadExperience()
        let previousRevision = state.revision
        let result: PatrickTimerControlIntentResult
        switch action {
        case .pause: result = .activity(state.controlActivity(.pause, at: date))
        case .resume: result = .activity(state.controlActivity(.resume, at: date))
        case .cancel: result = .activity(state.controlActivity(.cancel, at: date))
        case .takeBreak: result = .rest(state.manageBreak(.begin(minutes: breakMinutes), at: date))
        case .returnToActivity: result = .rest(state.manageBreak(.returnToActivity, at: date))
        }
        // manageBreak also settles an expired activity. Persist that completion
        // even when it cannot start a break, but never rewrite a repeated command.
        if state.revision != previousRevision {
            store.saveExperience(state)
            let settings = store.updateSettings { $0.experience = state }
            if let deliver { deliver(settings) }
            else {
                WatchSyncService.shared.send(command: PatrickCommandPayload(name: .updateExperience), settings: settings)
                WidgetCenter.shared.reloadAllTimelines()
                NotificationCenter.default.post(name: .patrickExperienceChanged, object: nil)
            }
            patrickSyncCountdownAlerts(from: state)
        }
        return result
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
    static func start(_ kind: PatrickActivityKind, minutes: Int) -> PatrickActivityStartResult {
        var state = PatrickSharedStore.shared.loadExperience()
        let previousRevision = state.revision
        let result = state.requestActivityStart(kind, minutes: minutes)
        if state.revision != previousRevision { send(state) }
        return result
    }
    static func send(_ state: PatrickExperienceState, action: PatrickCareAction? = nil, automationEvent: PatrickAutomationEvent? = nil) {
        let store = PatrickSharedStore.shared
        store.saveExperience(state)
        let settings = store.updateSettings { $0.experience = state }
        WatchSyncService.shared.send(command: PatrickCommandPayload(name: .updateExperience, careAction: action, automationEvent: automationEvent), settings: settings)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .patrickExperienceChanged, object: nil)
        patrickSyncCountdownAlerts(from: state)
    }
}

func patrickSyncCountdownAlerts(from state: PatrickExperienceState) {
    let activity = state.activity
    let session = state.breakSession
    let settings = state.settings
    Task { @MainActor in
        await PatrickCountdownNotifier.shared.sync(activity: activity, breakSession: session, legacy: nil, settings: settings)
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
