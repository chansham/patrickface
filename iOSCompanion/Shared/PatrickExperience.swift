import Foundation

/// Shared by both apps and widgets. Values describe the pet, never human physiology.
enum PatrickMood: String, CaseIterable, Codable, Identifiable, Sendable {
    case calm, happy, serious, tired, grumpy, low
    var id: String { rawValue }
    var title: String {
        switch self { case .calm: "平靜"; case .happy: "開心"; case .serious: "認真"; case .tired: "睏倦"; case .grumpy: "有點不耐煩"; case .low: "低落" }
    }
}

enum PatrickExperienceScene: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = "auto"
    case awake, sleeping, charging, exercise, focus, bath, celebrate
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: "依時間"; case .awake: "清醒"; case .sleeping: "睡前"; case .charging: "充電小劇場"; case .exercise: "運動陪伴"; case .focus: "專注"; case .bath: "泡澡小劇場"; case .celebrate: "慶祝" }
    }
}

enum PatrickFaceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case digital, arms
    var id: String { rawValue }
    var title: String { self == .digital ? "數字與角色" : "原味手臂時計 · 試稿" }
}

struct PatrickExperienceSettings: Codable, Equatable, Sendable {
    var outfitID = "auto"
    var scene: PatrickExperienceScene = .automatic
    var mood: PatrickMood = .calm
    var faceMode: PatrickFaceMode = .digital
    // Optional for v1 archives and WatchConnectivity peers made before layouts.
    var layoutID: String?
    var effectiveLayoutID: String { ["classic", "bold", "theater", "activity"].contains(layoutID ?? "") ? layoutID! : "classic" }
    var soundEnabled = false
    var hapticsEnabled = true
    var use24Hour = true
    var showDate = true
    var ambienceEnabled = true
    var birthdayMMDD: String?
    var sleepStartMinutes: Int?
    var sleepEndMinutes: Int?
    var holidaysEnabled: Bool?
    /// Nil means Sham. Text only; voice stays off unless explicitly enabled.
    var greetingName: String?
    var voiceGreetingEnabled: Bool?
    /// Nil keeps the default of six proactive haptics a day.
    var proactiveHapticBudget: Int?
    var proactiveHapticDay: String?
    var proactiveHapticCount: Int?
    /// Wake-up ringing on the iPhone stays off unless Sham turns it on.
    var phoneWakeFallbackEnabled: Bool?
    /// Nil keeps the night alarm off, so 06:00 does not surprise anyone.
    var wakeAlarmEnabled: Bool?
    /// Nil skips the night alarm on Hong Kong holidays and weekends.
    var skipWakeOnRestDays: Bool?
    /// Nil uses the morning boundary (sleep end).
    var wakeMinute: Int?
    var homeLatitude: Double?
    var homeLongitude: Double?
    var arrivedHomeAtMS: Double?
    var lastHandwashAtMS: Double?
    var handwashAskedMS: Double?
    var handwashUntilMS: Double?
    var greetedDay: String?
    var morningReport: String?
    var morningReportDay: String?
    var leavingDay: String?
    var gearLines: [String]?
    var gearKnockDay: String?
    var standSlot: String?
    var dayLine: String?
    var stationarySinceMS: Double?
    var observatoryTemperature: Double?
    var observatoryRainMM: Double?
    var observatoryWarnings: String?
    var observatoryAtMS: Double?
    /// A line held while the person is in a vehicle. Nil means nothing is waiting.
    var deferredLine: String?
    var commuteNoted: Bool?
    var moodAskedDay: String?
    var moodStars: Int?
    var eveningNoteDay: String?
    var eveningLine: String?
    var weeklyPage: String?
    var weeklyPageDay: String?
    var nightStory: String?
    var nightStoryDay: String?
    /// Nil until the morning story is actually on screen, then ten seconds later.
    var theaterUntilMS: Double?
    var phoneAtHome: Bool?
    var phoneWasReachable: Bool?
    var phoneLeftAlerted: Bool?
    var bathFlow: Bool?
    var waterOn: Bool?
    /// Nil means off. The microphone runs only while the app is in front.
    var soundTheaterEnabled: Bool?
    /// Nil follows the day. Stored negative moods remain in the archive.
    var moodFollowsDay: Bool?
    /// Phone-side signals. Nil means unknown, which does not suppress.
    var contextMeeting: Bool?
    var contextCommute: Bool?
    var contextFocus: Bool?
    var contextNap: Bool?
    /// Set on the phone, consumed by the watch, which is the HealthKit writer.
    var pendingMindRaw: String?
    /// Nil keeps the default: silent during the sleep window, alarms still sound.
    var quietAlertsRaw: String?
    var quietAlerts: PatrickQuietAlerts {
        get { PatrickQuietAlerts(rawValue: quietAlertsRaw ?? "") ?? .silentExceptAlarms }
        set { quietAlertsRaw = newValue == .silentExceptAlarms ? nil : newValue.rawValue }
    }

