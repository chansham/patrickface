import Foundation

/// Compile with iOSCompanion/Shared/PatrickHealthTrend.swift. These checks use
/// synthetic aggregates and do not access HealthKit or request permissions.
@main struct NativeHealthTrendChecks {
    struct Fixtures: Decodable {
        var schemaVersion: Int
        var cases: [Fixture]
    }
    struct Fixture: Decodable {
        var id: String
        var input: PatrickHealthTrendInput
        var expected: [PatrickHealthTrendResult]
    }
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        count += 1
    }
    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first ?? "ecosystem/health-trend-fixtures.json"
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        check(fixtures.schemaVersion == 1, "Unexpected fixture schema")
        check(fixtures.cases.count >= 20, "Shared regression scenarios must not disappear")
        check(Set(fixtures.cases.map(\.id)).count == fixtures.cases.count, "Fixture IDs must be unique")
        for fixture in fixtures.cases {
            let actual = PatrickHealthTrend.evaluate(fixture.input)
            check(actual == fixture.expected, "Shared fixture mismatch: \(fixture.id)")
            check(actual.map(\.metric) == PatrickHealthTrendMetric.allCases,
                  "All metrics remain explicit, including missing ones: \(fixture.id)")
            check(actual.allSatisfy { result in
                result.state == .ready || (result.baseline == nil && result.delta == nil)
            }, "Only a current, sufficiently populated comparison may have a delta: \(fixture.id)")
        }
        let example = fixtures.cases.first { $0.id == "ready" }!.input
        func altered(_ mutate: (inout PatrickHealthTrendInput) -> Void) -> PatrickHealthTrendResult {
            var input = example
            mutate(&input)
            return PatrickHealthTrend.evaluate(input).first { $0.metric == .sleepHours }!
        }
        check(altered { $0.points[$0.points.count - 1].value = .nan }.reason == .invalidPoint,
              "A NaN sample must not silently fall back to a previous day")
        check(altered { $0.points[$0.points.count - 1].value = .infinity }.invalidPointCount == 1,
              "Infinite data remain missing, with a rejection count")
        check(altered { $0.points[$0.points.count - 1].dayStartMS = .nan }.reason == .invalidPoint,
              "Malformed boundaries cannot bypass scope filtering")
        check(altered { $0.nowMS = .nan }.reason == .invalidInput, "Reject NaN query time")
        check(altered { $0.historyStartMS = $0.nowMS - 31 * 24 * 3_600_000 }.reason == .invalidInput,
              "The input cannot stretch a 28-calendar-day window into an unbounded history")
        check(altered { $0.points[$0.points.count - 1].sourceKey = " \n " }.reason == .invalidPoint,
              "Anonymous devices cannot form a same-source baseline")
        check(altered { $0.points[$0.points.count - 1].sourceLabel = "" }.reason == .invalidPoint,
              "A source must be explainable in the presentation")
        check(altered { input in
            input.points[input.points.count - 1].dayEndMS = input.points.last!.dayStartMS + 3_600_000
        }.reason == .invalidPoint, "An hourly fragment cannot masquerade as a calendar day")
        check(altered { input in
            input.nowMS = input.points.last!.observedAtMS + PatrickHealthTrend.freshnessMS + 1
        }.state == .stale, "One millisecond past the 36-hour boundary is stale")
        check(altered { input in input.points.reverse() } == PatrickHealthTrend.evaluate(example).first!,
              "Input order does not choose a different source or sample")
        let encoded = try JSONEncoder().encode(PatrickHealthTrend.evaluate(example))
        let roundTrip = try JSONDecoder().decode([PatrickHealthTrendResult].self, from: encoded)
        check(roundTrip == PatrickHealthTrend.evaluate(example), "Result Codable round trip remains lossless")
        print("PASS: \(count) native descriptive-health-trend checks; \(fixtures.cases.count) shared synthetic cases. No HealthKit/device execution.")
    }
}
