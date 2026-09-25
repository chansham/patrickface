import Foundation

enum PatrickMessageKind: String, Codable, Hashable, Sendable {
    case command
    case snapshot
    case acknowledgement
}

enum PatrickCommandName: String, Codable, Hashable, Sendable {
    case setTheme = "set-theme"
    case setSleepMode = "set-sleep-mode"
    case setPreviewState = "set-preview-state"
    case playThemeSound = "play-theme-sound"
    case openWatchFace = "open-watch-face"
    case startTimer = "start-timer"
    case stopTimer = "stop-timer"
}

struct PatrickCommandPayload: Codable, Equatable, Sendable {
    var name: PatrickCommandName
    var theme: PatrickTheme?
    var sleepMode: PatrickSleepMode?
    var previewState: PatrickVisualState?
    var timer: PatrickTimerSnapshot?
    var deepLink: URL?

    init(
        name: PatrickCommandName,
        theme: PatrickTheme? = nil,
        sleepMode: PatrickSleepMode? = nil,
        previewState: PatrickVisualState? = nil,
        timer: PatrickTimerSnapshot? = nil,
        deepLink: URL? = nil
    ) {
        self.name = name
        self.theme = theme
        self.sleepMode = sleepMode
        self.previewState = previewState
        self.timer = timer
        self.deepLink = deepLink
    }
}

struct PatrickAcknowledgement: Codable, Equatable, Sendable {
    var messageID: UUID
    var accepted: Bool
    var detail: String
}

struct PatrickMessageEnvelope: Codable, Equatable, Sendable {
    static let currentProtocolVersion = 1
    static let transportKey = "patrick.envelope.v1"

    var protocolVersion: Int
    var id: UUID
    var sentAt: Date
    var kind: PatrickMessageKind
    var command: PatrickCommandPayload?
    var settings: PatrickSettings?
    var timer: PatrickTimerSnapshot?
    var acknowledgement: PatrickAcknowledgement?

    static func command(
        _ payload: PatrickCommandPayload,
        settings: PatrickSettings? = nil
    ) -> PatrickMessageEnvelope {
        PatrickMessageEnvelope(
            protocolVersion: currentProtocolVersion,
            id: UUID(),
            sentAt: .now,
            kind: .command,
            command: payload,
            settings: settings,
            timer: payload.timer,
            acknowledgement: nil
        )
    }

    static func snapshot(
        settings: PatrickSettings,
        timer: PatrickTimerSnapshot? = nil
    ) -> PatrickMessageEnvelope {
        PatrickMessageEnvelope(
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
    ) -> PatrickMessageEnvelope {
        PatrickMessageEnvelope(
            protocolVersion: currentProtocolVersion,
            id: UUID(),
            sentAt: .now,
            kind: .acknowledgement,
            command: nil,
            settings: nil,
            timer: nil,
            acknowledgement: PatrickAcknowledgement(
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

    static func decode(_ data: Data) throws -> PatrickMessageEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(PatrickMessageEnvelope.self, from: data)
        guard envelope.protocolVersion == currentProtocolVersion else {
            throw PatrickMessageError.unsupportedProtocol(envelope.protocolVersion)
        }
        return envelope
    }
}

enum PatrickMessageError: LocalizedError {
    case unsupportedProtocol(Int)
    case missingPayload

    var errorDescription: String? {
        switch self {
        case let .unsupportedProtocol(version):
            "Unsupported Patrick message protocol version \(version)."
        case .missingPayload:
            "The Patrick message did not contain the expected payload."
        }
    }
}