    var greetingDisplayName: String {
        let trimmed = greetingName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Sham" : trimmed
    }
    var voiceGreetingOn: Bool { voiceGreetingEnabled ?? false }
    var soundTheaterOn: Bool { soundTheaterEnabled == true }
    var dailyHapticBudget: Int { min(24, max(0, proactiveHapticBudget ?? 6)) }
    var phoneWakeFallback: Bool { phoneWakeFallbackEnabled ?? false }
    var wakeAlarmOn: Bool { wakeAlarmEnabled ?? false }
    var skipsWakeOnRestDays: Bool { skipWakeOnRestDays ?? true }
    var effectiveWakeMinute: Int { (0..<1440).contains(wakeMinute ?? -1) ? wakeMinute! : sleepEnd }
    var moodFollowsDayOn: Bool { moodFollowsDay ?? true }
    var sleepStart: Int { (0..<1440).contains(sleepStartMinutes ?? -1) ? sleepStartMinutes! : 1320 }
    var sleepEnd: Int { (0..<1440).contains(sleepEndMinutes ?? -1) ? sleepEndMinutes! : 360 }
    func isSleepTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        guard sleepStart != sleepEnd else { return false }
        return sleepStart < sleepEnd ? minute >= sleepStart && minute < sleepEnd : minute >= sleepStart || minute < sleepEnd
    }
}

/// How a countdown alert behaves inside the sleep window or sleep scene.
/// Missing values stay silent except alarms so older saves keep the default.
enum PatrickQuietAlerts: String, Codable, Sendable {
    case silentExceptAlarms
    case allowSound
    case hideExceptAlarms
}

enum PatrickCareAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case pet, feed, rest
    var id: String { rawValue }
    var title: String { switch self { case .pet: "摸摸"; case .feed: "餵一口"; case .rest: "陪 Sham 休息" } }
    var clipID: String { self == .rest ? "yawn" : rawValue }
    /// Kept so older callers compile. Feeding and petting no longer refuse on a timer.
    var cooldown: TimeInterval { 0 }
}

enum PatrickActivityKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case focus, breathing, exercise, walking, running, strength
    var id: String { rawValue }
    var title: String {
        switch self {
        case .focus: "專注"
        case .breathing: "呼吸休息"
        case .exercise: "運動陪伴"
        case .walking: "散步陪伴"
        case .running: "跑步陪伴"
        case .strength: "肌力陪伴"
        }
    }
    var isExercise: Bool { self != .focus && self != .breathing }
    var clipID: String { isExercise ? "exercise" : "focus" }
    var sceneID: String { isExercise ? "exercise" : "focus" }
}

enum PatrickActivityControl: String, CaseIterable, Sendable { case pause, resume, cancel }

enum PatrickActivityControlResult: Equatable, Sendable {
    case paused, resumed, cancelled, alreadyPaused, alreadyRunning, completed, noActiveActivity
    var message: String {
        switch self {
        case .paused: "陪伴倒數已暫停。"
        case .resumed: "陪伴倒數已繼續。"
        case .cancelled: "已結束陪伴倒數。"
        case .alreadyPaused: "陪伴倒數已經暫停。"
        case .alreadyRunning: "陪伴倒數已經在進行。"
        case .completed: "這次陪伴倒數已完成。"
        case .noActiveActivity: "目前沒有正在進行的陪伴倒數。"
        }
    }
}

struct PatrickLocalActivity: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case running, paused, completed, cancelled }
    var id: UUID
    var kind: PatrickActivityKind
    var durationSeconds: TimeInterval
    var startedAtMS: Double
    var endsAtMS: Double?
    var remainingSeconds: TimeInterval
    var status: Status
    /// Set only for a nap the person just started. Older archives decode nil.
    var nap: Bool? = nil
    var startedAt: Date { Date(timeIntervalSince1970: startedAtMS / 1000) }
    var endsAt: Date? {
        get { endsAtMS.map { Date(timeIntervalSince1970: $0 / 1000) } }
        set { endsAtMS = newValue.map { $0.timeIntervalSince1970 * 1000 } }
    }
    func remaining(at date: Date) -> TimeInterval {
        min(durationSeconds, status == .running ? max(0, endsAt?.timeIntervalSince(date) ?? 0) : max(0, remainingSeconds))
    }
}

