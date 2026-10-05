import Foundation

enum PatrickTheme: String, CaseIterable, Codable, Sendable {
    case cel
    case clay

    var displayName: String {
        switch self {
        case .cel: "第一季 2D"
        case .clay: "第一季 Toon 3D"
        }
    }

    var statusLabel: String {
        switch self {
        case .cel: "1999 CEL"
        case .clay: "TOON 3D"
        }
    }

    var complicationLabel: String {
        switch self {
        case .cel: "1999 CEL"
        case .clay: "TOON"
        }
    }
}

enum PatrickFaceStatus: String, Codable, Sendable {
    case ready
    case sleeping
    case lowPower
    case charging
    case resting
    case exercise
    case preview

    var complicationLabel: String {
        switch self {
        case .ready: "READY"
        case .sleeping: "REST"
        case .lowPower: "LOW POWER"
        case .charging: "CHARGING"
        case .resting: "RESTING"
        case .exercise: "COMPANION"
        case .preview: "PREVIEW"
        }
    }
}

/// Local, user-chosen scenes. These describe the pet, not a measured human state.
enum PatrickPetScene: String, CaseIterable, Identifiable, Hashable, Sendable {
    case automatic
    case resting
    case sleeping
    case exercise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "依時間陪伴"
        case .resting: "休息陪伴"
        case .sleeping: "睡眠陪伴"
        case .exercise: "運動陪伴"
        }
    }
}

enum PatrickPetRules {
    static let nightStartsAtMinute = 22 * 60
    static let nightEndsAtMinute = 5 * 60 + 30

    static func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return minute >= nightStartsAtMinute || minute < nightEndsAtMinute
    }

    static func isSleeping(
        scene: PatrickPetScene,
        automaticNight: Bool,
        companionSleep: Bool?,
        companionPreviewSleeping: Bool
    ) -> Bool {
        switch scene {
        case .sleeping: return true
        case .resting, .exercise: return false
        case .automatic:
            return companionPreviewSleeping || (companionSleep ?? automaticNight)
        }
    }
}

/// Both app and complication use one pivot and the same hand-length ratio.
enum PatrickClockLayout {
    static let width = 720.0
    static let height = 880.0
    static let hubX = 360.0
    static let hubY = 498.0
    static let hourLength = 250.0
    static let minuteLength = 340.0
}

struct PatrickSharedState: Equatable, Sendable {
    let theme: PatrickTheme
    let status: PatrickFaceStatus
    let updatedAt: Date
}

enum PatrickSharedStore {
    static let appGroupIdentifier = "group.com.chans.patrickface.shared"
    static let complicationKind = "PatrickFaceComplication"

    static let themeKey = "patrick.theme"
    static let statusKey = "patrick.status"
    static let updatedAtKey = "patrick.updatedAt"
    private static let legacyThemeKey = "patrickTheme"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func load() -> PatrickSharedState {
        let defaults = defaults
        let sharedTheme = defaults.string(forKey: themeKey)
            .flatMap(PatrickTheme.init(rawValue:))
        let legacyTheme = UserDefaults.standard.string(forKey: legacyThemeKey)
            .flatMap(PatrickTheme.init(rawValue:))
        let theme = sharedTheme ?? legacyTheme ?? .cel
        if sharedTheme == nil, legacyTheme != nil {
            defaults.set(theme.rawValue, forKey: themeKey)
        }
        let status = defaults.string(forKey: statusKey)
            .flatMap(PatrickFaceStatus.init(rawValue:)) ?? .ready
        let timestamp = defaults.double(forKey: updatedAtKey)

        return PatrickSharedState(
            theme: theme,
            status: status,
            updatedAt: timestamp > 0
                ? Date(timeIntervalSince1970: timestamp)
                : .distantPast
        )
    }

    @discardableResult
    static func save(
        theme: PatrickTheme? = nil,
        status: PatrickFaceStatus? = nil,
        at date: Date = .now
    ) -> Bool {
        let defaults = defaults
        let current = load()
        let nextTheme = theme ?? current.theme
        let nextStatus = status ?? current.status
        let valuesChanged = nextTheme != current.theme || nextStatus != current.status
        let age = date.timeIntervalSince(current.updatedAt)
        let timestampNeedsRefresh = (theme != nil || status != nil)
            && (age < 0 || age >= 60)
        guard valuesChanged || timestampNeedsRefresh else {
            return false
        }

        defaults.set(nextTheme.rawValue, forKey: themeKey)
        defaults.set(nextStatus.rawValue, forKey: statusKey)
        defaults.set(date.timeIntervalSince1970, forKey: updatedAtKey)
        return true
    }
}

struct PatrickClockAngles: Equatable, Sendable {
    let hour: Double
    let minute: Double

    static func make(
        for date: Date,
        calendar: Calendar = .current
    ) -> PatrickClockAngles {
        let components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: date
        )
        let seconds = Double(components.second ?? 0)
            + Double(components.nanosecond ?? 0) / 1_000_000_000
        let minutes = Double(components.minute ?? 0) + seconds / 60
        let hours = Double((components.hour ?? 0) % 12) + minutes / 60

        return PatrickClockAngles(
            hour: normalized(hours * 30),
            minute: normalized(minutes * 6)
        )
    }

    private static func normalized(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}

struct PatrickDeepLink: Equatable, Sendable {
    enum Source: String, Sendable {
        case complication
        case external
    }

    static let scheme = "patrickface"

    let theme: PatrickTheme?
    let source: Source

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "face"

        var queryItems = [URLQueryItem(
            name: "source",
            value: source.rawValue
        )]
        if let theme {
            queryItems.append(URLQueryItem(name: "theme", value: theme.rawValue))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func parse(_ url: URL) -> PatrickDeepLink? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == scheme,
            components.user == nil,
            components.password == nil,
            components.port == nil
        else {
            return nil
        }

        let host = components.host?.lowercased()
        let path = components.path
            .split(separator: "/")
            .map { $0.lowercased() }
        let opensFace = (host == "face" && path.isEmpty)
            || (host == "open" && (path.isEmpty || path == ["face"]))
            || ((host == nil || host == "") && path == ["face"])
        guard opensFace else { return nil }

        let items = Dictionary(
            components.queryItems?.map { ($0.name.lowercased(), $0.value) } ?? [],
            uniquingKeysWith: { _, last in last }
        )

        let theme: PatrickTheme?
        if let rawTheme = items["theme"] {
            guard let parsedTheme = rawTheme
                .map { $0.lowercased() }
                .flatMap(PatrickTheme.init(rawValue:))
            else {
                return nil
            }
            theme = parsedTheme
        } else {
            theme = nil
        }

        let source = items["source"]
            .flatMap { $0 }
            .map { $0.lowercased() }
            .flatMap(Source.init(rawValue:)) ?? .external
        return PatrickDeepLink(theme: theme, source: source)
    }
}
