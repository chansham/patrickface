import Foundation

enum PatrickTheme: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case cel1999 = "cel-1999"
    case faithful3D = "faithful-3d"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cel1999: "1999 CEL"
        case .faithful3D: "Season-One Toon 3D"
        }
    }

    var detail: String {
        switch self {
        case .cel1999: "Season-one linework and flat color"
        case .faithful3D: "Smooth cel-derived volume with clean toon shading"
        }
    }

    var bodyAssetName: String {
        switch self {
        case .cel1999: "season1-body-normal"
        case .faithful3D: "season1-3d-body"
        }
    }

    var hourArmAssetName: String {
        switch self {
        case .cel1999: "season1-hour-arm"
        case .faithful3D: "season1-3d-arm"
        }
    }

    var minuteArmAssetName: String {
        switch self {
        case .cel1999: "season1-minute-arm"
        case .faithful3D: "season1-3d-arm"
        }
    }

    /// Matches the existing watch prototype's `@AppStorage("patrickTheme")` values.
    var legacyWatchValue: String {
        switch self {
        case .cel1999: "cel"
        case .faithful3D: "clay"
        }
    }
}

enum PatrickVisualState: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case normal
    case sleeping
    case lowBattery = "low-battery"
    case charging

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .sleeping: "Sleeping"
        case .lowBattery: "Low Battery"
        case .charging: "Charging"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "sparkles"
        case .sleeping: "moon.zzz.fill"
        case .lowBattery: "battery.25percent"
        case .charging: "bolt.fill"
        }
    }
}

enum PatrickSleepMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case automatic
    case on
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .on: "On"
        case .off: "Off"
        }
    }
}

struct PatrickSettings: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var version: Int
    var revision: UInt64
    var theme: PatrickTheme
    var previewState: PatrickVisualState
    var sleepMode: PatrickSleepMode
    var demoMode: Bool
    var updatedAt: Date

    static var defaults: PatrickSettings {
        PatrickSettings(
            version: schemaVersion,
            revision: 0,
            theme: .cel1999,
            previewState: .normal,
            sleepMode: .automatic,
            demoMode: false,
            updatedAt: .now
        )
    }

    func nextRevision(at date: Date = .now) -> PatrickSettings {
        var copy = self
        copy.version = Self.schemaVersion
        copy.revision &+= 1
        copy.updatedAt = date
        return copy
    }
}

struct PatrickTimerSnapshot: Codable, Equatable, Sendable {
    enum Status: String, Codable, Hashable, Sendable {
        case inactive
        case running
        case paused
        case complete
    }

    var id: UUID
    var status: Status
    var title: String
    var startedAt: Date
    var endsAt: Date?
    var remainingSeconds: TimeInterval?

    static var inactive: PatrickTimerSnapshot {
        PatrickTimerSnapshot(
            id: UUID(),
            status: .inactive,
            title: "Patrick Timer",
            startedAt: .now,
            endsAt: nil,
            remainingSeconds: nil
        )
    }
}