/// Shortcuts report the activity they actually kept or started, rather than
/// claiming a new timer was started when another session already occupies it.
enum PatrickActivityStartResult: Equatable, Sendable {
    case started(activity: PatrickLocalActivity, completedKind: PatrickActivityKind?)
    case preserved(activity: PatrickLocalActivity, remainingSeconds: TimeInterval)
    case savedActivityPending(PatrickActivityKind)

    var message: String {
        switch self {
        case .savedActivityPending(let kind):
            return "還保存著「\(kind.title)」的進度。請先返回原活動，或明確放棄原活動，再開始新的計時。"
        case .started(let activity, let completedKind):
            let completion = completedKind.map { "原本的「\($0.title)」已完成。" } ?? ""
            return completion + "已開始「\(activity.kind.title)」\(Self.durationText(activity.durationSeconds))。手錶授權後會把散步、跑步、肌力和運動寫進健康。"
        case .preserved(let activity, let remaining):
            let detail = Self.durationText(remaining)
            if activity.status == .paused {
                return "目前「\(activity.kind.title)」已暫停，尚餘\(detail)。已保留原進度，沒有自動繼續或另開計時。要接續，請用「控制派大星陪伴計時」選「繼續」；要換活動，先選「結束」，再開始新計時。"
            }
            return "目前「\(activity.kind.title)」仍在進行，尚餘\(detail)。已保留原進度，沒有另開計時。要換活動，請先用「控制派大星陪伴計時」選「結束」，再開始新計時。"
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "未能讀取的時間" }
        let value = Int(min(7200, max(0, seconds.rounded(.up))))
        let minutes = value / 60, remainder = value % 60
        if minutes == 0 { return "\(remainder) 秒" }
        return remainder == 0 ? "\(minutes) 分鐘" : "\(minutes) 分 \(remainder) 秒"
    }
}

struct PatrickBreakSession: Codable, Equatable, Sendable {
    var savedActivity: PatrickLocalActivity
    var resumeOnReturn: Bool
    var breakActivityID: UUID
}

enum PatrickBreakCommand: Sendable { case begin(minutes: Int), returnToActivity, discardSaved }
enum PatrickBreakResult: Equatable, Sendable {
    case started(PatrickActivityKind), alreadySaved, returned(PatrickActivityKind, running: Bool)
    case discarded(PatrickActivityKind), nothingSaved, noActiveActivity, anotherActivity
    var message: String {
        switch self {
        case .started(let kind): "已保存「\(kind.title)」進度。休息結束後，等你按「返回原活動」，不會自動開始。"
        case .alreadySaved: "原活動已保存；這次沒有重開休息或更改剩餘時間。"
        case .returned(let kind, let running): running ? "已接回「\(kind.title)」，從保存的剩餘時間繼續。" : "已返回「\(kind.title)」，維持原先暫停；準備好再按「繼續」。"
        case .discarded(let kind): "已放棄保存的「\(kind.title)」；沒有算作完成。"
        case .nothingSaved: "目前沒有保存中的原活動。"
        case .noActiveActivity: "目前沒有可暫存的活動；已到期的計時按完成處理。"
        case .anotherActivity: "目前有另一段活動，先結束它，再返回保存的原活動。"
        }
    }
}

struct PatrickCareState: Codable, Equatable, Sendable {
    var satiety = 60.0
    var bond = 0
    var totalFeeds = 0
    var totalPets = 0
    var lastActionAtMS: [String: Double] = [:]
    var lastDecayAtMS: Double?
}

struct PatrickJournalEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var atMS: Double
    var text: String
    var at: Date { Date(timeIntervalSince1970: atMS / 1000) }
}

struct PatrickSurpriseState: Codable, Equatable, Sendable {
    static let cooldownSeconds: TimeInterval = 60
    static let lines = [
        "我今天的計畫：先想一想。",
        "這顆泡泡看起來很有主見。",
        "我有在認真，只是看不出來。",
        "休息也是一項重要工作。",
        "我沒發呆，我在等靈感。",
        "我在。你忙你的就好。"
    ]
    var lastDiscoveredAtMS: Double
    var lineIndex: Int
    var line: String { Self.lines[((lineIndex % Self.lines.count) + Self.lines.count) % Self.lines.count] }
}

