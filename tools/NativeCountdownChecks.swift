import Foundation

@main struct NativeCountdownChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ text: String) {
        precondition(condition(), text)
        count += 1
    }

    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23))!
        var running = PatrickExperienceState()
        running.start(.focus, seconds: 120, at: noon)
        let id = running.activity!.id
        let day = PatrickCountdownPlanner.notices(activity: running.activity, breakSession: nil, legacy: nil,
                                                   settings: running.settings, now: noon, calendar: calendar)
        check(day.count == 1 && day[0].identifier == PatrickCountdownPlanner.identifier(for: id), "Running countdown has one stable identifier")
        check(day[0].fireAt == noon.addingTimeInterval(120) && day[0].playsSound && day[0].title == "派大星", "Daytime countdown sounds and names Patrick")
        check(day[0].body.contains("專注"), "Focus completion uses a Patrick line")
        running.pause(at: noon.addingTimeInterval(10))
        check(PatrickCountdownPlanner.notices(activity: running.activity, breakSession: nil, legacy: nil,
                                               settings: running.settings, now: noon.addingTimeInterval(10), calendar: calendar).isEmpty,
              "Pause cancels the pending alert")
        running.resume(at: noon.addingTimeInterval(20))
        let resumed = PatrickCountdownPlanner.notices(activity: running.activity, breakSession: nil, legacy: nil,
                                                       settings: running.settings, now: noon.addingTimeInterval(20), calendar: calendar)
        check(resumed.count == 1 && resumed[0].identifier == day[0].identifier && resumed[0].fireAt != day[0].fireAt,
              "Resume keeps the identifier and moves the fire date")
        running.cancel(at: noon.addingTimeInterval(30))
        check(PatrickCountdownPlanner.notices(activity: running.activity, breakSession: nil, legacy: nil,
                                               settings: running.settings, now: noon.addingTimeInterval(30), calendar: calendar).isEmpty,
              "Cancel removes the alert")
        var nightRun = PatrickExperienceState()
        nightRun.start(.breathing, seconds: 60, at: night)
        let quiet = PatrickCountdownPlanner.notices(activity: nightRun.activity, breakSession: nil, legacy: nil,
                                                     settings: nightRun.settings, now: night, calendar: calendar)
        check(quiet.count == 1 && !quiet[0].playsSound && !quiet[0].breaksQuietFocus, "Default sleep window is silent and not an alarm")
        nightRun.settings.quietAlerts = .allowSound
        let audible = PatrickCountdownPlanner.notices(activity: nightRun.activity, breakSession: nil, legacy: nil,
                                                       settings: nightRun.settings, now: night, calendar: calendar)
        check(audible.count == 1 && audible[0].playsSound, "Allow-sound keeps the sleep-window alert audible")
        nightRun.settings.quietAlerts = .hideExceptAlarms
        check(PatrickCountdownPlanner.pending(PatrickCountdownPlanner.notices(activity: nightRun.activity, breakSession: nil,
            legacy: nil, settings: nightRun.settings, now: night, calendar: calendar), now: night).isEmpty,
              "Hide-during-sleep drops a normal countdown")
        let alarm = PatrickCountdownPlanner.notices(activity: nightRun.activity, breakSession: nil, legacy: nil,
                                                     settings: nightRun.settings, now: night, calendar: calendar, isAlarm: true)
        check(alarm.count == 1 && alarm[0].playsSound && alarm[0].breaksQuietFocus && alarm[0].body.contains("叫你"),
              "Alarms still sound during the strictest quiet window")
        var sleepingScene = PatrickExperienceState()
        sleepingScene.settings.scene = .sleeping
        sleepingScene.start(.focus, seconds: 90, at: noon)
        let sceneQuiet = PatrickCountdownPlanner.notices(activity: sleepingScene.activity, breakSession: nil, legacy: nil,
                                                          settings: sleepingScene.settings, now: noon, calendar: calendar)
        check(sceneQuiet.count == 1 && !sceneQuiet[0].playsSound, "Sleep scene is quiet even at noon")
        var breaking = PatrickExperienceState()
        breaking.start(.running, seconds: 600, at: noon)
        _ = breaking.manageBreak(.begin(minutes: 1), at: noon.addingTimeInterval(30))
        let rest = PatrickCountdownPlanner.notices(activity: breaking.activity, breakSession: breaking.breakSession,
                                                    legacy: nil, settings: breaking.settings, now: noon.addingTimeInterval(30), calendar: calendar)
        check(rest.count == 1 && rest[0].body.contains("休息好了") && rest[0].identifier == PatrickCountdownPlanner.identifier(for: breaking.activity!.id),
              "Rest end uses the break activity and a return line")
        let legacy = PatrickCountdownLegacy(id: UUID(), running: true, endsAt: noon.addingTimeInterval(30), title: "legacy")
        let legacyOnly = PatrickCountdownPlanner.notices(activity: nil, breakSession: nil, legacy: legacy,
                                                          settings: PatrickExperienceSettings(), now: noon, calendar: calendar)
        check(legacyOnly.count == 1 && legacyOnly[0].body.contains("計時結束了"), "Legacy countdown alerts when no activity exists")
        let preferred = PatrickCountdownPlanner.notices(activity: running.activity, breakSession: nil, legacy: legacy,
                                                         settings: running.settings, now: noon, calendar: calendar)
        check(running.activity?.status == .cancelled && preferred.isEmpty, "A terminal activity suppresses the legacy timer instead of alerting twice")
        var fresh = PatrickExperienceState()
        fresh.start(.focus, seconds: 60, at: noon)
        let both = PatrickCountdownPlanner.notices(activity: fresh.activity, breakSession: nil, legacy: legacy,
                                                    settings: fresh.settings, now: noon, calendar: calendar)
        check(both.count == 1 && both[0].identifier == PatrickCountdownPlanner.identifier(for: fresh.activity!.id),
              "The experience countdown wins over a legacy timer")
        check(PatrickHapticPolicy.distinctKinds.count == 4, "Only four haptic patterns")
        check(PatrickHapticPolicy.kind(for: .knock) == .click, "A proactive knock is three clicks")
        check(PatrickHapticPolicy.kind(for: .timerClosing) == .notification, "Last seconds use attention")
        check(PatrickHapticPolicy.kind(for: .timerDone) == .success, "Timer done succeeds")
        check(PatrickHapticPolicy.kind(for: .restDone) == .notification, "Rest end notifies")
        check(PatrickHapticPolicy.kind(for: .wake) == .directionDown, "Wake settles")
        check(PatrickHapticPolicy.kind(for: .goodnight) == .directionDown, "Goodnight settles down")
        check(PatrickHapticPolicy.kind(for: .chargingFull) == .success, "Full charge succeeds")
        check(PatrickHapticPolicy.kind(for: .celebrate) == .success, "Celebration succeeds")
        check(PatrickHapticPolicy.kind(for: .failure) == .notification, "Errors use attention")
        check(PatrickHapticMoment.allCases.count == 9 && !PatrickHapticMoment.allCases.map(\.rawValue).contains("pet"),
              "Petting and browsing are not haptic moments")
        let moment = PatrickHapticMoment.timerDone
        check(PatrickHapticPolicy.allows(moment: moment, enabled: true, foreground: true, inWorkout: false,
                                          readingHeartRate: false, quiet: false, now: noon, lastPlayedAt: nil), "Foreground feed can play")
        check(!PatrickHapticPolicy.allows(moment: moment, enabled: false, foreground: true, inWorkout: false,
                                           readingHeartRate: false, quiet: false, now: noon, lastPlayedAt: nil), "Toggle silences every moment")
        check(!PatrickHapticPolicy.allows(moment: moment, enabled: true, foreground: false, inWorkout: false,
                                           readingHeartRate: false, quiet: false, now: noon, lastPlayedAt: nil), "Background stays quiet without a workout")
        check(PatrickHapticPolicy.allows(moment: moment, enabled: true, foreground: false, inWorkout: true,
                                          readingHeartRate: false, quiet: false, now: noon, lastPlayedAt: nil), "Workout session is the background exception")
        check(!PatrickHapticPolicy.allows(moment: moment, enabled: true, foreground: true, inWorkout: true,
                                           readingHeartRate: true, quiet: false, now: noon, lastPlayedAt: nil), "Heart-rate reads never buzz")
        check(!PatrickHapticPolicy.allows(moment: moment, enabled: true, foreground: true, inWorkout: false,
                                           readingHeartRate: false, quiet: true, now: noon, lastPlayedAt: nil), "Sleep quiets ordinary haptics")
        check(PatrickHapticPolicy.allows(moment: .goodnight, enabled: true, foreground: true, inWorkout: false,
                                          readingHeartRate: false, quiet: true, now: noon, lastPlayedAt: nil), "Goodnight plays once as sleep begins")
        check(PatrickHapticPolicy.allows(moment: .wake, enabled: true, foreground: true, inWorkout: false,
                                          readingHeartRate: false, quiet: true, now: noon, lastPlayedAt: nil), "Wake can play while the scene is still quiet")
        check(!PatrickHapticPolicy.allows(moment: moment, enabled: true, foreground: true, inWorkout: false,
                                           readingHeartRate: false, quiet: false, now: noon, lastPlayedAt: noon.addingTimeInterval(-0.4)),
              "Repeated events inside one second are dropped")
        var spoken = PatrickExperienceState()
        let beforeNight = spoken.revision
        let nightLine = PatrickSpokenActions.sayGoodNight(&spoken, at: noon)
        check(spoken.settings.scene == .sleeping && spoken.revision == beforeNight + 1 && nightLine.contains("晚安"), "Goodnight enters sleep once")
        let repeatedNight = spoken
        _ = PatrickSpokenActions.sayGoodNight(&spoken, at: noon.addingTimeInterval(5))
        check(spoken == repeatedNight, "Repeating goodnight does not write again")
        spoken.settings.scene = .awake
        spoken.start(.focus, seconds: 300, at: noon)
        let restLine = PatrickSpokenActions.startRest(&spoken, minutes: 3, at: noon.addingTimeInterval(20))
        check(spoken.breakSession != nil && spoken.activity?.kind == .breathing && restLine.contains("保存"), "Spoken rest saves the original activity")
        let savedRest = spoken
        _ = PatrickSpokenActions.startRest(&spoken, minutes: 5, at: noon.addingTimeInterval(25))
        check(spoken == savedRest, "Spoken rest does not extend a break")
        var hungry = PatrickExperienceState()
        check(PatrickSpokenActions.feed(&hungry, at: noon).contains("收起來") && hungry.care.totalFeeds == 0, "Spoken feed is retired")
        check(!PatrickSpokenActions.pet(&hungry, at: noon).contains("親密"), "Petting does not recite intimacy")
        hungry.settings.mood = .happy
        hungry.settings.moodFollowsDay = false
        check(PatrickSpokenActions.moodLine(hungry, at: noon).contains("開心") && !PatrickSpokenActions.moodLine(hungry, at: noon).contains("飽足"), "Mood line does not recite care numbers")
        check(PatrickAlertOwner.choose(paired: true, worn: true) == .watch, "A worn paired watch owns the alert")
        check(PatrickAlertOwner.choose(paired: true, worn: false) == .phone, "An unworn watch leaves the alert on the phone")
        check(PatrickAlertOwner.choose(paired: false, worn: true) == .phone, "An unpaired watch cannot own the alert")
        check(PatrickAlertOwner.isWorn(onWrist: true, observedAt: noon.addingTimeInterval(-90), at: noon, paired: true), "A 90 second heartbeat still counts as worn")
        check(!PatrickAlertOwner.isWorn(onWrist: true, observedAt: noon.addingTimeInterval(-91), at: noon, paired: true), "A stale heartbeat is not worn")
        check(!PatrickAlertOwner.isWorn(onWrist: nil, observedAt: noon, at: noon, paired: true), "An old observation without a wrist flag is not worn")
        var meeting = PatrickContextSnapshot(meeting: true)
        check(meeting.suppressesProactive, "A meeting closes the proactive gate")
        check(!PatrickHapticPolicy.allows(moment: .knock, enabled: true, foreground: true, inWorkout: false, readingHeartRate: false, quiet: false, now: noon, lastPlayedAt: nil, context: meeting), "A knock waits out a meeting")
        check(PatrickHapticPolicy.allows(moment: .timerDone, enabled: true, foreground: true, inWorkout: false, readingHeartRate: false, quiet: false, now: noon, lastPlayedAt: nil, context: meeting), "A countdown the person started can still complete")
        var budgeted = PatrickExperienceState()
        for _ in 0..<6 { check(budgeted.registerProactiveHaptic(at: noon, calendar: calendar), "Budget allows six knocks") }
        check(!budgeted.registerProactiveHaptic(at: noon, calendar: calendar), "The seventh knock waits until tomorrow")
        let quietMeeting = PatrickCountdownPlanner.notices(activity: fresh.activity, breakSession: nil, legacy: nil, settings: fresh.settings, now: noon, calendar: calendar, contextQuiet: true)
        check(quietMeeting.count == 1 && !quietMeeting[0].playsSound, "Context quiet keeps the banner and drops the sound")
        var nudged = PatrickExperienceState()
        nudged.start(.focus, seconds: 120, at: noon)
        let nudgedRevision = nudged.revision
        check(nudged.nudgeCountdown(by: 1, at: noon.addingTimeInterval(10)), "Crown can extend a running countdown")
        check(nudged.activity?.endsAt == noon.addingTimeInterval(10 + 110 + 60) && nudged.revision == nudgedRevision + 1, "Nudge moves the deadline once")
        check(nudged.journal.count == 1, "Crown nudges are not journal spam")
        var relevance = PatrickExperienceState()
        let idleScore = PatrickStackRelevance.make(experience: relevance, at: noon, calendar: calendar).score
        relevance.start(.focus, seconds: 120, at: noon)
        let runningScore = PatrickStackRelevance.make(experience: relevance, at: noon, calendar: calendar).score
        relevance.settings.scene = .sleeping
        relevance.activity = nil
        let sleepScore = PatrickStackRelevance.make(experience: relevance, at: noon, calendar: calendar).score
        check(runningScore > sleepScore && sleepScore > idleScore, "A running countdown outranks sleep, which outranks idle")
        var encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(PatrickExperienceSettings())) as! [String: Any]
        encoded.removeValue(forKey: "quietAlertsRaw")
        let decoded = try! JSONDecoder().decode(PatrickExperienceSettings.self, from: JSONSerialization.data(withJSONObject: encoded))
        check(decoded.quietAlerts == .silentExceptAlarms, "Older settings stay silent except alarms")
        print("PASS: \(count) native countdown, haptic, spoken-intent and relevance checks.")
    }
}
