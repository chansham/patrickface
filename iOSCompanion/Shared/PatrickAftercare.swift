import Foundation

/// These are companion countdown completions, never HealthKit workouts.
struct PatrickAftercareCompletion: Codable, Equatable, Sendable {
    var id: String
    var kind: String
    var status: String
    var endedAtMS: Double
}

struct PatrickAftercareState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case idle, offered, playing, done, dismissed }
    var phase: Phase = .idle
    var reason = "waiting"
    var eventID: String?
    var kind: String?
    var variant: String?
    var mode = "live"
    var availableVariants: [String] = []
    var offeredAtMS: Double?
    var playingAtMS: Double?
}

/// An ephemeral invitation state machine. It has no storage or permission APIs,
/// changes no pet state, starts no animation, and creates no workout records.
/// A foreground running observation must precede the completion. Disappearing,
/// reduced motion, low power, pausing, and starting another timer interrupt it.
struct PatrickAftercarePolicy: Sendable {
    static let variants = ["towel", "drink", "rest"]
    private static let exerciseKinds: Set<String> = ["exercise", "walking", "running", "strength"]
    private static let activityKinds: Set<String> = exerciseKinds.union(["focus", "breathing"])
    private struct Observation: Sendable { var id: String; var kind: String; var observedAtMS: Double }
    private(set) var state = PatrickAftercareState()
    private var allowed = false
    private var observed: Observation?
    private var seen: [String: PatrickAftercareCompletion] = [:]
    private var observedKinds: [String: String] = [:]
    private var blocked: Set<String> = []
    private var latestTimeMS: Double?
    private var endedAtMS: Double?
    private var reviewCount = 0

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf16.count <= 128 && id.trimmingCharacters(in: .whitespacesAndNewlines) == id
    }
    private static func validTime(_ value: Double) -> Bool { value.isFinite && value >= 0 }
    private static func canonicalVariants(_ values: [String]) -> [String] { variants.filter(values.contains) }

    private mutating func time(_ nowMS: Double) -> Bool {
        guard Self.validTime(nowMS) else { cancel("invalidTime"); return false }
        if let latestTimeMS, nowMS < latestTimeMS {
            self.latestTimeMS = nowMS
            cancel("clockChanged")
            return false
        }
        latestTimeMS = nowMS
        return true
    }
    @discardableResult private mutating func cancel(_ reason: String) -> PatrickAftercareState {
        observed = nil
        if state.phase == .offered || state.phase == .playing { state.phase = .dismissed }
        state.reason = reason
        return state
    }
    @discardableResult private mutating func reject(_ reason: String) -> PatrickAftercareState {
        state.reason = reason
        return state
    }
    @discardableResult mutating func updateVisibility(active: Bool, lowPower: Bool = false, reduceMotion: Bool = false, nowMS: Double) -> PatrickAftercareState {
        guard time(nowMS) else { allowed = false; return state }
        let nextAllowed = active && !lowPower && !reduceMotion
        if !nextAllowed { cancel(!active ? "inactive" : lowPower ? "lowPower" : "reduceMotion") }
        allowed = nextAllowed
        return state
    }
    @discardableResult mutating func observeActivity(id: String, kind: String, status: String, nowMS: Double) -> PatrickAftercareState {
        guard time(nowMS) else { return state }
        guard allowed else { return cancel("inactive") }
        guard Self.validID(id), Self.activityKinds.contains(kind) else { return cancel("invalidActivity") }
        guard status == "running" else { return cancel(status == "paused" ? "activityPaused" : "invalidActivity") }
        guard seen[id] == nil else { return cancel("reusedActivity") }
        if blocked.contains(id) || (observedKinds[id] != nil && observedKinds[id] != kind) {
            blocked.insert(id)
            return cancel("conflictingActivity")
        }
        observedKinds[id] = kind
        if observed?.id != id || ((state.phase == .offered || state.phase == .playing) && state.eventID != id) { cancel("newActivity") }
        if observed == nil { observed = Observation(id: id, kind: kind, observedAtMS: nowMS) }
        return state
    }
    @discardableResult mutating func receiveCompletion(_ event: PatrickAftercareCompletion, nowMS: Double, availableVariants: [String]) -> PatrickAftercareState {
        guard time(nowMS) else { return state }
        guard Self.validID(event.id) else { return reject("invalidEvent") }
        if let original = seen[event.id] {
            if original == event { return state }
            if state.eventID == event.id { cancel("conflictingEvent") }
            return reject("conflictingEvent")
        }
        // Consume every identified event, including hidden/cancelled/invalid
        // ones, so restoring visibility cannot play a cached completion.
        seen[event.id] = event
        guard !blocked.contains(event.id) else { return reject("conflictingActivity") }
        guard event.status == "completed" else {
            if observed?.id == event.id { observed = nil }
            return reject(event.status == "cancelled" ? "cancelled" : "invalidEvent")
        }
        guard Self.exerciseKinds.contains(event.kind) else { return reject("notExercise") }
        guard Self.validTime(event.endedAtMS) else { return reject("invalidEvent") }
        guard event.endedAtMS <= nowMS else { return reject("futureEvent") }
        guard nowMS - event.endedAtMS <= 60_000 else { return reject("staleEvent") }
        guard allowed else { return reject("inactive") }
        guard let observed, observed.id == event.id, observed.kind == event.kind, event.endedAtMS >= observed.observedAtMS else { return reject("notObserved") }
        self.observed = nil
        let available = Self.canonicalVariants(availableVariants)
        guard !available.isEmpty else { return reject("noAssets") }
        endedAtMS = event.endedAtMS
        state = PatrickAftercareState(phase: .offered, reason: "completionObserved", eventID: event.id,
            kind: event.kind, variant: nil, mode: "live", availableVariants: available,
            offeredAtMS: nowMS, playingAtMS: nil)
        return state
    }
    @discardableResult mutating func beginReview(kind: String = "exercise", nowMS: Double, availableVariants: [String]) -> PatrickAftercareState {
        guard time(nowMS) else { return state }
        guard allowed else { return reject("inactive") }
        guard Self.exerciseKinds.contains(kind) else { return reject("notExercise") }
        let available = Self.canonicalVariants(availableVariants)
        guard !available.isEmpty else { return reject("noAssets") }
        observed = nil
        endedAtMS = nowMS
        reviewCount += 1
        state = PatrickAftercareState(phase: .offered, reason: "manualReview", eventID: "review-\(reviewCount)",
            kind: kind, variant: nil, mode: "review", availableVariants: available,
            offeredAtMS: nowMS, playingAtMS: nil)
        return state
    }
    @discardableResult mutating func choose(_ variant: String, nowMS: Double) -> PatrickAftercareState {
        tick(nowMS: nowMS)
        guard state.phase == .offered else { return state }
        guard allowed else { return cancel("inactive") }
        guard state.availableVariants.contains(variant) else { return reject("unavailableVariant") }
        state.phase = .playing
        state.variant = variant
        state.playingAtMS = nowMS
        state.reason = "userChoice"
        return state
    }
    @discardableResult mutating func finish(nowMS: Double) -> PatrickAftercareState {
        tick(nowMS: nowMS)
        if state.phase == .playing { state.phase = .done; state.reason = "finished" }
        return state
    }
    @discardableResult mutating func dismiss() -> PatrickAftercareState { cancel("userDismissed") }
    @discardableResult mutating func tick(nowMS: Double) -> PatrickAftercareState {
        guard time(nowMS) else { return state }
        if state.phase == .offered, let endedAtMS, nowMS - endedAtMS > 60_000 { return cancel("offerExpired") }
        if state.phase == .playing, let playingAtMS = state.playingAtMS, nowMS - playingAtMS > 20_000 { return cancel("playbackTimeout") }
        return state
    }
}
