import Foundation

/// Run with the real Foundation model, independently of AppIntents or a device:
/// swiftc iOSCompanion/Shared/PatrickRoutineRun.swift tools/NativeRoutineRunChecks.swift -o native-routine-runs
/// ./native-routine-runs ecosystem/routine-run-fixtures.json
@main struct NativeRoutineRunChecks {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    struct Fixtures: Decodable {
        var schemaVersion: Int
        var executionID: UUID
        var createdAtMS: Double
        var cases: [Case]
    }
    struct Case: Decodable { var name: String; var operations: [Operation]; var expected: [String: Int] }
    struct Operation: Decodable {
        var type: String
        var atMS: Double?
        var receipt: PatrickRoutineRun.Receipt?
        var result: String?
        var stepID: PatrickRoutineRun.StepID?
        var attempt: Int?
    }
    static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }
    static func json(_ run: PatrickRoutineRun) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
    }
    static func corrupt(_ run: PatrickRoutineRun, _ message: String,
                        edit: (inout [String: Any]) -> Void) throws {
        var row = try json(run); edit(&row)
        let bytes = try JSONSerialization.data(withJSONObject: row)
        let decoded = try? JSONDecoder().decode(PatrickRoutineRun.self, from: bytes)
        check(decoded?.isValid != true, message)
    }
    static func main() throws {
        precondition(CommandLine.arguments.count == 2, "Pass ecosystem/routine-run-fixtures.json")
        let fixtures = try JSONDecoder().decode(Fixtures.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        check(fixtures.schemaVersion == 1, "Shared fixture version")
        for item in fixtures.cases {
            var run = PatrickRoutineRun(id: fixtures.executionID, at: date(fixtures.createdAtMS))
            check(run.isValid, "\(item.name): initial state")
            for op in item.operations {
                let before = run
                switch op.type {
                case "receipt":
                    let result = run.apply(op.receipt!, at: date(op.atMS!))
                    check(result.rawValue == op.result, "\(item.name): receipt \(result.rawValue), expected \(op.result ?? "nil")")
                    if result != .applied { check(run == before, "\(item.name): rejected receipt cannot change history") }
                case "retry":
                    let result = run.retry(op.stepID!, at: date(op.atMS!))
                    check(result == op.attempt, "\(item.name): retry attempt")
                    if result == nil { check(run == before, "\(item.name): rejected retry cannot change history") }
                case "restore":
                    run = try JSONDecoder().decode(PatrickRoutineRun.self, from: JSONEncoder().encode(run))
                    check(run == before, "\(item.name): exact persistence roundtrip")
                default: preconditionFailure("Unknown fixture operation \(op.type)")
                }
                check(run.isValid, "\(item.name): model remains valid after \(op.type)")
            }
            for status in [PatrickRoutineRun.Status.pending, .succeeded, .failed, .skipped] {
                check(run.steps.filter { $0.status == status }.count == item.expected[status.rawValue],
                      "\(item.name): final \(status.rawValue) count")
            }
        }

        // Stored rows have the same evidence requirements as new receipts.
        var valid = PatrickRoutineRun(at: date(1000))
        let first = PatrickRoutineRun.Receipt(receiptID: UUID(), executionID: valid.id,
            stepID: .focus, attempt: 1, status: .failed, source: .shortcut, note: "first failure", receivedAtMS: 1100)
        check(valid.apply(first, at: date(1100)) == .applied, "Create failed history")
        check(valid.retry(.focus, at: date(1200)) == 2, "Retry records a pending second attempt")
        let success = PatrickRoutineRun.Receipt(receiptID: UUID(), executionID: valid.id,
            stepID: .focus, attempt: 2, status: .succeeded, source: .shortcut, note: "reported success", receivedAtMS: 1300)
        check(valid.apply(success, at: date(1300)) == .applied && valid.isValid, "Create valid retried success")
        try corrupt(valid, "Success cannot exist without its receipts") { $0["events"] = [] }
        try corrupt(valid, "Duplicate receipt IDs cannot validate") { row in
            var events = row["events"] as! [[String: Any]]
            events[1]["receiptID"] = events[0]["receiptID"]; row["events"] = events
        }
        try corrupt(valid, "Previous attempt must have failed before a retry") { row in
            var events = row["events"] as! [[String: Any]]
            events[0]["status"] = "succeeded"; row["events"] = events
        }
        try corrupt(valid, "Receipts cannot come from another run") { row in
            var events = row["events"] as! [[String: Any]]
            events[0]["executionID"] = UUID().uuidString; row["events"] = events
        }
        try corrupt(valid, "Stored receipt source cannot be forged") { row in
            var events = row["events"] as! [[String: Any]]
            events[0]["source"] = "localApp"; row["events"] = events
        }
        try corrupt(valid, "Oversized historical notes are rejected") { row in
            var events = row["events"] as! [[String: Any]]
            events[0]["note"] = String(repeating: "a", count: 241); row["events"] = events
        }
        try corrupt(valid, "Step metadata must match its receipt") { row in
            var steps = row["steps"] as! [[String: Any]]
            steps[0]["note"] = "invented"; row["steps"] = steps
        }
        try corrupt(valid, "A missing attempt cannot be repaired by a larger attempt number") { row in
            var steps = row["steps"] as! [[String: Any]]
            steps[0]["attempt"] = 3; row["steps"] = steps
        }
        try corrupt(valid, "Global timestamps must describe actual step changes") { $0["updatedAtMS"] = 999999 }
        try corrupt(valid, "Pending steps cannot carry forged source metadata") { row in
            var steps = row["steps"] as! [[String: Any]]
            steps[1]["source"] = "shortcut"; row["steps"] = steps
        }
        var invalidNumber = valid; invalidNumber.updatedAtMS = .infinity
        check(!invalidNumber.isValid, "Non-finite state timestamps are invalid")
        invalidNumber = valid; invalidNumber.steps[0].updatedAtMS = .nan
        check(!invalidNumber.isValid, "NaN step timestamps are invalid")

        // Use a real isolated UserDefaults suite, including corruption recovery.
        let suite = "NativeRoutineRunChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PatrickRoutineStore(defaults: defaults)
        let started = store.start(at: date(1000))
        let initialBytes = defaults.data(forKey: PatrickRoutineStore.storageKey)
        check(store.start(id: started.id, at: date(2000)) == started, "Repeated execution ID keeps the original run")
        check(defaults.data(forKey: PatrickRoutineStore.storageKey) == initialBytes, "Repeated start leaves storage unchanged")
        let noop = store.update(id: started.id) { _ in }
        check(noop == started && defaults.data(forKey: PatrickRoutineStore.storageKey) == initialBytes,
              "No-op update leaves storage unchanged")
        check(store.update(id: started.id) { $0.steps[0].status = .succeeded } == nil,
              "Mutation without receipt is refused")
        check(store.load() == [started], "Rejected mutation cannot corrupt persisted history")
        check(store.update(id: started.id) { $0.executionID = UUID() } == nil,
              "A transaction cannot replace a different execution ID")
        check(store.update(id: UUID()) { _ in preconditionFailure("Missing run cannot execute mutation") } == nil,
              "Missing execution remains missing")

        let validRow = try json(valid)
        let initialRow = try json(started)
        let mixedRows: [Any] = [initialRow, ["executionID": "malformed"], 42, validRow, initialRow]
        defaults.set(try JSONSerialization.data(withJSONObject: mixedRows), forKey: PatrickRoutineStore.storageKey)
        let restored = PatrickRoutineStore(defaults: defaults).load()
        check(restored == [valid, started], "Keep valid rows and latest unique IDs despite corrupt neighbours")
        defaults.set(Data("broken JSON".utf8), forKey: PatrickRoutineStore.storageKey)
        check(store.load().isEmpty, "Malformed document is empty history, never fabricated success")
        defaults.removeObject(forKey: PatrickRoutineStore.storageKey)
        var ids: [UUID] = []
        for index in 0..<52 { ids.append(store.start(at: date(Double(1000 + index))).id) }
        check(store.load().map(\.id) == Array(ids.suffix(50)), "Retain exactly the latest 50 runs")
        store.clear()
        check(store.load().isEmpty && defaults.data(forKey: PatrickRoutineStore.storageKey) == nil,
              "Explicit clear removes only the routine history")
        print("PASS: \(checks) native routine-run checks, including \(fixtures.cases.count) shared fixture cases")
    }
}
