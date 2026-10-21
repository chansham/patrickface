import AppIntents
import Foundation

/// Opens the face. It is not an App Shortcut, so it does not use one of the ten phrases.
struct PatrickStackOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "看派大星"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult { .result() }
}

enum PatrickStackDonation {
    @available(watchOS 11.0, *)
    static func refresh(settings: PatrickExperienceSettings, workingOut: Bool, now: Date = .now) async {
        let windows = PatrickWeekPlan.stackWindows(settings: settings, workingOut: workingOut, now: now)
        let intents = windows.map { window in
            RelevantIntent(
                PatrickStackOpenIntent(),
                widgetKind: PatrickSharedStore.complicationKind,
                relevance: RelevantContext.date(from: window.start, to: window.end)
            )
        }
        try? await RelevantIntentManager.shared.updateRelevantIntents(intents)
    }
}
