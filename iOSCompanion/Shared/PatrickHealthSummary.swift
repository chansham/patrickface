import Foundation

/// Presentation-only health values. Intentionally not Codable, synced, or persisted.
enum PatrickHealthMetric: String, CaseIterable, Identifiable, Sendable {
    case steps, heartRate, hrvSDNN, restingHeartRate, respiratoryRate, wristTemperature, sleep
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: "今日步數"
        case .heartRate: "最近心率"
        case .hrvSDNN: "最近 HRV · SDNN"
        case .restingHeartRate: "靜止心率估計"
        case .respiratoryRate: "最近呼吸率"
        case .wristTemperature: "睡眠手腕溫度"
        case .sleep: "近 24 小時睡眠"
        }
    }
    var note: String {
        switch self {
        case .steps: "今天本地午夜起的 HealthKit 聚合值。"
        case .heartRate: "已儲存樣本，並非即時心率。"
        case .hrvSDNN: "心跳間隔變化，不是壓力分數。"
        case .restingHeartRate: "系統估計值，可能隨當日資料更新。"
        case .respiratoryRate: "已儲存的每分鐘呼吸次數。"
        case .wristTemperature: "睡眠期間手腕的絕對值；非體溫計，也非健康 App 的基準差。"
        case .sleep: "只合併已記錄的睡眠時段；不含臥床或清醒。"
        }
    }
    var unit: String {
        switch self {
        case .steps: "步"
        case .heartRate, .restingHeartRate: "次／分"
        case .hrvSDNN: "毫秒"
        case .respiratoryRate: "次呼吸／分"
        case .wristTemperature: "°C"
        case .sleep: "小時"
        }
    }
    func queryWindow(at now: Date, calendar: Calendar = .current) -> DateInterval {
        let start: Date
        switch self {
        case .steps: start = calendar.startOfDay(for: now)
        case .sleep: start = now.addingTimeInterval(-24 * 60 * 60)
        default: start = now.addingTimeInterval(-7 * 24 * 60 * 60)
        }
        return DateInterval(start: start, end: now)
    }
    func formatted(_ value: Double) -> String {
        guard value.isFinite else { return "尚無資料" }
        switch self {
        case .steps, .heartRate, .restingHeartRate: return String(format: "%.0f", value)
        case .wristTemperature: return String(format: "%.2f", value)
        default: return String(format: "%.1f", value)
        }
    }
}

struct PatrickHealthSource: Hashable, Sendable {
    var name: String
    var bundleID: String
    var deviceName: String?
    var label: String {
        guard let deviceName, !deviceName.isEmpty, deviceName != name else { return name }
        return "\(name) · \(deviceName)"
    }
}

struct PatrickHealthReading: Sendable {
    var value: Double
    /// Sample interval for discrete values; exact query interval for an aggregate.
    var interval: DateInterval
    var sources: [PatrickHealthSource]
    var sampleCount: Int?
    var isAggregate: Bool

    init?(value: Double, start: Date, end: Date, sources: [PatrickHealthSource],
          sampleCount: Int? = nil, isAggregate: Bool = false) {
        guard value.isFinite, end >= start else { return nil }
        self.value = value
        self.interval = DateInterval(start: start, end: end)
        self.sources = Array(Set(sources)).sorted { ($0.name, $0.bundleID, $0.deviceName ?? "") < ($1.name, $1.bundleID, $1.deviceName ?? "") }
        self.sampleCount = sampleCount
        self.isAggregate = isAggregate
    }
}

enum PatrickHealthResult: Sendable {
    case reading(PatrickHealthReading)
    case noSamples
    case unavailable
}

/// Stores only scope/cancellation state, never values or authorization conclusions.
struct PatrickHealthReadGate {
    private(set) var selected: Set<PatrickHealthMetric> = []
    private(set) var generation: UInt64 = 0
    private(set) var active = false

    mutating func invalidate() { generation &+= 1 }
    mutating func setSelected(_ value: Set<PatrickHealthMetric>) {
        selected = value
        invalidate()
    }
    mutating func setActive(_ value: Bool) {
        active = value
        invalidate()
    }
    func accepts(_ token: UInt64, metric: PatrickHealthMetric) -> Bool {
        active && token == generation && selected.contains(metric)
    }
    static func refreshable(selected: Set<PatrickHealthMetric>, previouslyRequested: Set<PatrickHealthMetric>) -> Set<PatrickHealthMetric> {
        // A previous request is not proof that read permission was granted.
        selected.intersection(previouslyRequested)
    }
}

struct PatrickSleepInterval: Sendable {
    var id: UUID
    var start: Date
    var end: Date
    var asleep: Bool
    var source: PatrickHealthSource
}

enum PatrickSleepSummary {
    /// Union of recorded asleep intervals within a rolling 24-hour window.
    /// Cross-source overlaps and duplicate samples count once, not as extra sleep.
    /// This is not Apple's private source-priority/staging algorithm.
    static func reading(_ samples: [PatrickSleepInterval], in window: DateInterval) -> PatrickHealthReading? {
        guard window.duration > 0 else { return nil }
        var seen = Set<UUID>()
        var intervals: [DateInterval] = []
        var sources: [PatrickHealthSource] = []
        for sample in samples where sample.asleep {
            guard sample.end > sample.start, seen.insert(sample.id).inserted else { continue }
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            guard end > start else { continue }
            intervals.append(DateInterval(start: start, end: end))
            sources.append(sample.source)
        }
        guard !intervals.isEmpty else { return nil } // no sample is not zero sleep
        intervals.sort { $0.start < $1.start }
        var total: TimeInterval = 0
        var merged = intervals[0]
        for interval in intervals.dropFirst() {
            if interval.start <= merged.end {
                merged = DateInterval(start: merged.start, end: max(merged.end, interval.end))
            } else {
                total += merged.duration
                merged = interval
            }
        }
        total += merged.duration
        return PatrickHealthReading(value: total / 3600, start: window.start, end: window.end,
            sources: sources, sampleCount: intervals.count, isAggregate: true)
    }
}
