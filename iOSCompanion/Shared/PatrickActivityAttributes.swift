import ActivityKit
import Foundation

struct PatrickActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var statusText: String
        var theme: PatrickTheme
        var visualState: PatrickVisualState
        var endsAt: Date?
        var isPaused: Bool
    }

    var sessionID: UUID
    var title: String
    var startedAt: Date
}
