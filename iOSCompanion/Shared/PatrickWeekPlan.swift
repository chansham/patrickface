import Foundation

/// P2 decisions that do not import HealthKit, CoreMotion, or RelevanceKit.
/// A story is a sentence. A zone only changes how much the existing body sways.
enum PatrickHeartZone: Int, Equatable, Sendable {
    case recover = 1, easy, steady, tempo, peak

    /// `maxBeats` stays 190 when age is unknown. A non-positive sample is no zone.
    static func zone(beatsPerMinute: Double, maxBeats: Double = 190) -> PatrickHeartZone? {
        guard beatsPerMinute > 0, maxBeats > 0, beatsPerMinute.isFinite, maxBeats.isFinite else { return nil }
        let ratio = beatsPerMinute / maxBeats
        if ratio < 0.6 { return .recover }
        if ratio < 0.7 { return .easy }
        if ratio < 0.8 { return .steady }
        if ratio < 0.9 { return .tempo }
        return .peak
    }

    /// Multiplies the existing exercise sway. Recover is quieter; peak is larger.
    var sway: Double {
        switch self {
        case .recover: 0.6
        case .easy: 1
        case .steady: 1.6
        case .tempo: 2.4
        case .peak: 3.2
        }
    }
}

enum PatrickKilometerMarks {
    /// The kilometer just completed, once. 999 m then 1000 m returns 1.
    /// The same kilometer, a backward sample, or anything under 1 km returns nil.
    static func crossed(previousMeters: Double, meters: Double) -> Int? {
        guard previousMeters.isFinite, meters.isFinite, previousMeters >= 0, meters >= 0 else { return nil }
        let before = Int(previousMeters / 1000)
        let after = Int(meters / 1000)
        guard after > before, after >= 1 else { return nil }
        return after
    }
}

struct PatrickNightBeat: Equatable, Sendable {
    var seconds: Double
    var line: String
}

enum PatrickNightMotion {
    /// A toss is a rise from a quiet sample through the threshold. Not a score.
    static func tosses(_ magnitudes: [Double], quiet: Double = 1.05, threshold: Double = 1.2) -> Int {
        var previous: Double?
        var count = 0
        for sample in magnitudes where sample.isFinite {
            if let previous, previous <= quiet, sample >= threshold { count += 1 }
            previous = sample
        }
        return count
    }
}

enum PatrickNightTheater {
    static func beats(quietMinutes: Double, tosses: Int, wakes: Int) -> [PatrickNightBeat] {
        guard quietMinutes >= 30 || tosses > 0 || wakes > 0 else { return [] }
        let opener: String
        if quietMinutes >= 30 && tosses == 0 && wakes == 0 {
            opener = "一夜很安靜。"
        } else if tosses >= 3 {
            opener = "夜裡翻過幾次身。"
        } else if wakes >= 2 {
            opener = "中間醒過，我沒出聲。"
        } else if quietMinutes >= 30 {
            opener = "夜裡大多安靜。"
        } else {
            opener = "昨夜我在旁邊。"
        }
        let middle = wakes > 0 ? "醒的時候我也醒著。" : "我就在旁邊。"
        return [
            PatrickNightBeat(seconds: 3, line: opener),
            PatrickNightBeat(seconds: 4, line: middle),
            PatrickNightBeat(seconds: 3, line: "今天慢慢來。")
        ]
    }

    static func script(quietMinutes: Double, tosses: Int, wakes: Int) -> String? {
        let rows = beats(quietMinutes: quietMinutes, tosses: tosses, wakes: wakes)
        guard !rows.isEmpty else { return nil }
        return rows.map(\.line).joined()
    }

    static func store(settings: inout PatrickExperienceSettings, script text: String?, now: Date, calendar: Calendar = PatrickHKHolidays.calendar) {
        guard let text, !text.isEmpty else { return }
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        guard settings.nightStoryDay != day else { return }
        settings.nightStory = text
        settings.nightStoryDay = day
        settings.theaterUntilMS = nil
    }
}

enum PatrickJournalVoice {
    static let banned = ["餵", "飽足", "親密", "點心", "照顧", "任務", "打卡", "分數", "診斷", "生病"]

    static func accept(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmed.count) else { return nil }
        guard banned.allSatisfy({ !trimmed.contains($0) }) else { return nil }
        let cjk = trimmed.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        guard cjk >= 4 else { return nil }
        return trimmed
    }

    static func evening(events: [String], modelText: String?) -> String {
        if let modelText, let accepted = accept(modelText) { return accepted }
        let names = events.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(2)
        if names.isEmpty { return "今天過完了，我在。" }
        return "今天有\(names.joined(separator: "、"))。就這樣，很好。"
    }

    static func weekly(lines: [String], modelText: String?) -> String {
        if let modelText, let accepted = accept(modelText) { return accepted }
        let kept = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { value in
            !value.isEmpty && !PatrickJournalFilter.hides(value)
        }.suffix(3)
        if kept.isEmpty { return "這週平靜地過去了。" }
        return "這週記得\(kept.joined(separator: "，"))。"
    }

    /// One note, at 21:00, or two seconds from now when the app opens inside the window.
    /// After 23:00 the day has missed it. A fire date inside the sleep window is skipped by the caller.
    static func eveningFireDate(now: Date, calendar: Calendar) -> Date? {
        let hour = calendar.component(.hour, from: now)
        if hour >= 23 { return nil }
        if hour >= 21 { return now.addingTimeInterval(2) }
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = 21
        parts.minute = 0
        parts.second = 0
        return calendar.date(from: parts)
    }

    static func isSunday(_ date: Date, calendar: Calendar) -> Bool {
        calendar.component(.weekday, from: date) == 1
    }
}

