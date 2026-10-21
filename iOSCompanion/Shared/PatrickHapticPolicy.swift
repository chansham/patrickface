import Foundation

/// Meaningful haptics only. Routine taps (pet, browse, crown, start, pause, cancel)
/// are intentionally absent so the watch does not buzz on every touch.
enum PatrickHapticMoment: String, CaseIterable, Equatable, Sendable {
    case feed
    case feedFull
    case timerClosing
    case timerDone
    case restDone
    case wake
    case goodnight
    case chargingFull
    case celebrate
    case failure
}

enum PatrickHapticKind: String, Equatable, Sendable {
    case directionUp
    case directionDown
    case retry
    case decrease
    case success
    case notification
    case failure
}

enum PatrickHapticPolicy {
    static let minimumGap: TimeInterval = 1

    static func kind(for moment: PatrickHapticMoment) -> PatrickHapticKind {
        switch moment {
        case .feed, .wake: .directionUp
        case .feedFull: .retry
        case .timerClosing: .decrease
        case .timerDone, .chargingFull, .celebrate: .success
        case .restDone: .notification
        case .goodnight: .directionDown
        case .failure: .failure
        }
    }

    /// Foreground only, unless a real workout session is in progress.
    /// Heart-rate reads and the sleep window stay quiet. Goodnight and wake
    /// are the exceptions that mark entering or leaving that quiet.
    static func allows(
        moment: PatrickHapticMoment,
        enabled: Bool,
        foreground: Bool,
        inWorkout: Bool,
        readingHeartRate: Bool,
        quiet: Bool,
        now: Date,
        lastPlayedAt: Date?,
        minimumGap: TimeInterval = PatrickHapticPolicy.minimumGap
    ) -> Bool {
        guard enabled, !readingHeartRate else { return false }
        guard foreground || inWorkout else { return false }
        if quiet, moment != .goodnight, moment != .wake { return false }
        if let lastPlayedAt, now.timeIntervalSince(lastPlayedAt) < minimumGap { return false }
        return true
    }
}
