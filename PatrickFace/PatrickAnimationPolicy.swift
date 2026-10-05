import Foundation

struct PatrickAnimationContext: Equatable, Sendable {
    var active = false
    var wristDown = false
    var reduceMotion = false
    var lowPower = false
    var sleeping = false
    var charging = false
    var focusing = false
    var exercising = false
    var completedTimerID: String?

    var allowsMotion: Bool { active && !wristDown && !reduceMotion && !lowPower }
    var allowsIdle: Bool { allowsMotion && !charging && !focusing && !exercising }
}

/// A deadline first noticed after an unobserved quiet interval is state catchup,
/// not a fresh performance. A second observation while visible may celebrate.
struct PatrickCompletionVisibility: Sendable {
    private var previouslyAllowed = false
    mutating func update(allowsMotion: Bool) -> Bool {
        let continuous = previouslyAllowed && allowsMotion
        previouslyAllowed = allowsMotion
        return continuous
    }
}

/// Pure state rules: state entry is an event, never a reason to loop a scene.
struct PatrickAnimationPolicy: Sendable {
    static let idleIDs = ["idle-blink-normal", "idle-blink-slow", "idle-blink-double"]
    static let yawnCooldown: TimeInterval = 10 * 60
    static let idleInterval: ClosedRange<TimeInterval> = 10...22
    private(set) var previous: PatrickAnimationContext?
    private(set) var lastYawnAt: Date?
    private(set) var lastCelebratedTimerID: String?
    private(set) var lastIdleID: String?

    init(lastYawnAt: Date? = nil) { self.lastYawnAt = lastYawnAt }

    mutating func transition(to next: PatrickAnimationContext, at date: Date) -> String? {
        let old = previous
        previous = next
        // Remember quiet transitions too: raising a wrist must not replay them.
        guard next.allowsMotion else { return nil }
        guard old?.allowsMotion != false else { return nil }
        if next.sleeping && old?.sleeping != true {
            guard lastYawnAt.map({ date.timeIntervalSince($0) >= Self.yawnCooldown }) ?? true else { return nil }
            return "yawn"
        }
        if !next.sleeping && old?.sleeping == true { return "wake" }
        if next.charging && old?.charging != true { return "charging" }
        if let id = next.completedTimerID, id != old?.completedTimerID,
           id != lastCelebratedTimerID { return "celebrate" }
        if next.focusing && old?.focusing != true { return "focus" }
        if next.exercising && old?.exercising != true { return "exercise" }
        return nil
    }

    mutating func didStart(_ clipID: String, at date: Date) {
        if clipID == "yawn" { lastYawnAt = date }
        if clipID == "celebrate" { lastCelebratedTimerID = previous?.completedTimerID }
        if Self.idleIDs.contains(clipID) { lastIdleID = clipID }
    }

    func idleCandidates(from available: [String]) -> [String] {
        available.filter { Self.idleIDs.contains($0) && $0 != lastIdleID }
    }
}

/// Protocol v1 clears the timer on stop. Keep its known deadline so an on-time
/// completion can be distinguished from an early cancellation without wire changes.
struct PatrickAnimationTimerTracker: Sendable {
    private var knownID: String?
    private var knownDeadline: Date?
    private var quietCompletedID: String?

    mutating func update(id: String?, running: Bool, paused: Bool, endsAt: Date?, at date: Date,
                         allowCompletion: Bool = true)
        -> (focusing: Bool, completedTimerID: String?) {
        if paused || (!running && id != nil && id != knownID) {
            knownID = nil; knownDeadline = nil
        } else if running {
            knownID = id; knownDeadline = endsAt
        } else if let deadline = knownDeadline, deadline > date {
            // An early phone stop is not a completed focus session.
            knownID = nil; knownDeadline = nil
        }
        let completed: String?
        if let deadline = knownDeadline, (0...60).contains(date.timeIntervalSince(deadline)) {
            if !allowCompletion { quietCompletedID = knownID }
            completed = knownID == quietCompletedID ? nil : knownID
        } else { completed = nil }
        return (running && (endsAt.map { $0 > date } ?? true), completed)
    }
}
