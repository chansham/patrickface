import Foundation

@main struct NativeHealthTrendAggregationChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); count += 1
    }
    static func main() {
        let formatter = ISO8601DateFormatter()
        func date(_ text: String) -> Date { formatter.date(from: text)! }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-10-13T15:00:00Z")
        func sample(_ start: String, _ end: String, _ value: Double = 1,
                    source: String? = "device-A", manual: Bool = false, id: UUID = UUID()) -> PatrickHealthTrendSample {
            PatrickHealthTrendSample(id: id, start: date(start), end: date(end), value: value,
                sourceKey: source, sourceLabel: source ?? "Unknown device", manuallyEntered: manual)
        }
        let duplicate = sample("2026-10-13T08:00:00Z", "2026-10-13T08:00:00Z", 60)
        let values = [duplicate, duplicate,
            sample("2026-10-13T09:00:00Z", "2026-10-13T09:00:00Z", 64),
            sample("2026-10-13T10:00:00Z", "2026-10-13T10:00:00Z", 200, manual: true),
            sample("2026-10-13T16:00:00Z", "2026-10-13T16:00:00Z", 200),
            sample("2026-10-13T08:00:00Z", "2026-10-13T08:00:00Z", 80, source: "device-B"),
            sample("2026-10-13T08:00:00Z", "2026-10-13T08:00:00Z", 70, source: nil)]
        let groups = PatrickHealthTrendAggregation.groups(metric: .restingHeartRate, samples: values, now: now, calendar: utc)
        check(groups.count == 3, "Keep devices separate, including a noncomparable unknown group")
        let a = groups.first { $0.id == "device-A" }!.points[0]
        check(a.value == 62, "Daily median excludes manual/future values and duplicate sample UUID")
        check(a.observedAtMS == date("2026-10-13T09:00:00Z").timeIntervalSince1970 * 1000,
              "Use latest contributing sample time, never read time")
        check(groups.first { $0.id == "device-B" }!.points[0].value == 80, "No cross-source median")
        check(groups.first { !$0.comparable }!.points.isEmpty, "Unknown source identity cannot produce baseline values")
        check(a.dayStartMS == date("2026-10-13T00:00:00Z").timeIntervalSince1970 * 1000 &&
              a.dayEndMS == date("2026-10-14T00:00:00Z").timeIntervalSince1970 * 1000, "Civil day keeps explicit bounds")
        let zero = PatrickHealthTrendAggregation.groups(metric: .hrvSDNN,
            samples: [sample("2026-10-13T08:00:00Z", "2026-10-13T08:00:00Z", 0)], now: now, calendar: utc)
        check(zero.first?.points.first?.value == 0, "Actual recorded zero HRV is distinct from absent samples")
        let invalid = PatrickHealthTrendAggregation.groups(metric: .restingHeartRate,
            samples: [duplicate, sample("2026-10-13T08:00:00Z", "2026-10-13T08:00:00Z", .nan)], now: now, calendar: utc)
        check(invalid[0].issue == .invalidSamples && invalid[0].points.isEmpty,
              "Malformed current data blocks its source instead of silently falling back to a valid old value")
        var conflicting = duplicate
        conflicting.value = 99
        let conflict = PatrickHealthTrendAggregation.groups(metric: .restingHeartRate,
            samples: [duplicate, conflicting], now: now, calendar: utc)
        let reversedConflict = PatrickHealthTrendAggregation.groups(metric: .restingHeartRate,
            samples: [conflicting, duplicate], now: now, calendar: utc)
        check(conflict[0].issue == .conflictingSampleID && conflict[0].points.isEmpty &&
              reversedConflict[0].issue == .conflictingSampleID, "Conflicting UUID cannot first-win in either query order")
        conflicting.sourceKey = "device-C"
        let crossConflict = PatrickHealthTrendAggregation.groups(metric: .restingHeartRate,
            samples: [duplicate, conflicting], now: now, calendar: utc)
        check(crossConflict.count == 2 && crossConflict.allSatisfy { !$0.comparable },
              "Conflicting UUID involving two source identities blocks both sources")

        let sleeps = [sample("2026-10-12T23:00:00Z", "2026-10-13T04:00:00Z"),
                      sample("2026-10-13T03:00:00Z", "2026-10-13T06:00:00Z"),
                      sample("2026-10-13T04:00:00Z", "2026-10-13T08:00:00Z", source: "device-B"),
                      sample("2026-10-13T13:00:00Z", "2026-10-13T14:00:00Z"),
                      sample("2026-10-13T14:00:00Z", "2026-10-14T02:00:00Z")]
        let sleepGroups = PatrickHealthTrendAggregation.groups(metric: .sleepHours, samples: sleeps, now: now, calendar: utc)
        let sleep = sleepGroups.first { $0.id == "device-A" }!.points
        check(sleep.count == 1 && sleep[0].value == 7, "Cross-midnight sleep is one union, overlaps once, partial current noon-window excluded")
        check(sleep[0].dayStartMS == date("2026-10-12T12:00:00Z").timeIntervalSince1970 * 1000 &&
              sleep[0].dayEndMS == date("2026-10-13T12:00:00Z").timeIntervalSince1970 * 1000, "Sleep windows use noon-to-noon")
        check(sleepGroups.first { $0.id == "device-B" }!.points[0].value == 4, "Sleep sources never union with each other")
        check(PatrickHealthTrendAggregation.groups(metric: .sleepHours, samples: sleeps,
            now: date("2026-10-13T10:00:00Z"), calendar: utc).allSatisfy { $0.points.isEmpty },
              "Before noon, the currently open sleep window is not compared against complete windows")

        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstSamples = [sample("2026-03-08T07:00:00Z", "2026-03-08T14:00:00Z")]
        let dst = PatrickHealthTrendAggregation.groups(metric: .sleepHours, samples: dstSamples,
            now: date("2026-03-08T22:00:00Z"), calendar: pacific)[0].points[0]
        check(dst.dayEndMS - dst.dayStartMS == 23 * 3600 * 1000 && dst.value == 7,
              "Spring-forward noon window is 23 actual hours; duration does not invent an hour")
        let fall = PatrickHealthTrendAggregation.groups(metric: .sleepHours,
            samples: [sample("2026-11-01T06:00:00Z", "2026-11-01T15:00:00Z")],
            now: date("2026-11-01T23:00:00Z"), calendar: pacific)[0].points[0]
        check(fall.dayEndMS - fall.dayStartMS == 25 * 3600 * 1000 && fall.value == 9,
              "Fall-back noon window is 25 hours with actual recorded duration")
        let early = sample("2026-09-14T10:00:00Z", "2026-09-14T11:00:00Z")
        check(PatrickHealthTrendAggregation.groups(metric: .sleepHours, samples: [early], now: now, calendar: utc).isEmpty,
              "Outside history window remains absent")
        check(PatrickHealthTrendAggregation.historyWindow(at: Date(timeIntervalSince1970: .nan), calendar: utc) == nil,
              "Invalid query clock cannot produce a baseline")
        print("PASS: \(count) native health trend aggregation checks (Foundation only; no HealthKit permissions, SDK, or Watch execution).")
    }
}
