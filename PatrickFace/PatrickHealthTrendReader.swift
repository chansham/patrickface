import Foundation
import HealthKit

/// HealthKit-to-value conversion occurs in the query callback. The UI receives only an ephemeral snapshot.
enum PatrickHealthTrendSnapshot {
    static func groups(metric: PatrickHealthTrendMetric, samples: [HKSample], now: Date,
                       calendar: Calendar) -> [PatrickHealthTrendSourceGroup] {
        let records: [PatrickHealthTrendSample] = samples.compactMap { sample in
            let value: Double
            if metric == .sleepHours {
                guard let sleep = sample as? HKCategorySample,
                      [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                       HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                       HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                       HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains(sleep.value) else { return nil }
                value = 1 // Only marks recorded asleep intervals; duration is calculated by the union.
            } else {
                guard let quantity = sample as? HKQuantitySample else { return nil }
                let unit: HKUnit = metric == .hrvSDNN ? .secondUnit(with: .milli) : .count().unitDivided(by: .minute())
                value = quantity.quantity.doubleValue(for: unit)
            }
            let source = sample.sourceRevision.source
            let device = sample.device
            let label = [source.name, device?.name, device?.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            // Bundle IDs identify apps, not necessarily the measuring device. A model alone cannot
            // distinguish two watches. localIdentifier is local-hardware-scoped and can change on update;
            // such a change intentionally starts a separate comparison group.
            let key: String?
            if let local = device?.localIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
               !local.isEmpty, !source.bundleIdentifier.isEmpty {
                key = [source.bundleIdentifier, local, device?.manufacturer ?? "", device?.model ?? "", device?.hardwareVersion ?? ""]
                    .map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
            } else { key = nil }
            let entered = (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue ?? false
            return PatrickHealthTrendSample(id: sample.uuid, start: sample.startDate, end: sample.endDate,
                value: value, sourceKey: key, sourceLabel: label.isEmpty ? "來源未命名" : label, manuallyEntered: entered)
        }
        return PatrickHealthTrendAggregation.groups(metric: metric, samples: records, now: now, calendar: calendar)
    }
}