enum PatrickImmediateSoundPolicy {
    static let maximumRequestAge: TimeInterval = 3
    static func isFresh(_ requestedAt: Date, now: Date = .now) -> Bool {
        (0...maximumRequestAge).contains(now.timeIntervalSince(requestedAt))
    }
    static func allows(active: Bool, presentationActive: Bool, enabled: Bool,
                       reduceMotion: Bool, lowPower: Bool, requestedAt: Date? = nil, now: Date = .now) -> Bool {
        guard active && presentationActive && enabled && !reduceMotion && !lowPower else { return false }
        guard let requestedAt else { return true }
        return isFresh(requestedAt, now: now)
    }
}

struct PatrickExperienceState: Codable, Equatable, Sendable {
    static let storageKey = "patrick.experience.native.v1"
    var version = 1
    var revision: UInt64 = 0
    var updatedAtMS = 0.0
    var updatedAt: Date { Date(timeIntervalSince1970: updatedAtMS / 1000) }
    var settings = PatrickExperienceSettings()
    var care = PatrickCareState()
    var activity: PatrickLocalActivity?
    // Optional for old v1 saves/peers. The saved activity is frozen, never a
    // second running timer; only an explicit return can restore it.
    var breakSession: PatrickBreakSession?
    var journal: [PatrickJournalEntry] = []
    var processedActionIDs: [UUID] = []
    var calendarCelebrationKeys: [String]?
    // Optional so existing v1 saves and WatchConnectivity snapshots still decode.
    var surprise: PatrickSurpriseState?

    mutating func changed(at date: Date = .now) {
        revision &+= 1; updatedAtMS = date.timeIntervalSince1970 * 1000
    }

    mutating func record(_ text: String, at date: Date) {
        journal.append(PatrickJournalEntry(atMS: date.timeIntervalSince1970 * 1000, text: text))
        journal = Array(journal.suffix(60))
    }

    /// Persist the discovery, not a playback request. Receiving a snapshot or
    /// returning from the background must never replay an old surprise.
    @discardableResult
    mutating func findSurprise(at date: Date = .now) -> String? {
        let now = date.timeIntervalSince1970 * 1000
        guard now.isFinite else { return nil }
        if let previous = surprise, previous.lastDiscoveredAtMS.isFinite,
           now - previous.lastDiscoveredAtMS < PatrickSurpriseState.cooldownSeconds * 1000 { return nil }
        let count = PatrickSurpriseState.lines.count
        let index = surprise.map { (($0.lineIndex % count) + count + 1) % count } ?? 0
        let value = PatrickSurpriseState(lastDiscoveredAtMS: now, lineIndex: index)
        surprise = value
        record("小驚喜：\(value.line)", at: date); changed(at: date)
        return value.line
    }

    /// Feeding is retired. Satiety, bond and old counters stay in storage and are not shown.
    /// Petting still answers the tap, without a cooldown, a number, or a journal line.
    @discardableResult
    mutating func perform(_ action: PatrickCareAction, id: UUID = UUID(), at date: Date = .now) -> Bool {
        guard !processedActionIDs.contains(id) else { return false }
        switch action {
        case .feed:
            return false
        case .pet:
            processedActionIDs = Array((processedActionIDs + [id]).suffix(100))
            changed(at: date)
            return true
        case .rest:
            processedActionIDs = Array((processedActionIDs + [id]).suffix(100))
            settings.scene = .sleeping
            record("一起休息", at: date)
            changed(at: date)
            return true
        }
    }

    mutating func start(_ kind: PatrickActivityKind, minutes: Int, at date: Date = .now) {
        start(kind, seconds: TimeInterval(min(120, max(1, minutes))) * 60, at: date)
    }

    mutating func start(_ kind: PatrickActivityKind, seconds: TimeInterval, at date: Date = .now) {
        guard breakSession == nil else { return }
        replaceActivity(kind, seconds: seconds, at: date)
    }

    private mutating func replaceActivity(_ kind: PatrickActivityKind, seconds: TimeInterval, at date: Date) {
        let duration = seconds.isFinite ? min(7200, max(10, seconds)) : 60
        activity = PatrickLocalActivity(id: UUID(), kind: kind, durationSeconds: duration,
            startedAtMS: date.timeIntervalSince1970 * 1000,
            endsAtMS: (date.timeIntervalSince1970 + duration) * 1000,
            remainingSeconds: duration, status: .running)
        record("開始\(kind.title)", at: date); changed(at: date)
    }

