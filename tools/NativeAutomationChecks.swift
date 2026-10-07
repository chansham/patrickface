import Foundation

@main struct NativeAutomationChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); count += 1
    }
    struct Fixtures: Decodable { let schemaVersion: Int; let cases: [Case] }
    struct Case: Decodable { let name: String; let steps: [Step] }
    struct Step: Decodable {
        let type: String
        let atMS: Double
        let active: Bool?
        let event: PatrickAutomationEvent?
        let outcome: String?
        let seenCount: Int?
    }
    static func name(_ outcome: PatrickAutomationGate.Outcome) -> String {
        switch outcome { case .invalid: "invalid"; case .duplicate: "duplicate"; case .recordOnly: "recordOnly"; case .play: "play" }
    }
    static func main() throws {
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: fixtureURL))
        check(fixtures.schemaVersion == 1, "Fixture version")
        for fixture in fixtures.cases {
            var gate = PatrickAutomationGate()
            for step in fixture.steps {
                let now = Date(timeIntervalSince1970: step.atMS / 1000)
                switch step.type {
                case "presentation": gate.setPresentationActive(step.active!, at: now)
                case "restart": gate = PatrickAutomationGate(receivedIDs: gate.receivedIDs)
                default:
                    check(name(gate.consume(step.event!, at: now)) == step.outcome, fixture.name)
                    check(gate.receivedIDs.count == step.seenCount, "Receipt count: " + fixture.name)
                }
            }
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000.375)
        let event = PatrickAutomationEvent(kind: .alarmStopped, source: .shortcut, at: date)
        let decoded = try JSONDecoder().decode(PatrickAutomationEvent.self, from: JSONEncoder().encode(event))
        check(decoded == event && decoded.occurredAtMS == 1_800_000_000_375, "Event retains epoch milliseconds")
        let envelope = PatrickMessageEnvelope.command(PatrickCommandPayload(name: .updateExperience, automationEvent: event))
        let wire = try PatrickMessageEnvelope.decode(envelope.encoded())
        check(wire.command?.automationEvent == event, "Optional v1 command retains event and milliseconds")
        let oldWire = PatrickMessageEnvelope.command(PatrickCommandPayload(name: .updateExperience))
        let oldDecoded = try PatrickMessageEnvelope.decode(oldWire.encoded())
        check(oldDecoded.command?.automationEvent == nil, "Existing v1 command decodes without event")
        let snapshot = PatrickMessageEnvelope.snapshot(settings: .defaults)
        check(snapshot.command == nil, "Snapshot contains no playback command")
        var state = PatrickExperienceState()
        let oldSettings = state.settings, oldCare = state.care
        check(state.recordAutomation(event, at: date), "Origin records first event")
        check(!state.recordAutomation(event, at: date.addingTimeInterval(1)), "Origin duplicate is not a second journal entry")
        check(state.journal.count == 1 && state.journal[0].text == event.journalText, "Journal accurately labels explicit shortcut source")
        check(state.settings == oldSettings && state.care == oldCare && state.activity == nil, "No hidden scene, outfit, sleep, reward or timer change")
        check(state.journal[0].atMS == event.occurredAtMS, "Journal retains the event time")
        check(event.clipKey == "wake", "Use existing wake art")
        let restored = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONEncoder().encode(state))
        check(restored == state, "Journal and de-dup survive persistence")
        var gate = PatrickAutomationGate()
        gate.setPresentationActive(true, at: date)
        for value in [Double.nan, .infinity, -.infinity, 0, -1] {
            var invalid = event; invalid.occurredAtMS = value
            check(gate.consume(invalid, at: date) == .invalid, "Reject invalid timestamp")
        }
        check(gate.receivedIDs.isEmpty, "Invalid events are not receipts")
        for i in 0..<105 {
            let nextDate = date.addingTimeInterval(Double(i))
            let next = PatrickAutomationEvent(kind: .wakeUp, source: .manual, at: nextDate)
            check(gate.consume(next, at: nextDate) == .play, "Visible explicit events remain functional")
        }
        check(gate.receivedIDs.count == 100, "Bound receipt storage")
        print("Native automation checks passed: \(count)")
    }
}
