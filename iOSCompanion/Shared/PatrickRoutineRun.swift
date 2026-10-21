import Foundation

/// Receipts from an explicitly assembled shortcut. A successful receipt is not
/// independent proof of a system setting or of the paired watch's state.
struct PatrickRoutineRun: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case pending, succeeded, failed, skipped }
    enum StepID: String, Codable, CaseIterable, Sendable {
        case focus = "sleep-focus", alarm = "existing-alarm", patrick = "patrick-state", home = "home-scene"
        var title: String {
            switch self { case .focus: "睡眠專注"; case .alarm: "指定鬧鐘"; case .patrick: "派大星睡前狀態"; case .home: "晚安燈光" }
        }
        var required: Bool { self == .focus || self == .patrick }
    }
    enum Source: String, Codable, Sendable { case shortcut, localApp }
    struct Step: Codable, Equatable, Identifiable, Sendable {
        var stepID: StepID
        var status: Status = .pending
        var attempt: Int = 1
        var receiptID: UUID?
        var source: Source?
        var note: String?
        var updatedAtMS: Double
        var id: String { stepID.rawValue }
    }
    struct Receipt: Codable, Equatable, Sendable {
        var receiptID: UUID
        var executionID: UUID
        var stepID: StepID
        var attempt: Int
        var status: Status
        var source: Source
        var note: String
        var receivedAtMS: Double
    }
    enum ApplyResult: String, Sendable { case applied, duplicate, invalid, staleAttempt, alreadyResolved }
    var schemaVersion = 1
    var executionID: UUID
    var routineID = "goodnight"
    var createdAtMS: Double
    var updatedAtMS: Double
    var steps: [Step]
    private(set) var events: [Receipt] = []
    var id: UUID { executionID }

    init(id: UUID = UUID(), at date: Date = .now) {
        let now = date.timeIntervalSince1970 * 1000
        executionID = id; createdAtMS = now; updatedAtMS = now
        steps = StepID.allCases.map { Step(stepID: $0, updatedAtMS: now) }
    }

    var summary: String {
        let failed = steps.filter { $0.status == .failed }.count
        let pending = steps.filter { $0.status == .pending }.count
        if failed > 0 { return "\(failed) 步未完成" + (pending > 0 ? "，\(pending) 步尚無回報" : "") }
        if pending > 0 { return "\(pending) 步尚無回報" }
        return "手機步驟回報完整"
    }

    var isValid: Bool {
        guard schemaVersion == 1 && routineID == "goodnight" && createdAtMS.isFinite && createdAtMS > 0
            && updatedAtMS.isFinite && updatedAtMS >= createdAtMS
            && steps.count == StepID.allCases.count && Set(steps.map(\.stepID)).count == steps.count
            && steps.allSatisfy { (1...5).contains($0.attempt) && $0.updatedAtMS.isFinite
                && $0.updatedAtMS >= createdAtMS && $0.updatedAtMS <= updatedAtMS
                && !($0.stepID.required && $0.status == .skipped) }
            && events.count <= 20
            && Set(events.map(\.receiptID)).count == events.count
            && steps.map(\.updatedAtMS).max() == updatedAtMS else { return false }
        // A stored success must have the same evidence as a live transition.
        // Validate each step independently: different steps can arrive out of
        // timestamp order, but attempts for one step cannot skip a failure.
        guard events.allSatisfy({ receipt in
            receipt.executionID == executionID && (1...5).contains(receipt.attempt)
                && receipt.status != .pending && !(receipt.status == .skipped && receipt.stepID.required)
                && (receipt.stepID == .patrick) == (receipt.source == .localApp)
                && receipt.note.count <= 240 && receipt.receivedAtMS.isFinite
                && receipt.receivedAtMS >= createdAtMS && receipt.receivedAtMS <= updatedAtMS
        }) else { return false }
        return steps.allSatisfy { step in
            let history = events.filter { $0.stepID == step.stepID }
            let expectedCount = step.status == .pending ? step.attempt - 1 : step.attempt
            guard history.count == expectedCount else { return false }
            var previousTime = createdAtMS
            for (offset, receipt) in history.enumerated() {
                guard receipt.attempt == offset + 1, receipt.receivedAtMS >= previousTime,
                      receipt.receivedAtMS <= step.updatedAtMS,
                      receipt.attempt == step.attempt || receipt.status == .failed else { return false }
                previousTime = receipt.receivedAtMS
            }
            if step.status == .pending {
                return step.receiptID == nil && step.source == nil && step.note == nil
                    && (step.attempt > 1 || step.updatedAtMS == createdAtMS)
            }
            guard let receipt = history.last else { return false }
            return step.receiptID == receipt.receiptID && step.source == receipt.source
                && step.note == receipt.note && step.status == receipt.status
                && step.updatedAtMS == receipt.receivedAtMS
        }
    }

    @discardableResult mutating func apply(_ receipt: Receipt, at date: Date = .now) -> ApplyResult {
        let now = date.timeIntervalSince1970 * 1000
        guard isValid, now.isFinite, receipt.executionID == executionID,
              receipt.receivedAtMS.isFinite, receipt.receivedAtMS >= createdAtMS,
              receipt.receivedAtMS <= now, receipt.status != .pending,
              let index = steps.firstIndex(where: { $0.stepID == receipt.stepID }),
              !(receipt.status == .skipped && receipt.stepID.required),
              receipt.note.count <= 240,
              // Only actual local state application can resolve the Patrick step.
              (receipt.stepID == .patrick) == (receipt.source == .localApp)
        else { return .invalid }
        if let previous = events.first(where: { $0.receiptID == receipt.receiptID }) {
            return previous == receipt ? .duplicate : .invalid
        }
        guard receipt.attempt == steps[index].attempt,
              receipt.receivedAtMS >= steps[index].updatedAtMS else { return .staleAttempt }
        guard steps[index].status == .pending else { return .alreadyResolved }
        steps[index].status = receipt.status
        steps[index].receiptID = receipt.receiptID
        steps[index].source = receipt.source
        steps[index].note = receipt.note
        steps[index].updatedAtMS = receipt.receivedAtMS
        updatedAtMS = max(updatedAtMS, receipt.receivedAtMS)
        events.append(receipt)
        return .applied
    }

    /// Prepares one explicitly chosen failed step; does not execute an action.
    /// A delayed receipt from an older attempt cannot resolve the retry.
    mutating func retry(_ stepID: StepID, at date: Date = .now) -> Int? {
        let now = date.timeIntervalSince1970 * 1000
        guard isValid, now.isFinite, now >= updatedAtMS,
              let index = steps.firstIndex(where: { $0.stepID == stepID }),
              steps[index].status == .failed, steps[index].attempt < 5 else { return nil }
        steps[index].attempt += 1
        steps[index].status = .pending
        steps[index].receiptID = nil; steps[index].source = nil; steps[index].note = nil
        steps[index].updatedAtMS = now; updatedAtMS = now
        return steps[index].attempt
    }
}

