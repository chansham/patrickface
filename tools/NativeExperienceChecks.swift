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
        var emptyRoutine = PatrickExperienceState()
        let firstStart = emptyRoutine.requestActivityStart(.focus, minutes: 5, at: now)
        check(firstStart == .started(activity: emptyRoutine.activity!, completedKind: nil), "Empty routine starts the requested activity")
        check(emptyRoutine.activity?.durationSeconds == 300 && emptyRoutine.revision == 1 && emptyRoutine.journal.count == 1,
              "A real shortcut start writes exactly one transition")
        for (existingKind, requestedKind) in [(PatrickActivityKind.focus, PatrickActivityKind.focus), (.running, .focus), (.focus, .breathing)] {
            for paused in [false, true] {
                var occupied = PatrickExperienceState()
                occupied.settings.outfitID = "mint-pajama"; occupied.settings.soundEnabled = true
                occupied.start(existingKind, seconds: 120, at: now)
                if paused { occupied.pause(at: now.addingTimeInterval(30)) }
                let before = occupied
                let requestTime = now.addingTimeInterval(paused ? 600 : 31)
                let result = occupied.requestActivityStart(requestedKind, minutes: 25, at: requestTime)
                check(occupied == before, "Same or different shortcut preserves the complete running/paused state")
                check(result == .preserved(activity: before.activity!, remainingSeconds: paused ? 90 : 89),
                      "Result describes the existing activity and its actual remaining time")
                check(result.message.contains(existingKind.title) && result.message.contains(paused ? "已暫停" : "仍在進行"),
                      "Dialog identifies the kept activity and status instead of claiming success")
                check(result.message.contains("控制派大星陪伴計時") && result.message.contains("結束"),
                      "Dialog gives an explicit path to replace the activity")
            }
        }
        var restoredRoutine = PatrickExperienceState()
        restoredRoutine.start(.strength, seconds: 120, at: now)
        restoredRoutine.pause(at: now.addingTimeInterval(30))
        restoredRoutine = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONEncoder().encode(restoredRoutine))
        let pausedRoutine = restoredRoutine
        _ = restoredRoutine.requestActivityStart(.focus, minutes: 5, at: now.addingTimeInterval(7200))
        check(restoredRoutine == pausedRoutine, "Persisted pause is not elapsed, resumed or replaced by a routine")
        var deadlineRoutine = PatrickExperienceState()
        deadlineRoutine.start(.running, seconds: 60, at: now)
        let beforeDeadline = deadlineRoutine
        _ = deadlineRoutine.requestActivityStart(.focus, minutes: 5, at: now.addingTimeInterval(59.999))
        check(deadlineRoutine == beforeDeadline, "An activity remains protected immediately before its deadline")
        let replacement = deadlineRoutine.requestActivityStart(.focus, minutes: 5, at: now.addingTimeInterval(60))
        check(replacement == .started(activity: deadlineRoutine.activity!, completedKind: .running), "Deadline is settled before a new requested timer starts")
        check(deadlineRoutine.care.bond == 1 && deadlineRoutine.revision == beforeDeadline.revision + 2,
              "Late start has one completion and one start transition")
        check(deadlineRoutine.journal.map(\.text) == ["開始跑步陪伴", "完成跑步陪伴", "開始專注"],
              "Late start neither cancels nor loses the completed activity record")
        let afterDeadlineStart = deadlineRoutine
        _ = deadlineRoutine.requestActivityStart(.focus, minutes: 5, at: now.addingTimeInterval(60.001))
        check(deadlineRoutine == afterDeadlineStart, "Immediate retry cannot double reward, duplicate the journal or extend the new deadline")
        for completed in [false, true] {
            var terminal = PatrickExperienceState(); terminal.start(.walking, seconds: 60, at: now)
            if completed { _ = terminal.reconcile(at: now.addingTimeInterval(60)) }
            else { terminal.cancel(at: now.addingTimeInterval(30)) }
            let bond = terminal.care.bond, journalCount = terminal.journal.count
            let result = terminal.requestActivityStart(.breathing, minutes: Int.max, at: now.addingTimeInterval(120))
            check(result == .started(activity: terminal.activity!, completedKind: nil), "An already terminal activity frees the slot without completing it again")
            check(terminal.care.bond == bond && terminal.journal.count == journalCount + 1 && terminal.activity?.durationSeconds == 7200,
                  "Terminal start preserves reward count and existing duration limits")
        }
        var resting = PatrickExperienceState(); resting.start(.focus, seconds: 600, at: now)
        let originalID = resting.activity!.id
        check(resting.manageBreak(.begin(minutes: 1), at: now.addingTimeInterval(30)) == .started(.focus), "Break saves a running original")
        check(resting.breakSession?.savedActivity.id == originalID && resting.breakSession?.savedActivity.remainingSeconds == 570,
              "Original identity and remaining seconds are frozen")
        let savedBreak = resting
        check(resting.manageBreak(.begin(minutes: 5), at: now.addingTimeInterval(31)) == .alreadySaved && resting == savedBreak,
              "Repeated break neither nests nor changes the break deadline")
        _ = resting.requestActivityStart(.running, minutes: 10, at: now.addingTimeInterval(32))
        resting.start(.exercise, seconds: 90, at: now.addingTimeInterval(32))
        check(resting == savedBreak, "Both shortcut and raw start preserve the saved activity")
        resting = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONEncoder().encode(resting))
        _ = resting.reconcile(at: now.addingTimeInterval(1000))
        check(resting.activity?.status == .completed && resting.breakSession?.savedActivity.remainingSeconds == 570,
              "A break completed in the background never restarts or consumes the original")
        check(resting.care.bond == 1, "Completed break settles its usual reward once")
        check(resting.manageBreak(.returnToActivity, at: now.addingTimeInterval(1000)) == .returned(.focus, running: true), "Explicit return resumes a formerly running activity")
        check(resting.activity?.id == originalID && resting.activity?.endsAt == now.addingTimeInterval(1570) && resting.breakSession == nil,
              "Return restores identity and frozen remaining time with a new deadline")
        let returned = resting
        check(resting.manageBreak(.returnToActivity, at: now.addingTimeInterval(1001)) == .nothingSaved && resting == returned,
              "Return retries neither extend deadline nor repeat journal/reward")
        var pausedOriginal = PatrickExperienceState(); pausedOriginal.start(.strength, seconds: 300, at: now)
        pausedOriginal.pause(at: now.addingTimeInterval(20))
        _ = pausedOriginal.manageBreak(.begin(minutes: 3), at: now.addingTimeInterval(100))
        _ = pausedOriginal.controlActivity(.cancel, at: now.addingTimeInterval(110))
        check(pausedOriginal.breakSession != nil && pausedOriginal.care.bond == 0, "Cancelling a break keeps the original without completion reward")
        _ = pausedOriginal.manageBreak(.returnToActivity, at: now.addingTimeInterval(500))
        check(pausedOriginal.activity?.status == .paused && pausedOriginal.activity?.remainingSeconds == 280 && pausedOriginal.activity?.endsAt == nil,
              "A originally paused task stays paused on explicit return")
        var boundary = PatrickExperienceState(); boundary.start(.walking, seconds: 60, at: now)
        check(boundary.manageBreak(.begin(minutes: 1), at: now.addingTimeInterval(60)) == .noActiveActivity
              && boundary.breakSession == nil && boundary.care.bond == 1, "Deadline wins over starting a break")
        var abandoned = PatrickExperienceState(); abandoned.start(.running, seconds: 300, at: now)
        _ = abandoned.manageBreak(.begin(minutes: 1), at: now.addingTimeInterval(10))
        let breakID = abandoned.activity?.id
        check(abandoned.manageBreak(.discardSaved, at: now.addingTimeInterval(20)) == .discarded(.running)
              && abandoned.activity?.id == breakID && abandoned.care.bond == 0, "Explicit discard leaves the current break and grants no reward")
        let afterDiscard = abandoned
        _ = abandoned.manageBreak(.discardSaved, at: now.addingTimeInterval(21))
        check(abandoned == afterDiscard, "Discard is idempotent")
        var legacyBreakSave = try JSONSerialization.jsonObject(with: JSONEncoder().encode(savedBreak)) as! [String: Any]
        legacyBreakSave.removeValue(forKey: "breakSession")
        let legacyWithoutBreak = try JSONDecoder().decode(PatrickExperienceState.self, from: JSONSerialization.data(withJSONObject: legacyBreakSave))
        check(legacyWithoutBreak.breakSession == nil && legacyWithoutBreak.activity == savedBreak.activity, "Old v1 archives still decode without a saved break")
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
