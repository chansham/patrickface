import Foundation

@main struct NativeExperienceChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ text: String) { precondition(condition(), text); count += 1 }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = PatrickExperienceState()
        check(!state.settings.soundEnabled && state.settings.hapticsEnabled, "Default sound must be opt in")
        check(PatrickImmediateSoundPolicy.allows(active: true, presentationActive: true, enabled: true,
            reduceMotion: false, lowPower: false), "Visible manual sound remains available")
        for quietFlag in 0..<5 {
            check(!PatrickImmediateSoundPolicy.allows(active: quietFlag != 0, presentationActive: quietFlag != 1,
                enabled: quietFlag != 2, reduceMotion: quietFlag == 3, lowPower: quietFlag == 4),
                "Every quiet gate independently suppresses legacy sound")
        }
        check(PatrickImmediateSoundPolicy.isFresh(now, now: now.addingTimeInterval(3)), "Fresh sound handoff boundary")
        check(!PatrickImmediateSoundPolicy.isFresh(now, now: now.addingTimeInterval(3.001)), "Queued sound must expire instead of replaying on foreground")
        check(!PatrickImmediateSoundPolicy.isFresh(now.addingTimeInterval(1), now: now), "Future sound timestamp cannot bypass freshness")
        let actionID = UUID()
        check(state.perform(.feed, id: actionID, at: now), "First feed")
        check(!state.perform(.feed, id: actionID, at: now.addingTimeInterval(5)), "Retransmission rewarded twice")
        check(!state.perform(.feed, at: now.addingTimeInterval(2.999)), "Feed cooldown")
        check(state.perform(.feed, at: now.addingTimeInterval(3)), "Feed boundary")
        check(state.care.totalFeeds == 2 && state.care.satiety == 84 && state.care.bond == 4, "Care values")
        state.start(.focus, seconds: 120, at: now)
        state.pause(at: now.addingTimeInterval(30))
        check(state.activity?.status == .paused && state.activity?.endsAt == nil, "Pause clears deadline")
        check(state.activity?.remaining(at: now.addingTimeInterval(500)) == 90, "Paused time cannot decay")
        state.resume(at: now.addingTimeInterval(500))
        check(state.activity?.endsAt == now.addingTimeInterval(590), "Resume creates fresh deadline")
        let id = state.reconcile(at: now.addingTimeInterval(591))
        check(id != nil && state.activity?.status == .completed, "Foreground catchup completes state")
        check(state.care.bond == 5, "One completion reward")
        check(state.reconcile(at: now.addingTimeInterval(1000)) == nil && state.care.bond == 5, "Completion cannot repeat")
        var quietCompletion = PatrickExperienceState()
        quietCompletion.start(.focus, seconds: 60, at: now)
        check(quietCompletion.reconcile(at: now.addingTimeInterval(90)) != nil, "Quiet expiry still settles its state")
        check(quietCompletion.activity?.status == .completed && quietCompletion.care.bond == 1,
              "Quiet expiry retains exactly one completion reward")
        check(quietCompletion.reconcile(at: now.addingTimeInterval(91)) == nil && quietCompletion.care.bond == 1,
              "Foreground observation cannot reward a quiet completion twice")
        state.start(.exercise, seconds: 30, at: now)
        state.cancel(at: now.addingTimeInterval(10))
        check(state.activity?.status == .cancelled, "Cancel has its own terminal state")
        check(state.reconcile(at: now.addingTimeInterval(40)) == nil && state.care.bond == 5, "Cancellation is not completion")
        state.start(.breathing, seconds: 1, at: now)
        check(state.activity?.durationSeconds == 10, "Minimum seconds")
        state.pause(at: now.addingTimeInterval(10))
        check(state.activity?.status == .completed && state.care.bond == 6, "Pause exactly at deadline reconciles once")
        state.start(.exercise, seconds: .infinity, at: now)
        check(state.activity?.durationSeconds == 60, "Nonfinite duration rejected safely")
        state.start(.exercise, minutes: Int.max, at: now)
        check(state.activity?.durationSeconds == 7200, "Unbounded shortcut minutes cannot overflow")
        check(state.activity?.remaining(at: now.addingTimeInterval(-300)) == 7200, "Clock rollback cannot extend duration")
        for kind in PatrickActivityKind.allCases {
            var activityState = PatrickExperienceState()
            activityState.start(kind, seconds: 120, at: now)
            let restored = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONEncoder().encode(activityState))
            check(restored.activity?.kind == kind && restored.journal.first?.text == "開始\(kind.title)", "Activity kind survives reload and journal")
            check(kind.clipID == kind.sceneID && kind.sceneID == (kind.isExercise ? "exercise" : "focus"), "Activity uses the existing appropriate artwork family")
        }
        for kind in [PatrickActivityKind.walking, .running, .strength] {
            check(kind.isExercise && kind.clipID == "exercise", "Named exercise timers must not invent ungenerated animations")
        }
        var controls = PatrickExperienceState()
        check(controls.controlActivity(.pause, at: now) == .noActiveActivity && controls.revision == 0, "Empty shortcut cannot claim it paused a timer")
        controls.start(.walking, seconds: 120, at: now)
        let originalID = controls.activity?.id
        check(controls.controlActivity(.pause, at: now.addingTimeInterval(30)) == .paused, "Pause shortcut")
        let pausedRevision = controls.revision
        check(controls.controlActivity(.pause, at: now.addingTimeInterval(500)) == .alreadyPaused && controls.revision == pausedRevision, "Repeated pause does not write or decay")
        controls = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONEncoder().encode(controls))
        check(controls.controlActivity(.resume, at: now.addingTimeInterval(600)) == .resumed, "Resume survives persistence")
        check(controls.activity?.id == originalID && controls.activity?.endsAt == now.addingTimeInterval(690), "Resume retains identity and frozen remaining duration")
        let resumedRevision = controls.revision
        check(controls.controlActivity(.resume, at: now.addingTimeInterval(620)) == .alreadyRunning && controls.revision == resumedRevision && controls.activity?.endsAt == now.addingTimeInterval(690), "Repeated resume cannot extend session")
        check(controls.controlActivity(.cancel, at: now.addingTimeInterval(630)) == .cancelled && controls.care.bond == 0, "Early cancellation has no completion reward")
        let cancelledRevision = controls.revision
        check(controls.controlActivity(.resume, at: now.addingTimeInterval(640)) == .noActiveActivity && controls.revision == cancelledRevision, "Cancelled session cannot be resumed")
        check(controls.journal.map(\.text) == ["開始散步陪伴", "暫停散步陪伴", "繼續散步陪伴", "結束散步陪伴"], "Only actual control transitions are journalled")
        for command in PatrickActivityControl.allCases {
            var elapsed = PatrickExperienceState(); elapsed.start(.running, seconds: 60, at: now)
            check(elapsed.controlActivity(command, at: now.addingTimeInterval(60)) == .completed, "Deadline wins over a late control")
            check(elapsed.activity?.status == .completed && elapsed.care.bond == 1, "Exactly one completion reward at deadline")
            let revision = elapsed.revision
            check(elapsed.controlActivity(command, at: now.addingTimeInterval(61)) == .completed && elapsed.revision == revision && elapsed.care.bond == 1, "Repeated late controls are idempotent")
        }
        for index in 0..<80 { state.record("Entry \(index)", at: now) }
        check(state.journal.count == 60, "Journal bound")
        var decay = PatrickExperienceState()
        check(decay.updateCare(at: now), "Initialize decay clock")
        check(!decay.updateCare(at: now.addingTimeInterval(59)), "No per-frame writes")
        check(decay.updateCare(at: now.addingTimeInterval(3600)) && decay.care.satiety == 58.5, "One hour is minus 1.5 satiety")
        _ = decay.updateCare(at: now.addingTimeInterval(3600 * 1000))
        check(decay.care.satiety == 0, "Long absence clamps at zero")
        var offlineFeed = PatrickExperienceState(); offlineFeed.care.satiety = 95
        _ = offlineFeed.updateCare(at: now)
        _ = offlineFeed.perform(.feed, at: now.addingTimeInterval(3600))
        check(offlineFeed.care.satiety == 100, "Decay must precede feed saturation after an offline shortcut")
        var surprise = PatrickExperienceState(); surprise.settings.outfitID = "chef"
        let firstLine = surprise.findSurprise(at: now)
        check(firstLine == PatrickSurpriseState.lines[0] && surprise.journal.count == 1, "First surprise records one personal line")
        let surpriseRevision = surprise.revision
        check(surprise.findSurprise(at: now.addingTimeInterval(59.999)) == nil, "Surprise cooldown before boundary")
        check(surprise.revision == surpriseRevision && surprise.journal.count == 1, "Cooldown makes no state or journal write")
        check(surprise.findSurprise(at: now.addingTimeInterval(-60)) == nil, "Clock rollback does not bypass cooldown")
        let surpriseData = try JSONEncoder().encode(surprise)
        var restoredSurprise = try JSONDecoder().decode(PatrickExperienceState.self, from: surpriseData)
        check(restoredSurprise.findSurprise(at: now.addingTimeInterval(30)) == nil, "Transferred snapshot retains cooldown")
        let suiteName = "patrick.native-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        surprise.save(to: defaults)
        var diskSurprise = PatrickExperienceState.load(from: defaults)
        check(diskSurprise == surprise && diskSurprise.findSurprise(at: now.addingTimeInterval(30)) == nil, "Local reload retains discovery without replay")
        check(restoredSurprise.findSurprise(at: now.addingTimeInterval(60)) == PatrickSurpriseState.lines[1], "Cooldown boundary unlocks a different line")
        check(restoredSurprise.settings.outfitID == "chef" && restoredSurprise.care == surprise.care, "Surprise does not change costume or invent care rewards")
        check(restoredSurprise.journal.last?.text == "小驚喜：\(PatrickSurpriseState.lines[1])", "Second discovery journals the actual line")
        var oldSave = try JSONSerialization.jsonObject(with: surpriseData) as! [String: Any]
        oldSave.removeValue(forKey: "surprise")
        let migrated = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONSerialization.data(withJSONObject: oldSave))
        check(migrated.surprise == nil && migrated.settings == surprise.settings && migrated.journal == surprise.journal, "Old v1 saves decode without losing settings or journal")
        var oldSettings = try JSONSerialization.jsonObject(with: JSONEncoder().encode(surprise.settings)) as! [String: Any]
        oldSettings.removeValue(forKey: "layoutID")
        let legacySettings = try JSONDecoder().decode(PatrickExperienceSettings.self, from: JSONSerialization.data(withJSONObject: oldSettings))
        check(legacySettings.layoutID == nil && legacySettings.effectiveLayoutID == "classic" && legacySettings.outfitID == "chef", "Older settings retain outfit and use classic layout")
        for layoutID in ["classic", "bold", "theater", "activity"] {
            var settings = legacySettings; settings.layoutID = layoutID
            let restored = try JSONDecoder().decode(PatrickExperienceSettings.self, from: JSONEncoder().encode(settings))
            check(restored == settings && restored.effectiveLayoutID == layoutID, "Each layout survives persistence and sync encoding")
        }
        var unknownLayout = legacySettings; unknownLayout.layoutID = "future-layout"
        check(unknownLayout.effectiveLayoutID == "classic" && unknownLayout.outfitID == "chef", "Unknown layout falls back without changing outfit")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let birthday = calendar.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 23))!
        var celebration = PatrickExperienceState(); celebration.settings.birthdayMMDD = "02-29"
        check(celebration.settings.isSleepTime(birthday, calendar: calendar), "Custom sleep default spans midnight")
        celebration.settings.sleepStartMinutes = 360; celebration.settings.sleepEndMinutes = 360
        check(!celebration.settings.isSleepTime(birthday, calendar: calendar), "Equal sleep endpoints disable schedule")
        check(celebration.observeCalendar(nil, at: birthday, allowCelebration: true, localCalendar: calendar) == "生日快樂", "Leap birthday exact date")
        check(celebration.observeCalendar(nil, at: birthday, allowCelebration: true, localCalendar: calendar) == nil, "Birthday once per day")
        celebration.calendarCelebrationKeys = nil
        check(celebration.observeCalendar(nil, at: birthday, allowCelebration: false, localCalendar: calendar) == nil, "Quiet birthday suppressed")
        check(celebration.observeCalendar(nil, at: birthday, allowCelebration: true, localCalendar: calendar) == nil, "Quiet birthday not caught up")
        celebration.settings.birthdayMMDD = nil; celebration.calendarCelebrationKeys = nil
        check(celebration.observeCalendar(nil, at: birthday, allowCelebration: true, localCalendar: calendar) == nil, "No calendar data means no guessed holiday")
        let data = try JSONEncoder().encode(state)
        let reloaded = try JSONDecoder().decode(PatrickExperienceState.self, from: data)
        check(reloaded == state, "Settings and paused/running state persistence roundtrip")
        var newer = state; newer.changed(at: now.addingTimeInterval(2000))
        check(newer.isNewer(than: state) && !state.isNewer(than: newer), "Older snapshot cannot roll back")
        if CommandLine.arguments.count > 1 {
            let catalog = try JSONDecoder().decode(PatrickOutfitCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            check(catalog.schemaVersion == 1 && !catalog.outfits.isEmpty, "Actual themes decode")
            let pajamas = catalog.outfits.first { $0.id == "star-pajamas" }
            check(pajamas?.idleClips.count == 3, "Array action supports all three idle rhythms")
            check(pajamas?.actionClips["yawn"] == "yawn", "String action remains supported")
            check(pajamas?.surpriseClipID == "idle-blink-slow", "Surprise reuses a same-costume reaction")
            check(catalog.outfits.first { $0.id == "chef" }?.surpriseClipID == nil, "No reaction means no borrowed costume or fake feeding animation")
        }
        if CommandLine.arguments.count > 2 {
            let calendarData = try JSONDecoder().decode(PatrickCelebrationCalendar.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
            let christmas = calendar.date(from: DateComponents(year: 2026, month: 12, day: 25, hour: 12))!
            var holidayState = PatrickExperienceState()
            check(holidayState.observeCalendar(calendarData, at: christmas, allowCelebration: true, localCalendar: calendar) == "聖誕節", "Fixed Christmas must remain reachable")
            holidayState.calendarCelebrationKeys = nil; holidayState.settings.birthdayMMDD = "12-25"
            check(holidayState.observeCalendar(calendarData, at: christmas, allowCelebration: true, localCalendar: calendar) == "生日快樂", "Birthday wins over holiday")
        }
        print("PASS: \(count) native experience checks (Foundation only).")
    }
}
