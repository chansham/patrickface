import Foundation

/// Daytime companion decisions that do not import HealthKit, EventKit, location,
/// or a language model. Callers pass the readings they already have.
enum PatrickWakeStrength: String, Equatable, Sendable { case soft, medium, firm }

enum PatrickWakeRole: Equatable, Sendable { case none, watch, phone }

struct PatrickWakeCue: Equatable, Sendable {
    var fireAt: Date
    var identifier: String
    var title: String
    var body: String
    var strength: PatrickWakeStrength
    var playsSound: Bool
    static let prefix = "patrick.wake."
}

struct PatrickCalendarInterval: Equatable, Sendable {
    var start: Date
    var end: Date
    var title: String = ""
}

struct PatrickObservatoryReading: Equatable, Sendable {
    var warningCodes: [String] = []
    var temperatureC: Double?
    var rainfallMM: Double?
}

struct PatrickGoingOutCard: Equatable, Sendable {
    var lines: [String]
    var attention: Bool
}

enum PatrickMorningMetric: String, CaseIterable, Equatable, Sendable {
    case sleepHours, hrvSDNN, restingHeartRate, wristTemperature, respiratoryRate
}

struct PatrickMorningSeries: Equatable, Sendable {
    var metric: PatrickMorningMetric
    /// Oldest first. The overnight value is `values[overnightIndex]` when present.
    var values: [Double]
    var overnightIndex: Int?
}

enum PatrickButlerPhrase: String, CaseIterable, Equatable, Sendable {
    case leaving, arrived, nap, goodNight, tired
}

struct PatrickDayAdvance: Equatable, Sendable {
    var knocks = 0
    var wake: [PatrickWakeCue] = []
    var journal: [String] = []
}

enum PatrickDayPlan {
    static let napChoices = [20, 25, 30]

    static func boundedNap(_ minutes: Int) -> Int { napChoices.contains(minutes) ? minutes : 25 }

