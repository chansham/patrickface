#if os(watchOS)
import Foundation

/// Watch-local representation of the versioned iPhone/watch wire contract.
///
/// Every DTO is nested so this file can live beside the watch app's existing
/// `PatrickTheme` and related types without creating duplicate declarations.
enum PatrickWatchWire {
    static let currentProtocolVersion = 1
    static let settingsSchemaVersion = 1
    static let transportKey = "patrick.envelope.v1"
    // Kept separate from settings/timer envelopes for v1 compatibility.
    static let watchStatusTransportKey = "patrick.watch-status.v1"

    enum MessageKind: String, Codable, Sendable {
        case command
        case snapshot
        case acknowledgement
    }

    enum CommandName: String, Codable, Sendable {
        case setTheme = "set-theme"
        case setSleepMode = "set-sleep-mode"
        case setPreviewState = "set-preview-state"
        case playThemeSound = "play-theme-sound"
        case openWatchFace = "open-watch-face"
        case startTimer = "start-timer"
        case stopTimer = "stop-timer"
        case updateExperience = "update-experience"
    }

    enum Theme: String, Codable, Sendable {
        case cel1999 = "cel-1999"
        case faithful3D = "faithful-3d"

        init(_ theme: PatrickTheme) {
            switch theme {
            case .cel:
                self = .cel1999
            case .clay:
                self = .faithful3D
            }
        }

        var watchTheme: PatrickTheme {
            switch self {
            case .cel1999:
                .cel
            case .faithful3D:
                .clay
            }
        }
    }

    enum VisualState: String, Codable, Sendable {
        case normal
        case sleeping
        case lowBattery = "low-battery"
        case charging
    }

    enum SleepMode: String, Codable, Sendable {
        case automatic
        case on
        case off
    }

    struct Settings: Codable, Equatable, Sendable {
        var version: Int
        var revision: UInt64
        var theme: Theme
        var previewState: VisualState
        var sleepMode: SleepMode
        var demoMode: Bool
        var updatedAt: Date
        var experience: PatrickExperienceState? = nil

        static func initial(theme: PatrickTheme) -> Settings {
            Settings(
                version: settingsSchemaVersion,
                revision: 0,
                theme: Theme(theme),
                previewState: .normal,
                sleepMode: .automatic,
                demoMode: false,
                updatedAt: Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
            )
        }
    }

    struct TimerSnapshot: Codable, Equatable, Sendable {
        enum Status: String, Codable, Sendable {
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
    }

    struct Command: Codable, Equatable, Sendable {
        var name: CommandName
        var theme: Theme?
        var sleepMode: SleepMode?
        var previewState: VisualState?
        var timer: TimerSnapshot?
        var deepLink: URL?
        var careAction: PatrickCareAction?
        var automationEvent: PatrickAutomationEvent? = nil
    }

    struct Acknowledgement: Codable, Equatable, Sendable {
        var messageID: UUID
        var accepted: Bool
        var detail: String
    }

    struct Envelope: Codable, Equatable, Sendable {
        var protocolVersion: Int
        var id: UUID
        var sentAt: Date
        var kind: MessageKind
        var command: Command?
        var settings: Settings?
        var timer: TimerSnapshot?
        var acknowledgement: Acknowledgement?

        static func snapshot(
            settings: Settings,
            timer: TimerSnapshot?
        ) -> Envelope {
            Envelope(
                protocolVersion: currentProtocolVersion,
                id: UUID(),
                sentAt: .now,
                kind: .snapshot,
                command: nil,
                settings: settings,
                timer: timer,
                acknowledgement: nil
            )
        }

        static func acknowledgement(
            for messageID: UUID,
            accepted: Bool,
            detail: String
        ) -> Envelope {
            Envelope(
                protocolVersion: currentProtocolVersion,
                id: UUID(),
                sentAt: .now,
                kind: .acknowledgement,
                command: nil,
                settings: nil,
                timer: nil,
                acknowledgement: Acknowledgement(
                    messageID: messageID,
                    accepted: accepted,
                    detail: detail
                )
            )
        }

        func encoded() throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(self)
        }

        static func decode(_ data: Data) throws -> Envelope {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.protocolVersion == currentProtocolVersion else {
                throw WireError.unsupportedProtocol(envelope.protocolVersion)
            }
            if let settings = envelope.settings,
               settings.version != settingsSchemaVersion
            {
                throw WireError.unsupportedSettings(settings.version)
            }
            return envelope
        }
    }

    enum WireError: LocalizedError {
        case unsupportedProtocol(Int)
        case unsupportedSettings(Int)

        var errorDescription: String? {
            switch self {
            case let .unsupportedProtocol(version):
                "Unsupported Patrick protocol version \(version)."
            case let .unsupportedSettings(version):
                "Unsupported Patrick settings version \(version)."
            }
        }
    }
}
#endif