enum PatrickMoodStars {
    static let ask = "今天的心情，點一下星星。"

    static func raw(stars: Int) -> String? {
        switch stars {
        case 1: "veryUnpleasant"
        case 2: "unpleasant"
        case 3: "neutral"
        case 4: "pleasant"
        case 5: "veryPleasant"
        default: nil
        }
    }

    static func company(stars: Int) -> String {
        switch stars {
        case 1: "我在。今天可以慢一點。"
        case 2: "我陪著你。"
        case 3: "今天這樣也很好。"
        case 4: "聽到了，我在。"
        case 5: "跟你一起待著。"
        default: "我在。"
        }
    }

    static func shouldAsk(hour: Int, askedDay: String?, today: String, suppressed: Bool) -> Bool {
        !suppressed && askedDay != today && (19..<23).contains(hour)
    }
}

enum PatrickBathCharge {
    static let wristLine = "洗完把手錶戴回來。"

    static func chargeLine(battery: Double?) -> String? {
        guard let battery, battery >= 0, battery < 0.4 else { return nil }
        return "先充 20 分鐘，再去泡澡。"
    }
}

enum PatrickPhoneLeft {
    static let pulses = 3
    static let line = "手機還在家。"

    static func shouldAlert(wasReachable: Bool, reachable: Bool, atHome: Bool, already: Bool, suppressed: Bool) -> Bool {
        wasReachable && !reachable && atHome && !already && !suppressed
    }
}

enum PatrickWaterCue {
    /// The wardrobe has no swim-ring drawing. Auto mode uses the existing sport outfit.
    static let outfitID = "sport"
    static let enterLine = "下水了，泳圈模式。"
    static let drainLine = "上岸了，把水倒一倒。"
}

struct PatrickStackWindow: Equatable, Sendable {
    var start: Date
    var end: Date
    var reason: String
}

enum PatrickWeekPlan {
    static let lookOut = "坐車看窗外。"

    static func stackWindows(settings: PatrickExperienceSettings, workingOut: Bool, now: Date, calendar: Calendar = PatrickHKHolidays.calendar) -> [PatrickStackWindow] {
        var windows: [PatrickStackWindow] = []
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        if workingOut {
            windows.append(PatrickStackWindow(start: now, end: now.addingTimeInterval(60 * 60), reason: "運動"))
        }
        if settings.waterOn == true {
            windows.append(PatrickStackWindow(start: now, end: now.addingTimeInterval(20 * 60), reason: "玩水"))
        }
        if settings.nightStoryDay == day, (5..<11).contains(hour) {
            windows.append(PatrickStackWindow(start: now, end: now.addingTimeInterval(10 * 60), reason: "昨夜"))
        }
        if settings.eveningNoteDay == day, (21..<23).contains(hour) {
            windows.append(PatrickStackWindow(start: now, end: now.addingTimeInterval(30 * 60), reason: "晚上"))
        }
        if settings.contextCommute == true {
            windows.append(PatrickStackWindow(start: now, end: now.addingTimeInterval(20 * 60), reason: "乘車"))
        }
        return windows
    }