    static func nightTarget(enabled: Bool, skipRestDays: Bool, wakeMinute: Int, now: Date) -> Date? {
        guard enabled, (0..<1440).contains(wakeMinute) else { return nil }
        let calendar = PatrickHKHolidays.calendar
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: now)) else { return nil }
        for offset in 0..<16 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let target = calendar.date(byAdding: .minute, value: wakeMinute, to: day) else { continue }
            if target <= now { continue }
            if skipRestDays, !PatrickHKHolidays.isWorkday(target) { continue }
            return target
        }
        return nil
    }

    static func nightCues(target: Date, now: Date, role: PatrickWakeRole) -> [PatrickWakeCue] {
        guard role != .none else { return [] }
        let plan: [(Int, PatrickWakeStrength, Bool, String)] = [
            (-20, .soft, false, "快到了，我輕輕叫你。"),
            (-10, .medium, false, "再過十分鐘。"),
            (0, .firm, true, "早安。該起來了。")
        ]
        return plan.compactMap { offset, strength, sound, body in
            if role == .phone, strength != .firm { return nil }
            let fireAt = target.addingTimeInterval(TimeInterval(offset * 60))
            guard fireAt > now else { return nil }
            let stamp = Int(target.timeIntervalSince1970)
            return PatrickWakeCue(fireAt: fireAt, identifier: "\(PatrickWakeCue.prefix)night.\(stamp).\(strength.rawValue)",
                                  title: "派大星", body: body, strength: strength, playsSound: sound)
        }
    }

    /// Soft and medium only. The countdown alert already owns the end, so a nap
    /// does not add a second firm cue. A nap the person just started still fires
    /// on a Sunday.
    static func napCues(endsAt: Date?, now: Date, role: PatrickWakeRole) -> [PatrickWakeCue] {
        guard role != .none, let endsAt else { return [] }
        let plan: [(Int, PatrickWakeStrength, String)] = [(-5, .soft, "午睡快結束了。"), (-2, .medium, "再兩分鐘。")]
        return plan.compactMap { offset, strength, body in
            let fireAt = endsAt.addingTimeInterval(TimeInterval(offset * 60))
            guard fireAt > now, fireAt < endsAt else { return nil }
            let stamp = Int(endsAt.timeIntervalSince1970)
            return PatrickWakeCue(fireAt: fireAt, identifier: "\(PatrickWakeCue.prefix)nap.\(stamp).\(strength.rawValue)",
                                  title: "派大星", body: body, strength: strength, playsSound: false)
        }
    }

    static func wakeCues(settings: PatrickExperienceSettings, napEndsAt: Date?, role: PatrickWakeRole, now: Date) -> [PatrickWakeCue] {
        let phoneAllowsNight = role == .watch || (role == .phone && settings.phoneWakeFallback)
        let nightRole: PatrickWakeRole = phoneAllowsNight ? role : .none
        let target = nightTarget(enabled: settings.wakeAlarmOn, skipRestDays: settings.skipsWakeOnRestDays,
                                 wakeMinute: settings.effectiveWakeMinute, now: now)
        let night = target.map { nightCues(target: $0, now: now, role: nightRole) } ?? []
        return night + napCues(endsAt: napEndsAt, now: now, role: role)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return sorted[middle - 1] / 2 + sorted[middle] / 2 }
        return sorted[middle]
    }

    /// Nil when the personal baseline is thinner than seven days or the overnight
    /// value stays inside the threshold. The sentence never names an illness.
    static func morningSentence(_ series: [PatrickMorningSeries]) -> String? {
        var facts: [String] = []
        var streak = 0
        for metric in PatrickMorningMetric.allCases {
            guard let item = series.first(where: { $0.metric == metric }),
                  let index = item.overnightIndex, item.values.indices.contains(index) else { continue }
            let prior = Array(item.values[..<index]).filter(\.isFinite)
            guard prior.count >= 7, let baseline = median(prior) else { continue }
            let overnight = item.values[index]
            guard overnight.isFinite, deviates(metric, overnight: overnight, baseline: baseline) else { continue }
            facts.append(fact(metric, overnight: overnight, baseline: baseline, leading: facts.isEmpty))
            streak = max(streak, consecutive(metric, values: prior, baseline: baseline))
        }
        guard !facts.isEmpty else { return nil }
        if streak >= 2 {
            return facts.joined(separator: "，") + "。連續幾天都偏離你自己的平常，今天慢慢來。"
        }
        return facts.joined(separator: "，") + "，今天慢慢來。"
    }

    static func deviates(_ metric: PatrickMorningMetric, overnight: Double, baseline: Double) -> Bool {
        switch metric {
        case .sleepHours: return overnight <= baseline - 1 + 0.000_001
        case .hrvSDNN: return baseline > 0 && overnight <= baseline * 0.85 + 0.000_001
        case .restingHeartRate: return overnight + 0.000_001 >= baseline + 5
        case .wristTemperature: return overnight + 0.000_001 >= baseline + 0.3
        case .respiratoryRate: return overnight + 0.000_001 >= baseline + 1
        }
    }

    private static func consecutive(_ metric: PatrickMorningMetric, values: [Double], baseline: Double) -> Int {
        var count = 0
        for value in values.reversed() {
            guard deviates(metric, overnight: value, baseline: baseline) else { break }
            count += 1
        }
        return count
    }

    private static func fact(_ metric: PatrickMorningMetric, overnight: Double, baseline: Double, leading: Bool) -> String {
        switch metric {
        case .sleepHours:
            return "昨晚少睡了 \(hourText(baseline - overnight)) 小時"
        case .hrvSDNN:
            return "心率變異偏低"
        case .restingHeartRate:
            return leading ? "心率偏高" : "心率也偏高"
        case .wristTemperature:
            return "手腕溫度偏高"
        case .respiratoryRate:
            return "呼吸偏快"
        }
    }

    private static func hourText(_ delta: Double) -> String {
        let hours = abs(delta)
        if abs(hours - hours.rounded()) < 0.05 { return String(Int(hours.rounded())) }
        let tenths = Int((hours * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }

    /// Watch writes the sentence it measured. It only replaces a greeting line,
    /// so a handwash or stand line from the phone stays put.
    static func storeMorning(settings: inout PatrickExperienceSettings, sentence: String?, now: Date, calendar: Calendar = .current) {
        guard let sentence else { return }
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        settings.morningReport = sentence
        settings.morningReportDay = day
        guard settings.dayLine == nil || settings.dayLine?.hasPrefix("早安") == true else { return }
        guard settings.dayLine?.contains(sentence) != true else { return }
        let suppressed = settings.scene == .sleeping || settings.isSleepTime(now, calendar: calendar)
            || settings.contextFocus == true || settings.contextMeeting == true
            || settings.contextCommute == true || settings.contextNap == true
        settings.dayLine = greeting(name: settings.greetingDisplayName, hour: calendar.component(.hour, from: now),
                                    report: sentence, weather: nil, firstEvent: nil, suppressed: suppressed)
    }

    static func noteWash(settings: inout PatrickExperienceSettings, washedAt: Date?) {
        guard let washedAt, let arrived = settings.arrivedHomeAtMS else { return }
        let ms = (washedAt.timeIntervalSince1970 * 1000).rounded()
        guard ms >= arrived else { return }
        settings.lastHandwashAtMS = ms
    }

    static func warnings(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var codes: [String] = []
        for value in object.values {
            guard let item = value as? [String: Any], let code = item["code"] as? String, !code.isEmpty else { continue }
            codes.append(code)
        }
        return codes.sorted()
    }

    static func temperatureAndRain(from data: Data) -> (Double?, Double?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        return (quantity(object["temperature"], keys: ["value"]), quantity(object["rainfall"], keys: ["max", "value"]))
    }

    private static func quantity(_ node: Any?, keys: [String]) -> Double? {
        guard let dict = node as? [String: Any], let rows = dict["data"] as? [[String: Any]], !rows.isEmpty else { return nil }
        let chosen = rows.first { ($0["place"] as? String) == "香港天文台" } ?? rows[0]
        for key in keys {
            if let number = chosen[key] as? Double { return number }
            if let number = chosen[key] as? Int { return Double(number) }
            if let text = chosen[key] as? String, let number = Double(text) { return number }
        }
        return nil
    }

    /// Umbrella, jacket, and a charger. Mask and air-quality are not Observatory data, so they are omitted.
    static func goingOutCard(reading: PatrickObservatoryReading, battery: Double?, longOuting: Bool) -> PatrickGoingOutCard {
        let codes = reading.warningCodes.map { $0.uppercased() }
        let storm = codes.contains { $0.hasPrefix("TC") || $0.contains("WRAIN") }
        let cold = codes.contains { $0.contains("WCOLD") }
        let wet = (reading.rainfallMM ?? 0) >= 0.5 || storm
        var lines: [String] = []
        if let temp = reading.temperatureC, temp.isFinite { lines.append("天文台 \(Int(temp.rounded())) 度") }
        if wet { lines.append("帶傘") }
        if cold || (reading.temperatureC ?? 99) <= 18 { lines.append("加件外套") }
        if let battery, battery >= 0, battery < 0.3, longOuting { lines.append("手錶電量偏低，長時間外出記得帶充電器") }
        if lines.isEmpty { lines = ["天文台暫時沒有讀數"] }
        return PatrickGoingOutCard(lines: lines, attention: storm)
    }

    static func merged(_ events: [PatrickCalendarInterval]) -> [PatrickCalendarInterval] {
        let sorted = events.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var result: [PatrickCalendarInterval] = []
        for event in sorted {
            if let last = result.indices.last, result[last].end >= event.start {
                result[last].end = max(result[last].end, event.end)
                if result[last].title.isEmpty { result[last].title = event.title }
            } else {
                result.append(event)
            }
        }
        return result
    }

    static func longOuting(_ events: [PatrickCalendarInterval], now: Date) -> Bool {
        merged(events).contains { event in
            event.end.timeIntervalSince(event.start) >= 3 * 3600
                && event.start.timeIntervalSince(now) >= -5 * 60
                && event.start.timeIntervalSince(now) <= 2 * 3600
        }
    }

    static func nextEventTitle(_ events: [PatrickCalendarInterval], now: Date) -> String? {
        merged(events).first { $0.start > now && !$0.title.isEmpty }?.title
    }

    /// Nil inside an event, in a gap shorter than five minutes, without a following
    /// event, while the gate is closed, when the budget is spent, or before 70 minutes of sitting.
    static func standPrompt(events: [PatrickCalendarInterval], now: Date, sittingMinutes: Int?,
                             contextSuppresses: Bool, budgetRemaining: Int, minimumGapMinutes: Int = 5) -> String? {
        guard !contextSuppresses, budgetRemaining > 0, let sittingMinutes, sittingMinutes >= 70 else { return nil }
        let events = merged(events)
        if events.contains(where: { $0.start <= now && $0.end > now }) { return nil }
        guard let next = events.first(where: { $0.start > now }) else { return nil }
        let gap = Int(next.start.timeIntervalSince(now) / 60)
        guard gap >= minimumGapMinutes else { return nil }
        return "坐了 \(sittingMinutes) 分鐘，下個會前有 \(gap) 分鐘，倒杯水？"
    }

    static func handwashInvite(arrivedAt: Date?, washedAt: Date?, now: Date,
                               contextSuppresses: Bool, alreadyAsked: Bool, budgetRemaining: Int) -> String? {
        guard let arrivedAt, !alreadyAsked, !contextSuppresses, budgetRemaining > 0 else { return nil }
        let age = now.timeIntervalSince(arrivedAt)
        guard age >= 0, age <= 30 * 60 else { return nil }
        if let washedAt, washedAt >= arrivedAt { return nil }
        return "先洗手？"
    }

    static func greeting(name: String, hour: Int, report: String?, weather: String?, firstEvent: String?,
                         suppressed: Bool) -> String? {
        guard !suppressed, (5..<11).contains(hour) else { return nil }
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sham" : name
        if let report, !report.isEmpty { return "早安，\(who)。\(report)" }
        if let weather, let firstEvent, !weather.isEmpty, !firstEvent.isEmpty {
            return "早安，\(who)。\(weather)，接著是\(firstEvent)。"
        }
        if let weather, !weather.isEmpty { return "早安，\(who)。\(weather)。" }
        if let firstEvent, !firstEvent.isEmpty { return "早安，\(who)。接著是\(firstEvent)。" }
        return "早安，\(who)。"
    }

    static func acceptButler(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.count) else { return nil }
        let banned = ["餵", "飽足", "親密", "感冒", "着涼", "著涼", "生病", "診斷", "壓力"]
        guard banned.allSatisfy({ !trimmed.contains($0) }) else { return nil }
        let cjk = trimmed.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        guard cjk >= 4 else { return nil }
        return trimmed
    }

    static func butlerSentence(_ phrase: PatrickButlerPhrase, name: String, modelText: String?) -> String {
        if let modelText, let accepted = acceptButler(modelText) { return accepted }
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sham" : name
        switch phrase {
        case .leaving: return "\(who)，出門看一下天文台的卡片。"
        case .arrived: return "\(who)回來了。先洗手？"
        case .nap: return "午睡 25 分鐘，結束前我會輕輕叫你。"
        case .goodNight: return "晚安，\(who)。睡前我會安靜。"
        case .tired: return "\(who)累了就慢慢來，我在。"
        }
    }

    static func reading(from settings: PatrickExperienceSettings) -> PatrickObservatoryReading {
        let codes = (settings.observatoryWarnings ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        return PatrickObservatoryReading(warningCodes: codes, temperatureC: settings.observatoryTemperature, rainfallMM: settings.observatoryRainMM)
    }

    /// One pass for the phone. Alarm cues do not spend the proactive budget.
    /// Stand, handwash, and a storm knock do, and they stay silent when the gate is closed.
    static func advance(settings: inout PatrickExperienceSettings, activity: PatrickLocalActivity?,
                        events: [PatrickCalendarInterval], sittingMinutes: Int?, battery: Double?,
                        role: PatrickWakeRole, now: Date, calendar: Calendar = .current) -> PatrickDayAdvance {
        if activity?.nap == true, activity?.status == .running {
            settings.contextNap = true
        } else if settings.contextNap == true {
            settings.contextNap = nil
        }
        var result = PatrickDayAdvance()
        let napEnds = activity?.nap == true && activity?.status == .running ? activity?.endsAt : nil
        result.wake = wakeCues(settings: settings, napEndsAt: napEnds, role: role, now: now)
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        let report = settings.morningReportDay == day ? settings.morningReport : nil
        let gate = snapshot(settings: settings, activity: activity, now: now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let suppressed = gate.sleeping || gate.napping || gate.focus || gate.meeting || gate.commute || gate.workout
        let weather = settings.observatoryTemperature.map { "天文台 \(Int($0.rounded())) 度" }
        let hello = greeting(name: settings.greetingDisplayName, hour: hour, report: report, weather: weather,
                             firstEvent: nextEventTitle(events, now: now), suppressed: suppressed)
        if hello != nil, settings.greetedDay != day {
            settings.greetedDay = day
            if let report, settings.morningReportDay == day {
                result.journal.append(report)
            } else if let hello {
                result.journal.append(hello)
            }
        }
        let leaving = settings.leavingDay == day
        let card = goingOutCard(reading: reading(from: settings), battery: battery, longOuting: longOuting(events, now: now))
        if leaving { settings.gearLines = card.lines }
        var knocks = 0
        func claim() -> Bool {
            guard knocks == 0 else { return false }
            let fresh = snapshot(settings: settings, activity: activity, now: now, calendar: calendar)
            guard !fresh.suppressesProactive else { return false }
            if settings.proactiveHapticDay != day {
                settings.proactiveHapticDay = day
                settings.proactiveHapticCount = 0
            }
            settings.proactiveHapticCount = (settings.proactiveHapticCount ?? 0) + 1
            knocks += 1
            return true
        }
        let arrived = settings.arrivedHomeAtMS.map { Date(timeIntervalSince1970: $0 / 1000) }
        let washed = settings.lastHandwashAtMS.map { Date(timeIntervalSince1970: $0 / 1000) }
        let asked = settings.handwashAskedMS != nil && settings.handwashAskedMS == settings.arrivedHomeAtMS
        let remaining = max(0, settings.dailyHapticBudget - (settings.proactiveHapticDay == day ? (settings.proactiveHapticCount ?? 0) : 0))
        let wash = handwashInvite(arrivedAt: arrived, washedAt: washed, now: now, contextSuppresses: gate.suppressesProactive,
                                  alreadyAsked: asked, budgetRemaining: remaining)
        var line = hello
        if wash != nil, claim() {
            settings.handwashAskedMS = settings.arrivedHomeAtMS
            line = wash
            result.journal.append("先洗手？")
        }
        let slot = standSlot(events: events, now: now)
        let stand = standPrompt(events: events, now: now, sittingMinutes: sittingMinutes,
                                contextSuppresses: gate.suppressesProactive, budgetRemaining: max(0, remaining - knocks))
        if let stand, let slot, settings.standSlot != slot, claim() {
            settings.standSlot = slot
            line = stand
            result.journal.append(stand)
        }
        if card.attention, settings.gearKnockDay != day, claim() {
            settings.gearKnockDay = day
            if line == nil || line == hello { line = card.lines.joined(separator: "，") }
            result.journal.append(card.lines.joined(separator: "，"))
        }
        if leaving, line == hello || line == nil {
            line = card.lines.joined(separator: "，")
        }
        if let until = settings.handwashUntilMS, until > now.timeIntervalSince1970 * 1000 {
            line = "洗手 20 秒，我等你。"
        }
        settings.dayLine = line
        result.knocks = knocks
        return result
    }

    static func standSlot(events: [PatrickCalendarInterval], now: Date) -> String? {
        guard let next = merged(events).first(where: { $0.start > now }) else { return nil }
        return "\(Int(next.start.timeIntervalSince1970))"
    }

    private static func snapshot(settings: PatrickExperienceSettings, activity: PatrickLocalActivity?,
                                 now: Date, calendar: Calendar) -> PatrickContextSnapshot {
        let day = PatrickContextSnapshot.dayKey(now, calendar: calendar)
        let count = settings.proactiveHapticDay == day ? (settings.proactiveHapticCount ?? 0) : 0
        let exercise = activity?.status == .running && activity?.kind.isExercise == true
        let napping = settings.contextNap == true || (activity?.status == .running && activity?.kind == .breathing)
        return PatrickContextSnapshot(
            sleeping: settings.scene == .sleeping || settings.isSleepTime(now, calendar: calendar),
            napping: napping, focus: settings.contextFocus == true, meeting: settings.contextMeeting == true,
            commute: settings.contextCommute == true, workout: exercise, proactiveCount: count, budget: settings.dailyHapticBudget)
    }
}
