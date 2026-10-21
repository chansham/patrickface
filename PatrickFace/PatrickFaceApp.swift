import SwiftUI
import WidgetKit
import Combine
import WatchKit

@MainActor
final class PatrickAppModel: ObservableObject {
    @Published private(set) var theme: PatrickTheme
    @Published private(set) var status: PatrickFaceStatus
    @Published private(set) var sleepMode: PatrickWatchWire.SleepMode = .automatic
    @Published private(set) var previewState: PatrickWatchWire.VisualState = .normal
    @Published private(set) var activationSequence = 0
    @Published private(set) var petScene: PatrickPetScene
    @Published private(set) var companionTimer: PatrickWatchWire.TimerSnapshot? = nil
    @Published private(set) var experience = PatrickExperienceState.load(from: PatrickSharedStore.defaults)
    @Published private(set) var requestedAction: PatrickCareAction?
    @Published private(set) var soundSequence = 0
    @Published private(set) var completedActivityID: String?
    @Published private(set) var calendarCelebrationSequence = 0
    @Published private(set) var careNotice = "今天也陪著你"
    @Published private(set) var automationSequence = 0
    @Published private(set) var soundCue: PatrickSoundCue?
    @Published private(set) var soundCueUntil: Date?
    @Published var workoutZone: Int?
    private var latestReachable: Bool?
    private var latestWater: Bool?
    private var requestedAutomation: PatrickAutomationEvent?
    private var automationGate = PatrickAutomationGate(receivedIDs:
        (PatrickSharedStore.defaults.stringArray(forKey: PatrickAutomationGate.storageKey) ?? []).compactMap(UUID.init(uuidString:)))