    static func fold(settings: inout PatrickExperienceSettings, line incoming: String?, hello: String?, knocks incomingKnocks: Int,
                     gate: PatrickContextSnapshot, events: [PatrickCalendarInterval], journalLines: [String], battery: Double?,
                     modelEvening: String?, modelWeekly: String?, phoneReachable: Bool?, waterSubmerged: Bool?,
                     writesJournal: Bool, now: Date, calendar: Calendar) -> PatrickWeekFold {
        var line = incoming
        var knocks = incomingKnocks
        var journal: [String] = []
        var pulses = 0
        var eveningNotice: String?
        var eveningFireAt: Date?
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let suppressed = gate.suppressesProactive

        let bathing = settings.scene == .bath
        if bathing && settings.bathFlow != true {
            settings.bathFlow = true
            if let charge = PatrickBathCharge.chargeLine(battery: battery) {
                line = charge
                journal.append(charge)
                _ = claim(settings: &settings, gate: gate, knocks: &knocks, now: now, calendar: calendar)
            }
        } else if !bathing && settings.bathFlow == true {
            settings.bathFlow = nil
            line = PatrickBathCharge.wristLine
            journal.append(PatrickBathCharge.wristLine)
            _ = claim(settings: &settings, gate: gate, knocks: &knocks, now: now, calendar: calendar)
        }

        if let submerged = waterSubmerged {
            if submerged && settings.waterOn != true {
                settings.waterOn = true
                line = PatrickWaterCue.enterLine
                journal.append(PatrickWaterCue.enterLine)
            } else if !submerged && settings.waterOn == true {
                settings.waterOn = nil
                line = PatrickWaterCue.drainLine
                journal.append(PatrickWaterCue.drainLine)
                _ = claim(settings: &settings, gate: gate, knocks: &knocks, now: now, calendar: calendar)
            }
        }

        if let reachable = phoneReachable {
            let was = settings.phoneWasReachable == true
            let atHome = settings.phoneAtHome == true
            let already = settings.phoneLeftAlerted == true
            if PatrickPhoneLeft.shouldAlert(wasReachable: was, reachable: reachable, atHome: atHome, already: already, suppressed: suppressed),
               claim(settings: &settings, gate: gate, knocks: &knocks, now: now, calendar: calendar) {
                settings.phoneLeftAlerted = true
                settings.phoneWasReachable = false
                pulses = PatrickPhoneLeft.pulses
                line = PatrickPhoneLeft.line
                journal.append(PatrickPhoneLeft.line)
            } else if reachable || !was || !atHome || already {
                if reachable { settings.phoneLeftAlerted = nil }
                settings.phoneWasReachable = reachable
            }
        }

        if !gate.commute {
            if settings.commuteNoted == true { settings.commuteNoted = nil }
            if let held = settings.deferredLine, replaceable(line, hello: hello),
               claim(settings: &settings, gate: gate, knocks: &knocks, now: now, calendar: calendar) {
                settings.deferredLine = nil
                line = held
                journal.append(held)
            }
            if let story = settings.nightStory, settings.nightStoryDay == day, !story.isEmpty,
               (5..<11).contains(hour), !suppressed, replaceable(line, hello: hello) {
                if settings.theaterUntilMS == nil {
                    settings.theaterUntilMS = ((now.timeIntervalSince1970 + 10) * 1000).rounded()
                }
                if let until = settings.theaterUntilMS, until >= now.timeIntervalSince1970 * 1000 {
                    line = story
                }
            }
            if PatrickMoodStars.shouldAsk(hour: hour, askedDay: settings.moodAskedDay, today: day, suppressed: suppressed),
               replaceable(line, hello: hello) {
                settings.moodAskedDay = day
                line = PatrickMoodStars.ask
                if claim(settings: &settings, gate: gate, knocks: &knocks, now: now, calendar: calendar) {
                    journal.append(PatrickMoodStars.ask)
                }
            }
            if writesJournal, settings.eveningNoteDay != day,
               let fireAt = PatrickJournalVoice.eveningFireDate(now: now, calendar: calendar),
               !settings.isSleepTime(fireAt, calendar: calendar) {
                let sentence = PatrickJournalVoice.evening(events: events.map(\.title), modelText: modelEvening)
                settings.eveningNoteDay = day
                settings.eveningLine = sentence
                eveningNotice = sentence
                eveningFireAt = fireAt
                if hour >= 21, replaceable(line, hello: hello) { line = sentence }
            }
            if writesJournal, PatrickJournalVoice.isSunday(now, calendar: calendar), settings.weeklyPageDay != day {
                settings.weeklyPageDay = day
                settings.weeklyPage = PatrickJournalVoice.weekly(lines: journalLines, modelText: modelWeekly)
            }
        } else {
            if let line, line != Self.lookOut, settings.deferredLine == nil, line != hello {
                settings.deferredLine = line
            }
            line = Self.lookOut
            knocks = 0
            pulses = 0
            if settings.commuteNoted != true {
                settings.commuteNoted = true
                journal.append(Self.lookOut)
            }
        }
        return PatrickWeekFold(line: line, knocks: knocks, journal: journal, phoneLeftPulses: pulses,
                               eveningNotice: eveningNotice, eveningFireAt: eveningFireAt)
    }

    private static func replaceable(_ line: String?, hello: String?) -> Bool {
        guard let line, !line.isEmpty else { return true }
        return line == hello || line == lookOut || line.hasPrefix("早安")
    }

    private static func claim(settings: inout PatrickExperienceSettings, gate: PatrickContextSnapshot, knocks: inout Int, now: Date, calendar: Calendar) -> Bool {
        guard knocks == 0, !gate.suppressesProactive else { return false }
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        let count = settings.proactiveHapticDay == day ? (settings.proactiveHapticCount ?? 0) : 0
        guard count < settings.dailyHapticBudget else { return false }
        if settings.proactiveHapticDay != day {
            settings.proactiveHapticDay = day
            settings.proactiveHapticCount = 0
        }
        settings.proactiveHapticCount = (settings.proactiveHapticCount ?? 0) + 1
        knocks += 1
        return true
    }
}

struct PatrickWeekFold: Equatable, Sendable {
    var line: String?
    var knocks = 0
    var journal: [String] = []
    var phoneLeftPulses = 0
    var eveningNotice: String?
    var eveningFireAt: Date?
}
