import AppIntents
import WidgetKit

enum PatrickThemeIntentChoice: String, AppEnum {
    case cel1999
    case faithful3D

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Patrick Theme")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .cel1999: "1999 CEL",
        .faithful3D: "Faithful 3D",
    ]

    var theme: PatrickTheme {
        switch self {
        case .cel1999: .cel1999
        case .faithful3D: .faithful3D
        }
    }
}

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

struct SetPatrickThemeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Patrick Theme"
    static var description = IntentDescription(
        "Selects 1999 CEL or Faithful 3D in the Patrick apps."
    )

    @Parameter(title: "Theme")
    var theme: PatrickThemeIntentChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Set Patrick theme to \(\.$theme)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = await PatrickIntentExecutor.setTheme(theme.theme)
        return .result(
            dialog: "Patrick is now using \(settings.theme.displayName)."
        )
    }
}

struct SetPatrickSleepModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Patrick Sleep Mode"
    static var description = IntentDescription(
        "Sets automatic, on, or off sleep behavior in the Patrick apps."
    )

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
        return .result(dialog: "Opening Patrick to play the theme cue.")
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

struct PatrickAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetPatrickThemeIntent(),
            phrases: [
                "Set Patrick theme in \(.applicationName)",
                "Change Patrick style with \(.applicationName)",
            ],
            shortTitle: "Set Patrick Theme",
            systemImageName: "paintpalette.fill"
        )

        AppShortcut(
            intent: SetPatrickSleepModeIntent(),
            phrases: [
                "Set Patrick sleep mode in \(.applicationName)",
            ],
            shortTitle: "Patrick Sleep Mode",
            systemImageName: "moon.zzz.fill"
        )

        AppShortcut(
            intent: PlayPatrickThemeSoundIntent(),
            phrases: [
                "Play Patrick sound in \(.applicationName)",
            ],
            shortTitle: "Patrick Sound",
            systemImageName: "speaker.wave.2.fill"
        )

        AppShortcut(
            intent: OpenPatrickWatchFaceIntent(),
            phrases: [
                "Open Patrick face in \(.applicationName)",
            ],
            shortTitle: "Open Patrick Face",
            systemImageName: "applewatch"
        )
    }
}

private enum PatrickIntentExecutor {
    static let store = PatrickSharedStore.shared

    static func setTheme(_ theme: PatrickTheme) async -> PatrickSettings {
        let settings = store.updateSettings { $0.theme = theme }
        await MainActor.run {
            WatchSyncService.shared.send(
                command: PatrickCommandPayload(
                    name: .setTheme,
                    theme: theme,
                    deepLink: PatrickDeepLinkRoute.setTheme(theme).url
                ),
                settings: settings
            )
            WidgetCenter.shared.reloadAllTimelines()
        }
        return settings
    }

    static func setSleepMode(_ mode: PatrickSleepMode) async -> PatrickSettings {
        let settings = store.updateSettings { $0.sleepMode = mode }
        await MainActor.run {
            WatchSyncService.shared.send(
                command: PatrickCommandPayload(
                    name: .setSleepMode,
                    sleepMode: mode,
                    deepLink: PatrickDeepLinkRoute.setSleepMode(mode).url
                ),
                settings: settings
            )
            WidgetCenter.shared.reloadAllTimelines()
        }
        return settings
    }

    static func queueForegroundAction(_ action: PendingPatrickAction.Kind) async {
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
