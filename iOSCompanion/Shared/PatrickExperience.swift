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
    var soundEnabled = false
    var hapticsEnabled = true
    var use24Hour = true
    var showDate = true
    var ambienceEnabled = true
    var birthdayMMDD: String?
    var sleepStartMinutes: Int?
    var sleepEndMinutes: Int?
    var holidaysEnabled: Bool?

    var sleepStart: Int { (0..<1440).contains(sleepStartMinutes ?? -1) ? sleepStartMinutes! : 1320 }
    var sleepEnd: Int { (0..<1440).contains(sleepEndMinutes ?? -1) ? sleepEndMinutes! : 360 }
    func isSleepTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        guard sleepStart != sleepEnd else { return false }
        return sleepStart < sleepEnd ? minute >= sleepStart && minute < sleepEnd : minute >= sleepStart || minute < sleepEnd
    }
}

enum PatrickCareAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case pet, feed, rest
    var id: String { rawValue }
    var title: String { switch self { case .pet: "摸摸"; case .feed: "餵一口"; case .rest: "陪牠休息" } }
    var clipID: String { self == .rest ? "yawn" : rawValue }
    var cooldown: TimeInterval { self == .feed ? 3 : 2 }
}

enum PatrickActivityKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case focus, breathing, exercise
    var id: String { rawValue }
    var title: String {
        switch self { case .focus: "專注"; case .breathing: "呼吸休息"; case .exercise: "運動陪伴" }
    }
    var clipID: String { self == .focus || self == .breathing ? "focus" : "exercise" }
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
    var startedAt: Date { Date(timeIntervalSince1970: startedAtMS / 1000) }
    var endsAt: Date? {
        get { endsAtMS.map { Date(timeIntervalSince1970: $0 / 1000) } }
        set { endsAtMS = newValue.map { $0.timeIntervalSince1970 * 1000 } }
    }
    func remaining(at date: Date) -> TimeInterval {
        min(durationSeconds, status == .running ? max(0, endsAt?.timeIntervalSince(date) ?? 0) : max(0, remainingSeconds))
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
        "點心還沒來，我先陪你。"
    ]
    var lastDiscoveredAtMS: Double
    var lineIndex: Int
    var line: String { Self.lines[((lineIndex % Self.lines.count) + Self.lines.count) % Self.lines.count] }
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

    @discardableResult
    mutating func perform(_ action: PatrickCareAction, id: UUID = UUID(), at date: Date = .now) -> Bool {
        guard !processedActionIDs.contains(id) else { return false }
        if let last = care.lastActionAtMS[action.rawValue], date.timeIntervalSince1970 - last / 1000 < action.cooldown { return false }
        _ = updateCare(at: date)
        care.lastActionAtMS[action.rawValue] = date.timeIntervalSince1970 * 1000
        processedActionIDs = Array((processedActionIDs + [id]).suffix(100))
        switch action {
        case .feed: care.satiety = min(100, care.satiety + 12); care.totalFeeds += 1; care.bond = min(100, care.bond + 2)
        case .pet: care.totalPets += 1; care.bond = min(100, care.bond + 1)
        case .rest: settings.scene = .sleeping
        }
        record(action.title, at: date); changed(at: date)
        return true
    }

    mutating func start(_ kind: PatrickActivityKind, minutes: Int, at date: Date = .now) {
        start(kind, seconds: TimeInterval(min(120, max(1, minutes))) * 60, at: date)
    }

    mutating func start(_ kind: PatrickActivityKind, seconds: TimeInterval, at date: Date = .now) {
        let duration = seconds.isFinite ? min(7200, max(10, seconds)) : 60
        activity = PatrickLocalActivity(id: UUID(), kind: kind, durationSeconds: duration,
            startedAtMS: date.timeIntervalSince1970 * 1000,
            endsAtMS: (date.timeIntervalSince1970 + duration) * 1000,
            remainingSeconds: duration, status: .running)
        record("開始\(kind.title)", at: date); changed(at: date)
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

    mutating func cancel(at date: Date = .now) {
        guard var value = activity, value.status == .running || value.status == .paused else { return }
        value.status = .cancelled; value.endsAt = nil; value.remainingSeconds = 0
        activity = value; record("結束\(value.kind.title)", at: date); changed(at: date)
    }

    /// Returns the completed ID once. Call on foreground and while visible.
    mutating func reconcile(at date: Date = .now) -> UUID? {
        guard var value = activity, value.status == .running, let end = value.endsAt, date >= end else { return nil }
        value.status = .completed; value.remainingSeconds = 0; activity = value
        care.bond = min(100, care.bond + 1)
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
        if settings.birthdayMMDD == mmdd { events.append(("birthday", "生日快樂")) }
        else if settings.holidaysEnabled ?? true,
                let holiday = calendar?.annualHolidays?[mmdd] ?? calendar?.holidays[day] { events.append((holiday.id, holiday.name)) }
        var seen = calendarCelebrationKeys ?? []
        let fresh = events.filter { !seen.contains(day + ":" + $0.0) }
        guard !fresh.isEmpty else { return nil }
        seen += fresh.map { day + ":" + $0.0 }
        calendarCelebrationKeys = Array(seen.suffix(128))
        let text = fresh.map { $0.1 }.joined(separator: " · ")
        record(text, at: date); changed(at: date)
        return allowCelebration ? text : nil
    }

    /// Elapsed-time game decay, at most one write a minute; no background loop.
    @discardableResult mutating func updateCare(at date: Date = .now) -> Bool {
        let now = date.timeIntervalSince1970 * 1000
        guard let last = care.lastDecayAtMS else { care.lastDecayAtMS = now; changed(at: date); return true }
        guard now >= last + 60_000 else { return false }
        care.satiety = min(100, max(0, care.satiety - (now - last) / 3_600_000 * 1.5))
        care.lastDecayAtMS = now; changed(at: date); return true
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
