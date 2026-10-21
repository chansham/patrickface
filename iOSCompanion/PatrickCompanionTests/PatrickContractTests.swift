import XCTest
@testable import PatrickCompanion

final class PatrickContractTests: XCTestCase {
    @MainActor func testBreakIntentSavesOnceAndReturnsPersistedOriginalWithoutExtendingOnRepeat() throws {
        let suite = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        var original = PatrickExperienceState()
        original.settings.outfitID = "mint-pajama"
        original.settings.scene = .focus
        original.start(.focus, seconds: 600, at: now)
        store.saveExperience(original)
        var initialSettings = PatrickSettings.defaults
        initialSettings.experience = original
        store.saveSettings(initialSettings)
        var deliveries: [PatrickSettings] = []

        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.takeBreak, breakMinutes: 3,
            using: store, at: now.addingTimeInterval(30), deliver: { deliveries.append($0) }), .rest(.started(.focus)))
        let resting = store.loadExperience()
        XCTAssertEqual(resting.breakSession?.savedActivity.id, original.activity?.id)
        XCTAssertEqual(resting.breakSession?.savedActivity.remainingSeconds, 570)
        XCTAssertEqual(resting.activity?.kind, .breathing)
        XCTAssertEqual(resting.activity?.endsAt, now.addingTimeInterval(210))
        XCTAssertEqual(resting.settings, original.settings)
        XCTAssertEqual(deliveries.count, 1)
        XCTAssertEqual(deliveries.last?.experience, resting)
        let persistedBytes = defaults.data(forKey: PatrickAppGroup.settingsKey)
        let reopened = PatrickSharedStore(defaults: defaults)
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.takeBreak, breakMinutes: 15,
            using: reopened, at: now.addingTimeInterval(40), deliver: { deliveries.append($0) }), .rest(.alreadySaved))
        XCTAssertEqual(defaults.data(forKey: PatrickAppGroup.settingsKey), persistedBytes)
        XCTAssertEqual(reopened.loadExperience(), resting)
        XCTAssertEqual(deliveries.count, 1, "A repeated break cannot rewrite or send a new command")

        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.returnToActivity,
            using: reopened, at: now.addingTimeInterval(100), deliver: { deliveries.append($0) }),
            .rest(.returned(.focus, running: true)))
        let returned = reopened.loadExperience()
        XCTAssertEqual(returned.activity?.id, original.activity?.id)
        XCTAssertEqual(returned.activity?.endsAt, now.addingTimeInterval(670))
        XCTAssertNil(returned.breakSession)
        XCTAssertEqual(returned.care.bond, 0, "Returning early cancels the break without a completion reward")
        XCTAssertEqual(deliveries.count, 2)
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.returnToActivity,
            using: reopened, at: now.addingTimeInterval(101), deliver: { deliveries.append($0) }), .rest(.nothingSaved))
        XCTAssertEqual(reopened.loadExperience(), returned)
        XCTAssertEqual(deliveries.count, 2)
        let wire = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.snapshot(settings: deliveries[1]).encoded())
        XCTAssertEqual(wire.settings?.experience, returned)
        XCTAssertTrue(reopened.consumePendingActions().isEmpty, "No delayed animation or sound is queued by a break")
    }

    @MainActor func testBreakIntentKeepsPausedOriginalThroughPauseResumeAndCancelOfBreak() throws {
        let suite = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = PatrickExperienceState(); state.start(.strength, seconds: 300, at: now)
        state.pause(at: now.addingTimeInterval(20))
        let original = try XCTUnwrap(state.activity)
        store.saveExperience(state)
        var deliveries: [PatrickSettings] = []
        let send: (PatrickSettings) -> Void = { deliveries.append($0) }
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.takeBreak,
            using: store, at: now.addingTimeInterval(100), deliver: send), .rest(.started(.strength)))
        let saved = store.loadExperience().breakSession
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.pause,
            using: store, at: now.addingTimeInterval(110), deliver: send), .activity(.paused))
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.resume,
            using: store, at: now.addingTimeInterval(120), deliver: send), .activity(.resumed))
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.cancel,
            using: store, at: now.addingTimeInterval(130), deliver: send), .activity(.cancelled))
        XCTAssertEqual(store.loadExperience().breakSession, saved)
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.returnToActivity,
            using: store, at: now.addingTimeInterval(500), deliver: send), .rest(.returned(.strength, running: false)))
        XCTAssertEqual(store.loadExperience().activity, original, "A pre-existing pause is not converted into running work")
        XCTAssertEqual(store.loadExperience().care.bond, 0)
        XCTAssertEqual(deliveries.count, 5)
    }

    @MainActor func testExpiredBreakIntentSettlesOnceAndWaitsForExplicitReturn() throws {
        let suite = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = PatrickExperienceState(); state.start(.running, seconds: 600, at: now)
        let originalID = state.activity?.id
        store.saveExperience(state)
        var deliveries: [PatrickSettings] = []
        let send: (PatrickSettings) -> Void = { deliveries.append($0) }
        _ = PatrickTimerControlIntentExecutor.control(.takeBreak, breakMinutes: 1,
            using: store, at: now.addingTimeInterval(30), deliver: send)
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.takeBreak, breakMinutes: 5,
            using: store, at: now.addingTimeInterval(1000), deliver: send), .rest(.alreadySaved))
        let settled = store.loadExperience()
        XCTAssertEqual(settled.activity?.status, .completed)
        XCTAssertEqual(settled.breakSession?.savedActivity.id, originalID)
        XCTAssertEqual(settled.breakSession?.savedActivity.remainingSeconds, 570)
        XCTAssertEqual(settled.care.bond, 0)
        XCTAssertEqual(deliveries.count, 2, "The expired break must be persisted even when the requested new break is refused")
        _ = PatrickTimerControlIntentExecutor.control(.takeBreak,
            using: store, at: now.addingTimeInterval(1001), deliver: send)
        XCTAssertEqual(store.loadExperience(), settled)
        XCTAssertEqual(deliveries.count, 2)
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.returnToActivity,
            using: store, at: now.addingTimeInterval(1002), deliver: send), .rest(.returned(.running, running: true)))
        XCTAssertEqual(store.loadExperience().activity?.endsAt, now.addingTimeInterval(1572))
        XCTAssertEqual(store.loadExperience().care.bond, 0)
    }

    @MainActor func testBreakIntentEmptyAndExpiredOriginalNeverCreatesAnUnattachedBreak() throws {
        let suite = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var deliveries: [PatrickSettings] = []
        let send: (PatrickSettings) -> Void = { deliveries.append($0) }
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.takeBreak,
            using: store, at: now, deliver: send), .rest(.noActiveActivity))
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.returnToActivity,
            using: store, at: now, deliver: send), .rest(.nothingSaved))
        XCTAssertTrue(deliveries.isEmpty)
        XCTAssertNil(defaults.data(forKey: PatrickAppGroup.settingsKey))
        var state = PatrickExperienceState(); state.start(.focus, seconds: 60, at: now)
        store.saveExperience(state)
        XCTAssertEqual(PatrickTimerControlIntentExecutor.control(.takeBreak,
            using: store, at: now.addingTimeInterval(60), deliver: send), .rest(.noActiveActivity))
        let expired = store.loadExperience()
        XCTAssertNil(expired.breakSession)
        XCTAssertEqual(expired.activity?.status, .completed)
        XCTAssertEqual(expired.care.bond, 0)
        XCTAssertEqual(deliveries.count, 1)
        _ = PatrickTimerControlIntentExecutor.control(.takeBreak,
            using: store, at: now.addingTimeInterval(61), deliver: send)
        XCTAssertEqual(store.loadExperience(), expired)
        XCTAssertEqual(deliveries.count, 1)
    }

    @MainActor func testBreakIntentUsesSharedDurationBounds() throws {
        for (requested, expected) in [(-1, 60.0), (3, 180.0), (999, 900.0)] {
            let suite = "PatrickContractTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = PatrickSharedStore(defaults: defaults)
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var state = PatrickExperienceState(); state.start(.focus, seconds: 600, at: now)
            store.saveExperience(state)
            _ = PatrickTimerControlIntentExecutor.control(.takeBreak, breakMinutes: requested,
                using: store, at: now.addingTimeInterval(30), deliver: { _ in })
            XCTAssertEqual(store.loadExperience().activity?.remainingSeconds, expected)
            XCTAssertEqual(store.loadExperience().activity?.endsAt, now.addingTimeInterval(30 + expected))
            XCTAssertEqual(store.loadExperience().breakSession?.savedActivity.remainingSeconds, 570)
        }
    }

    func testBreakSurvivesSleepMergeWireAndReloadWithoutAutomaticReturn() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        var state = PatrickExperienceState(); state.start(.running, seconds: 600, at: now)
        let originalID = try XCTUnwrap(state.activity?.id)
        XCTAssertEqual(state.manageBreak(.begin(minutes: 1), at: now.addingTimeInterval(30)), .started(.running))
        let saved = try XCTUnwrap(state.breakSession)
        var settings = PatrickSettings.defaults; settings.experience = state
        let sleeping = try XCTUnwrap(PatrickSleepModeMutation.applying(.on, to: settings, experience: state, at: now.addingTimeInterval(31)))
        let wire = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.snapshot(settings: sleeping).encoded())
        let incoming = try XCTUnwrap(wire.settings?.experience)
        let merged = PatrickSettingsMerge.resolve(localExperience: state, incomingExperience: incoming,
            localRevision: 1, incomingRevision: 2, localSleepMode: "automatic", incomingSleepMode: "on")
        XCTAssertEqual(merged.experience.breakSession, saved)
        let suite = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        merged.experience.save(to: defaults)
        var reopened = PatrickExperienceState.load(from: defaults)
        XCTAssertNotNil(reopened.reconcile(at: now.addingTimeInterval(1000)))
        XCTAssertEqual(reopened.activity?.status, .completed)
        XCTAssertEqual(reopened.breakSession?.savedActivity.remainingSeconds, 570)
        XCTAssertEqual(reopened.settings.scene, .sleeping)
        XCTAssertEqual(reopened.care.bond, 0)
        XCTAssertEqual(reopened.manageBreak(.returnToActivity, at: now.addingTimeInterval(1001)), .returned(.running, running: true))
        XCTAssertEqual(reopened.activity?.id, originalID)
        XCTAssertEqual(reopened.activity?.endsAt, now.addingTimeInterval(1571))
        XCTAssertEqual(reopened.settings.scene, .sleeping, "Returning must not change a later scene selection")
        let afterReturn = reopened
        XCTAssertEqual(reopened.manageBreak(.returnToActivity, at: now.addingTimeInterval(1002)), .nothingSaved)
        XCTAssertEqual(reopened, afterReturn)
    }

    func testBreakPauseCancelAndNewStartCannotLoseSavedTask() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = PatrickExperienceState(); state.start(.focus, seconds: 300, at: now)
        state.pause(at: now.addingTimeInterval(20))
        let original = try XCTUnwrap(state.activity)
        _ = state.manageBreak(.begin(minutes: 3), at: now.addingTimeInterval(100))
        let duringBreak = state
        XCTAssertEqual(state.manageBreak(.begin(minutes: 5), at: now.addingTimeInterval(101)), .alreadySaved)
        XCTAssertEqual(state.requestActivityStart(.walking, minutes: 5, at: now.addingTimeInterval(102)), .savedActivityPending(.focus))
        state.start(.exercise, seconds: 30, at: now.addingTimeInterval(102))
        XCTAssertEqual(state, duringBreak)
        XCTAssertEqual(state.controlActivity(.cancel, at: now.addingTimeInterval(110)), .cancelled)
        XCTAssertNotNil(state.breakSession)
        XCTAssertEqual(state.manageBreak(.returnToActivity, at: now.addingTimeInterval(500)), .returned(.focus, running: false))
        XCTAssertEqual(state.activity, original)
        XCTAssertEqual(state.care.bond, 0)
        let presentation = PatrickTimerSnapshot.resolving(.inactive, experience: state, at: now.addingTimeInterval(501))
        XCTAssertEqual(presentation.status, .paused)
        XCTAssertEqual(presentation.remainingSeconds, 280)
    }

    @MainActor func testRepeatedLifestyleRetriesOnlyPersistedSnapshotWithoutNewAction() throws {
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        for mode in [PatrickSleepMode.on, .off, .automatic] {
            var experience = PatrickExperienceState()
            experience.settings.scene = .celebrate
            experience.settings.outfitID = "mint-pajama"
            experience.settings.soundEnabled = true
            experience.start(.running, seconds: 600, at: now)
            experience.pause(at: now.addingTimeInterval(30))
            var initial = PatrickSettings.defaults; initial.experience = experience
            let saved = try XCTUnwrap(PatrickSleepModeMutation.applying(mode, to: initial,
                experience: experience, at: now.addingTimeInterval(31)))
            store.saveSettings(saved); store.saveExperience(try XCTUnwrap(saved.experience))
            let settingsBytes = defaults.data(forKey: PatrickAppGroup.settingsKey)
            var deliveries: [PatrickSettings] = []
            for _ in 0..<2 {
                let result = PatrickIntentExecutor.setSleepMode(mode, using: store, retrySnapshot: { deliveries.append($0) })
                XCTAssertEqual(result, saved)
            }
            XCTAssertEqual(deliveries, [saved, saved], "An explicit repeat retries even after the first process could not deliver")
            XCTAssertEqual(defaults.data(forKey: PatrickAppGroup.settingsKey), settingsBytes)
            XCTAssertEqual(store.loadSettings(), saved)
            XCTAssertEqual(store.loadExperience(), saved.experience)
            XCTAssertTrue(store.consumePendingActions().isEmpty)
            for settings in deliveries {
                let envelope = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.snapshot(settings: settings).encoded())
                XCTAssertEqual(envelope.kind, .snapshot)
                XCTAssertEqual(envelope.settings, saved)
                XCTAssertNil(envelope.command, "A retry cannot request animation, sound, care, timer or opening the app")
                XCTAssertNil(envelope.timer)
            }
        }
    }

    func testRoutineStartPreservesRunningAndPausedActivityAcrossStoreReloadAndWire() throws {
        let suiteName = "PatrickContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PatrickSharedStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        for paused in [false, true] {
            for requestedKind in [PatrickActivityKind.running, .focus] {
                var state = PatrickExperienceState()
                state.settings.outfitID = "mint-pajama"; state.settings.soundEnabled = true
                state.start(.running, seconds: 120, at: now)
                if paused { state.pause(at: now.addingTimeInterval(30)) }
                store.saveExperience(state)
                let before = state
                var reopened = PatrickSharedStore(defaults: defaults).loadExperience()
                let date = now.addingTimeInterval(paused ? 3600 : 31)
                let result = reopened.requestActivityStart(requestedKind, minutes: 25, at: date)
                XCTAssertEqual(reopened, before, "Repeated or different routines cannot reset, resume or replace an occupied timer")
                XCTAssertEqual(result, .preserved(activity: try XCTUnwrap(before.activity), remainingSeconds: paused ? 90 : 89))
                XCTAssertTrue(result.message.contains("跑步陪伴"))
                XCTAssertTrue(result.message.contains(paused ? "已暫停" : "仍在進行"))
                XCTAssertTrue(result.message.contains("控制派大星陪伴計時"))
                XCTAssertFalse(result.message.contains("已開始"))
                XCTAssertEqual(store.loadExperience(), before)
                var settings = PatrickSettings.defaults; settings.experience = reopened
                let decoded = try PatrickMessageEnvelope.decode(PatrickMessageEnvelope.snapshot(settings: settings).encoded())
                XCTAssertEqual(decoded.settings?.experience, before)
                let presentation = PatrickTimerSnapshot.resolving(.inactive, experience: reopened, at: date)
                XCTAssertEqual(presentation.id, before.activity?.id)
                XCTAssertEqual(presentation.status, paused ? .paused : .running)
                XCTAssertEqual(presentation.endsAt, paused ? nil : before.activity?.endsAt)
            }
        }
    }

    func testRoutineStartAtDeadlineCompletesOldActivityOnceThenProtectsTheNewOne() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000.375)
        var state = PatrickExperienceState()
        state.start(.walking, seconds: 60, at: now)
        let oldID = try XCTUnwrap(state.activity?.id)
        let revision = state.revision
        let result = state.requestActivityStart(.focus, minutes: 25, at: now.addingTimeInterval(60))
        XCTAssertEqual(result, .started(activity: try XCTUnwrap(state.activity), completedKind: .walking))
        XCTAssertNotEqual(state.activity?.id, oldID)
        XCTAssertEqual(state.activity?.endsAt, now.addingTimeInterval(1560))
        XCTAssertEqual(state.care.bond, 0)
        XCTAssertEqual(state.revision, revision + 2)
        XCTAssertEqual(state.journal.map(\.text), ["開始散步陪伴", "完成散步陪伴", "開始專注"])
        XCTAssertTrue(result.message.contains("散步陪伴」已完成"))
        let after = state
        _ = state.requestActivityStart(.focus, minutes: 25, at: now.addingTimeInterval(60.001))
        XCTAssertEqual(state, after, "A repeat must not re-journal, re-reward or extend the new session")
        let presentation = PatrickTimerSnapshot.resolving(.inactive, experience: state, at: now.addingTimeInterval(61))
        XCTAssertEqual(presentation.id, state.activity?.id)
        XCTAssertEqual(presentation.status, .running)
        XCTAssertEqual(presentation.endsAt, now.addingTimeInterval(1560))
    }

    func testRoutineStartOnlyUsesEmptyOrTerminalActivitySlot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let statuses: [PatrickLocalActivity.Status?] = [.cancelled, .completed, nil]
        for terminal in statuses {
            var state = PatrickExperienceState()
            if let terminal {
                state.start(.strength, seconds: 60, at: now)
                if terminal == .completed { _ = state.reconcile(at: now.addingTimeInterval(60)) }
                else { state.cancel(at: now.addingTimeInterval(30)) }
            }
            let before = state
            let result = state.requestActivityStart(.breathing, minutes: 1, at: now.addingTimeInterval(90))
            XCTAssertEqual(result, .started(activity: try XCTUnwrap(state.activity), completedKind: nil))
            XCTAssertEqual(state.activity?.kind, .breathing)
            XCTAssertEqual(state.activity?.durationSeconds, 60)
            XCTAssertEqual(state.care, before.care)
            XCTAssertEqual(state.settings, before.settings)
            XCTAssertEqual(state.journal.count, before.journal.count + 1)
            XCTAssertEqual(state.revision, before.revision + 1)
        }
    }

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
            XCTAssertEqual(state.care.bond, 0)
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

    func testDayPlanBaselineHolidayGapAndGate() {
        let calendar = PatrickHKHolidays.calendar
        func hk(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
            var parts = DateComponents()
            parts.calendar = calendar
            parts.timeZone = calendar.timeZone
            parts.year = 2026
            parts.month = month
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return parts.date!
        }
        XCTAssertNil(PatrickDayPlan.nightTarget(enabled: false, skipRestDays: true, wakeMinute: 360, now: hk(21, 5, 0)))
        XCTAssertEqual(PatrickDayPlan.nightTarget(enabled: true, skipRestDays: true, wakeMinute: 360, now: hk(1, 5, 0)), hk(2, 6, 0))
        XCTAssertEqual(PatrickDayPlan.nightTarget(enabled: true, skipRestDays: true, wakeMinute: 360, now: hk(23, 22, 0)), hk(26, 6, 0))
        let sleep = PatrickMorningSeries(metric: .sleepHours, values: Array(repeating: 8, count: 7) + [7], overnightIndex: 7)
        XCTAssertEqual(PatrickDayPlan.morningSentence([sleep]), "昨晚少睡了 1 小時，今天慢慢來。")
        XCTAssertNil(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .hrvSDNN, values: Array(repeating: 50, count: 6) + [20], overnightIndex: 6)]))
        XCTAssertNil(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .restingHeartRate, values: Array(repeating: 60, count: 7) + [64], overnightIndex: 7)]))
        XCTAssertTrue(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .wristTemperature, values: Array(repeating: 36.5, count: 7) + [36.8], overnightIndex: 7)])?.contains("手腕溫度") == true)
        XCTAssertTrue(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .respiratoryRate, values: Array(repeating: 14, count: 7) + [15], overnightIndex: 7)])?.contains("呼吸偏快") == true)
        let now = hk(21, 15, 0)
        let gap = [PatrickCalendarInterval(start: now.addingTimeInterval(5 * 60), end: now.addingTimeInterval(3600))]
        let inside = [PatrickCalendarInterval(start: now.addingTimeInterval(-30 * 60), end: now.addingTimeInterval(30 * 60))]
        XCTAssertEqual(PatrickDayPlan.standPrompt(events: gap, now: now, sittingMinutes: 70, contextSuppresses: false, budgetRemaining: 6), "坐了 70 分鐘，下個會前有 5 分鐘，倒杯水？")
        XCTAssertNil(PatrickDayPlan.standPrompt(events: inside, now: now, sittingMinutes: 90, contextSuppresses: false, budgetRemaining: 6))
        XCTAssertNil(PatrickDayPlan.standPrompt(events: gap, now: now, sittingMinutes: 90, contextSuppresses: true, budgetRemaining: 6))
        XCTAssertNil(PatrickDayPlan.standPrompt(events: gap, now: now, sittingMinutes: 90, contextSuppresses: false, budgetRemaining: 0))
        XCTAssertEqual(PatrickDayPlan.merged([
            PatrickCalendarInterval(start: now, end: now.addingTimeInterval(3600)),
            PatrickCalendarInterval(start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400))
        ]).count, 1)
        var settings = PatrickExperienceSettings()
        settings.wakeAlarmEnabled = true
        settings.proactiveHapticBudget = 0
        let armed = PatrickDayPlan.advance(settings: &settings, activity: nil, events: gap, sittingMinutes: 90, battery: 1, role: .watch, now: hk(21, 8, 0), calendar: calendar)
        XCTAssertFalse(armed.wake.isEmpty)
        XCTAssertEqual(armed.knocks, 0)
        XCTAssertEqual(PatrickDayPlan.butlerSentence(.arrived, name: "Sham", modelText: nil), "Sham回來了。先洗手？")
        XCTAssertNil(PatrickDayPlan.acceptButler("可能着涼了"))
        XCTAssertEqual(PatrickDayPlan.greeting(name: "Sham", hour: 8, report: nil, weather: nil, firstEvent: nil, suppressed: false), "早安，Sham。")
    }

    func testWeekPlanZonesStoryJournalMoodAndGate() {
        let calendar = PatrickHKHolidays.calendar
        XCTAssertEqual(PatrickHeartZone.zone(beatsPerMinute: 100)?.sway, 0.6)
        XCTAssertEqual(PatrickHeartZone.zone(beatsPerMinute: 180), .peak)
        XCTAssertNil(PatrickHeartZone.zone(beatsPerMinute: 0))
        XCTAssertEqual(PatrickKilometerMarks.crossed(previousMeters: 999, meters: 1000), 1)
        XCTAssertNil(PatrickKilometerMarks.crossed(previousMeters: 1000, meters: 1400))
        XCTAssertEqual(PatrickNightMotion.tosses([1, 1.3, 1, 1.3]), 2)
        XCTAssertEqual(PatrickNightTheater.beats(quietMinutes: 90, tosses: 0, wakes: 0).map(\.seconds).reduce(0, +), 10)
        XCTAssertNil(PatrickNightTheater.script(quietMinutes: 0, tosses: 0, wakes: 0))
        XCTAssertFalse(PatrickNightTheater.script(quietMinutes: 40, tosses: 4, wakes: 1)?.contains("分數") ?? true)
        XCTAssertEqual(PatrickJournalVoice.evening(events: ["站會"], modelText: "去餵食"), "今天有站會。就這樣，很好。")
        XCTAssertEqual(PatrickJournalVoice.weekly(lines: ["餵一口"], modelText: nil), "這週平靜地過去了。")
        XCTAssertEqual(PatrickMoodStars.raw(stars: 3), "neutral")
        XCTAssertFalse(PatrickMoodStars.company(stars: 1).contains("判斷"))
        XCTAssertFalse(PatrickMoodStars.shouldAsk(hour: 20, askedDay: "2026-10-21", today: "2026-10-21", suppressed: false))
        XCTAssertEqual(PatrickBathCharge.chargeLine(battery: 0.39), "先充 20 分鐘，再去泡澡。")
        XCTAssertNil(PatrickBathCharge.chargeLine(battery: 0.4))
        XCTAssertFalse(PatrickPhoneLeft.shouldAlert(wasReachable: true, reachable: false, atHome: true, already: false, suppressed: true))
        XCTAssertTrue(PatrickPhoneLeft.shouldAlert(wasReachable: true, reachable: false, atHome: true, already: false, suppressed: false))
        XCTAssertEqual(PatrickPhoneLeft.pulses, 3)
        var settings = PatrickExperienceSettings()
        settings.contextCommute = true
        let noon = calendar.date(from: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 10, day: 21, hour: 12))!
        let riding = PatrickDayPlan.advance(settings: &settings, activity: nil, events: [
            PatrickCalendarInterval(start: noon.addingTimeInterval(5 * 60), end: noon.addingTimeInterval(3600))
        ], sittingMinutes: 80, battery: 1, role: .none, now: noon, calendar: calendar, writesJournal: false)
        XCTAssertEqual(riding.knocks, 0)
        XCTAssertEqual(settings.dayLine, "坐車看窗外。")
        settings.contextCommute = nil
        settings.scene = .bath
        _ = PatrickDayPlan.advance(settings: &settings, activity: nil, events: [], sittingMinutes: nil, battery: 0.2, role: .none, now: noon, calendar: calendar, writesJournal: false)
        XCTAssertEqual(settings.dayLine, "先充 20 分鐘，再去泡澡。")
        XCTAssertEqual(PatrickAutomaticScene.resolve(selection: .automatic, activitySceneID: nil, charging: false, sleeping: false, focus: false, workout: false, meeting: false, water: true), "exercise")
        var wet = PatrickExperienceSettings()
        let entered = PatrickWeekPlan.fold(settings: &wet, line: nil, hello: nil, knocks: 0, gate: PatrickContextSnapshot(budget: 6), events: [], journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil, phoneReachable: nil, waterSubmerged: true, writesJournal: false, now: noon, calendar: calendar)
        XCTAssertEqual(entered.line, "下水了，泳圈模式。")
        XCTAssertEqual(entered.knocks, 0)
        var home = PatrickExperienceSettings()
        home.phoneAtHome = true
        home.phoneWasReachable = true
        let left = PatrickWeekPlan.fold(settings: &home, line: nil, hello: nil, knocks: 0, gate: PatrickContextSnapshot(budget: 6), events: [], journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil, phoneReachable: false, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        XCTAssertEqual(left.phoneLeftPulses, 3)
        var stack = PatrickExperienceState()
        let idle = PatrickStackRelevance.make(experience: stack, at: noon, calendar: calendar).score
        stack.settings.contextCommute = true
        let ride = PatrickStackRelevance.make(experience: stack, at: noon, calendar: calendar).score
        XCTAssertGreaterThan(ride, idle)
    }
}
