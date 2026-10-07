import XCTest
@testable import PatrickCompanion

final class PatrickContractTests: XCTestCase {
    func testLifestylePreservesFixedOutfitSoundCareAndRunningOrPausedActivity() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        for outfit in ["auto", "mint-pajama"] {
            for paused in [false, true] {
                for flow in [PatrickLifestyleChoice.goodNight, .goodMorning, .restoreSchedule] {
                    var state = PatrickExperienceState()
                    state.settings.outfitID = outfit
                    state.settings.scene = .celebrate
                    state.settings.soundEnabled = true
                    state.settings.sleepStartMinutes = 1380
                    state.settings.sleepEndMinutes = 420
                    state.start(.running, seconds: 600, at: now)
                    if paused { state.pause(at: now.addingTimeInterval(30)) }
                    let before = state
                    var settings = PatrickSettings.defaults
                    settings.experience = state
                    let result = try XCTUnwrap(PatrickSleepModeMutation.applying(flow.sleepMode, to: settings,
                        experience: state, at: now.addingTimeInterval(31)))
                    let applied = try XCTUnwrap(result.experience)
                    var expectedPreferences = before.settings
                    expectedPreferences.scene = flow == .goodNight ? .sleeping : flow == .goodMorning ? .awake : .automatic
                    XCTAssertEqual(applied.settings, expectedPreferences)
                    XCTAssertEqual(result.sleepMode, flow.sleepMode)
                    XCTAssertEqual(applied.activity, before.activity, "A routine cannot cancel, resume or complete an existing activity")
                    XCTAssertEqual(applied.care, before.care)
                    XCTAssertEqual(applied.journal, before.journal)
                    XCTAssertEqual(applied.processedActionIDs, before.processedActionIDs)
                    XCTAssertEqual(applied.calendarCelebrationKeys, before.calendarCelebrationKeys)
                    XCTAssertEqual(applied.surprise, before.surprise)
                    XCTAssertEqual(applied.revision, before.revision + 1)
                    XCTAssertEqual(result.revision, settings.revision + 1)
                }
            }
        }
    }

    func testLifestyleEarlyMorningOverrideDiffersFromRestoringSchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 5)))
        var state = PatrickExperienceState()
        state.settings.scene = .sleeping
        state.settings.sleepStartMinutes = 1320
        state.settings.sleepEndMinutes = 360
        XCTAssertTrue(state.settings.isSleepTime(now, calendar: calendar), "The 05:00 fixture is still inside the configured sleep window")
        var settings = PatrickSettings.defaults
        settings.sleepMode = .on
        settings.experience = state
        let morning = try XCTUnwrap(PatrickSleepModeMutation.applying(PatrickLifestyleChoice.goodMorning.sleepMode,
            to: settings, experience: state, at: now))
        XCTAssertEqual(morning.sleepMode, .off)
        XCTAssertEqual(morning.experience?.settings.scene, .awake, "Explicit early waking must not remain in automatic sleep")
        let restored = try XCTUnwrap(PatrickSleepModeMutation.applying(PatrickLifestyleChoice.restoreSchedule.sleepMode,
            to: morning, experience: try XCTUnwrap(morning.experience), at: now.addingTimeInterval(1)))
        XCTAssertEqual(restored.sleepMode, .automatic)
        XCTAssertEqual(restored.experience?.settings.scene, .automatic)
        XCTAssertEqual(restored.experience?.settings.sleepStartMinutes, 1320)
        XCTAssertEqual(restored.experience?.settings.sleepEndMinutes, 360)
        XCTAssertTrue(try XCTUnwrap(restored.experience).settings.isSleepTime(now, calendar: calendar))
    }

    func testLifestyleRepeatIsIdempotentAfterPersistenceAndHasNoActionPayload() throws {
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        for mode in [PatrickSleepMode.on, .off, .automatic] {
            let current = store.loadSettings()
            let applied = try XCTUnwrap(PatrickSleepModeMutation.applying(mode, to: current,
                experience: store.loadExperience(), at: now))
            store.saveExperience(try XCTUnwrap(applied.experience))
            store.saveSettings(applied)
            let reopened = PatrickSharedStore(defaults: defaults)
            XCTAssertEqual(reopened.loadSettings(), applied)
            XCTAssertNil(PatrickSleepModeMutation.applying(mode, to: reopened.loadSettings(),
                experience: reopened.loadExperience(), at: now.addingTimeInterval(60)), "Repeating a preset must not write a revision or send a new command")
            let payload = PatrickCommandPayload(name: .setSleepMode, sleepMode: mode)
            let wire = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.command(payload, settings: applied).encoded())
            XCTAssertEqual(wire.command?.name, .setSleepMode)
            XCTAssertEqual(wire.command?.sleepMode, mode)
            XCTAssertNil(wire.command?.careAction)
            XCTAssertNil(wire.command?.automationEvent)
            XCTAssertNil(wire.command?.timer)
            XCTAssertNil(wire.command?.deepLink)
            XCTAssertEqual(wire.settings?.experience, applied.experience)
        }
    }

    func testAutomationReceiptSurvivesReloadWithoutRestoringPlaybackPermission() throws {
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        let event = PatrickAutomationEvent(kind: .alarmStopped, source: .shortcut, at: now)
        var gate = PatrickAutomationGate()
        gate.setPresentationActive(true, at: now)
        XCTAssertEqual(gate.consume(event, at: now), .play)
        store.saveAutomationReceiptIDs(gate.receivedIDs)
        let reopened = PatrickSharedStore(defaults: defaults)
        var restored = PatrickAutomationGate(receivedIDs: reopened.loadAutomationReceiptIDs())
        XCTAssertEqual(restored.consume(event, at: now.addingTimeInterval(0.1)), .duplicate)
        let newEvent = PatrickAutomationEvent(kind: .wakeUp, source: .manual, at: now.addingTimeInterval(0.2))
        XCTAssertEqual(restored.consume(newEvent, at: now.addingTimeInterval(0.2)), .recordOnly)
        store.resetLocalData()
        XCTAssertTrue(store.loadAutomationReceiptIDs().isEmpty)
    }

    func testAutomationCommandPreservesMillisecondsAndDoesNotMutatePreferences() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        let event = PatrickAutomationEvent(kind: .wakeUp, source: .manual, at: now)
        var experience = PatrickExperienceState()
        experience.settings.scene = .sleeping
        experience.settings.outfitID = "mint-pajama"
        let settingsBefore = experience.settings, careBefore = experience.care
        XCTAssertTrue(experience.recordAutomation(event, at: now))
        XCTAssertFalse(experience.recordAutomation(event, at: now))
        var settings = PatrickSettings.defaults; settings.experience = experience
        let wire = PatrickMessageEnvelope.command(PatrickCommandPayload(name: .updateExperience, automationEvent: event), settings: settings)
        let decoded = try PatrickMessageEnvelope.decode(wire.encoded())
        XCTAssertEqual(decoded.command?.automationEvent, event)
        XCTAssertEqual(decoded.command?.automationEvent?.occurredAtMS, 1_800_000_000_375)
        XCTAssertEqual(decoded.settings?.experience?.settings, settingsBefore)
        XCTAssertEqual(decoded.settings?.experience?.care, careBefore)
        XCTAssertEqual(decoded.settings?.experience?.journal.count, 1)
        let old = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.command(PatrickCommandPayload(name: .updateExperience)).encoded())
        XCTAssertNil(old.command?.automationEvent)
    }

    func testLiveActivityContentHonorsInitialRunningAndPausedSnapshots() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var settings = PatrickSettings.defaults
        settings.theme = .faithful3D
        var experience = PatrickExperienceState()
        experience.start(.walking, seconds: 120, at: now)
        let running = PatrickTimerSnapshot.resolving(.inactive, experience: experience, at: now)
        let initial = PatrickActivityController.contentState(timer: running, settings: settings)
        XCTAssertFalse(initial.isPaused)
        XCTAssertEqual(initial.statusText, "Timer running")
        XCTAssertEqual(initial.endsAt, now.addingTimeInterval(120))
        XCTAssertEqual(initial.theme, settings.theme)

        experience.controlActivity(.pause, at: now.addingTimeInterval(30))
        let paused = PatrickTimerSnapshot.resolving(.inactive, experience: experience, at: now.addingTimeInterval(30))
        let firstReceived = PatrickActivityController.contentState(timer: paused, settings: settings)
        XCTAssertTrue(firstReceived.isPaused, "A first handoff may already be paused")
        XCTAssertEqual(firstReceived.statusText, "Timer paused")
        XCTAssertNil(firstReceived.endsAt, "Paused presentation must not count down")
        XCTAssertEqual(firstReceived.theme, settings.theme)
        XCTAssertEqual(firstReceived.visualState, settings.previewState)
    }

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