    /// A routine cannot replace or resume an existing activity. Settle a passed
    /// deadline once before deciding whether the single activity slot is free.
    /// A preserved activity makes no storage, journal or synchronization change.
    @discardableResult
    mutating func requestActivityStart(_ kind: PatrickActivityKind, minutes: Int,
                                      at date: Date = .now) -> PatrickActivityStartResult {
        let previousKind = activity?.kind
        let completedKind = reconcile(at: date) != nil ? previousKind : nil
        if let saved = breakSession { return .savedActivityPending(saved.savedActivity.kind) }
        if let current = activity, current.status == .running || current.status == .paused {
            return .preserved(activity: current, remainingSeconds: current.remaining(at: date))
        }
        start(kind, minutes: minutes, at: date)
        // start always creates an activity, using the existing duration bounds.
        return .started(activity: activity!, completedKind: completedKind)
    }

    @discardableResult
    mutating func manageBreak(_ command: PatrickBreakCommand, at date: Date = .now) -> PatrickBreakResult {
        // Completion always wins over a late pause/cancel/return. Reconcile is
        // idempotent, including an expired break observed after a quiet period.
        _ = reconcile(at: date)
        switch command {
        case .begin(let minutes):
            guard breakSession == nil else { return .alreadySaved }
            guard var original = activity, original.status == .running || original.status == .paused,
                  original.remaining(at: date) > 0 else { return .noActiveActivity }
            let resumeOnReturn = original.status == .running
            original.remainingSeconds = original.remaining(at: date)
            original.status = .paused; original.endsAt = nil
            replaceActivity(.breathing, seconds: Double(min(15, max(1, minutes))) * 60, at: date)
            breakSession = PatrickBreakSession(savedActivity: original, resumeOnReturn: resumeOnReturn,
                                              breakActivityID: activity!.id)
            record("保存\(original.kind.title)進度，休息後再返回", at: date)
            return .started(original.kind)
        case .returnToActivity:
            guard let saved = breakSession else { return .nothingSaved }
            if let current = activity, current.id != saved.breakActivityID,
               current.status == .running || current.status == .paused { return .anotherActivity }
            if activity?.id == saved.breakActivityID { cancel(at: date) }
            var original = saved.savedActivity
            original.status = saved.resumeOnReturn ? .running : .paused
            original.endsAt = saved.resumeOnReturn ? date.addingTimeInterval(original.remainingSeconds) : nil
            activity = original; breakSession = nil
            record("返回\(original.kind.title)\(saved.resumeOnReturn ? "，繼續剩餘時間" : "，保持暫停")", at: date)
            changed(at: date)
            return .returned(original.kind, running: saved.resumeOnReturn)
        case .discardSaved:
            guard let saved = breakSession else { return .nothingSaved }
            breakSession = nil
            record("放棄保存的\(saved.savedActivity.kind.title)", at: date); changed(at: date)
            return .discarded(saved.savedActivity.kind)
        }
    }

    mutating func pause(at date: Date = .now) {
        if reconcile(at: date) != nil { return }
        guard var value = activity, value.status == .running else { return }
        value.remainingSeconds = value.remaining(at: date); value.endsAt = nil
        value.status = value.remainingSeconds > 0 ? .paused : .completed
        activity = value; changed(at: date)
    }

    mutating func resume(at date: Date = .now) {
        guard var value = activity, value.status == .paused, value.remainingSeconds > 0 else { return }
        value.endsAt = date.addingTimeInterval(value.remainingSeconds); value.status = .running
        activity = value; changed(at: date)
    }

    /// Crown adjustment of the one local countdown. Does not journal each detent.
    @discardableResult
    mutating func nudgeCountdown(by minutes: Int, at date: Date = .now) -> Bool {
        guard minutes != 0, var value = activity, value.status == .running || value.status == .paused else { return false }
        let before = value.remaining(at: date)
        let remaining = min(7200, max(10, before + Double(minutes) * 60))
        guard abs(remaining - before) > 0.5 else { return false }
        value.remainingSeconds = remaining
        value.durationSeconds = min(7200, max(value.durationSeconds, remaining))
        if value.status == .running { value.endsAt = date.addingTimeInterval(remaining) }
        activity = value
        changed(at: date)
        return true
    }

    mutating func cancel(at date: Date = .now) {
        guard var value = activity, value.status == .running || value.status == .paused else { return }
        value.status = .cancelled; value.endsAt = nil; value.remainingSeconds = 0
        activity = value; record("結束\(value.kind.title)", at: date); changed(at: date)
    }

