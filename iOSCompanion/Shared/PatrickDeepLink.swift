import Foundation

enum PatrickDeepLinkRoute: Equatable, Sendable {
    static let scheme = "patrickface"

    case controlCenter
    case setTheme(PatrickTheme)
    case setSleepMode(PatrickSleepMode)
    case playThemeSound
    case openWatchFace
    case timer

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        let route = (url.host ?? url.pathComponents.dropFirst().first ?? "")
            .lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = (components?.queryItems ?? []).reduce(into: [String: String]()) {
            values, item in
            if let value = item.value {
                values[item.name] = value
            }
        }

        switch route {
        case "control", "control-center":
            self = .controlCenter
        case "set-theme":
            guard
                let value = query["value"],
                let theme = PatrickTheme(rawValue: value)
            else { return nil }
            self = .setTheme(theme)
        case "set-sleep-mode":
            guard
                let value = query["value"],
                let mode = PatrickSleepMode(rawValue: value)
            else { return nil }
            self = .setSleepMode(mode)
        case "play-theme-sound":
            self = .playThemeSound
        case "open-watch-face":
            self = .openWatchFace
        case "timer":
            self = .timer
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .controlCenter:
            components.host = "control-center"
        case let .setTheme(theme):
            components.host = "set-theme"
            components.queryItems = [URLQueryItem(name: "value", value: theme.rawValue)]
        case let .setSleepMode(mode):
            components.host = "set-sleep-mode"
            components.queryItems = [URLQueryItem(name: "value", value: mode.rawValue)]
        case .playThemeSound:
            components.host = "play-theme-sound"
        case .openWatchFace:
            components.host = "open-watch-face"
        case .timer:
            components.host = "timer"
        }

        // Every case above produces a valid custom-scheme URL.
        return components.url!
    }
}
