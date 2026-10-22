import Combine
import Foundation
import WidgetKit
import UIKit

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable {
        case control
        case timer
        case routines
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
    @Published private(set) var soundCue: PatrickSoundCue?
    @Published private(set) var soundCueUntil: Date?
    @Published private(set) var stickerNotice: String?
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
    private var companionEvents: [PatrickCalendarInterval] = []
    private var companionSitting: Int?
    private var didNoteFieldTestAlarm = false

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
        NotificationCenter.default.publisher(for: .patrickWatchWornChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.syncCountdownAlerts() }
            }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: .patrickAutomationReceived)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.object as? PatrickAutomationEvent else { return }
                self?.settings = store.loadSettings()
                self?.experience = store.loadExperience()
                self?.receiveAutomation(event)
            }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: .patrickSoundCue)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.noteSound(note) }
            .store(in: &cancellables)

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

    var soundOutfitID: String? {
        guard experience.settings.outfitID == "auto",
              let cue = soundCue, let until = soundCueUntil, until > Date() else { return nil }
        return cue.outfitID
    }

    var activeSoundLine: String? {
        guard let cue = soundCue, let until = soundCueUntil, until > Date() else { return nil }
        return cue.line
    }

    func clearExpiredSound(at date: Date = .now) {
        guard let until = soundCueUntil, until.timeIntervalSince(date) <= 0.05 else { return }
        soundCue = nil
        soundCueUntil = nil
    }

    private func noteSound(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info["kind"] as? String,
              let kind = PatrickSoundKind(rawValue: raw),
              let outfitID = info["outfit"] as? String,
              let line = info["line"] as? String else { return }
        let seconds = (info["seconds"] as? Double) ?? (info["seconds"] as? NSNumber)?.doubleValue ?? 20
        soundCue = PatrickSoundCue(kind: kind, outfitID: outfitID, line: line, seconds: seconds)
        soundCueUntil = Date().addingTimeInterval(seconds)
    }

    /// 「出门」 uses the existing leaving sentence. 「晚安」 uses the existing good-night path.
    func playHook(_ phrase: PatrickButlerPhrase) async {
        let text: String
        switch phrase {
        case .goodNight:
            text = PatrickSpokenIntentBridge.goodNight()
        case .leaving:
            let name = store.loadExperience().settings.greetingDisplayName
            let modelText = await PatrickButlerModel.reply(to: .leaving, name: name)
            text = PatrickSpokenIntentBridge.butler(.leaving, modelText: modelText)
        default:
            return
        }
        settings = store.loadSettings()
        experience = store.loadExperience()
        stickerNotice = text
        notice = text
    }

    func scanSticker() {
        PatrickNFCReader.shared.onPhrase = { [weak self] phrase in
            Task { @MainActor in await self?.playHook(phrase) }
        }
        PatrickNFCReader.shared.onUnavailable = { [weak self] in
            Task { @MainActor in
                self?.stickerNotice = PatrickNFCHook.unavailableLine
                self?.notice = PatrickNFCHook.unavailableLine
            }
        }
        if !PatrickNFCReader.shared.scanIfAvailable() {
            stickerNotice = PatrickNFCHook.unavailableLine
            notice = PatrickNFCHook.unavailableLine
        }
    }

    func performCare(_ action: PatrickCareAction) {
        guard action != .feed else { notice = "餵食已經收起來了。"; return }
        guard experience.perform(action) else { notice = "我在。"; return }
        if action == .pet { requestedCare = action; actionSequence &+= 1 }
        saveExperience(action: action == .pet ? action : nil)
        notice = action == .rest ? "一起休息。" : "摸了摸。"
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

    func refreshExperience(allowEffects: Bool = false, observeCalendar: Bool = true, announceCompletion: Bool = false) {
        if !allowEffects { completedActivityID = nil }
        let revision = experience.revision
        _ = experience.updateCare()
        _ = experience.syncDisplayedMood()
        if observeCalendar, let celebration = experience.observeCalendar(PatrickExperienceResources.calendar(), allowCelebration: allowEffects) {
            notice = celebration; calendarCelebrationSequence &+= 1
        }
        if experience.revision != revision { saveExperience() }
        if let id = experience.reconcile() {
            completedActivityID = allowEffects ? id.uuidString : nil
            saveExperience(); notice = "陪伴計時完成"
            synchronizeActivityPresentation()
            if announceCompletion {
                let rest = experience.breakSession?.breakActivityID == id
                PatrickHaptics.shared.play(rest ? .restDone : .timerDone, settings: experience.settings, foreground: true)
            }
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
        if case .started = result {
            Task { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
        }
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
            if case .started = result {
                Task { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
            }
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
        syncCountdownAlerts()
    }

    private func syncCountdownAlerts() {
        let legacy: PatrickCountdownLegacy? = experience.activity == nil && timer.status == .running
            ? PatrickCountdownLegacy(id: timer.id, running: true, endsAt: timer.endsAt, title: timer.title)
            : nil
        let activity = experience.activity
        let breakSession = experience.breakSession
        let settings = experience.settings
        let schedules = watchSync.alertOwner() == .phone
        let quiet = experience.contextSnapshot().suppressesProactive
        let role: PatrickWakeRole = schedules ? .phone : .none
        Task {
            await PatrickCountdownNotifier.shared.sync(activity: activity, breakSession: breakSession, legacy: legacy, settings: settings, schedules: schedules, contextQuiet: quiet)
            let cues = PatrickDayPlan.wakeCues(settings: settings, napEndsAt: activity?.nap == true && activity?.status == .running ? activity?.endsAt : nil, role: role, now: .now)
            await PatrickWakeNotifier.shared.sync(cues: cues)
            PatrickWakeNotifier.shared.playDue(cues, settings: settings, foreground: schedules)
        }
    }

    func refreshCompanionDay() {
        let since = experience.settings.stationarySinceMS
        PatrickHomeMonitor.shared.onArrive = { [weak self] date in
            Task { @MainActor in self?.noteArrival(at: date) }
        }
        PatrickHomeMonitor.shared.onLeave = { [weak self] date in
            Task { @MainActor in self?.noteDeparture(at: date) }
        }
        PatrickHomeMonitor.shared.update(latitude: experience.settings.homeLatitude, longitude: experience.settings.homeLongitude)
        PatrickContextSensors.shared.refreshCompanion(stationarySinceMS: since) { [weak self] day in
            self?.applyCompanion(day)
        }
        let fetchedAt = experience.settings.observatoryAtMS ?? 0
        if Date().timeIntervalSince1970 * 1000 - fetchedAt > 30 * 60 * 1000 {
            Task { [weak self] in
                guard let reading = await PatrickObservatoryClient.fetch() else { return }
                await MainActor.run { self?.applyObservatory(reading) }
            }
        }
    }

    func markHandwash() {
        let now = Date()
        experience.settings.lastHandwashAtMS = (now.timeIntervalSince1970 * 1000).rounded()
        experience.settings.handwashUntilMS = ((now.timeIntervalSince1970 + 20) * 1000).rounded()
        experience.settings.dayLine = "洗手 20 秒，我等你。"
        experience.record("洗手", at: now)
        experience.changed(at: now)
        saveExperience()
    }

    private func noteArrival(at date: Date) {
        experience.settings.arrivedHomeAtMS = (date.timeIntervalSince1970 * 1000).rounded()
        experience.settings.handwashAskedMS = nil
        experience.settings.phoneAtHome = true
        experience.record("回來了", at: date)
        experience.changed(at: date)
        saveExperience()
        refreshCompanionDay()
    }

    private func noteDeparture(at date: Date) {
        experience.settings.phoneAtHome = false
        experience.record("離開家", at: date)
        experience.changed(at: date)
        saveExperience()
    }

    func recordMood(stars: Int) {
        guard let raw = PatrickMoodStars.raw(stars: stars) else { return }
        let now = Date()
        let line = PatrickMoodStars.company(stars: stars)
        experience.settings.moodStars = stars
        experience.settings.pendingMindRaw = raw
        experience.settings.dayLine = line
        experience.record(line, at: now)
        experience.changed(at: now)
        saveExperience()
    }

    private func applyObservatory(_ reading: PatrickObservatoryReading) {
        let origin = experience
        experience.settings.observatoryTemperature = reading.temperatureC
        experience.settings.observatoryRainMM = reading.rainfallMM
        experience.settings.observatoryWarnings = reading.warningCodes.joined(separator: ",")
        experience.settings.observatoryAtMS = (Date().timeIntervalSince1970 * 1000).rounded()
        Task { await self.finishDay(events: self.companionEvents, sitting: self.companionSitting, origin: origin) }
    }

    private func applyCompanion(_ day: PatrickContextSensors.CompanionDay) {
        let origin = experience
        experience.settings.contextMeeting = day.meeting
        experience.settings.contextCommute = day.commute
        experience.settings.contextFocus = day.focus
        experience.settings.stationarySinceMS = day.stationarySinceMS
        companionEvents = day.events
        companionSitting = day.sittingMinutes
        Task { await self.finishDay(events: day.events, sitting: day.sittingMinutes, origin: origin) }
    }

    private func finishDay(events: [PatrickCalendarInterval], sitting: Int?, origin: PatrickExperienceState) async {
        let calendar = PatrickHKHolidays.calendar
        let now = Date()
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        var modelEvening: String?
        var modelWeekly: String?
        if experience.settings.eveningNoteDay != day,
           let fireAt = PatrickJournalVoice.eveningFireDate(now: now, calendar: calendar),
           !experience.settings.isSleepTime(fireAt, calendar: calendar) {
            modelEvening = await PatrickJournalModel.evening(events: events.map(\.title))
        }
        if PatrickJournalVoice.isSunday(now, calendar: calendar), experience.settings.weeklyPageDay != day {
            modelWeekly = await PatrickJournalModel.weekly(lines: experience.lifeJournal.map(\.text))
        }
        applyDay(events: events, sitting: sitting, origin: origin, journalLines: experience.lifeJournal.map(\.text),
                 modelEvening: modelEvening, modelWeekly: modelWeekly)
    }

    private func applyDay(events: [PatrickCalendarInterval], sitting: Int?, origin: PatrickExperienceState,
                          journalLines: [String] = [], modelEvening: String? = nil, modelWeekly: String? = nil) {
        let now = Date()
        let calendar = PatrickHKHolidays.calendar
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let battery = level >= 0 ? Double(level) : nil
        let role: PatrickWakeRole = watchSync.alertOwner() == .phone ? .phone : .none
        let gate = origin.contextSnapshot(at: now, calendar: calendar)
        let advance = PatrickDayPlan.advance(settings: &experience.settings, activity: experience.activity, events: events,
                                             sittingMinutes: sitting, battery: battery, role: role, now: now, calendar: calendar,
                                             journalLines: journalLines, modelEvening: modelEvening, modelWeekly: modelWeekly)
        for line in advance.journal { experience.record(line, at: now) }
        if experience != origin {
            experience.changed()
            saveExperience()
        }
        if advance.phoneLeftPulses > 0 {
            PatrickHaptics.shared.playRepeated(.timerClosing, count: advance.phoneLeftPulses, settings: experience.settings, foreground: true, context: gate)
        } else if advance.knocks > 0 {
            _ = PatrickHaptics.shared.play(.knock, settings: experience.settings, foreground: true, context: gate)
        }
        if let body = advance.eveningNotice, let fireAt = advance.eveningFireAt {
            Task { await PatrickEveningNotifier.shared.sync(body: body, fireAt: fireAt, calendar: calendar) }
        }
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
        syncCountdownAlerts()
        Task { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
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
        syncCountdownAlerts()
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
        if !didNoteFieldTestAlarm {
            didNoteFieldTestAlarm = true
            PatrickFieldTestAlarm.noteLaunch()
        }
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
        syncCountdownAlerts()
        refreshCompanionDay()
        PatrickContextSensors.shared.refresh { [weak self] meeting, commute, focus in
            self?.noteContext(meeting: meeting, commute: commute, focus: focus)
        }
    }

    private func noteContext(meeting: Bool, commute: Bool, focus: Bool) {
        guard experience.settings.contextMeeting != meeting
                || experience.settings.contextCommute != commute
                || experience.settings.contextFocus != focus else { return }
        experience.settings.contextMeeting = meeting
        experience.settings.contextCommute = commute
        experience.settings.contextFocus = focus
        experience.changed()
        saveExperience()
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
        PatrickRoutineStore.shared.clear()
        watchSync.clearWatchStatus()
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
        syncCountdownAlerts()
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
        syncCountdownAlerts()
    }

    private func acceptRemoteTimer(_ value: PatrickTimerSnapshot) {
        timer = PatrickTimerSnapshot.resolving(value, experience: experience)
        store.saveTimer(timer)
        WidgetCenter.shared.reloadAllTimelines()
        notice = "Applied a timer update from Apple Watch."
        syncCountdownAlerts()
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