    /// A shared control path for Shortcuts and phone controls. Settle an elapsed
    /// deadline first; a late cancel is not allowed to erase a completed session.
    /// Repeated pause/resume commands do not advance revision or move a deadline.
    @discardableResult
    mutating func controlActivity(_ command: PatrickActivityControl, at date: Date = .now) -> PatrickActivityControlResult {
        if reconcile(at: date) != nil { return .completed }
        guard let value = activity else { return .noActiveActivity }
        if value.status == .completed { return .completed }
        guard value.status == .running || value.status == .paused else { return .noActiveActivity }
        switch command {
        case .pause:
            guard value.status == .running else { return .alreadyPaused }
            pause(at: date); record("暫停\(value.kind.title)", at: date); return .paused
        case .resume:
            guard value.status == .paused else { return .alreadyRunning }
            resume(at: date); record("繼續\(value.kind.title)", at: date); return .resumed
        case .cancel:
            cancel(at: date); return .cancelled
        }
    }

    /// Returns the completed ID once. Call on foreground and while visible.
    mutating func reconcile(at date: Date = .now) -> UUID? {
        guard var value = activity, value.status == .running, let end = value.endsAt, date >= end else { return nil }
        value.status = .completed; value.remainingSeconds = 0; activity = value
        record("完成\(value.kind.title)", at: date); changed(at: date)
        return value.id
    }

    func isNewer(than other: Self) -> Bool {
        updatedAt != other.updatedAt ? updatedAt > other.updatedAt : revision > other.revision
    }

    /// A quiet observation records the date but never queues a celebration.
    mutating func observeCalendar(_ calendar: PatrickCelebrationCalendar?, at date: Date = .now,
                                  allowCelebration: Bool, localCalendar: Calendar = .current) -> String? {
        let parts = localCalendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let mmdd = String(format: "%02d-%02d", parts.month ?? 0, parts.day ?? 0)
        var events: [(String, String)] = []
        let birthday = settings.birthdayMMDD == mmdd
        if birthday { events.append(("birthday", "生日快樂")) }
        else if settings.holidaysEnabled ?? true,
                let holiday = calendar?.annualHolidays?[mmdd] ?? calendar?.holidays[day] { events.append((holiday.id, holiday.name)) }
        if !birthday, settings.holidaysEnabled ?? true, let name = PatrickHKHolidays.name(on: date),
           !events.contains(where: { $0.1 == name }) {
            events.append(("hk-public", name))
        }
        var seen = calendarCelebrationKeys ?? []
        let fresh = events.filter { !seen.contains(day + ":" + $0.0) }
        guard !fresh.isEmpty else { return nil }
        seen += fresh.map { day + ":" + $0.0 }
        calendarCelebrationKeys = Array(seen.suffix(128))
        let text = fresh.map { $0.1 }.joined(separator: " · ")
        record(text, at: date); changed(at: date)
        return allowCelebration ? text : nil
    }

    /// The decay clock is still stamped so old archives stay valid. Satiety no longer falls.
    @discardableResult mutating func updateCare(at date: Date = .now) -> Bool {
        let now = date.timeIntervalSince1970 * 1000
        guard let last = care.lastDecayAtMS else { care.lastDecayAtMS = now; changed(at: date); return true }
        guard now >= last + 60_000 else { return false }
        care.lastDecayAtMS = now; changed(at: date); return true
    }

    /// Writes the expression only when the day actually changes it.
    @discardableResult
    mutating func syncDisplayedMood(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard settings.moodFollowsDayOn else { return false }
        let next = displayedMood(at: date, calendar: calendar)
        guard settings.mood != next else { return false }
        settings.mood = next
        changed(at: date)
        return true
    }

    func displayedMood(at date: Date = .now, calendar: Calendar = .current) -> PatrickMood {
        guard settings.moodFollowsDayOn else {
            return PatrickDayMood.displayable.contains(settings.mood) ? settings.mood : .calm
        }
        let hour = calendar.component(.hour, from: date)
        let workingOut = activity?.status == .running && activity?.kind.isExercise == true
        return PatrickDayMood.expression(PatrickDaySignals(
            hour: hour,
            sleeping: settings.scene == .sleeping || settings.isSleepTime(date, calendar: calendar),
            napping: settings.contextNap == true || (activity?.status == .running && activity?.kind == .breathing),
            workout: workingOut,
            meeting: settings.contextMeeting == true,
            focus: settings.contextFocus == true || settings.scene == .focus,
            holiday: PatrickHKHolidays.name(on: date) != nil,
            weekend: !PatrickHKHolidays.isWeekday(date)
        ))
    }

