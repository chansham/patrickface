import Foundation

/// Descriptive comparisons of daily aggregates. No diagnosis, stress/readiness
/// score, care-state mutation, storage, or HealthKit authorization is performed.
enum PatrickHealthTrendMetric: String, Codable, CaseIterable, Sendable {
    case sleepHours, restingHeartRate, hrvSDNN
}

struct PatrickHealthTrendPoint: Codable, Equatable, Sendable {
    var metric: PatrickHealthTrendMetric
    /// Explicit local-calendar boundaries; do not infer a day by dividing UTC
    /// timestamps by 86,400. A current civil day's end may be after now.
    var dayStartMS: Double
    var dayEndMS: Double
    /// Time of the latest contributing observation, not the query execution.
    var observedAtMS: Double
    var value: Double
    /// Stable source/device identity selected explicitly by the caller.
    var sourceKey: String
    var sourceLabel: String
}

struct PatrickHealthTrendInput: Codable, Sendable {
    var nowMS: Double
    /// Caller computes the start using 28 local calendar days, including DST.
    /// An aggregate crossing this boundary is omitted rather than truncated.
    var historyStartMS: Double
    var points: [PatrickHealthTrendPoint]
}

struct PatrickHealthTrendResult: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case noData, stale, building, ready }
    enum Reason: String, Codable, Sendable {
        case noSamples, invalidInput, invalidPoint, conflictingDay, overlappingDays
        case sourceChanged, insufficientHistory, staleObservation, comparable
    }
    var metric: PatrickHealthTrendMetric
    var state: State
    var reason: Reason
    var baselineCount: Int = 0
    var invalidPointCount: Int = 0
    var current: PatrickHealthTrendPoint?
    var baseline: Double?
    /// Absolute difference in the metric's own units, not a percentage/score.
    var delta: Double?
}

enum PatrickHealthTrend {
    static let minimumDays = 7
    static let freshnessMS: Double = 36 * 60 * 60 * 1000
    private static let hourMS: Double = 60 * 60 * 1000

    static func evaluate(_ input: PatrickHealthTrendInput) -> [PatrickHealthTrendResult] {
        guard input.nowMS.isFinite, input.nowMS > 0,
              input.historyStartMS.isFinite, input.historyStartMS > 0,
              input.historyStartMS <= input.nowMS,
              // 28 local days plus today's partial day can exceed 29 actual
              // 24-hour days across a fall-back clock change.
              input.nowMS - input.historyStartMS <= 30 * 24 * hourMS else {
            return PatrickHealthTrendMetric.allCases.map {
                PatrickHealthTrendResult(metric: $0, state: .noData, reason: .invalidInput)
            }
        }
        return PatrickHealthTrendMetric.allCases.map { evaluate($0, in: input) }
    }

    private static func evaluate(_ metric: PatrickHealthTrendMetric,
                                 in input: PatrickHealthTrendInput) -> PatrickHealthTrendResult {
        // Earlier/partial days are outside the caller's window. Never silently
        // accept a malformed current record and fall back to an older value.
        let scoped = input.points.filter {
            $0.metric == metric && (!$0.dayStartMS.isFinite || $0.dayStartMS >= input.historyStartMS)
        }
        let invalid = scoped.filter { !valid($0, nowMS: input.nowMS) }.count
        guard invalid == 0 else {
            return PatrickHealthTrendResult(metric: metric, state: .noData,
                                            reason: .invalidPoint, invalidPointCount: invalid)
        }
        var points: [PatrickHealthTrendPoint] = []
        for point in scoped where !points.contains(point) { points.append(point) }
        points.sort { $0.dayStartMS < $1.dayStartMS }
        guard let current = points.last else {
            return PatrickHealthTrendResult(metric: metric, state: .noData, reason: .noSamples)
        }
        // A daily aggregate is indivisible. Different values/sources/boundaries
        // for the same day are ambiguity, not independent evidence to average.
        guard Set(points.map(\.dayStartMS)).count == points.count else {
            return PatrickHealthTrendResult(metric: metric, state: .noData, reason: .conflictingDay)
        }
        for index in 1..<points.count where points[index - 1].dayEndMS > points[index].dayStartMS {
            return PatrickHealthTrendResult(metric: metric, state: .noData, reason: .overlappingDays)
        }
        let previous = points.filter { $0.dayEndMS <= current.dayStartMS }
        let history = Array(previous.filter { $0.sourceKey == current.sourceKey }.suffix(28))
        var result = PatrickHealthTrendResult(metric: metric, state: .building,
            reason: history.isEmpty && !previous.isEmpty ? .sourceChanged : .insufficientHistory,
            baselineCount: history.count, current: current)
        if input.nowMS - current.observedAtMS > freshnessMS {
            result.state = .stale
            result.reason = .staleObservation
            return result
        }
        guard history.count >= minimumDays else { return result }
        let values = history.map(\.value).sorted()
        let middle = values.count / 2
        let baseline = values.count.isMultiple(of: 2)
            ? values[middle - 1] / 2 + values[middle] / 2 : values[middle]
        result.state = .ready
        result.reason = .comparable
        result.baseline = baseline
        result.delta = current.value - baseline
        return result
    }

    private static func valid(_ point: PatrickHealthTrendPoint, nowMS: Double) -> Bool {
        guard point.dayStartMS.isFinite, point.dayEndMS.isFinite,
              point.observedAtMS.isFinite, point.value.isFinite,
              point.dayStartMS > 0, point.dayStartMS <= nowMS,
              point.dayEndMS > point.dayStartMS,
              point.observedAtMS >= point.dayStartMS,
              point.observedAtMS <= point.dayEndMS, point.observedAtMS <= nowMS,
              !point.sourceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !point.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let hours = (point.dayEndMS - point.dayStartMS) / hourMS
        // Prevent hourly fragments being counted as distinct baseline days;
        // still accept 23/25-hour and half-hour DST calendar boundaries.
        guard (22...26).contains(hours) else { return false }
        switch point.metric {
        case .sleepHours: return point.value >= 0 && point.value <= hours
        case .restingHeartRate: return point.value > 0
        case .hrvSDNN: return point.value >= 0
        }
    }
}
