import XCTest
@testable import PatrickCompanion

final class PatrickContractTests: XCTestCase {
    func testNamedExerciseTimersSurviveWatchEnvelopeAndPersistence() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)
        for kind in [PatrickActivityKind.walking, .running, .strength] {
            var experience = PatrickExperienceState()
            experience.start(kind, seconds: 120, at: now)
            XCTAssertEqual(experience.controlActivity(.pause, at: now.addingTimeInterval(30)), .paused)
            store.saveExperience(experience)
            XCTAssertEqual(store.loadExperience(), experience)
            var settings = PatrickSettings.defaults; settings.experience = experience
            let decoded = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.snapshot(settings: settings).encoded())
            let incoming = try XCTUnwrap(decoded.settings?.experience)
            XCTAssertEqual(incoming.activity?.kind, kind)
            XCTAssertEqual(incoming.activity?.remainingSeconds, 90)
            XCTAssertEqual(kind.sceneID, "exercise")
            XCTAssertEqual(kind.clipID, "exercise", "Specific labels share existing exercise art")
        }
    }

    func testLateTimerControlCompletesOnceAndKeepsCompanionPresentationConsistent() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for command in PatrickActivityControl.allCases {
            var state = PatrickExperienceState()
            state.start(.running, seconds: 60, at: now)
            XCTAssertEqual(state.controlActivity(command, at: now.addingTimeInterval(60)), .completed)
            let revision = state.revision
            XCTAssertEqual(state.controlActivity(command, at: now.addingTimeInterval(61)), .completed)
            XCTAssertEqual(state.revision, revision)
            XCTAssertEqual(state.care.bond, 1)
            XCTAssertEqual(state.journal.filter { $0.text == "完成跑步陪伴" }.count, 1)
            let presentation = PatrickTimerSnapshot.resolving(.inactive, experience: state, at: now.addingTimeInterval(61))
            XCTAssertEqual(presentation.status, .complete)
        }
    }

    func testNewExperienceTimerWinsOverLegacyTimerInSameEnvelope() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = PatrickTimerSnapshot(id: UUID(), status: .running, title: "Old timer A", startedAt: now,
            endsAt: now.addingTimeInterval(900), remainingSeconds: nil)
        var experience = PatrickExperienceState()
        experience.start(.exercise, seconds: 60, at: now)
        experience.pause(at: now.addingTimeInterval(20))
        let effective = PatrickTimerSnapshot.resolving(old, experience: experience, at: now.addingTimeInterval(30))
        XCTAssertEqual(effective.id, experience.activity?.id)
        XCTAssertNotEqual(effective.id, old.id)
        XCTAssertEqual(effective.status, .paused)
        XCTAssertEqual(effective.remainingSeconds, 40)
    }
    func testExperienceWireRoundTripUsesMilliseconds() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        var experience = PatrickExperienceState()
        experience.start(.exercise, seconds: 90, at: now)
        var settings = PatrickSettings.defaults; settings.experience = experience
        let original = PatrickMessageEnvelope.command(PatrickCommandPayload(name: .updateExperience, careAction: .pet), settings: settings)
        let decoded = try PatrickMessageEnvelope.decode(original.encoded())
        XCTAssertEqual(decoded.settings?.experience, experience)
        XCTAssertEqual(decoded.settings?.experience?.activity?.endsAtMS, 1_800_000_090_375)
        XCTAssertEqual(decoded.command?.careAction, .pet)
    }
    func testOldSnapshotWithoutExperienceRemainsReadable() throws {
        let data = try PatrickMessageEnvelope.snapshot(settings: .defaults).encoded()
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var settings = object["settings"] as! [String: Any]
        settings.removeValue(forKey: "experience"); object["settings"] = settings
        let decoded = try PatrickMessageEnvelope.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.settings?.experience)
        XCTAssertEqual(decoded.protocolVersion, 1)
    }

    func testMessageRoundTripPreservesThemeAndProtocol() throws {
        var settings = PatrickSettings.defaults
        settings.theme = .faithful3D
        let original = PatrickMessageEnvelope.snapshot(settings: settings)

        let decoded = try PatrickMessageEnvelope.decode(original.encoded())

        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.settings?.theme, .faithful3D)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testDeepLinksRoundTrip() {
        let routes: [PatrickDeepLinkRoute] = [
            .controlCenter,
            .setTheme(.cel1999),
            .setTheme(.faithful3D),
            .setSleepMode(.automatic),
            .setSleepMode(.on),
            .playThemeSound,
            .openWatchFace,
            .timer,
        ]

        for route in routes {
            XCTAssertEqual(PatrickDeepLinkRoute(url: route.url), route)
        }
    }

    func testSharedStorePersistsOnlyCodablePresentationState() {
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)

        let value = store.updateSettings {
            $0.theme = .faithful3D
            $0.previewState = .charging
            $0.sleepMode = .on
        }

        XCTAssertEqual(store.loadSettings(), value)
        XCTAssertEqual(value.revision, 1)
    }

    func testLegacyTimestampMatchesDiskAndWireWithoutLosingRevisionOrder() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.875)
        let first = PatrickSettings.defaults.nextRevision(at: now)
        let second = first.nextRevision(at: now.addingTimeInterval(0.1))
        XCTAssertEqual(first.updatedAt.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(second.updatedAt, first.updatedAt)
        XCTAssertEqual(second.revision, first.revision + 1)
        let decoded = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.snapshot(settings: first).encoded())
        XCTAssertEqual(decoded.settings, first)
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)
        store.saveSettings(first)
        XCTAssertEqual(store.loadSettings(), first)
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: PatrickAppGroup.settingsKey))) as! [String: Any]
        let timestamp = try XCTUnwrap(json["updatedAt"] as? String)
        XCTAssertTrue(timestamp.hasSuffix("Z") && !timestamp.contains("."), "Existing v1 ISO 8601 shape remains unchanged")
    }

    func testPendingSoundPreservesPrecisionAndReadsOldActions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.875)
        let action = PendingPatrickAction(id: UUID(), kind: .playThemeSound, createdAt: now,
                                          createdAtMS: now.timeIntervalSince1970 * 1000)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(PendingPatrickAction.self, from: data)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(decoded.effectiveCreatedAt, now)
        XCTAssertTrue(decoded.effectiveCreatedAt > now.addingTimeInterval(-0.1), "A fresh request must not appear older than the latest quiet boundary")
        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        old.removeValue(forKey: "createdAtMS")
        let migrated = try decoder.decode(PendingPatrickAction.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(migrated.createdAtMS)
        XCTAssertEqual(migrated.effectiveCreatedAt, decoded.createdAt)
    }

    func testDuplicateWatchMessageIsRejected() {
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)
        let id = UUID()

        XCTAssertTrue(store.markMessageProcessed(id))
        XCTAssertFalse(store.markMessageProcessed(id))
    }
}
