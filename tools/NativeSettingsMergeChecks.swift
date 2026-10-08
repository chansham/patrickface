import Foundation

@main struct NativeSettingsMergeChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); count += 1
    }
    struct Fixtures: Decodable { var schemaVersion: Int; var cases: [Case] }
    struct Case: Decodable { var name: String; var local: Side; var incoming: Side; var expected: Expected }
    struct Side: Decodable {
        var scene: PatrickExperienceScene?; var revision: UInt64?; var atMS: Double?
        var legacyRevision: UInt64; var sleepMode: String
        func state() -> PatrickExperienceState? {
            guard let scene, let revision, let atMS else { return nil }
            var value = PatrickExperienceState()
            value.settings.scene = scene; value.settings.outfitID = "mint-pajama"; value.settings.soundEnabled = true
            value.start(.running, seconds: 600, at: Date(timeIntervalSince1970: 50))
            value.pause(at: Date(timeIntervalSince1970: 60))
            value.care.bond = 8; value.care.totalFeeds = 3
            value.revision = revision; value.updatedAtMS = atMS
            return value
        }
    }
    struct Expected: Decodable {
        var scene: PatrickExperienceScene; var mode: String
        var acceptsLegacy: Bool; var acceptsExperience: Bool; var source: String
    }
    static func main() throws {
        let fixtures = try JSONDecoder().decode(Fixtures.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        check(fixtures.schemaVersion == 1, "Fixture schema")
        let now = Date(timeIntervalSince1970: 400.375)
        for item in fixtures.cases {
            let local = item.local.state()!, incoming = item.incoming.state()
            let result = PatrickSettingsMerge.resolve(localExperience: local, incomingExperience: incoming,
                localRevision: item.local.legacyRevision, incomingRevision: item.incoming.legacyRevision,
                localSleepMode: item.local.sleepMode, incomingSleepMode: item.incoming.sleepMode, at: now)
            check(result.experience.settings.scene == item.expected.scene, item.name + ": winning scene")
            check(result.sleepModeRawValue == item.expected.mode, item.name + ": corresponding legacy mode")
            check(result.acceptsLegacySettings == item.expected.acceptsLegacy, item.name + ": legacy header decision")
            check(result.acceptedIncomingExperience == item.expected.acceptsExperience, item.name + ": experience decision")
            check(result.hasModernExperience == (incoming != nil), item.name + ": presence is not freshness")
            var expected = item.expected.source == "incoming" ? incoming! : local
            if item.expected.source == "legacy" {
                expected.settings.scene = item.expected.scene; expected.changed(at: now)
            }
            check(result.experience == expected, item.name + ": activity, sound, outfit, care and journal preserved")
            let persisted = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONEncoder().encode(result.experience))
            check(persisted == expected, item.name + ": stored state retains millisecond identity")
            let repeated = PatrickSettingsMerge.resolve(localExperience: persisted, incomingExperience: persisted,
                localRevision: max(item.local.legacyRevision, item.incoming.legacyRevision),
                incomingRevision: max(item.local.legacyRevision, item.incoming.legacyRevision),
                localSleepMode: result.sleepModeRawValue, incomingSleepMode: item.incoming.sleepMode,
                at: now.addingTimeInterval(10))
            check(repeated.experience == persisted, item.name + ": snapshot/command double delivery makes no new revision")
        }
        print("PASS: \(count) native settings merge checks (Foundation only; no device transport).")
    }
}
