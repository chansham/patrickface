import SwiftUI
import WidgetKit

@MainActor
final class PatrickAppModel: ObservableObject {
    @Published private(set) var theme: PatrickTheme
    @Published private(set) var status: PatrickFaceStatus
    @Published private(set) var sleepMode: PatrickWatchWire.SleepMode = .automatic
    @Published private(set) var previewState: PatrickWatchWire.VisualState = .normal
    @Published private(set) var activationSequence = 0

    private let companion: PatrickWatchReceiver

    init(companion: PatrickWatchReceiver = .shared) {
        let state = PatrickSharedStore.load()
        theme = state.theme
        // Runtime device state is re-established by PatrickFaceView. Starting
        // from ready guarantees a stale non-ready status is cleared on launch.
        status = .ready
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
    }

    func toggleTheme() {
        setTheme(theme == .cel ? .clay : .cel)
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
        activationSequence &+= 1
        return true
    }

    private func activateFromCompanion() {
        activationSequence &+= 1
    }

    private func apply(_ update: PatrickWatchReceiver.AppliedState) {
        if let theme = update.theme, theme != self.theme {
            self.theme = theme
            persist(theme: theme)
        }
        if let sleepMode = update.sleepMode {
            self.sleepMode = sleepMode
        }
        if let previewState = update.previewState {
            self.previewState = previewState
        }
    }

    private func persist(
        theme: PatrickTheme? = nil,
        status: PatrickFaceStatus? = nil
    ) {
        guard PatrickSharedStore.save(theme: theme, status: status) else { return }
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
            PatrickFaceView()
                .environmentObject(model)
                .onOpenURL { url in
                    _ = model.handle(url)
                }
        }
    }
}
