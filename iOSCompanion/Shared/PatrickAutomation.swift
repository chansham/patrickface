import Foundation

/// A report from an explicit action, never proof that this app observed Clock.
struct PatrickAutomationEvent: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case alarmStopped = "alarm-stopped"
        case wakeUp = "wake-up"
        var title: String { self == .alarmStopped ? "鬧鐘已停止" : "我起床了" }
    }
    enum Source: String, Codable, Sendable {
        case shortcut, manual
        var title: String { self == .shortcut ? "捷徑回報" : "手動回報" }
    }
    var id: UUID
    var kind: Kind
    var source: Source
    var occurredAtMS: Double
    var clipKey: String { "wake" }
    var journalText: String { "\(kind.title)（\(source.title)）" }
    var isValid: Bool { occurredAtMS.isFinite && occurredAtMS > 0 }
    static let maximumAgeMS = 3_000.0

    init(id: UUID = UUID(), kind: Kind, source: Source, at date: Date = .now) {
        self.id = id; self.kind = kind; self.source = source
        occurredAtMS = date.timeIntervalSince1970 * 1000
    }
    func isFresh(at date: Date = .now) -> Bool {
        let age = date.timeIntervalSince1970 * 1000 - occurredAtMS
        return isValid && age.isFinite && (0...Self.maximumAgeMS).contains(age)
    }
}

/// Receipt IDs survive restart; presentation permission never does. Quiet or
/// expired deliveries are consumed immediately, not queued for a later replay.
struct PatrickAutomationGate {
    static let storageKey = "patrick.automation.received-ids.v1"
    enum Outcome: Equatable { case invalid, duplicate, recordOnly, play }
    private(set) var receivedIDs: [UUID]
    private var presentationActive = false
    private var visibleSinceMS = Double.infinity

    init(receivedIDs: [UUID] = []) { self.receivedIDs = Array(receivedIDs.suffix(100)) }

    mutating func setPresentationActive(_ active: Bool, at date: Date = .now) {
        if active && !presentationActive { visibleSinceMS = date.timeIntervalSince1970 * 1000 }
        if !active { visibleSinceMS = .infinity }
        presentationActive = active
    }

    func allowsPlayback(_ event: PatrickAutomationEvent, at date: Date = .now) -> Bool {
        presentationActive && event.isFresh(at: date) && event.occurredAtMS >= visibleSinceMS
    }

    mutating func consume(_ event: PatrickAutomationEvent, at date: Date = .now) -> Outcome {
        let now = date.timeIntervalSince1970 * 1000
        guard event.isValid, now.isFinite, event.occurredAtMS <= now else { return .invalid }
        guard !receivedIDs.contains(event.id) else { return .duplicate }
        receivedIDs = Array((receivedIDs + [event.id]).suffix(100))
        return allowsPlayback(event, at: date) ? .play : .recordOnly
    }
}

extension PatrickExperienceState {
    /// Only the originating action records the journal. A received snapshot
    /// carries this entry; receivers must not record or reward it a second time.
    @discardableResult
    mutating func recordAutomation(_ event: PatrickAutomationEvent, at date: Date = .now) -> Bool {
        guard event.isValid, date.timeIntervalSince1970.isFinite,
              event.occurredAtMS <= date.timeIntervalSince1970 * 1000,
              !processedActionIDs.contains(event.id) else { return false }
        processedActionIDs = Array((processedActionIDs + [event.id]).suffix(100))
        record(event.journalText, at: Date(timeIntervalSince1970: event.occurredAtMS / 1000))
        changed(at: date)
        return true
    }
}

extension Notification.Name {
    static let patrickAutomationReceived = Notification.Name("com.chans.patrickface.automation-received")
}
