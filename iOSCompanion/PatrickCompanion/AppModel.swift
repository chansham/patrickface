import Combine
import Foundation
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable {
        case control
        case timer
        case status
    }

    @Published private(set) var settings: PatrickSettings
    @Published private(set) var timer: PatrickTimerSnapshot
    @Published var selectedTab: Tab = .control
    @Published var isPresentingWatchFace = false
    @Published private(set) var notice: String?
    @Published private(set) var experience: PatrickExperienceState
    @Published private(set) var actionSequence = 0
    @Published private(set) var requestedCare: PatrickCareAction?
    @Published private(set) var completedActivityID: String?
    @Published private(set) var calendarCelebrationSequence = 0

    let watchSync: WatchSyncService
    let activityController: PatrickActivityController

    private let store: PatrickSharedStore
    private let soundPlayer = ThemeSoundPlayer()
    private let forcedDemoMode: Bool
    private var cancellables = Set<AnyCancellable>()
    private var timerCompletionTask: Task<Void, Never>?

    convenience init() {
        self.init(
            store: .shared,
            watchSync: .shared,
            activityController: PatrickActivityController()
        )
    }

    init(
        store: PatrickSharedStore,
        watchSync: WatchSyncService,
        activityController: PatrickActivityController
    ) {
        self.store = store
        self.watchSync = watchSync
        self.activityController = activityController
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let forcedDemoMode =
            environment["PATRICK_DEMO"] == "1" || arguments.contains("-patrick-demo")
        self.forcedDemoMode = forcedDemoMode

        var initialSettings = store.loadSettings()
        if forcedDemoMode {
            initialSettings.demoMode = true
        }
        self.settings = initialSettings
        self.timer = store.loadTimer()
        self.experience = store.loadExperience()

        watchSync.setDemoMode(settings.demoMode)
        watchSync.onSettingsReceived = { [weak self] settings in
            self?.acceptRemoteSettings(settings)
        }
        watchSync.onTimerReceived = { [weak self] timer in
            self?.acceptRemoteTimer(timer)
        }
        watchSync.onCommandReceived = { [weak self] command in
            self?.acceptRemoteCommand(command)
        }

        NotificationCenter.default.publisher(for: .patrickExperienceChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.becameActive() }
            }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: .patrickPendingActionsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.consumePendingActions()
                }
            }
            .store(in: &cancellables)
    }

    func setTheme(_ theme: PatrickTheme) {
        settings = store.updateSettings { $0.theme = theme }
        watchSync.send(
            command: PatrickCommandPayload(
                name: .setTheme,
                theme: theme,
                deepLink: PatrickDeepLinkRoute.setTheme(theme).url
            ),
            settings: settings
        )
        didChangePresentation()
    }

    func updateExperience(_ mutation: (inout PatrickExperienceState) -> Void) {
        mutation(&experience); experience.changed()
        saveExperience()
    }

    func performCare(_ action: PatrickCareAction) {
        guard experience.perform(action) else { notice = "稍等一下，再\(action.title)"; return }
        requestedCare = action; actionSequence &+= 1
        saveExperience(action: action)
        notice = "\(action.title) · 飽足 \(Int(experience.care.satiety.rounded())) · 親密 \(experience.care.bond)"
    }

    @discardableResult
    func findSurprise() -> Bool {
        guard let line = experience.findSurprise() else { notice = "小驚喜歇一分鐘，再來看看"; return false }
        notice = line
        saveExperience()
        return true
    }

    func refreshExperience(allowEffects: Bool = false, observeCalendar: Bool = true) {
        let revision = experience.revision
        _ = experience.updateCare()
        if observeCalendar, let celebration = experience.observeCalendar(PatrickExperienceResources.calendar(), allowCelebration: allowEffects) {
            notice = celebration; calendarCelebrationSequence &+= 1
        }
        if experience.revision != revision { saveExperience() }
        if let id = experience.reconcile() {
            completedActivityID = allowEffects ? id.uuidString : nil
            timer = .inactive; store.saveTimer(timer)
            saveExperience(); notice = "陪伴計時完成"
            Task { await activityController.endAll(finalStatus: "陪伴計時完成") }
        }
    }

    func startExperienceActivity(_ kind: PatrickActivityKind, minutes: Int) async {
        timerCompletionTask?.cancel(); timerCompletionTask = nil
        experience.start(kind, minutes: minutes)
        saveExperience()
        if let value = experience.activity {
            timer = PatrickTimerSnapshot(id: value.id, status: .running, title: value.kind.title,
                startedAt: value.startedAt, endsAt: value.endsAt, remainingSeconds: nil)
            store.saveTimer(timer)
            await activityController.start(timer: timer, settings: settings)
        }
    }

    func toggleExperiencePause() async {
        if experience.activity?.status == .paused { experience.resume() } else { experience.pause() }
        saveExperience()
        if let value = experience.activity {
            if value.status == .completed { synchronizeActivityPresentation(); return }
            timer = PatrickTimerSnapshot(id: value.id, status: value.status == .paused ? .paused : .running,
                title: value.kind.title, startedAt: value.startedAt, endsAt: value.endsAt, remainingSeconds: value.remaining(at: .now))
            store.saveTimer(timer)
            await activityController.update(timer: timer, settings: settings)
        }
    }

    func cancelExperienceActivity() async {
        experience.cancel(); saveExperience()
        timer = .inactive; store.saveTimer(timer)
        await activityController.endAll(finalStatus: "已結束陪伴計時")
    }

    private func saveExperience(action: PatrickCareAction? = nil) {
        let value = experience
        store.saveExperience(value)
        settings = store.updateSettings { $0.experience = value }
        watchSync.send(command: PatrickCommandPayload(name: .updateExperience, careAction: action), settings: settings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setVisualState(_ state: PatrickVisualState) {
        settings = store.updateSettings { $0.previewState = state }
        watchSync.send(
            command: PatrickCommandPayload(
                name: .setPreviewState,
                previewState: state
            ),
            settings: settings
        )
        didChangePresentation()
    }

    func setSleepMode(_ mode: PatrickSleepMode) {
        experience.settings.scene = mode == .automatic ? .automatic : mode == .on ? .sleeping : .awake
        experience.changed(); store.saveExperience(experience)
        let state = experience
        settings = store.updateSettings { $0.sleepMode = mode; $0.experience = state }
        watchSync.send(
            command: PatrickCommandPayload(
                name: .setSleepMode,
                sleepMode: mode,
                deepLink: PatrickDeepLinkRoute.setSleepMode(mode).url
            ),
            settings: settings
        )
        didChangePresentation()
    }

    func setDemoMode(_ enabled: Bool) {
        settings = store.updateSettings { $0.demoMode = enabled }
        watchSync.setDemoMode(enabled)
        notice = enabled
            ? "Demo mode is acknowledging commands locally."
            : "Demo mode is off; WatchConnectivity status is live."
        WidgetCenter.shared.reloadAllTimelines()
    }

    func playThemeSound(sendToWatch: Bool = true) {
        guard experience.settings.soundEnabled else { notice = "先在設定開啟音效"; return }
        do {
            try soundPlayer.play(for: settings.theme)
            notice = "Played the locally generated \(settings.theme.displayName) cue."
        } catch {
            notice = error.localizedDescription
        }

        if sendToWatch {
            watchSync.send(
                command: PatrickCommandPayload(
                    name: .playThemeSound,
                    theme: settings.theme,
                    deepLink: PatrickDeepLinkRoute.playThemeSound.url
                ),
                settings: settings
            )
        }
    }

    func openWatchFace(sendToWatch: Bool = true) {
        selectedTab = .control
        isPresentingWatchFace = true
        if sendToWatch {
            watchSync.send(
                command: PatrickCommandPayload(
                    name: .openWatchFace,
                    deepLink: PatrickDeepLinkRoute.openWatchFace.url
                ),
                settings: settings
            )
        }
        notice = "Requested the in-app Patrick face on the paired watch."
    }

    func startTimer(minutes: Int) async {
        let now = Date.now
        let value = PatrickTimerSnapshot(
            id: UUID(),
            status: .running,
            title: "Patrick \(minutes)-minute timer",
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
            remainingSeconds: nil
        )
        timer = value
        store.saveTimer(value)
        await activityController.start(timer: value, settings: settings)
        watchSync.send(
            command: PatrickCommandPayload(name: .startTimer, timer: value),
            settings: settings
        )
        WidgetCenter.shared.reloadAllTimelines()
        notice = "Started a \(minutes)-minute Live Activity."
        scheduleTimerCompletion(for: value)
    }

    func stopTimer(completedAutomatically: Bool = false) async {
        timerCompletionTask?.cancel()
        timerCompletionTask = nil
        let stopped = PatrickTimerSnapshot(
            id: timer.id,
            status: .complete,
            title: timer.title,
            startedAt: timer.startedAt,
            endsAt: nil,
            remainingSeconds: 0
        )
        timer = stopped
        store.saveTimer(stopped)
        await activityController.endAll(
            finalStatus: completedAutomatically ? "Timer complete" : "Timer ended"
        )
        watchSync.send(
            command: PatrickCommandPayload(name: .stopTimer, timer: stopped),
            settings: settings
        )
        WidgetCenter.shared.reloadAllTimelines()
        notice = completedAutomatically
            ? "Patrick timer completed."
            : "Ended the Patrick timer."
    }

    func syncNow() {
        watchSync.syncSnapshot(settings: settings, timer: timer)
        notice = "Sent the latest local snapshot."
    }

    func handle(url: URL) {
        guard let route = PatrickDeepLinkRoute(url: url) else {
            notice = "That Patrick link is not supported."
            return
        }

        switch route {
        case .controlCenter:
            selectedTab = .control
        case let .setTheme(theme):
            selectedTab = .control
            setTheme(theme)
        case let .setSleepMode(mode):
            selectedTab = .control
            setSleepMode(mode)
        case .playThemeSound:
            selectedTab = .control
            playThemeSound()
        case .openWatchFace:
            openWatchFace()
        case .timer:
            selectedTab = .timer
        }
    }

    func becameActive() {
        requestedCare = nil
        var storedSettings = store.loadSettings()
        if forcedDemoMode {
            storedSettings.demoMode = true
        }
        settings = storedSettings
        timer = store.loadTimer()
        experience = store.loadExperience()
        refreshExperience(observeCalendar: false)
        synchronizeActivityPresentation()
        watchSync.setDemoMode(settings.demoMode)

        consumePendingActions()
        activityController.refresh()

        if experience.activity == nil && timer.status == .running {
            if let endsAt = timer.endsAt, endsAt <= .now {
                Task {
                    await stopTimer(completedAutomatically: true)
                }
            } else {
                scheduleTimerCompletion(for: timer)
            }
        }
    }

    private func synchronizeActivityPresentation() {
        guard let value = experience.activity else { return }
        let isRunning = value.status == .running || value.status == .paused
        if !isRunning {
            timer = .inactive; store.saveTimer(timer)
            Task { await activityController.endAll(finalStatus: value.status == .completed ? "陪伴計時完成" : "已結束陪伴計時") }
            return
        }
        let previousID = timer.id
        timer = PatrickTimerSnapshot(id: value.id, status: value.status == .paused ? .paused : .running,
            title: value.kind.title, startedAt: value.startedAt, endsAt: value.endsAt,
            remainingSeconds: value.remaining(at: .now))
        store.saveTimer(timer)
        Task {
            if previousID == value.id { await activityController.update(timer: timer, settings: settings) }
            else { await activityController.start(timer: timer, settings: settings) }
        }
    }

    private func consumePendingActions() {
        for action in store.consumePendingActions() {
            switch action.kind {
            case .playThemeSound:
                playThemeSound(sendToWatch: false)
            case .openWatchFace:
                openWatchFace(sendToWatch: false)
            }
        }
    }

    func resetLocalData() {
        store.resetLocalData()
        settings = .defaults
        timer = .inactive
        experience = PatrickExperienceState()
        store.saveExperience(experience)
        watchSync.setDemoMode(false)
        timerCompletionTask?.cancel()
        timerCompletionTask = nil
        WidgetCenter.shared.reloadAllTimelines()
        notice = "Local Patrick settings were reset."
        Task {
            await activityController.endAll(
                finalStatus: "Local timer reset",
                dismissalPolicy: .immediate
            )
        }
    }

    private func acceptRemoteSettings(_ value: PatrickSettings) {
        if let incoming = value.experience, incoming.isNewer(than: experience) {
            experience = incoming; store.saveExperience(incoming)
            synchronizeActivityPresentation()
        }
        var merged = value.revision >= settings.revision ? value : settings
        merged.demoMode = settings.demoMode
        merged.experience = experience
        settings = merged
        store.saveSettings(merged)
        WidgetCenter.shared.reloadAllTimelines()
        notice = "Applied a settings update from Apple Watch."
    }

    private func acceptRemoteTimer(_ value: PatrickTimerSnapshot) {
        timer = PatrickTimerSnapshot.resolving(value, experience: experience)
        store.saveTimer(timer)
        WidgetCenter.shared.reloadAllTimelines()
        notice = "Applied a timer update from Apple Watch."
    }

    private func acceptRemoteCommand(_ command: PatrickCommandPayload) {
        switch command.name {
        case .setTheme:
            if let theme = command.theme, theme != settings.theme {
                settings = store.updateSettings { $0.theme = theme }
                didChangePresentation()
            }
        case .setSleepMode:
            if let mode = command.sleepMode, mode != settings.sleepMode {
                settings = store.updateSettings { $0.sleepMode = mode }
                didChangePresentation()
            }
        case .setPreviewState:
            if let state = command.previewState, state != settings.previewState {
                settings = store.updateSettings { $0.previewState = state }
                didChangePresentation()
            }
        case .playThemeSound:
            playThemeSound(sendToWatch: false)
        case .openWatchFace:
            openWatchFace(sendToWatch: false)
        case .startTimer, .stopTimer:
            if let timer = command.timer {
                acceptRemoteTimer(timer)
            }
        case .updateExperience:
            // Care values arrive in the snapshot; never apply a second reward.
            if let action = command.careAction { requestedCare = action; actionSequence &+= 1 }
        }
    }

    private func scheduleTimerCompletion(for snapshot: PatrickTimerSnapshot) {
        timerCompletionTask?.cancel()
        guard
            snapshot.status == .running,
            let endsAt = snapshot.endsAt
        else {
            timerCompletionTask = nil
            return
        }

        let delay = max(0, endsAt.timeIntervalSinceNow)
        timerCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard
                !Task.isCancelled,
                self?.timer.id == snapshot.id,
                self?.timer.status == .running
            else {
                return
            }
            await self?.stopTimer(completedAutomatically: true)
        }
    }

    private func didChangePresentation() {
        WidgetCenter.shared.reloadAllTimelines()
        if timer.status == .running || timer.status == .paused {
            Task {
                await activityController.update(timer: timer, settings: settings)
            }
        }
    }
}