    var lifeJournal: [PatrickJournalEntry] { journal.filter { !PatrickJournalFilter.hides($0.text) } }

    func contextSnapshot(at date: Date = .now, calendar: Calendar = .current) -> PatrickContextSnapshot {
        let day = PatrickContextSnapshot.dayKey(date, calendar: calendar)
        let count = settings.proactiveHapticDay == day ? (settings.proactiveHapticCount ?? 0) : 0
        let exercise = activity?.status == .running && activity?.kind.isExercise == true
        return PatrickContextSnapshot(
            sleeping: settings.scene == .sleeping || settings.isSleepTime(date, calendar: calendar),
            napping: settings.contextNap == true || (activity?.status == .running && activity?.kind == .breathing),
            focus: settings.contextFocus == true,
            meeting: settings.contextMeeting == true,
            commute: settings.contextCommute == true,
            workout: exercise,
            proactiveCount: count,
            budget: settings.dailyHapticBudget
        )
    }

    /// Counts one proactive reach-out. Completion haptics do not call this.
    mutating func registerProactiveHaptic(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        let snapshot = contextSnapshot(at: date, calendar: calendar)
        guard !snapshot.suppressesProactive else { return false }
        let day = PatrickContextSnapshot.dayKey(date, calendar: calendar)
        if settings.proactiveHapticDay != day {
            settings.proactiveHapticDay = day
            settings.proactiveHapticCount = 0
        }
        settings.proactiveHapticCount = (settings.proactiveHapticCount ?? 0) + 1
        changed(at: date)
        return true
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey), let state = try? JSONDecoder().decode(Self.self, from: data), state.version == 1 else { return Self() }
        return state
    }
    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

struct PatrickCelebrationCalendar: Decodable, Sendable {
    struct Holiday: Decodable, Sendable { let id: String; let name: String; let motif: String }
    let schemaVersion: Int
    let years: [Int]
    let holidays: [String: Holiday]
    let annualHolidays: [String: Holiday]?
}

struct PatrickOutfitCatalog: Decodable, Sendable {
    enum Action: Decodable, Sendable {
        case clip(String), variants([String])
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let id = try? value.decode(String.self) { self = .clip(id) }
            else { self = .variants(try value.decode([String].self)) }
        }
        var clips: [String] { switch self { case .clip(let id): [id]; case .variants(let ids): ids } }
    }
    struct Outfit: Decodable, Identifiable, Sendable {
        var id: String
        var title: String
        var scene: String
        var clipId: String?
        var actions: [String: Action]?
        var ambience: String?
        var accent: String?
        var status: String?
        var reviewClipId: String?
        var actionClips: [String: String] { (actions ?? [:]).compactMapValues { $0.clips.first } }
        var idleClips: [String] { actions?["idle"]?.clips ?? [] }
        // Never borrow another outfit's reaction or reinterpret a feed as a pet.
        var surpriseClipID: String? { actionClips["surprise"] ?? actionClips["pet"] ?? idleClips.first }
    }
    var schemaVersion: Int
    var defaultOutfitID: String
    var defaultSceneOutfits: [String: String]?
    var defaultActionOutfits: [String: String]?
    var outfits: [Outfit]
}

/// One device owns a countdown alert. The watch wins only while it is paired
/// and a fresh on-wrist heartbeat says it is being worn. There is no public
/// worn API: a recent foreground observation, including wrist-down Always On,
/// is the signal. If the watch crashes before it can cancel, the phone may
/// also notify until that heartbeat goes stale (90 seconds).
enum PatrickAlertDevice: String, Equatable, Sendable { case watch, phone }

enum PatrickAlertOwner {
    static let wornFreshness: TimeInterval = 90

    static func choose(paired: Bool, worn: Bool) -> PatrickAlertDevice {
        paired && worn ? .watch : .phone
    }

    static func isWorn(onWrist: Bool?, observedAt: Date?, at date: Date, paired: Bool) -> Bool {
        guard paired, onWrist == true, let observedAt else { return false }
        let age = date.timeIntervalSince(observedAt)
        return age >= 0 && age <= wornFreshness
    }

    static func schedules(device: PatrickAlertDevice, owner: PatrickAlertDevice) -> Bool { device == owner }
}

/// Signals the gate can see without importing EventKit, CoreMotion or HealthKit.
struct PatrickContextSnapshot: Equatable, Sendable {
    var sleeping = false
    var napping = false
    var focus = false
    var meeting = false
    var commute = false
    var workout = false
    var proactiveCount = 0
    var budget = 6

