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
        settings = store.updateSettings { $0.sleepMode = mode }
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
        var storedSettings = store.loadSettings()
        if forcedDemoMode {
            storedSettings.demoMode = true
        }
        settings = storedSettings
        timer = store.loadTimer()
        watchSync.setDemoMode(settings.demoMode)

        consumePendingActions()
        activityController.refresh()

        if timer.status == .running {
            if let endsAt = timer.endsAt, endsAt <= .now {
                Task {
                    await stopTimer(completedAutomatically: true)
                }
            } else {
                scheduleTimerCompletion(for: timer)
            }
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
        guard value.revision >= settings.revision else { return }
        var merged = value
        merged.demoMode = settings.demoMode
        settings = merged
        store.saveSettings(merged)
        WidgetCenter.shared.reloadAllTimelines()
        notice = "Applied a settings update from Apple Watch."
    }

    private func acceptRemoteTimer(_ value: PatrickTimerSnapshot) {
        timer = value
        store.saveTimer(value)
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
