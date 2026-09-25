import XCTest
@testable import PatrickCompanion

final class PatrickContractTests: XCTestCase {
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
