import Foundation

@main struct NativeDayPlanChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ text: String) {
        precondition(condition(), text)
        count += 1
    }

    static func hk(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.calendar = PatrickHKHolidays.calendar
        parts.timeZone = PatrickHKHolidays.calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return parts.date!
    }

    static func main() {
        let calendar = PatrickHKHolidays.calendar
        check(PatrickDayPlan.nightTarget(enabled: false, skipRestDays: true, wakeMinute: 360, now: hk(2026, 10, 21, 5, 0)) == nil, "Night alarm stays off")
        let wednesday = PatrickDayPlan.nightTarget(enabled: true, skipRestDays: true, wakeMinute: 360, now: hk(2026, 10, 21, 5, 0))
        check(wednesday == hk(2026, 10, 21, 6, 0), "A workday morning is the next alarm")
        let holiday = PatrickDayPlan.nightTarget(enabled: true, skipRestDays: true, wakeMinute: 360, now: hk(2026, 10, 1, 5, 0))
        check(holiday == hk(2026, 10, 2, 6, 0), "National Day is skipped")
        let holidayKept = PatrickDayPlan.nightTarget(enabled: true, skipRestDays: false, wakeMinute: 360, now: hk(2026, 10, 1, 5, 0))
        check(holidayKept == hk(2026, 10, 1, 6, 0), "Rest-day skip can be turned off")
        let weekend = PatrickDayPlan.nightTarget(enabled: true, skipRestDays: true, wakeMinute: 360, now: hk(2026, 10, 23, 22, 0))
        check(weekend == hk(2026, 10, 26, 6, 0), "Saturday and Sunday are skipped")
        let afterHolidayWeekend = PatrickDayPlan.nightTarget(enabled: true, skipRestDays: true, wakeMinute: 360, now: hk(2026, 10, 17, 22, 0))
        check(afterHolidayWeekend == hk(2026, 10, 20, 6, 0), "Weekend plus Chung Yeung is skipped")
        let cues = PatrickDayPlan.nightCues(target: hk(2026, 10, 21, 6, 0), now: hk(2026, 10, 21, 5, 0), role: .watch)
        check(cues.map(\.strength) == [.soft, .medium, .firm], "Night cues get stronger")
        check(cues.map(\.playsSound) == [false, false, true], "Only the last night cue rings")
        check(PatrickDayPlan.nightCues(target: hk(2026, 10, 21, 6, 0), now: hk(2026, 10, 21, 5, 0), role: .phone).map(\.strength) == [.firm], "Phone fallback is the firm cue only")
        let sundayNap = PatrickDayPlan.napCues(endsAt: hk(2026, 10, 18, 15, 0), now: hk(2026, 10, 18, 14, 30), role: .watch)
        check(sundayNap.map(\.strength) == [.soft, .medium] && sundayNap.allSatisfy { !$0.playsSound }, "A Sunday nap still has light cues and no second firm alert")
        check(PatrickDayPlan.napCues(endsAt: hk(2026, 10, 18, 15, 0), now: hk(2026, 10, 18, 14, 30), role: .none).isEmpty, "The device that does not own alerts schedules nothing")

        let baseline = Array(repeating: 8.0, count: 7)
        let short = PatrickMorningSeries(metric: .sleepHours, values: baseline + [7], overnightIndex: 7)
        let sentence = PatrickDayPlan.morningSentence([short])
        check(sentence == "昨晚少睡了 1 小時，今天慢慢來。", "One short night speaks")
        check(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .sleepHours, values: Array(repeating: 8.0, count: 6) + [7], overnightIndex: 6)]) == nil, "Six baseline days stay silent")
        check(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .sleepHours, values: baseline + [7.2], overnightIndex: 7)]) == nil, "Less than one hour stays silent")
        let hrv = PatrickMorningSeries(metric: .hrvSDNN, values: Array(repeating: 50, count: 7) + [42], overnightIndex: 7)
        check(PatrickDayPlan.morningSentence([hrv])?.contains("心率變異偏低") == true, "HRV 15 percent under the median speaks")
        check(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .hrvSDNN, values: Array(repeating: 50, count: 7) + [43], overnightIndex: 7)]) == nil, "HRV inside 15 percent stays silent")
        let pulse = PatrickMorningSeries(metric: .restingHeartRate, values: Array(repeating: 60, count: 7) + [65], overnightIndex: 7)
        check(PatrickDayPlan.morningSentence([pulse]) == "心率偏高，今天慢慢來。", "Resting heart rate five beats over speaks")
        check(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .restingHeartRate, values: Array(repeating: 60, count: 7) + [64], overnightIndex: 7)]) == nil, "Four beats stay silent")
        let wrist = PatrickMorningSeries(metric: .wristTemperature, values: Array(repeating: 36.5, count: 7) + [36.8], overnightIndex: 7)
        check(PatrickDayPlan.morningSentence([wrist])?.contains("手腕溫度偏高") == true, "Wrist temperature 0.3 degrees over speaks")
        check(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .wristTemperature, values: Array(repeating: 36.5, count: 7) + [36.7], overnightIndex: 7)]) == nil, "Wrist temperature inside 0.3 stays silent")
        let breath = PatrickMorningSeries(metric: .respiratoryRate, values: Array(repeating: 14, count: 7) + [15], overnightIndex: 7)
        check(PatrickDayPlan.morningSentence([breath])?.contains("呼吸偏快") == true, "Respiratory rate one breath over speaks")
        check(PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .respiratoryRate, values: Array(repeating: 14, count: 7) + [14.9], overnightIndex: 7)]) == nil, "Respiratory rate inside one breath stays silent")
        let both = PatrickDayPlan.morningSentence([short, pulse])
        check(both == "昨晚少睡了 1 小時，心率也偏高，今天慢慢來。", "Sleep and heart rate share one sentence")
        let streakValues = Array(repeating: 8.0, count: 7) + [6, 6, 6]
        let streak = PatrickDayPlan.morningSentence([PatrickMorningSeries(metric: .sleepHours, values: streakValues, overnightIndex: 9)])
        check(streak?.contains("連續幾天都偏離你自己的平常") == true, "Two earlier deviant days add the streak clause")
        check(streak?.contains("感冒") == false && streak?.contains("着涼") == false && streak?.contains("著涼") == false, "The report does not name an illness")
        check(PatrickDayPlan.morningSentence([]) == nil, "No overnight data stays silent")
        func series(_ metric: PatrickMorningMetric, _ baseline: Double, _ overnight: Double, _ days: Int) -> PatrickMorningSeries {
            PatrickMorningSeries(metric: metric, values: Array(repeating: baseline, count: days) + [overnight], overnightIndex: days)
        }
        let longSleep = series(.sleepHours, 8, 7, 14)
        let longHRV = series(.hrvSDNN, 50, 42, 14)
        let longPulse = series(.restingHeartRate, 60, 65, 14)
        let slower = PatrickDayPlan.morningSentence([longSleep, longHRV, longPulse])
        check(slower == PatrickColdPrecursor.text, "Fourteen days and three signals use the slower sentence")
        check(slower?.contains("感冒") == false && slower?.contains("診斷") == false && slower?.contains("分數") == false, "The slower sentence is not a diagnosis")
        let thirteen = [series(.sleepHours, 8, 7, 13), series(.hrvSDNN, 50, 42, 13), series(.restingHeartRate, 60, 65, 13)]
        check(PatrickColdPrecursor.sentence(thirteen) == nil, "Thirteen days do not cross the longer threshold")
        let ordinary = PatrickDayPlan.morningSentence(thirteen)
        check(ordinary?.contains("昨晚少睡了") == true && ordinary != PatrickColdPrecursor.text, "Thirteen days keep the ordinary fact sentence")
        check(PatrickColdPrecursor.sentence([longSleep, longHRV]) == nil, "Two signals at fourteen days stay silent on the longer line")

        let warnings = #"{"WRAIN":{"code":"WRAINY","name":"黃色暴雨警告信號"}}"#.data(using: .utf8)!
        check(PatrickDayPlan.warnings(from: warnings) == ["WRAINY"], "Warning summary reads the code")
        check(PatrickDayPlan.warnings(from: Data("{}".utf8)).isEmpty, "An empty warning summary is no warning")
        let reading = #"{"temperature":{"data":[{"place":"京士柏","value":27},{"place":"香港天文台","value":28}]},"rainfall":{"data":[{"place":"香港天文台","max":1}]}}"#.data(using: .utf8)!
        let parsed = PatrickDayPlan.temperatureAndRain(from: reading)
        check(parsed.0 == 28 && parsed.1 == 1, "Observatory temperature and rain prefer the Hong Kong Observatory station")
        let drizzle = PatrickDayPlan.goingOutCard(reading: PatrickObservatoryReading(rainfallMM: 0.5), battery: 0.8, longOuting: false)
        check(drizzle.lines.contains("帶傘") && drizzle.attention == false, "Half a millimetre of rain means an umbrella without a storm knock")
        let typhoon = PatrickDayPlan.goingOutCard(reading: PatrickObservatoryReading(warningCodes: ["TC8NE"], temperatureC: 27), battery: nil, longOuting: false)
        check(typhoon.attention && typhoon.lines.contains("帶傘") && !typhoon.lines.contains { $0.contains("口罩") }, "A typhoon signal asks for an umbrella and never a mask")
        let cold = PatrickDayPlan.goingOutCard(reading: PatrickObservatoryReading(temperatureC: 18), battery: 1, longOuting: false)
        check(cold.lines.contains("加件外套"), "18 degrees adds a jacket")
        let charger = PatrickDayPlan.goingOutCard(reading: PatrickObservatoryReading(temperatureC: 26), battery: 0.29, longOuting: true)
        check(charger.lines.contains { $0.contains("充電器") }, "A low watch and a long outing add a charger")
        check(!PatrickDayPlan.goingOutCard(reading: PatrickObservatoryReading(temperatureC: 26), battery: 0.29, longOuting: false).lines.contains { $0.contains("充電器") }, "A short outing does not add a charger")

        let now = hk(2026, 10, 21, 15, 0)
        let overlap = [
            PatrickCalendarInterval(start: hk(2026, 10, 21, 14, 0), end: hk(2026, 10, 21, 15, 30)),
            PatrickCalendarInterval(start: hk(2026, 10, 21, 15, 0), end: hk(2026, 10, 21, 16, 0))
        ]
        check(PatrickDayPlan.merged(overlap).count == 1, "Overlapping events become one block")
        check(PatrickDayPlan.standPrompt(events: overlap, now: now, sittingMinutes: 80, contextSuppresses: false, budgetRemaining: 6) == nil, "Inside a merged event there is no stand reminder")
        let soon = [PatrickCalendarInterval(start: now.addingTimeInterval(4 * 60), end: now.addingTimeInterval(60 * 60))]
        check(PatrickDayPlan.standPrompt(events: soon, now: now, sittingMinutes: 80, contextSuppresses: false, budgetRemaining: 6) == nil, "A four minute gap is too short")
        let gap = [PatrickCalendarInterval(start: now.addingTimeInterval(5 * 60), end: now.addingTimeInterval(60 * 60), title: "站會")]
        check(PatrickDayPlan.standPrompt(events: gap, now: now, sittingMinutes: 70, contextSuppresses: false, budgetRemaining: 1) == "坐了 70 分鐘，下個會前有 5 分鐘，倒杯水？", "A five minute gap after 70 minutes is the reminder")
        check(PatrickDayPlan.standPrompt(events: gap, now: now, sittingMinutes: 69, contextSuppresses: false, budgetRemaining: 6) == nil, "69 minutes is not yet a reminder")
        check(PatrickDayPlan.standPrompt(events: gap, now: now, sittingMinutes: 80, contextSuppresses: true, budgetRemaining: 6) == nil, "A closed context gate hides the reminder")
        check(PatrickDayPlan.standPrompt(events: gap, now: now, sittingMinutes: 80, contextSuppresses: false, budgetRemaining: 0) == nil, "A spent haptic budget hides the reminder")
        check(PatrickDayPlan.standPrompt(events: [], now: now, sittingMinutes: 80, contextSuppresses: false, budgetRemaining: 6) == nil, "An empty calendar is not a gap")
        check(PatrickDayPlan.longOuting([PatrickCalendarInterval(start: now.addingTimeInterval(30 * 60), end: now.addingTimeInterval(4 * 3600))], now: now), "Three hours away counts as a long outing")

        let arrived = now.addingTimeInterval(-10 * 60)
        check(PatrickDayPlan.handwashInvite(arrivedAt: arrived, washedAt: nil, now: now, contextSuppresses: false, alreadyAsked: false, budgetRemaining: 6) == "先洗手？", "Ten minutes after arriving asks once")
        check(PatrickDayPlan.handwashInvite(arrivedAt: now.addingTimeInterval(-31 * 60), washedAt: nil, now: now, contextSuppresses: false, alreadyAsked: false, budgetRemaining: 6) == nil, "The handwash window closes after 30 minutes")
        check(PatrickDayPlan.handwashInvite(arrivedAt: arrived, washedAt: now.addingTimeInterval(-60), now: now, contextSuppresses: false, alreadyAsked: false, budgetRemaining: 6) == nil, "A wash after arrival clears the reminder")
        check(PatrickDayPlan.handwashInvite(arrivedAt: arrived, washedAt: nil, now: now, contextSuppresses: true, alreadyAsked: false, budgetRemaining: 6) == nil, "Handwash stays quiet in a meeting or at night")
        check(PatrickDayPlan.handwashInvite(arrivedAt: nil, washedAt: nil, now: now, contextSuppresses: false, alreadyAsked: false, budgetRemaining: 6) == nil, "No arrival means no handwash reminder")
        check(PatrickDayPlan.handwashInvite(arrivedAt: arrived, washedAt: nil, now: now, contextSuppresses: false, alreadyAsked: false, budgetRemaining: 0) == nil, "Handwash respects the haptic budget")

        check(PatrickDayPlan.acceptButler("出門看一下天文台的卡片。") != nil, "A short Traditional Chinese sentence is kept")
        check(PatrickDayPlan.acceptButler("去餵食吧") == nil, "Feeding talk is rejected")
        check(PatrickDayPlan.acceptButler(String(repeating: "星", count: 41)) == nil, "More than 40 characters is rejected")
        check(PatrickDayPlan.butlerSentence(.tired, name: "Sham", modelText: "hello") == "Sham累了就慢慢來，我在。", "A model miss falls back to the fixed sentence")
        check(PatrickDayPlan.greeting(name: "Sham", hour: 8, report: nil, weather: nil, firstEvent: nil, suppressed: false) == "早安，Sham。", "Morning greeting uses the name")
        check(PatrickDayPlan.greeting(name: "Sham", hour: 8, report: "昨晚少睡了 1 小時，今天慢慢來。", weather: "天文台 28 度", firstEvent: "站會", suppressed: false) == "早安，Sham。昨晚少睡了 1 小時，今天慢慢來。", "A deviant morning replaces the weather line")
        check(PatrickDayPlan.greeting(name: "Sham", hour: 8, report: nil, weather: nil, firstEvent: nil, suppressed: true) == nil, "Meetings, focus, commute, sleep and workouts stay quiet")
        check(PatrickDayPlan.greeting(name: "Sham", hour: 4, report: nil, weather: nil, firstEvent: nil, suppressed: false) == nil, "Outside the morning window there is no greeting")
        check(PatrickDayPlan.greeting(name: " Sham ", hour: 8, report: nil, weather: "天文台 28 度", firstEvent: "站會", suppressed: false) == "早安，Sham。天文台 28 度，接著是站會。", "Weather and the first event share the greeting")

        var settings = PatrickExperienceSettings()
        settings.wakeAlarmEnabled = true
        settings.proactiveHapticBudget = 0
        let quietMorning = hk(2026, 10, 21, 8, 0)
        let advance = PatrickDayPlan.advance(settings: &settings, activity: nil, events: [
            PatrickCalendarInterval(start: quietMorning.addingTimeInterval(5 * 60), end: quietMorning.addingTimeInterval(3600))
        ], sittingMinutes: 90, battery: 0.2, role: .watch, now: quietMorning, calendar: calendar)
        check(!advance.wake.isEmpty && advance.knocks == 0, "An enabled alarm does not spend the knock budget")
        check(settings.dayLine == "早安，Sham。", "With no deviant report the greeting is only the name")
        check(!settings.dayLine!.contains("倒杯水"), "Budget zero does not nag about standing")
        settings.contextMeeting = true
        settings.proactiveHapticBudget = 6
        settings.proactiveHapticCount = 0
        settings.greetedDay = nil
        let blocked = PatrickDayPlan.advance(settings: &settings, activity: nil, events: [
            PatrickCalendarInterval(start: quietMorning.addingTimeInterval(10 * 60), end: quietMorning.addingTimeInterval(3600))
        ], sittingMinutes: 90, battery: 1, role: .none, now: quietMorning, calendar: calendar)
        check(blocked.knocks == 0 && settings.dayLine == nil, "A meeting closes the gate for greeting and knocks")
        print("native day plan checks: \(count)")
    }
}
