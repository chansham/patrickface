import Foundation

/// Four patterns. Knock is the only proactive one and spends the daily budget.
/// Done, attention and settle answer something the person already started.
enum PatrickHapticMoment: String, CaseIterable, Equatable, Sendable {
    case knock
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
    /// Three clicks. Proactive reach-outs only.
    case click
    /// Completion: timer done, full charge, celebration.
    case success
    /// Attention: last seconds, rest ending, and a failed read.
    case notification
    /// Settle: goodnight and the wake that leaves sleep.
    case directionDown
}

enum PatrickHapticPolicy {
    static let minimumGap: TimeInterval = 1

    static func kind(for moment: PatrickHapticMoment) -> PatrickHapticKind {
        switch moment {
        case .knock: .click
        case .timerDone, .chargingFull, .celebrate: .success
        case .timerClosing, .restDone, .failure: .notification
        case .goodnight, .wake: .directionDown
        }
    }

    static var distinctKinds: Set<PatrickHapticKind> {
        Set(PatrickHapticMoment.allCases.map { kind(for: $0) })
    }

    /// Foreground only, unless a real workout session is in progress.
    /// Heart-rate reads stay quiet. Sleep quiets everything except goodnight
    /// and wake. A knock is also refused while the context gate is closed.
    static func allows(
        moment: PatrickHapticMoment,
        enabled: Bool,
        foreground: Bool,
        inWorkout: Bool,
        readingHeartRate: Bool,
        quiet: Bool,
        now: Date,
        lastPlayedAt: Date?,
        context: PatrickContextSnapshot = PatrickContextSnapshot(),
        minimumGap: TimeInterval = PatrickHapticPolicy.minimumGap
    ) -> Bool {
        guard enabled, !readingHeartRate else { return false }
        guard foreground || inWorkout else { return false }
        if moment == .knock, context.suppressesProactive { return false }
        if quiet, moment != .goodnight, moment != .wake { return false }
        if let lastPlayedAt, now.timeIntervalSince(lastPlayedAt) < minimumGap { return false }
        return true
    }
}
