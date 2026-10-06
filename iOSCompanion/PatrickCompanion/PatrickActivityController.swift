import ActivityKit
import Combine
import Foundation

@MainActor
final class PatrickActivityController: ObservableObject {
    @Published private(set) var activeActivityID: String?
    @Published private(set) var authorizationEnabled = true
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        authorizationEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        activeActivityID = Activity<PatrickActivityAttributes>.activities.first?.id
    }

    /// Initial handoff can already be paused. Creation and later updates must
    /// describe the same snapshot without assuming every new presentation runs.
    nonisolated static func contentState(
        timer: PatrickTimerSnapshot,
        settings: PatrickSettings
    ) -> PatrickActivityAttributes.ContentState {
        PatrickActivityAttributes.ContentState(
            statusText: timer.status == .paused ? "Timer paused" : "Timer running",
            theme: settings.theme,
            visualState: settings.previewState,
            endsAt: timer.endsAt,
            isPaused: timer.status == .paused
        )
    }

    func start(
        timer: PatrickTimerSnapshot,
        settings: PatrickSettings
    ) async {
        guard authorizationEnabled else {
            lastError = "Live Activities are disabled in system settings."
            return
        }

        await endAll(dismissalPolicy: .immediate)

        let attributes = PatrickActivityAttributes(
            sessionID: timer.id,
            title: timer.title,
            startedAt: timer.startedAt
        )
        let state = Self.contentState(timer: timer, settings: settings)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: state,
                    staleDate: timer.endsAt
                ),
                pushType: nil
            )
            activeActivityID = activity.id
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func update(
        timer: PatrickTimerSnapshot,
        settings: PatrickSettings
    ) async {
        let state = Self.contentState(timer: timer, settings: settings)
        let content = ActivityContent(
            state: state,
            staleDate: timer.endsAt
        )
        for activity in Activity<PatrickActivityAttributes>.activities {
            await activity.update(content)
        }
        refresh()
    }

    func endAll(
        finalStatus: String = "Timer complete",
        dismissalPolicy: ActivityUIDismissalPolicy = .default
    ) async {
        for activity in Activity<PatrickActivityAttributes>.activities {
            var state = activity.content.state
            state.statusText = finalStatus
            state.endsAt = nil
            state.isPaused = false
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: dismissalPolicy
            )
        }
        refresh()
    }
}
