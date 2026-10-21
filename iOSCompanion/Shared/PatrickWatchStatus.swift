import Foundation

/// An observation made while Patrick is visible on the watch, never a promise
/// that the watch is still charging when the phone later receives it.
struct PatrickWatchStatusObservation: Codable, Equatable, Sendable {
    static let transportKey = "patrick.watch-status.v1"
    static let schemaVersion = 1
    enum ChargingState: String, Codable, Sendable {
        case unknown, unplugged, charging, full
    }
    var version = PatrickWatchStatusObservation.schemaVersion
    var id = UUID()
    var observedAtMS: Double
    var batteryLevel: Double?
    var chargingState: ChargingState

    init(batteryLevel: Double?, chargingState: ChargingState, at date: Date = .now) {
        observedAtMS = date.timeIntervalSince1970 * 1000
        self.batteryLevel = batteryLevel.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
        self.chargingState = chargingState
    }

    var observedAt: Date { Date(timeIntervalSince1970: observedAtMS / 1000) }
    var isValid: Bool {
        guard version == Self.schemaVersion, observedAtMS.isFinite, observedAtMS >= 0 else { return false }
        return batteryLevel.map { $0.isFinite && (0...1).contains($0) } ?? true
    }
    func encoded() throws -> Data { try JSONEncoder().encode(self) }
    static func decode(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
}

struct PatrickWatchStatusReceipt: Codable, Equatable, Sendable {
    enum Freshness: Equatable { case recent, stale, clockMismatch }
    static let recentInterval: TimeInterval = 300
    var observation: PatrickWatchStatusObservation
    var receivedAt: Date

    func freshness(at now: Date = .now) -> Freshness {
        let age = now.timeIntervalSince(observation.observedAt)
        guard age >= 0, now >= receivedAt else { return .clockMismatch }
        return age <= Self.recentInterval ? .recent : .stale
    }
}

/// Independent storage: a charge observation cannot change settings, timers,
/// animations or their revisions. Only a strictly newer sample advances it.
final class PatrickWatchStatusStore {
    enum Acceptance: Equatable { case accepted, duplicate, older, beforeReset, invalid, clockAhead }
    static let storageKey = "patrick.watch-status-receipt.v1"
    private static let resetKey = "patrick.watch-status-reset-ms.v1"
    private let defaults: UserDefaults
    private(set) var receipt: PatrickWatchStatusReceipt?
    private var resetAtMS: Double?

    init(defaults: UserDefaults = .standard, at now: Date = .now) {
        self.defaults = defaults
        if defaults.object(forKey: Self.resetKey) != nil {
            let cutoff = defaults.double(forKey: Self.resetKey)
            if cutoff.isFinite && cutoff >= 0 && cutoff / 1000 - now.timeIntervalSince1970 <= 30 {
                resetAtMS = cutoff
            } else {
                defaults.removeObject(forKey: Self.resetKey)
            }
        }
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        guard let stored = try? JSONDecoder().decode(PatrickWatchStatusReceipt.self, from: data),
              stored.observation.isValid, stored.receivedAt.timeIntervalSince1970.isFinite,
              stored.receivedAt.timeIntervalSince1970 >= 0,
              stored.observation.observedAt.timeIntervalSince(stored.receivedAt) <= 30,
              stored.observation.observedAt.timeIntervalSince(now) <= 30,
              stored.receivedAt.timeIntervalSince(now) <= 30,
              resetAtMS.map({ stored.observation.observedAtMS > $0 }) != false else {
            // Corruption or a large clock correction must not pin an impossible
            // future sample above all subsequent, correctly timed samples.
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        receipt = stored
    }

    @discardableResult
    func accept(_ observation: PatrickWatchStatusObservation, at receivedAt: Date = .now) -> Acceptance {
        guard observation.isValid, receivedAt.timeIntervalSince1970.isFinite,
              receivedAt.timeIntervalSince1970 >= 0 else { return .invalid }
        // Reject a clock far in the future so it cannot lock out later samples.
        guard observation.observedAt.timeIntervalSince(receivedAt) <= 30 else { return .clockAhead }
        if let cutoff = resetAtMS, cutoff / 1000 - receivedAt.timeIntervalSince1970 > 30 {
            resetAtMS = nil
            defaults.removeObject(forKey: Self.resetKey)
        }
        if let cutoff = resetAtMS, observation.observedAtMS <= cutoff { return .beforeReset }
        if let receipt, receipt.observation.observedAt.timeIntervalSince(receivedAt) > 30
            || receipt.receivedAt.timeIntervalSince(receivedAt) > 30 {
            defaults.removeObject(forKey: Self.storageKey)
            self.receipt = nil // The phone clock can be corrected while the app runs.
        }
        if let previous = receipt?.observation {
            if observation.id == previous.id { return .duplicate }
            guard observation.observedAtMS > previous.observedAtMS else { return .older }
        }
        let next = PatrickWatchStatusReceipt(observation: observation, receivedAt: receivedAt)
        guard let data = try? JSONEncoder().encode(next) else { return .invalid }
        defaults.set(data, forKey: Self.storageKey)
        receipt = next
        return .accepted
    }

    func reset(at now: Date = .now) {
        defaults.removeObject(forKey: Self.storageKey)
        receipt = nil
        resetAtMS = now.timeIntervalSince1970 * 1000
        defaults.set(resetAtMS, forKey: Self.resetKey)
    }
}

/// Repeated five-second face refreshes keep one latest observation, not a
/// background-transfer queue. A changed percent/state is sent immediately;
/// unchanged foreground observations send at most once per minute.
struct PatrickWatchStatusSampler {
    private(set) var latest: PatrickWatchStatusObservation?
    mutating func sample(batteryLevel: Double?, chargingState: PatrickWatchStatusObservation.ChargingState,
                         foreground: Bool, at date: Date = .now) -> PatrickWatchStatusObservation? {
        guard foreground else { return nil }
        let next = PatrickWatchStatusObservation(batteryLevel: batteryLevel, chargingState: chargingState, at: date)
        guard next.isValid else { return nil }
        if let previous = latest {
            let samePercent = previous.batteryLevel.map { Int(($0 * 100).rounded()) }
                == next.batteryLevel.map { Int(($0 * 100).rounded()) }
            let elapsed = date.timeIntervalSince(previous.observedAt)
            if samePercent && previous.chargingState == chargingState && elapsed >= 0 && elapsed < 60 { return nil }
        }
        latest = next
        return next
    }
}

enum PatrickWatchStatusTransport {
    /// WCSession application context replaces the whole dictionary. Preserve
    /// the settings channel when updating status, and vice versa.
    static func merging(key: String, data: Data, into context: [String: Any]) -> [String: Any] {
        var next = context
        next[key] = data
        return next
    }
}

/// A status-only context update carries the unchanged settings envelope too.
/// Keep its identity independently of the command receiver's bounded ID list,
/// so later battery heartbeats cannot reapply an old timer after ID eviction.
final class PatrickWatchContextReplayGate {
    private static let key = "patrick.watch-context-envelope.v1"
    private let defaults: UserDefaults
    private var lastEnvelope: Data?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastEnvelope = defaults.data(forKey: Self.key)
    }
    func alreadyApplied(_ data: Data) -> Bool { lastEnvelope == data }
    func rememberApplied(_ data: Data) {
        lastEnvelope = data
        defaults.set(data, forKey: Self.key)
    }
    func reset() {
        lastEnvelope = nil
        defaults.removeObject(forKey: Self.key)
    }
}
