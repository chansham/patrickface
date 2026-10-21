import Foundation
import HealthKit

/// Overnight body readings for the morning sentence. Empty when HealthKit cannot
/// be read. Handwashing samples are optional: Series 12 may not record them.
@MainActor
enum PatrickOvernightReader {
    private static let store = HKHealthStore()

    static func load(now: Date = .now) async -> [PatrickMorningSeries] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        async let sleep = sleepHours(now: now)
        async let hrv = daily(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), now: now)
        async let resting = daily(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), now: now)
        async let wrist = daily(.appleSleepingWristTemperature, unit: .degreeCelsius(), now: now)
        async let breath = daily(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), now: now)
        return [
            series(.sleepHours, rows: await sleep, now: now),
            series(.hrvSDNN, rows: await hrv, now: now),
            series(.restingHeartRate, rows: await resting, now: now),
            series(.wristTemperature, rows: await wrist, now: now),
            series(.respiratoryRate, rows: await breath, now: now)
        ]
    }

    static func lastNight(now: Date = .now) async -> (quietMinutes: Double, wakes: Int) {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return (0, 0) }
        let calendar = PatrickHKHolidays.calendar
        guard let start = calendar.date(byAdding: .hour, value: -18, to: now) else { return (0, 0) }
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let awake = HKCategoryValueSleepAnalysis.awake.rawValue
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var quiet: TimeInterval = 0
                var wakes = 0
                for sample in samples as? [HKCategorySample] ?? [] {
                    if asleep.contains(sample.value) {
                        quiet += sample.endDate.timeIntervalSince(sample.startDate)
                    } else if sample.value == awake {
                        wakes += 1
                    }
                }
                continuation.resume(returning: (quiet / 60, wakes))
            }
            store.execute(query)
        }
    }

    static func latestHandwash(since: Date) async -> Date? {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .handwashingEvent) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictEndDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                continuation.resume(returning: samples?.first?.endDate)
            }
            store.execute(query)
        }
    }

    private static func series(_ metric: PatrickMorningMetric, rows: [(Date, Double)], now: Date) -> PatrickMorningSeries {
        let calendar = PatrickHKHolidays.calendar
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let sorted = rows.filter { $0.0 <= now && $0.1.isFinite }.sorted { $0.0 < $1.0 }
        let overnight = sorted.last { sample in
            let day = calendar.startOfDay(for: sample.0)
            return day == today || day == yesterday
        }?.0
        let index = overnight.flatMap { moment in sorted.lastIndex { $0.0 == moment } }
        return PatrickMorningSeries(metric: metric, values: sorted.map(\.1), overnightIndex: index)
    }

    private static func daily(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, now: Date) async -> [(Date, Double)] {
        let type = HKQuantityType(identifier)
        let calendar = PatrickHKHolidays.calendar
        guard let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var rows: [(Date, Double)] = []
                collection?.enumerateStatistics(from: start, to: now) { stats, _ in
                    if let quantity = stats.averageQuantity() {
                        rows.append((stats.startDate, quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }

    private static func sleepHours(now: Date) async -> [(Date, Double)] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let calendar = PatrickHKHolidays.calendar
        guard let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) else { return [] }
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var hours: [Date: TimeInterval] = [:]
                for sample in samples as? [HKCategorySample] ?? [] {
                    guard asleep.contains(sample.value) else { continue }
                    let day = calendar.startOfDay(for: sample.endDate)
                    hours[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
                }
                continuation.resume(returning: hours.map { ($0.key, $0.value / 3600) })
            }
            store.execute(query)
        }
    }
}
