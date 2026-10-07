import Foundation

@main struct NativeHealthChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); count += 1
    }
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let watch = PatrickHealthSource(name: "Watch", bundleID: "fixture.watch", deviceName: "Fixture Watch")
        let phone = PatrickHealthSource(name: "Phone", bundleID: "fixture.phone", deviceName: nil)
        func interval(_ from: Double, _ to: Double, asleep: Bool = true, source: PatrickHealthSource? = nil, id: UUID = UUID()) -> PatrickSleepInterval {
            PatrickSleepInterval(id: id, start: now.addingTimeInterval(from * 3600),
                end: now.addingTimeInterval(to * 3600), asleep: asleep, source: source ?? watch)
        }
        let window = PatrickHealthMetric.sleep.queryWindow(at: now)
        check(window.duration == 86400, "Rolling sleep window must remain 24 actual hours")
        check(PatrickSleepSummary.reading([], in: window) == nil, "Missing sleep is not zero")
        check(PatrickSleepSummary.reading([interval(-10, -2, asleep: false)], in: window) == nil,
              "In-bed and awake samples alone do not invent asleep time")
        let duplicateID = UUID()
        let first = interval(-10, -6, id: duplicateID)
        let samples = [first, first, interval(-8, -4, source: phone), interval(-4, -3),
                       interval(-2, -1), interval(-9, -5, asleep: false)]
        let summary = PatrickSleepSummary.reading(samples, in: window)!
        check(summary.value == 8, "Overlaps, adjacent stages, duplicate IDs and a separated nap count once")
        check(summary.sampleCount == 4, "Only contributing distinct asleep samples counted")
        check(summary.sources.count == 2, "Both actual contributing sources remain visible")
        check(summary.interval == window && summary.isAggregate, "Aggregate states its exact queried interval")
        let clipped = PatrickSleepSummary.reading([interval(-28, -22), interval(-1, 3)], in: window)!
        check(clipped.value == 3, "Clip both ends; future sleep cannot enter the total")
        check(PatrickSleepSummary.reading([interval(-3, -5), interval(-25, -24), interval(0, 2)], in: window) == nil,
              "Invalid, zero-overlap and future-only samples are absent, not zero")
        check(PatrickSleepSummary.reading([interval(-30, 3)], in: window)?.value == 24,
              "No combination can exceed the bounded interval")
        check(PatrickSleepSummary.reading(Array(samples.reversed()), in: window)?.value == summary.value,
              "Query ordering does not change a union")
        let point = PatrickHealthReading(value: 0, start: now, end: now, sources: [watch, watch])!
        check(point.value == 0 && point.sources.count == 1, "An actual zero sample remains distinct from absence")
        check(PatrickHealthReading(value: .nan, start: now, end: now, sources: []) == nil, "Reject NaN")
        check(PatrickHealthReading(value: .infinity, start: now, end: now, sources: []) == nil, "Reject infinite values")
        check(PatrickHealthReading(value: 10, start: now, end: now.addingTimeInterval(-1), sources: []) == nil,
              "Reject reversed sample times")
        check(PatrickHealthMetric.wristTemperature.formatted(34.126) == "34.13", "Show temperature with explicit precision")
        check(PatrickHealthMetric.hrvSDNN.unit == "毫秒", "HRV remains SDNN milliseconds, never a stress score")
        var gate = PatrickHealthReadGate()
        check(gate.selected.isEmpty && !gate.active, "Health selection starts opt-in")
        gate.setSelected([.hrvSDNN]); gate.setActive(true)
        let token = gate.generation
        check(gate.accepts(token, metric: .hrvSDNN), "Current selected read may present")
        check(!gate.accepts(token, metric: .heartRate), "Unselected metric cannot present")
        gate.setSelected([.sleep])
        check(!gate.accepts(token, metric: .hrvSDNN), "Changing scope rejects an old query result")
        let sleepToken = gate.generation
        gate.setActive(false); gate.setActive(true)
        check(!gate.accepts(sleepToken, metric: .sleep), "Leaving and returning cannot replay cached health data")
        check(gate.accepts(gate.generation, metric: .sleep), "Fresh foreground read remains enabled")
        check(PatrickHealthReadGate.refreshable(selected: [.sleep, .hrvSDNN], previouslyRequested: [.hrvSDNN]) == [.hrvSDNN],
              "Automatic refresh never requests a newly selected permission")
        check(PatrickHealthReadGate.refreshable(selected: [.sleep], previouslyRequested: []) == [],
              "First entry never prompts or reads")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = ISO8601DateFormatter().date(from: "2026-03-09T06:30:00Z")!
        check(PatrickHealthMetric.steps.queryWindow(at: spring, calendar: calendar).start ==
              ISO8601DateFormatter().date(from: "2026-03-08T08:00:00Z")!, "Today begins at local midnight across DST")
        check(PatrickHealthMetric.hrvSDNN.queryWindow(at: now).duration == 7 * 86400,
              "Latest samples are bounded to the stated recent window")
        print("PASS: \(count) native health summary/scope checks (Foundation only; no HealthKit permission or sensor execution).")
    }
}
