import SwiftUI
import WidgetKit
import Combine

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

    private let companion: PatrickWatchReceiver
    private static let sceneKey = "patrick.pet-scene.v1"
    private var isRestoringCompanionState = true
    private var lastComplicationReload = Date.distantPast

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
    }

    func toggleTheme() {
        setTheme(theme == .cel ? .clay : .cel)
    }

    func updateExperience(_ mutation: (inout PatrickExperienceState) -> Void) {
        mutation(&experience)
        experience.changed()
        persistExperience()
    }

    func performCare(_ action: PatrickCareAction) {
        guard experience.perform(action) else { careNotice = "稍等一下，再\(action.title)"; return }
        requestedAction = action
        activationSequence &+= 1
        careNotice = action == .feed ? "吃了一口，飽足 \(Int(experience.care.satiety.rounded()))" : "\(action.title)，親密 \(experience.care.bond)"
        persistExperience()
    }

    func refreshExperience(at date: Date = .now, allowEffects: Bool) {
        let revision = experience.revision
        _ = experience.updateCare(at: date)
        if let celebration = experience.observeCalendar(PatrickExperienceResources.calendar(), at: date, allowCelebration: allowEffects) {
            careNotice = celebration; calendarCelebrationSequence &+= 1
        }
        if experience.revision != revision { persistExperience() }
        guard let id = experience.reconcile(at: date) else { return }
        completedActivityID = allowEffects ? id.uuidString : nil
        careNotice = "完成\(experience.activity?.kind.title ?? "陪伴計時")"
        persistExperience()
    }

    private func persistExperience() {
        experience.save(to: PatrickSharedStore.defaults)
        companion.sendSnapshot(theme: theme, experience: experience)
        WidgetCenter.shared.reloadTimelines(ofKind: PatrickSharedStore.complicationKind)
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
        if let value = update.experience, value.isNewer(than: experience) {
            experience = value
            experience.save(to: PatrickSharedStore.defaults)
        }
        if let action = update.careAction {
            requestedAction = action
            activationSequence &+= 1
            careNotice = "手機已送來\(action.title)"
        }
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
        }
    }
}