    private let companion: PatrickWatchReceiver
    private static let sceneKey = "patrick.pet-scene.v1"
    private var isRestoringCompanionState = true
    private var lastComplicationReload = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init(companion: PatrickWatchReceiver = .shared) {
        let state = PatrickSharedStore.load()
        theme = state.theme
        // Runtime device state is re-established by PatrickFaceView. Starting
        // from ready guarantees a stale non-ready status is cleared on launch.
        status = .ready
        petScene = UserDefaults.standard.string(forKey: Self.sceneKey)
            .flatMap(PatrickPetScene.init(rawValue:)) ?? .automatic
        self.companion = companion

        companion.activate(
            currentTheme: { [weak self] in
                self?.theme ?? state.theme
            },
            onControlApplied: { [weak self] update in
                self?.apply(update)
            },
            onOpenFace: { [weak self] in
                self?.activateFromCompanion()
            }
        )
        isRestoringCompanionState = false
        companion.$latestTimer.assign(to: &$companionTimer)
        NotificationCenter.default.publisher(for: .patrickWatchSpokenIntent)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadSpokenIntent() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .patrickRideChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.noteRide(note.userInfo?["riding"] as? Bool ?? false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .patrickWaterChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.noteWater(note.userInfo?["submerged"] as? Bool ?? false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .patrickSoundCue)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.noteSound(note) }
            .store(in: &cancellables)
        companion.onReachability = { [weak self] reachable in
            Task { @MainActor in
                self?.latestReachable = reachable
                self?.refreshWeek()
            }
        }
        PatrickWorkoutCompanion.shared.onZone = { [weak self] zone in
            Task { @MainActor in self?.workoutZone = zone }
        }
        PatrickWorkoutCompanion.shared.onKilometer = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let foreground = WKExtension.shared().applicationState == .active
                _ = PatrickHaptics.shared.play(.celebrate, settings: self.experience.settings, foreground: foreground, inWorkout: true)
            }
        }
        PatrickWeekSensors.shared.start()
    }

    private func reloadSpokenIntent() {
        let stored = PatrickExperienceState.load(from: PatrickSharedStore.defaults)
        guard stored != experience else { syncCountdownAlerts(); return }
        experience = stored
        persistExperience()
    }

    private func syncCountdownAlerts() {
        let legacy: PatrickCountdownLegacy?
        if experience.activity == nil, let timer = companionTimer, timer.status == .running {
            legacy = PatrickCountdownLegacy(id: timer.id, running: true, endsAt: timer.endsAt, title: timer.title)
        } else {
            legacy = nil
        }
        let activity = experience.activity
        let session = experience.breakSession
        let settings = experience.settings
        let worn = WKExtension.shared().applicationState == .active
        let quiet = experience.contextSnapshot().suppressesProactive
        let role: PatrickWakeRole = worn ? .watch : .none
        Task {
            await PatrickCountdownNotifier.shared.sync(activity: activity, breakSession: session, legacy: legacy, settings: settings, schedules: worn, contextQuiet: quiet)
            let cues = PatrickDayPlan.wakeCues(settings: settings, napEndsAt: activity?.nap == true && activity?.status == .running ? activity?.endsAt : nil, role: role, now: .now)
            await PatrickWakeNotifier.shared.sync(cues: cues)
            PatrickWakeNotifier.shared.playDue(cues, settings: settings, foreground: worn)
            if let next = cues.map(\.fireAt).min() { PatrickWakeSession.shared.arm(at: next) }
            else { PatrickWakeSession.shared.disarm() }
        }
    }

    func startNap(minutes: Int = 25) {
        let text = PatrickSpokenActions.startNap(&experience, minutes: minutes)
        persistExperience()
        careNotice = text
    }

    func refreshOvernight() async {
        let series = await PatrickOvernightReader.load()
        let sentence = PatrickDayPlan.morningSentence(series)
        var next = experience.settings
        let before = next
        PatrickDayPlan.storeMorning(settings: &next, sentence: sentence, now: .now, calendar: PatrickHKHolidays.calendar)
        let night = await PatrickOvernightReader.lastNight()
        let end = Date()
        let tosses = PatrickWeekSensors.shared.tossCount(from: end.addingTimeInterval(-12 * 60 * 60), to: end)
        PatrickNightTheater.store(settings: &next, script: PatrickNightTheater.script(quietMinutes: night.quietMinutes, tosses: tosses, wakes: night.wakes), now: end)
        if let arrived = next.arrivedHomeAtMS {
            let washed = await PatrickOvernightReader.latestHandwash(since: Date(timeIntervalSince1970: arrived / 1000))
            PatrickDayPlan.noteWash(settings: &next, washedAt: washed)
        }
        if next != before {
            experience.settings = next
            experience.changed()
            persistExperience()
        }
        refreshWeek()
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
        persistExperience()
        Task { await self.commitMind(raw) }
    }

    private func noteRide(_ riding: Bool) {
        let next: Bool? = riding ? true : nil
        guard experience.settings.contextCommute != next else { return }
        experience.settings.contextCommute = next
        experience.changed()
        persistExperience()
        refreshWeek()
    }

    private func noteWater(_ submerged: Bool) {
        latestWater = submerged
        refreshWeek()
    }

    private func refreshWeek() {
        let now = Date()
        let calendar = PatrickHKHolidays.calendar
        let origin = experience
        let device = WKInterfaceDevice.current()
        let level = device.batteryLevel
        let battery = level >= 0 ? Double(level) : nil
        var settings = experience.settings
        let folded = PatrickWeekPlan.fold(
            settings: &settings, line: settings.dayLine, hello: nil, knocks: 0,
            gate: experience.contextSnapshot(at: now, calendar: calendar), events: [],
            journalLines: experience.lifeJournal.map(\.text), battery: battery,
            modelEvening: nil, modelWeekly: nil, phoneReachable: latestReachable,
            waterSubmerged: latestWater, writesJournal: false, now: now, calendar: calendar)
        experience.settings = settings
        for line in folded.journal { experience.record(line, at: now) }
        let gate = origin.contextSnapshot(at: now, calendar: calendar)
        if experience != origin {
            experience.changed(at: now)
            persistExperience()
        }
        let foreground = WKExtension.shared().applicationState == .active
        if folded.phoneLeftPulses > 0 {
            PatrickHaptics.shared.playRepeated(.timerClosing, count: folded.phoneLeftPulses, settings: experience.settings, foreground: foreground, context: gate)
        } else if folded.knocks > 0 {
            _ = PatrickHaptics.shared.play(.knock, settings: experience.settings, foreground: foreground, context: gate)
        }
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

    /// One knock, and only when the glass pattern cleared the budget and the gate.
    /// A tickle never calls this.
    func playGlassKnock(at date: Date = .now) {
        let calendar = PatrickHKHolidays.calendar
        let context = experience.contextSnapshot(at: date, calendar: calendar)
        guard experience.registerProactiveHaptic(at: date, calendar: calendar) else { return }
        persistExperience()
        let foreground = WKExtension.shared().applicationState == .active
        _ = PatrickHaptics.shared.play(.knock, settings: experience.settings, foreground: foreground, context: context, at: date)
    }

    func markHandwash() {
        let now = Date()
        experience.settings.lastHandwashAtMS = (now.timeIntervalSince1970 * 1000).rounded()
        experience.settings.handwashUntilMS = ((now.timeIntervalSince1970 + 20) * 1000).rounded()
        experience.settings.dayLine = "洗手 20 秒，我等你。"
        experience.record("洗手", at: now)
        experience.changed(at: now)
        persistExperience()
    }

    func toggleTheme() {
        setTheme(theme == .cel ? .clay : .cel)
    }

    func updateExperience(_ mutation: (inout PatrickExperienceState) -> Void) {
        mutation(&experience)
        experience.changed()
        persistExperience()
        refreshWeek()
    }

    func controlActivity(_ command: PatrickActivityControl) {
        let wasExercise = experience.activity?.kind.isExercise == true
        let revision = experience.revision
        let result = experience.controlActivity(command)
        if wasExercise, experience.activity?.status != .running {
            workoutZone = nil
            Task { await PatrickWorkoutCompanion.shared.end() }
        }
        if experience.revision != revision { persistExperience() }
        careNotice = result.message
    }

    private var lastFocusCheck: Date?
    private func refreshFocusFilter() async {
        if let lastFocusCheck, Date().timeIntervalSince(lastFocusCheck) < 60 { return }
        lastFocusCheck = Date()
        let focus = await PatrickFocusFilterIntent.refreshStoredFlag()
        guard experience.settings.contextFocus != focus else { return }
        experience.settings.contextFocus = focus
        experience.changed()
        persistExperience()
    }

    private func commitMind(_ raw: String) async {
        guard experience.settings.pendingMindRaw == raw else { return }
        let wrote = await PatrickMoodRecord.shared.write(raw: raw)
        guard wrote, experience.settings.pendingMindRaw == raw else { return }
        experience.settings.pendingMindRaw = nil
        experience.changed()
        persistExperience()
    }

    @discardableResult
    func startActivity(_ kind: PatrickActivityKind, minutes: Int) -> Bool {
        let revision = experience.revision
        let result = experience.requestActivityStart(kind, minutes: minutes)
        if experience.revision != revision { persistExperience() }
        careNotice = result.message
        if case .started(let activity, _) = result {
            Task { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
            if activity.kind.isExercise {
                Task { await PatrickWorkoutCompanion.shared.begin(activity.kind) }
            }
            return true
        }
        return false
    }

    func manageBreak(_ command: PatrickBreakCommand) {
        let revision = experience.revision
        let result = experience.manageBreak(command)
        if experience.revision != revision { persistExperience() }
        careNotice = result.message
        if case .started = result {
            Task { await PatrickCountdownNotifier.shared.requestPermissionForNewCountdown() }
        }
    }

    func nudgeCountdown(by minutes: Int) {
        guard experience.nudgeCountdown(by: minutes) else { return }
        persistExperience()
    }

    func performCare(_ action: PatrickCareAction, allowEffects: Bool = true) {
        guard experience.perform(action) else {
            careNotice = action == .feed ? "餵食已經收起來了。" : "我在。"
            return
        }
        requestedAction = allowEffects && action == .pet ? action : nil
        if allowEffects && action != .feed { activationSequence &+= 1 }
        careNotice = action == .rest ? "一起休息。" : "摸了摸。"
        persistExperience()
    }

    func setAutomationPresentationActive(_ active: Bool, at date: Date = .now) {
        automationGate.setPresentationActive(active, at: date)
        if !active { requestedAutomation = nil }
    }

    func reportWakeUp(allowEffects: Bool = true) {
        let event = PatrickAutomationEvent(kind: .wakeUp, source: .manual)
        guard experience.recordAutomation(event) else { return }
        persistExperience(automationEvent: event)
        if !allowEffects { setAutomationPresentationActive(false) }
        receiveAutomation(event)
    }

    private func receiveAutomation(_ event: PatrickAutomationEvent) {
        if WKExtension.shared().applicationState != .active { setAutomationPresentationActive(false) }
        let result = automationGate.consume(event)
        PatrickSharedStore.defaults.set(automationGate.receivedIDs.map(\.uuidString), forKey: PatrickAutomationGate.storageKey)
        guard result != .duplicate && result != .invalid else { return }
        careNotice = event.journalText
        if result == .play { requestedAutomation = event; automationSequence &+= 1 }
    }

    func takeAutomationForPlayback() -> PatrickAutomationEvent? {
        defer { requestedAutomation = nil }
        guard let event = requestedAutomation, WKExtension.shared().applicationState == .active,
              automationGate.allowsPlayback(event) else { return nil }
        return event
    }

    @discardableResult
    func findSurprise() -> Bool {
        guard let line = experience.findSurprise() else { careNotice = "小驚喜歇一分鐘，再來看看"; return false }
        careNotice = line
        persistExperience()
        return true
    }

    func refreshExperience(at date: Date = .now, allowEffects: Bool, observeCalendar: Bool = true, announceCompletion: Bool = false) {
        if !allowEffects { completedActivityID = nil }
        if experience.settings.contextNap == true, experience.activity?.nap != true || experience.activity?.status != .running {
            experience.settings.contextNap = nil
            experience.changed(at: date)
        }
        let revision = experience.revision
        _ = experience.updateCare(at: date)
        _ = experience.syncDisplayedMood(at: date)
        Task { await self.refreshFocusFilter() }
        if observeCalendar, let celebration = experience.observeCalendar(PatrickExperienceResources.calendar(), at: date, allowCelebration: allowEffects) {
            careNotice = celebration; calendarCelebrationSequence &+= 1
        }
        if experience.revision != revision { persistExperience() }
        guard let id = experience.reconcile(at: date) else { return }
        if experience.activity?.kind.isExercise == true {
            workoutZone = nil
            Task { await PatrickWorkoutCompanion.shared.end() }
        }
        completedActivityID = allowEffects ? id.uuidString : nil
        careNotice = "完成\(experience.activity?.kind.title ?? "陪伴計時")"
        persistExperience()
        if announceCompletion {
            let rest = experience.breakSession?.breakActivityID == id
            PatrickHaptics.shared.play(rest ? .restDone : .timerDone, settings: experience.settings, foreground: true, at: date)
        }
    }

    private func persistExperience(automationEvent: PatrickAutomationEvent? = nil) {
        experience.save(to: PatrickSharedStore.defaults)
        companion.sendSnapshot(theme: theme, experience: experience, automationEvent: automationEvent)
        WidgetCenter.shared.reloadTimelines(ofKind: PatrickSharedStore.complicationKind)
        syncCountdownAlerts()
        let workingOut = experience.activity?.status == .running && experience.activity?.kind.isExercise == true
        let donated = experience.settings
        if #available(watchOS 11.0, *) {
            Task { await PatrickStackDonation.refresh(settings: donated, workingOut: workingOut) }
        }
    }

    func setPetScene(_ scene: PatrickPetScene) {
        petScene = scene
        UserDefaults.standard.set(scene.rawValue, forKey: Self.sceneKey)
    }

    func setTheme(_ newTheme: PatrickTheme) {
        guard newTheme != theme else { return }
        theme = newTheme
        persist(theme: newTheme)
        companion.sendSnapshot(theme: newTheme)
    }

    func setStatus(_ newStatus: PatrickFaceStatus) {
        if newStatus != status {
            status = newStatus
        }
        persist(status: newStatus)
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let deepLink = PatrickDeepLink.parse(url) else { return false }
        if let requestedTheme = deepLink.theme {
            setTheme(requestedTheme)
        }
        requestedAction = nil
        activationSequence &+= 1
        return true
    }

    private func activateFromCompanion() {
        careNotice = "手機已傳來開啟請求，抬腕開App就能陪伴"
    }

    private func apply(_ update: PatrickWatchReceiver.AppliedState) {
        let previousExperience = experience
        if let value = update.experience, value.isNewer(than: experience) {
            experience = value
            experience.save(to: PatrickSharedStore.defaults)
        }
        if let action = update.careAction {
            requestedAction = action
            activationSequence &+= 1
            careNotice = "手機已送來\(action.title)"
        }
        if let event = update.automationEvent { receiveAutomation(event) }
        if update.playSound { soundSequence &+= 1 }
        if let theme = update.theme, theme != self.theme {
            self.theme = theme
            persist(theme: theme)
        }
        if let sleepMode = update.sleepMode {
            // An explicit phone change regains control; keep the v1 wire intact.
            if !isRestoringCompanionState {
                setPetScene(.automatic)
            }
            if update.experience == nil && self.sleepMode != sleepMode {
                experience.settings.scene = sleepMode == .automatic ? .automatic : sleepMode == .on ? .sleeping : .awake
                experience.changed(); experience.save(to: PatrickSharedStore.defaults)
            }
            self.sleepMode = sleepMode
        }
        if let previewState = update.previewState {
            if !isRestoringCompanionState {
                setPetScene(.automatic)
            }
            self.previewState = previewState
        }
        if experience != previousExperience {
            WidgetCenter.shared.reloadTimelines(ofKind: PatrickSharedStore.complicationKind)
            syncCountdownAlerts()
            if let raw = experience.settings.pendingMindRaw {
                Task { await self.commitMind(raw) }
            }
        }
    }

    private func persist(
        theme: PatrickTheme? = nil,
        status: PatrickFaceStatus? = nil
    ) {
        let previous = PatrickSharedStore.load()
        let valuesChanged = (theme != nil && theme != previous.theme)
            || (status != nil && status != previous.status)
        guard PatrickSharedStore.save(theme: theme, status: status) else { return }
        // Heartbeats keep local status fresh without requesting a widget reload
        // every minute. A visible app refreshes its timeline at most each 15 min.
        guard valuesChanged || Date.now.timeIntervalSince(lastComplicationReload) >= 15 * 60 else {
            return
        }
        lastComplicationReload = .now
        WidgetCenter.shared.reloadTimelines(
            ofKind: PatrickSharedStore.complicationKind
        )
    }
}

@main
struct PatrickFaceApp: App {
    @StateObject private var model = PatrickAppModel()

    var body: some Scene {
        WindowGroup {
            PatrickAnimatedFaceView()
                .environmentObject(model)
                .onOpenURL { url in
                    _ = model.handle(url)
                }
                .task { PatrickWatchShortcuts.updateAppShortcutParameters() }
        }
    }
}
