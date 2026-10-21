import Foundation

/// Ephemeral adapter input. No Codable conformance, persistence, or cross-device delivery.
struct PatrickHealthTrendSample: Equatable, Sendable {
    var id: UUID
    var start: Date
    var end: Date
    var value: Double
    var sourceKey: String?
    var sourceLabel: String
    var manuallyEntered: Bool
}

struct PatrickHealthTrendSourceGroup: Identifiable, Sendable {
    enum Issue: Equatable, Sendable { case missingDeviceIdentity, invalidSamples, conflictingSampleID }
    var id: String
    var label: String
    var comparable: Bool
    var points: [PatrickHealthTrendPoint]
    var issue: Issue? = nil
    var firstRecordedAt: Date? = nil
    var lastRecordedAt: Date? = nil
}

enum PatrickHealthTrendAggregation {
    static func historyWindow(at now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard now.timeIntervalSince1970.isFinite,
              let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now)), start < now else { return nil }
        return DateInterval(start: start, end: now)
    }

    /// Quantity points are the within-day median for one app/device identity.
    /// Sleep is a union of recorded asleep time in *completed* local noon-to-noon windows.
    /// Missing days stay missing. Different devices and manual records never become a baseline.
    static func groups(metric: PatrickHealthTrendMetric, samples: [PatrickHealthTrendSample],
                       now: Date, calendar: Calendar = .current) -> [PatrickHealthTrendSourceGroup] {
        guard let history = historyWindow(at: now, calendar: calendar) else { return [] }
        let byID = Dictionary(grouping: samples, by: \.id)
        // Compare other copies with the first. A lone NaN is not equal to itself,
        // and that must not look like two records fighting over one UUID.
        let conflicts = Set(byID.values.filter { group in
            guard let first = group.first else { return false }
            return group.dropFirst().contains { $0 != first }
        }.flatMap { $0.compactMap(\.sourceKey) })
        // Filtering a future/unfinished interval is intentional. Malformed in-scope records are
        // different: their source becomes unavailable so an old record cannot silently replace them.
        let scoped = byID.values.compactMap(\.first).filter {
            !$0.manuallyEntered && (!$0.end.timeIntervalSince1970.isFinite ||
                ($0.end >= history.start && $0.end <= now))
        }
        func isValid(_ record: PatrickHealthTrendSample) -> Bool {
            record.start.timeIntervalSince1970.isFinite && record.end.timeIntervalSince1970.isFinite &&
            record.end >= record.start && record.value.isFinite &&
            (metric == .restingHeartRate ? record.value > 0 : record.value >= 0)
        }
        // Include each conflicting record's source, even if the first duplicate used another device.
        let conflictRecords = byID.values.filter { group in
            guard let first = group.first else { return false }
            return group.dropFirst().contains { $0 != first }
        }.flatMap { $0 }.filter { !$0.manuallyEntered }
        let known = Dictionary(grouping: (scoped + conflictRecords).filter { $0.sourceKey?.isEmpty == false }, by: { $0.sourceKey! })
        var result = known.map { key, records in
            let label = records.map(\.sourceLabel).sorted().first ?? "來源未命名"
            let issue: PatrickHealthTrendSourceGroup.Issue? = conflicts.contains(key) ? .conflictingSampleID
                : records.allSatisfy(isValid) ? nil : .invalidSamples
            let points: [PatrickHealthTrendPoint]
            if issue != nil { points = [] }
            else {
                points = metric == .sleepHours
                    ? sleepPoints(records, key: key, label: label, history: history, calendar: calendar)
                    : quantityPoints(records, metric: metric, key: key, label: label, history: history, calendar: calendar)
            }
            let validDates = records.filter(isValid).map(\.end)
            return PatrickHealthTrendSourceGroup(id: key, label: label, comparable: issue == nil, points: points,
                issue: issue, firstRecordedAt: validDates.min(), lastRecordedAt: validDates.max())
        }
        // These labels are shown only as an explanation; no values are combined across unknown devices.
        let unknownLabels = Set(scoped.filter { $0.sourceKey == nil || $0.sourceKey?.isEmpty == true }.map(\.sourceLabel))
        result += unknownLabels.sorted().map {
            PatrickHealthTrendSourceGroup(id: "unknown:\($0)", label: $0, comparable: false, points: [], issue: .missingDeviceIdentity)
        }
        return result.sorted { ($0.label, $0.id) < ($1.label, $1.id) }
    }

    private static func quantityPoints(_ records: [PatrickHealthTrendSample], metric: PatrickHealthTrendMetric,
                                       key: String, label: String, history: DateInterval,
                                       calendar: Calendar) -> [PatrickHealthTrendPoint] {
        let days = Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.end) })
        return days.keys.sorted().compactMap { start in
            guard start >= history.start, let end = calendar.date(byAdding: .day, value: 1, to: start),
                  let day = days[start], let latest = day.map(\.end).max() else { return nil }
            let values = day.map(\.value).sorted()
            let middle = values.count / 2
            let median = values.count % 2 == 0 ? values[middle - 1] / 2 + values[middle] / 2 : values[middle]
            return PatrickHealthTrendPoint(metric: metric, dayStartMS: ms(start), dayEndMS: ms(end),
                observedAtMS: ms(latest), value: median, sourceKey: key, sourceLabel: label)
        }
    }

    private static func sleepPoints(_ records: [PatrickHealthTrendSample], key: String, label: String,
                                    history: DateInterval, calendar: Calendar) -> [PatrickHealthTrendPoint] {
        guard var start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: history.start) else { return [] }
        var points: [PatrickHealthTrendPoint] = []
        while let end = calendar.date(byAdding: .day, value: 1, to: start), end > start, end <= history.end {
            let spans = records.compactMap { record -> DateInterval? in
                let lower = max(record.start, start), upper = min(record.end, end)
                return upper > lower ? DateInterval(start: lower, end: upper) : nil
            }.sorted { $0.start < $1.start }
            if var merged = spans.first {
                var seconds: TimeInterval = 0
                for span in spans.dropFirst() {
                    if span.start <= merged.end { merged = DateInterval(start: merged.start, end: max(merged.end, span.end)) }
                    else { seconds += merged.duration; merged = span }
                }
                seconds += merged.duration
                let observed = spans.map(\.end).max()!
                points.append(PatrickHealthTrendPoint(metric: .sleepHours,
                    dayStartMS: ms(start), dayEndMS: ms(end), observedAtMS: ms(observed),
                    value: seconds / 3600, sourceKey: key, sourceLabel: label))
            }
            start = end
        }
        return points
    }

    static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }
}
