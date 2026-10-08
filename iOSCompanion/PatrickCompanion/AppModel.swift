import Combine
import Foundation
import WidgetKit
import UIKit

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
    @Published private(set) var automationSequence = 0
    private var requestedAutomation: PatrickAutomationEvent?
    private var automationGate: PatrickAutomationGate

    let watchSync: WatchSyncService
    let activityController: PatrickActivityController

    private let store: PatrickSharedStore
    private let soundPlayer = ThemeSoundPlayer()
    private var soundPresentationActive = false
    private var lastQuietSoundAt = Date.now
    private let forcedDemoMode: Bool
    private var cancellables = Set<AnyCancellable>()
    private var timerCompletionTask: Task<Void, Never>?
    private var activityPresentationTask: Task<Void, Never>?
    private var activityPresentationGeneration: UInt64 = 0

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
        self.automationGate = PatrickAutomationGate(receivedIDs: store.loadAutomationReceiptIDs())
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

        NotificationCenter.default.publisher(for: .patrickAutomationReceived)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.object as? PatrickAutomationEvent else { return }
                self?.settings = store.loadSettings()
                self?.experience = store.loadExperience()
                self?.receiveAutomation(event)
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

    func setAutomationPresentationActive(_ active: Bool) {
        automationGate.setPresentationActive(active)
        if !active { requestedAutomation = nil }
    }

    func reportWakeUp() {
        let event = PatrickAutomationEvent(kind: .wakeUp, source: .manual)
        guard experience.recordAutomation(event) else { return }
        saveExperience(automationEvent: event)
        receiveAutomation(event)
    }

    private func receiveAutomation(_ event: PatrickAutomationEvent) {
        if UIApplication.shared.applicationState != .active { setAutomationPresentationActive(false) }
        let result = automationGate.consume(event)
        store.saveAutomationReceiptIDs(automationGate.receivedIDs)
        guard result != .duplicate && result != .invalid else { return }
        notice = event.journalText
        if result == .play { requestedAutomation = event; automationSequence &+= 1 }
    }

    func takeAutomationForPlayback() -> PatrickAutomationEvent? {
        defer { requestedAutomation = nil }
        guard let event = requestedAutomation, UIApplication.shared.applicationState == .active,
              automationGate.allowsPlayback(event) else { return nil }
        return event
    }

    @discardableResult
    func findSurprise() -> Bool {
        guard let line = experience.findSurprise() else { notice = "小驚喜歇一分鐘，再來看看"; return false }
        notice = line
        saveExperience()
        return true
    }

    func refreshExperience(allowEffects: Bool = false, observeCalendar: Bool = true) {
        if !allowEffects { completedActivityID = nil }
        let revision = experience.revision
        _ = experience.updateCare()
        if observeCalendar, let celebration = experience.observeCalendar(PatrickExperienceResources.calendar(), allowCelebration: allowEffects) {
            notice = celebration; calendarCelebrationSequence &+= 1
        }
        if experience.revision != revision { saveExperience() }
        if let id = experience.reconcile() {
            completedActivityID = allowEffects ? id.uuidString : nil
            saveExperience(); notice = "陪伴計時完成"
            synchronizeActivityPresentation()
        }
    }

    func startExperienceActivity(_ kind: PatrickActivityKind, minutes: Int) async {
        let revision = experience.revision
        let result = experience.requestActivityStart(kind, minutes: minutes)
        notice = result.message
        guard experience.revision != revision else { return }
        timerCompletionTask?.cancel(); timerCompletionTask = nil
        saveExperience()
        synchronizeActivityPresentation()
    }

    func toggleExperiencePause() async {
        let revision = experience.revision
        let result = experience.controlActivity(experience.activity?.status == .paused ? .resume : .pause)
        if experience.revision != revision { saveExperience() }
        synchronizeActivityPresentation()
        notice = result.message
    }

    func manageBreak(_ command: PatrickBreakCommand) {
        let revision = experience.revision
        let result = experience.manageBreak(command)
        if experience.revision != revision {
            timerCompletionTask?.cancel(); timerCompletionTask = nil
            saveExperience(); synchronizeActivityPresentation()
        }
        notice = result.message
    }

    func cancelExperienceActivity() async {
        let revision = experience.revision
        let result = experience.controlActivity(.cancel)
        if experience.revision != revision { saveExperience() }
        synchronizeActivityPresentation()
        notice = result.message
    }

    private func saveExperience(action: PatrickCareAction? = nil, automationEvent: PatrickAutomationEvent? = nil) {
        let value = experience
        store.saveExperience(value)
        settings = store.updateSettings { $0.experience = value }
        watchSync.send(command: PatrickCommandPayload(name: .updateExperience, careAction: action, automationEvent: automationEvent), settings: settings)
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

    func setSoundPresentationActive(_ active: Bool) {
        soundPresentationActive = active
        if !active { lastQuietSoundAt = .now; soundPlayer.stop() }
    }

    func playThemeSound(sendToWatch: Bool = true, manual: Bool = false, requestedAt: Date? = nil) {
        if let requestedAt, requestedAt < lastQuietSoundAt { return }
        guard PatrickImmediateSoundPolicy.allows(active: UIApplication.shared.applicationState == .active,
            presentationActive: manual || soundPresentationActive, enabled: experience.settings.soundEnabled,
            reduceMotion: UIAccessibility.isReduceMotionEnabled, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            requestedAt: requestedAt) else { return }
        do {
            guard try soundPlayer.play(for: settings.theme, allowEffects: true) else { return }
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
        let snapshot = isRunning ? PatrickTimerSnapshot(id: value.id, status: value.status == .paused ? .paused : .running,
            title: value.kind.title, startedAt: value.startedAt, endsAt: value.endsAt,
            remainingSeconds: value.remaining(at: .now)) : .inactive
        timer = snapshot; store.saveTimer(snapshot)
        let snapshotSettings = settings
        let preceding = activityPresentationTask
        activityPresentationGeneration &+= 1
        let generation = activityPresentationGeneration
        // ActivityKit awaits can interleave. Finish an in-flight presentation
        // before applying the latest immutable state; skip superseded work.
        activityPresentationTask = Task { [weak self] in
            await preceding?.value
            guard let self, generation == self.activityPresentationGeneration else { return }
            if isRunning { await self.activityController.present(timer: snapshot, settings: snapshotSettings) }
            else { await self.activityController.endAll(finalStatus: value.status == .completed ? "陪伴計時完成" : "已結束陪伴計時") }
        }
    }

    private func consumePendingActions() {
        for action in store.consumePendingActions() {
            switch action.kind {
            case .playThemeSound:
                playThemeSound(sendToWatch: false, requestedAt: action.effectiveCreatedAt)
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
        requestedAutomation = nil
        automationGate = PatrickAutomationGate()
        store.saveExperience(experience)
        watchSync.setDemoMode(false)
        timerCompletionTask?.cancel()
        timerCompletionTask = nil
        WidgetCenter.shared.reloadAllTimelines()
        notice = "Local Patrick settings were reset."
        let preceding = activityPresentationTask
        activityPresentationGeneration &+= 1
        let generation = activityPresentationGeneration
        activityPresentationTask = Task { [weak self] in
            await preceding?.value
            guard let self, generation == self.activityPresentationGeneration else { return }
            await self.activityController.endAll(
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
            if let event = command.automationEvent { receiveAutomation(event) }
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
        if experience.activity != nil { synchronizeActivityPresentation(); return }
        if timer.status == .running || timer.status == .paused {
            Task {
                await activityController.update(timer: timer, settings: settings)
            }
        }
    }
}
