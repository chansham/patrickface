import Foundation

@main struct NativeWeekPlanChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        count += 1
    }

    static func main() {
        let calendar = PatrickHKHolidays.calendar
        func hk(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
            var parts = DateComponents()
            parts.calendar = calendar
            parts.timeZone = calendar.timeZone
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return parts.date!
        }
        check(PatrickHeartZone.zone(beatsPerMinute: 100)?.sway == 0.6, "A quiet heart uses the small sway")
        check(PatrickHeartZone.zone(beatsPerMinute: 120) == .easy, "Just under 70 percent is easy")
        check(PatrickHeartZone.zone(beatsPerMinute: 140) == .steady, "The middle zone is steady")
        check(PatrickHeartZone.zone(beatsPerMinute: 160) == .tempo, "A hard effort is tempo")
        check(PatrickHeartZone.zone(beatsPerMinute: 180) == .peak, "Near the max is the peak")
        check(PatrickHeartZone.zone(beatsPerMinute: 0) == nil, "A missing heart rate does not invent a zone")
        check(PatrickHeartZone.zone(beatsPerMinute: 114, maxBeats: 190)?.sway == PatrickHeartZone.easy.sway, "The 60 percent edge is easy")
        check([PatrickHeartZone.recover, .easy, .steady, .tempo, .peak].map(\.sway) == [0.6, 1, 1.6, 2.4, 3.2], "Sway grows with the zone and stays one motion")

        check(PatrickKilometerMarks.crossed(previousMeters: 999, meters: 1000) == 1, "The first kilometer cues once")
        check(PatrickKilometerMarks.crossed(previousMeters: 1000, meters: 1500) == nil, "The same kilometer stays quiet")
        check(PatrickKilometerMarks.crossed(previousMeters: 1500, meters: 2000) == 2, "The next kilometer cues once")
        check(PatrickKilometerMarks.crossed(previousMeters: 0, meters: 2500) == 2, "A jump still cues one mark, not a burst")
        check(PatrickKilometerMarks.crossed(previousMeters: -1, meters: 1000) == nil, "A bad sample does not cue")

        check(PatrickNightMotion.tosses([1.0, 1.3]) == 1, "A rise through the threshold is one toss")
        check(PatrickNightMotion.tosses([1.3, 1.4]) == 0, "Staying above the threshold is not another toss")
        check(PatrickNightMotion.tosses([1.0, 1.3, 1.0, 1.3]) == 2, "Two separated rises are two tosses")
        let quiet = PatrickNightTheater.beats(quietMinutes: 400, tosses: 0, wakes: 0)
        check(quiet.map(\.seconds).reduce(0, +) == 10, "A quiet night is a ten second story")
        check(PatrickNightTheater.script(quietMinutes: 0, tosses: 0, wakes: 0) == nil, "No overnight signal stays silent")
        let told = PatrickNightTheater.script(quietMinutes: 20, tosses: 4, wakes: 2) ?? ""
        check(told.contains("翻過幾次身") && !told.contains("分數") && !told.contains("餵"), "Tosses become a story, not a score or a chore")
        check(PatrickNightTheater.script(quietMinutes: 40, tosses: 0, wakes: 3)?.contains("醒過") == true, "Wakes are mentioned without a number")

        check(PatrickJournalVoice.evening(events: [], modelText: nil) == "今天過完了，我在。", "An empty day still gets one evening sentence")
        check(PatrickJournalVoice.evening(events: ["站會"], modelText: "去餵食") == "今天有站會。就這樣，很好。", "Chore language from the model is dropped")
        check(PatrickJournalVoice.evening(events: ["站會", "午餐"], modelText: nil).contains("站會、午餐"), "Two local events share the sentence")
        check(PatrickJournalVoice.weekly(lines: ["一起休息"], modelText: "這週要打卡") == "這週記得一起休息。", "A scored weekly line falls back")
        check(PatrickJournalVoice.weekly(lines: ["餵一口"], modelText: nil) == "這週平靜地過去了。", "Hidden chore lines do not fill the week")
        let eveningAt = PatrickJournalVoice.eveningFireDate(now: hk(2026, 10, 21, 15, 0), calendar: calendar)
        check(calendar.component(.hour, from: eveningAt!) == 21, "Before the window, the note waits until 21:00")
        check(PatrickJournalVoice.eveningFireDate(now: hk(2026, 10, 21, 23, 5), calendar: calendar) == nil, "After 23:00 the evening note is over")
        check(PatrickJournalVoice.isSunday(hk(2026, 10, 25, 18, 0), calendar: calendar), "25 October 2026 is the weekly page")
        check(!PatrickJournalVoice.isSunday(hk(2026, 10, 21, 18, 0), calendar: calendar), "A Wednesday is not the weekly page")

        check(PatrickMoodStars.raw(stars: 1) == "veryUnpleasant" && PatrickMoodStars.raw(stars: 5) == "veryPleasant", "Stars map onto the existing state of mind words")
        check(PatrickMoodStars.raw(stars: 0) == nil && PatrickMoodStars.raw(stars: 6) == nil, "Only five stars write")
        let company = (1...5).map { PatrickMoodStars.company(stars: $0) }.joined()
        check(!company.contains("判斷") && !company.contains("差") && !company.contains("餵"), "The reply stays with Sham and does not judge")
        check(PatrickMoodStars.shouldAsk(hour: 20, askedDay: nil, today: "2026-10-21", suppressed: false), "The evening ask happens once")
        check(!PatrickMoodStars.shouldAsk(hour: 20, askedDay: "2026-10-21", today: "2026-10-21", suppressed: false), "The second pass does not ask again")
        check(!PatrickMoodStars.shouldAsk(hour: 20, askedDay: nil, today: "2026-10-21", suppressed: true), "Sleep, focus, a meeting, or a ride skips the ask")
        check(!PatrickMoodStars.shouldAsk(hour: 18, askedDay: nil, today: "2026-10-21", suppressed: false), "Eighteen is before the ask")

        check(PatrickBathCharge.chargeLine(battery: 0.39) == "先充 20 分鐘，再去泡澡。", "Under 40 percent suggests a short charge")
        check(PatrickBathCharge.chargeLine(battery: 0.4) == nil, "40 percent does not suggest a charge")
        check(PatrickBathCharge.chargeLine(battery: nil) == nil, "An unknown battery is not treated as empty")
        check(PatrickBathCharge.wristLine == "洗完把手錶戴回來。", "Leaving the bath asks for the watch")

        check(PatrickPhoneLeft.pulses == 3, "The left-behind cue is three pulses")
        check(PatrickPhoneLeft.shouldAlert(wasReachable: true, reachable: false, atHome: true, already: false, suppressed: false), "An unreachable phone at home alerts once")
        check(!PatrickPhoneLeft.shouldAlert(wasReachable: false, reachable: false, atHome: true, already: false, suppressed: false), "A phone that was already away does not alert")
        check(!PatrickPhoneLeft.shouldAlert(wasReachable: true, reachable: false, atHome: false, already: false, suppressed: false), "A phone that left home with Sham stays quiet")
        check(!PatrickPhoneLeft.shouldAlert(wasReachable: true, reachable: false, atHome: true, already: false, suppressed: true), "The context gate holds the left-behind cue")
        check(!PatrickPhoneLeft.shouldAlert(wasReachable: true, reachable: true, atHome: true, already: false, suppressed: false), "A reachable phone is not left behind")

        var riding = PatrickExperienceSettings()
        riding.contextCommute = true
        let noon = hk(2026, 10, 21, 12, 0)
        let gate = PatrickContextSnapshot(commute: true, budget: 6)
        let held = PatrickWeekPlan.fold(settings: &riding, line: "先洗手？", hello: nil, knocks: 0, gate: gate, events: [],
                                        journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                        phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        check(held.line == PatrickWeekPlan.lookOut && held.knocks == 0 && held.phoneLeftPulses == 0, "A ride shows the window and defers every knock")
        check(riding.deferredLine == "先洗手？", "The reminder waits in the car")
        riding.contextCommute = nil
        let open = PatrickContextSnapshot(budget: 6)
        let released = PatrickWeekPlan.fold(settings: &riding, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                            journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                            phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        check(released.knocks == 1 && released.line == "先洗手？" && riding.deferredLine == nil, "Leaving the car delivers the held line once")

        var bath = PatrickExperienceSettings()
        bath.scene = .bath
        let started = PatrickWeekPlan.fold(settings: &bath, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                           journalLines: [], battery: 0.2, modelEvening: nil, modelWeekly: nil,
                                           phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        check(started.line == "先充 20 分鐘，再去泡澡。" && started.knocks == 1 && bath.bathFlow == true, "Starting a bath under 40 percent suggests charging")
        bath.scene = .automatic
        let ended = PatrickWeekPlan.fold(settings: &bath, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                         journalLines: [], battery: 0.8, modelEvening: nil, modelWeekly: nil,
                                         phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        check(ended.line == PatrickBathCharge.wristLine && bath.bathFlow == nil, "Ending the bath asks Sham to put the watch back on")

        var water = PatrickExperienceSettings()
        let entered = PatrickWeekPlan.fold(settings: &water, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                           journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                           phoneReachable: nil, waterSubmerged: true, writesJournal: false, now: noon, calendar: calendar)
        check(entered.line == PatrickWaterCue.enterLine && water.waterOn == true && entered.knocks == 0, "Entering the water changes clothes without a knock")
        check(PatrickAutomaticScene.resolve(selection: .automatic, activitySceneID: nil, charging: true, sleeping: false, focus: false, workout: false, meeting: false, water: true) == "exercise", "Water uses the existing sport scene")
        check(PatrickWaterCue.outfitID == "sport", "The swim-ring moment uses the sport outfit already in the wardrobe")
        let drained = PatrickWeekPlan.fold(settings: &water, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                           journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                           phoneReachable: nil, waterSubmerged: false, writesJournal: false, now: noon, calendar: calendar)
        check(drained.line == PatrickWaterCue.drainLine && drained.knocks == 1 && water.waterOn == nil, "Leaving the water asks to drain it")
        let unknown = PatrickWeekPlan.fold(settings: &water, line: "早安，Sham。", hello: "早安，Sham。", knocks: 0, gate: open, events: [],
                                           journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                           phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        check(water.waterOn == nil && unknown.line == "早安，Sham。", "An unavailable water sensor does not invent a swim")

        var phone = PatrickExperienceSettings()
        phone.phoneAtHome = true
        phone.phoneWasReachable = true
        let left = PatrickWeekPlan.fold(settings: &phone, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                        journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                        phoneReachable: false, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        check(left.phoneLeftPulses == 3 && left.knocks == 1 && phone.phoneLeftAlerted == true, "The transition spends one budget unit and pulses three times")
        let again = PatrickWeekPlan.fold(settings: &phone, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                         journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                         phoneReachable: false, waterSubmerged: nil, writesJournal: false, now: noon, calendar: calendar)
        check(again.phoneLeftPulses == 0, "The same departure does not pulse again")

        var mood = PatrickExperienceSettings()
        let ask = PatrickWeekPlan.fold(settings: &mood, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                       journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                       phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: hk(2026, 10, 21, 20, 0), calendar: calendar)
        check(ask.line == PatrickMoodStars.ask && mood.moodAskedDay == "2026-10-21", "The evening ask is shown once")
        let quietAsk = PatrickWeekPlan.fold(settings: &mood, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                            journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                            phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: hk(2026, 10, 21, 20, 30), calendar: calendar)
        check(quietAsk.line == nil, "The ask does not repeat half an hour later")

        var story = PatrickExperienceSettings()
        PatrickNightTheater.store(settings: &story, script: "一夜很安靜。我就在旁邊。今天慢慢來。", now: hk(2026, 10, 21, 7, 0), calendar: calendar)
        let shown = PatrickWeekPlan.fold(settings: &story, line: "早安，Sham。", hello: "早安，Sham。", knocks: 0, gate: open, events: [],
                                         journalLines: [], battery: 1, modelEvening: nil, modelWeekly: nil,
                                         phoneReachable: nil, waterSubmerged: nil, writesJournal: false, now: hk(2026, 10, 21, 7, 0), calendar: calendar)
        check(shown.line?.contains("一夜很安靜") == true && story.theaterUntilMS != nil && shown.knocks == 0, "The morning story plays without a knock")

        var journal = PatrickExperienceSettings()
        journal.moodAskedDay = "2026-10-21"
        let noted = PatrickWeekPlan.fold(settings: &journal, line: nil, hello: nil, knocks: 0, gate: open,
                                         events: [PatrickCalendarInterval(start: noon, end: noon, title: "站會")],
                                         journalLines: ["一起休息"], battery: 1, modelEvening: "去照顧一下", modelWeekly: nil,
                                         phoneReachable: nil, waterSubmerged: nil, writesJournal: true, now: hk(2026, 10, 21, 21, 10), calendar: calendar)
        check(noted.eveningNotice == "今天有站會。就這樣，很好。" && noted.knocks == 0, "The evening note is one notification and not a knock")
        check(journal.eveningNoteDay == "2026-10-21", "The evening note is marked for the day")
        let sunday = hk(2026, 10, 25, 11, 0)
        var week = PatrickExperienceSettings()
        let page = PatrickWeekPlan.fold(settings: &week, line: nil, hello: nil, knocks: 0, gate: open, events: [],
                                        journalLines: ["出門"], battery: 1, modelEvening: nil, modelWeekly: "今天要打卡",
                                        phoneReachable: nil, waterSubmerged: nil, writesJournal: true, now: sunday, calendar: calendar)
        check(week.weeklyPage == "這週記得出門。" && page.eveningNotice == "今天過完了，我在。", "Sunday keeps a local page and schedules the evening note for later")

        var stack = PatrickExperienceState()
        let idle = PatrickStackRelevance.make(experience: stack, at: noon, calendar: calendar).score
        stack.settings.waterOn = true
        let wet = PatrickStackRelevance.make(experience: stack, at: noon, calendar: calendar).score
        stack.settings.waterOn = nil
        stack.settings.scene = .sleeping
        let sleep = PatrickStackRelevance.make(experience: stack, at: noon, calendar: calendar).score
        check(wet > sleep && sleep > idle, "Water outranks sleep, which outranks an idle stack")
        let windows = PatrickWeekPlan.stackWindows(settings: PatrickExperienceSettings(), workingOut: true, now: noon, calendar: calendar)
        check(windows.contains { $0.reason == "運動" }, "A workout donates a stack window")
        check(PatrickWeekPlan.stackWindows(settings: PatrickExperienceSettings(), workingOut: false, now: noon, calendar: calendar).isEmpty, "An ordinary noon does not invent a stack moment")

        print("native week plan checks: \(count)")
    }
}