/// Separate local history; it does not change a timer, Focus, alarm or Watch.
/// App entry points serialize these transactions on the main actor.
final class PatrickRoutineStore: @unchecked Sendable {
    static let shared = PatrickRoutineStore()
    static let storageKey = "patrick.routine-runs.v1"
    static let changed = Notification.Name("com.chans.patrickface.routine-runs-changed")
    private let defaults: UserDefaults
    private let lock = NSLock()
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: "group.com.chans.patrickface.shared") ?? .standard
    }
    private func read() -> [PatrickRoutineRun] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        // One malformed row must not hide other valid history. Keep the latest
        // valid occurrence of an execution ID so updates target a single run.
        let runs = rows.compactMap { row -> PatrickRoutineRun? in
            guard JSONSerialization.isValidJSONObject(row),
                  let bytes = try? JSONSerialization.data(withJSONObject: row),
                  let run = try? JSONDecoder().decode(PatrickRoutineRun.self, from: bytes),
                  run.isValid else { return nil }
            return run
        }
        var seen = Set<UUID>()
        return Array(runs.reversed().filter { seen.insert($0.id).inserted }.prefix(50).reversed())
    }
    func load() -> [PatrickRoutineRun] { lock.withLock { read() } }
    @discardableResult func start(id: UUID = UUID(), at date: Date = .now) -> PatrickRoutineRun {
        var changed = false
        let result: PatrickRoutineRun = lock.withLock {
            var runs = read()
            if let existing = runs.first(where: { $0.id == id }) { return existing }
            let run = PatrickRoutineRun(id: id, at: date)
            guard run.isValid else { return run }
            runs = Array((runs + [run]).suffix(50))
            if let data = try? JSONEncoder().encode(runs) {
                defaults.set(data, forKey: Self.storageKey); changed = true
            }
            return run
        }
        if changed { NotificationCenter.default.post(name: Self.changed, object: nil) }
        return result
    }
    @discardableResult func update(id: UUID, _ mutation: (inout PatrickRoutineRun) -> Void) -> PatrickRoutineRun? {
        var changed = false
        let result: PatrickRoutineRun? = lock.withLock {
            var runs = read()
            guard let index = runs.firstIndex(where: { $0.id == id }) else { return nil }
            let before = runs[index]
            mutation(&runs[index])
            guard runs[index].isValid, runs[index].id == id,
                  runs[index].createdAtMS == before.createdAtMS else { return nil }
            guard runs[index] != before else { return before }
            guard let data = try? JSONEncoder().encode(runs) else { return nil }
            defaults.set(data, forKey: Self.storageKey)
            changed = true
            return runs[index]
        }
        if changed { NotificationCenter.default.post(name: Self.changed, object: nil) }
        return result
    }
    func clear() {
        lock.withLock { defaults.removeObject(forKey: Self.storageKey) }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
