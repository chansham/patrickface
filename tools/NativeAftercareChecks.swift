import Foundation

/// Foundation-only checks using the exact browser-policy scenarios. These do
/// not exercise SwiftUI playback, HealthKit, permissions, or an Apple device.
@main struct NativeAftercareChecks {
    struct Fixtures: Decodable { var schemaVersion: Int; var cases: [Fixture] }
    struct Fixture: Decodable { var id: String; var actions: [Action] }
    struct Action: Decodable {
        var op: String
        var nowMS: Double?
        var active: Bool?
        var lowPower: Bool?
        var reduceMotion: Bool?
        var id: String?
        var kind: String?
        var status: String?
        var event: PatrickAftercareCompletion?
        var availableVariants: [String]?
        var variant: String?
    }
    static var assertions = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        assertions += 1
    }
    static func run(_ policy: inout PatrickAftercarePolicy, _ action: Action) -> PatrickAftercareState {
        switch action.op {
        case "visibility": return policy.updateVisibility(active: action.active ?? false,
            lowPower: action.lowPower ?? false, reduceMotion: action.reduceMotion ?? false, nowMS: action.nowMS!)
        case "observe": return policy.observeActivity(id: action.id!, kind: action.kind!, status: action.status!, nowMS: action.nowMS!)
        case "complete": return policy.receiveCompletion(action.event!, nowMS: action.nowMS!, availableVariants: action.availableVariants ?? [])
        case "choose": return policy.choose(action.variant!, nowMS: action.nowMS!)
        case "finish": return policy.finish(nowMS: action.nowMS!)
        case "tick": return policy.tick(nowMS: action.nowMS!)
        case "dismiss": return policy.dismiss()
        case "review": return policy.beginReview(kind: action.kind ?? "exercise", nowMS: action.nowMS!, availableVariants: action.availableVariants ?? [])
        default: preconditionFailure("Unknown fixture operation: \(action.op)")
        }
    }
    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first ?? "preview/aftercare-fixtures.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: data)
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rawCases = raw["cases"] as! [[String: Any]]
        check(fixtures.schemaVersion == 1, "Unexpected fixture schema")
        check(fixtures.cases.count >= 30, "Shared regression scenarios must not disappear")
        check(Set(fixtures.cases.map(\.id)).count == fixtures.cases.count, "Fixture IDs must be unique")
        var operations = 0
        for (caseIndex, fixture) in fixtures.cases.enumerated() {
            var policy = PatrickAftercarePolicy()
            let rawActions = rawCases[caseIndex]["actions"] as! [[String: Any]]
            for (actionIndex, action) in fixture.actions.enumerated() {
                let actual = run(&policy, action)
                var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(actual)) as! [String: Any]
                for key in ["eventID", "kind", "variant", "offeredAtMS", "playingAtMS"] where encoded[key] == nil { encoded[key] = NSNull() }
                if let expected = rawActions[actionIndex]["expected"] as? [String: Any] {
                    for (key, value) in expected {
                        check(NSDictionary(dictionary: [key: encoded[key] ?? NSNull()]).isEqual(to: [key: value]),
                              "\(fixture.id) operation \(actionIndex): \(key)")
                    }
                }
                check(actual == policy.state, "Returned state equals policy state")
                check(actual.availableVariants.allSatisfy(PatrickAftercarePolicy.variants.contains), "Only supported capabilities are offered")
                if actual.phase == .playing { check(actual.variant.map(actual.availableVariants.contains) == true, "Playing requires an available capability") }
                operations += 1
            }
        }
        for value in [Double.nan, .infinity, -.infinity, -1] {
            var policy = PatrickAftercarePolicy()
            policy.updateVisibility(active: true, nowMS: 1000)
            policy.beginReview(nowMS: 2000, availableVariants: ["towel"])
            check(policy.choose("towel", nowMS: value).phase == .dismissed, "Invalid time cannot start playback")
            check(policy.state.reason == "invalidTime", "Invalid time is explicit")
        }
        for value in [Double.nan, .infinity, -.infinity] {
            var policy = PatrickAftercarePolicy()
            policy.updateVisibility(active: true, nowMS: 1000)
            policy.observeActivity(id: "session", kind: "running", status: "running", nowMS: 2000)
            let event = PatrickAftercareCompletion(id: "session", kind: "running", status: "completed", endedAtMS: value)
            check(policy.receiveCompletion(event, nowMS: 3000, availableVariants: ["towel"]).reason == "invalidEvent", "Non-finite completion cannot be offered")
        }
        print("PASS: \(fixtures.cases.count) shared aftercare scenarios; \(operations) operations; \(assertions) native policy checks. No SwiftUI/device execution.")
    }
}
