import XCTest
@testable import PatrickCompanion

final class PatrickContractTests: XCTestCase {
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
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var experience = PatrickExperienceState()
        experience.start(.exercise, seconds: 90, at: now)
        var settings = PatrickSettings.defaults; settings.experience = experience
        let original = PatrickMessageEnvelope.command(PatrickCommandPayload(name: .updateExperience, careAction: .pet), settings: settings)
        let decoded = try PatrickMessageEnvelope.decode(original.encoded())
        XCTAssertEqual(decoded.settings?.experience, experience)
        XCTAssertEqual(decoded.settings?.experience?.activity?.endsAtMS, 1_800_000_090_000)
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