    var suppressesProactive: Bool {
        sleeping || napping || focus || meeting || commute || workout || proactiveCount >= budget
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

struct PatrickDaySignals: Equatable, Sendable {
    var hour: Int
    var sleeping: Bool
    var napping: Bool
    var workout: Bool
    var meeting: Bool
    var focus: Bool
    var holiday: Bool
    var weekend: Bool
}

enum PatrickDayMood {
    static let displayable: Set<PatrickMood> = [.calm, .happy, .serious]

    /// Neutral or positive only. Sleep and naps stay calm; a workout is happy;
    /// a meeting or focus is the serious face; holidays and weekends stay happy.
    static func expression(_ signals: PatrickDaySignals) -> PatrickMood {
        if signals.workout { return .happy }
        if signals.sleeping || signals.napping { return .calm }
        if signals.meeting || signals.focus { return .serious }
        if signals.holiday || signals.weekend { return .happy }
        if (9..<18).contains(signals.hour) { return .serious }
        if (7..<22).contains(signals.hour) { return .happy }
        return .calm
    }
}

enum PatrickJournalFilter {
    static func hides(_ text: String) -> Bool {
        if text == "摸摸" || text == "餵一口" || text == "陪牠休息" { return true }
        return ["餵", "飽足", "親密", "點心", "照顧"].contains { text.contains($0) }
    }
}

enum PatrickAutomaticScene {
    /// Manual selection wins. Automatic follows the moment: workout, charge,
    /// sleep, focus or a meeting, otherwise awake. Outfits stay on "auto".
    static func resolve(selection: PatrickExperienceScene, activitySceneID: String?, charging: Bool,
                        sleeping: Bool, focus: Bool, workout: Bool, meeting: Bool, water: Bool = false) -> String {
        if selection != .automatic { return selection.rawValue }
        if let activitySceneID { return activitySceneID }
        if water { return "exercise" }
        if workout { return "exercise" }
        if charging { return "charging" }
        if sleeping { return "sleeping" }
        if focus || meeting { return "focus" }
        return "awake"
    }
}

/// Hong Kong general holidays for 2026–2027, copied from the 1823 JSON bundled
/// at experience/hk-public-holidays.json (fetched 2026-10-21). The source omits
/// ordinary Sundays; this table does not add them. A date is a workday only
/// when it is a Hong Kong weekday and not in this table.
enum PatrickHKHolidays {
    static let source = "https://www.1823.gov.hk/common/ical/tc.json"
    private static let days: [String: String] = [
        "2026-01-01": "一月一日",
        "2026-02-17": "農曆年初一",
        "2026-02-18": "農曆年初二",
        "2026-02-19": "農曆年初三",
        "2026-04-03": "耶穌受難節",
        "2026-04-04": "耶穌受難節翌日",
        "2026-04-06": "清明節翌日",
        "2026-04-07": "復活節星期一翌日",
        "2026-05-01": "勞動節",
        "2026-05-25": "佛誕翌日",
        "2026-06-19": "端午節",
        "2026-07-01": "香港特別行政區成立紀念日",
        "2026-09-26": "中秋節翌日",
        "2026-10-01": "國慶日",
        "2026-10-19": "重陽節翌日",
        "2026-12-25": "聖誕節",
        "2026-12-26": "聖誕節後第一個周日",
        "2027-01-01": "一月一日",
        "2027-02-06": "農曆年初一",
        "2027-02-08": "農曆年初三",
        "2027-02-09": "農曆年初四",
        "2027-03-26": "耶穌受難節",
        "2027-03-27": "耶穌受難節翌日",
        "2027-03-29": "復活節星期一",
        "2027-04-05": "清明節",
        "2027-05-01": "勞動節",
        "2027-05-13": "佛誕",
        "2027-06-09": "端午節",
        "2027-07-01": "香港特別行政區成立紀念日",
        "2027-09-16": "中秋節翌日",
        "2027-10-01": "國慶日",
        "2027-10-08": "重陽節",
        "2027-12-25": "聖誕節",
        "2027-12-27": "聖誕節後第一個周日"
    ]

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func name(on date: Date) -> String? { days[key(date)] }
    static func name(on key: String) -> String? { days[key] }

    static func isWeekday(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    /// Workday-only behavior (the serious daytime face, and later alarms) skips
    /// Hong Kong weekends and these general holidays.
    static func isWorkday(_ date: Date) -> Bool { isWeekday(date) && name(on: date) == nil }
}
